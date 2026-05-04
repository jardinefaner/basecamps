// Survey audio service (Slice 2.5+) — plays Deepgram-rendered
// MP3s for the BASECamp Student Survey kiosk. Question prompts,
// transitions, nudges, and voice samples all flow through this
// one service.
//
// **Three-tier cache**, in order:
//   1. `assets/audio/<voice>/<hash>.mp3` — committed bundle.
//      Empty by default; populated by `tool/generate_voices.dart`
//      if a developer wants to ship audio with the binary.
//   2. App docs runtime cache:
//      `<docs>/survey_audio_cache/<voice>/<hash>.mp3`. Populated
//      by `ensureCached(...)` the first time a phrase is needed
//      on this device.
//   3. Deepgram TTS via the existing `deepgram-token` Supabase
//      edge function (same auth pattern STT uses). Long-lived
//      project key never leaves Supabase secrets; the client gets
//      a 30-second JWT that's enough to grab the MP3.
//
// **Pre-warm at survey creation.** The setup-form's Save & Start
// calls `prewarmForSurvey(...)` so the cache is hot before a kid
// taps the kiosk; subsequent runs are local-only.
//
// **Graceful no-op**: if the user isn't signed in to Supabase, or
// the network is down, or the edge function fails — `play(...)`
// resolves to no audio. The kiosk continues silently.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:basecamp/config/env.dart';
import 'package:basecamp/features/surveys/canonical_questions.dart';
import 'package:basecamp/features/surveys/survey_models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stable hash for a phrase. Used as the asset / cache filename.
String _phraseHash(String text) {
  final digest = sha256.convert(utf8.encode(text.trim()));
  return digest.toString().substring(0, 16);
}

/// Asset path layout — used by both the runtime + the legacy
/// build-time generator script. The bundle ships this empty by
/// default; runtime fetches go to the docs-folder cache instead.
String surveyAudioAssetPath(SurveyVoice voice, String text) {
  return 'assets/audio/${voice.code}/${_phraseHash(text)}.mp3';
}

/// Default sample text the voice picker uses for previews.
const String kSampleText = "Hi! Let's get started.";

class SurveyAudioService {
  SurveyAudioService();

  final AudioPlayer _player = AudioPlayer();

  /// Cooldown timestamp — no nudge plays before this. Cleared
  /// each time a new question starts so the kid gets a fresh
  /// post-question quiet window.
  DateTime _nudgeCooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Last category played (so we don't repeat the same category
  /// twice in a row). Reset on each question advance.
  SurveyNudgeCategory? _lastNudgeCategory;

  final math.Random _rng = math.Random();

  /// In-memory map: `<voice>:<hash>` → either a Future being
  /// resolved (de-duplicates parallel ensureCached calls for the
  /// same phrase) or a fully-resolved local path string.
  final Map<String, Future<String?>> _inflightFetches =
      <String, Future<String?>>{};

  /// Deepgram TTS endpoint — proxied via Bearer JWT from the
  /// `deepgram-token` Supabase edge function. The model id is
  /// `aura-<voice>-en` and we ask for MP3 output.
  Uri _ttsUri(SurveyVoice voice) => Uri.parse(
        'https://api.deepgram.com/v1/speak'
        '?model=aura-${voice.code}-en'
        '&encoding=mp3',
      );

  // ——— Playback API ————————————————————————————————————————————

  /// Play a question prompt. Always interrupts whatever's playing.
  /// Resets the nudge cooldown so the kid hears the question
  /// cleanly before any encouragement plays.
  Future<void> playQuestion(SurveyVoice voice, String text) async {
    await _stopAndPlay(voice, text);
    _nudgeCooldownUntil = DateTime.now().add(const Duration(seconds: 5));
    _lastNudgeCategory = null;
  }

  /// Play a transition line ("Let's start with 2 practice
  /// questions first!").
  Future<void> playTransition(SurveyVoice voice, String text) async {
    await _stopAndPlay(voice, text);
  }

  /// Play a one-shot voice sample for the picker.
  Future<void> playSample(SurveyVoice voice) async {
    await _stopAndPlay(voice, kSampleText);
  }

  /// **Maybe** play a nudge — 10% probability per call, with a
  /// 12-second floor between nudges and a 5-second quiet window
  /// right after every question. Returns `true` if a nudge
  /// actually started playing.
  Future<bool> maybePlayNudge({
    required SurveyVoice voice,
    required SurveyAudioMode audioMode,
    required SurveyNudgeCategory category,
  }) async {
    if (audioMode != SurveyAudioMode.full) return false;
    final now = DateTime.now();
    if (now.isBefore(_nudgeCooldownUntil)) return false;
    if (_rng.nextDouble() > 0.10) return false;
    final phrase = _pickNudge(category);
    if (phrase == null) return false;
    _lastNudgeCategory = category;
    _nudgeCooldownUntil = now.add(const Duration(seconds: 12));
    await _stopAndPlay(voice, phrase.text, volume: 0.6);
    return true;
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }

  // ——— Pre-warm at survey creation —————————————————————————————

  /// Kick the cache for [survey]'s configured voice. Returns when
  /// every canonical phrase used by the kiosk has either been
  /// cached or failed (cache misses don't block — the kiosk just
  /// runs silent for those).
  ///
  /// Idempotent. Safe to call multiple times. Cheap on the
  /// already-cached path (filesystem stat per phrase).
  Future<SurveyAudioPrewarmResult> prewarmForSurvey(
    SurveyConfig survey,
  ) async {
    final voice = survey.voice;
    final phrases = <String>{
      kSampleText,
      for (final q in survey.questions) q.prompt,
      for (final q in survey.questions)
        for (final opt in q.options) opt.label,
      for (final t in kBasecampTransitions) t.text,
      if (survey.audioMode == SurveyAudioMode.full)
        for (final n in kBasecampNudges) n.text,
    };
    var ok = 0;
    var failed = 0;
    var skipped = 0;
    final tasks = phrases.map((text) async {
      final cached = await _localPathForCachedPhrase(voice, text);
      if (cached != null) {
        skipped += 1;
        return;
      }
      final fetched = await ensureCached(voice, text);
      if (fetched != null) {
        ok += 1;
      } else {
        failed += 1;
      }
    });
    await Future.wait(tasks);
    return SurveyAudioPrewarmResult(
      total: phrases.length,
      generated: ok,
      alreadyCached: skipped,
      failed: failed,
    );
  }

  // ——— Cache lookup + fetch ————————————————————————————————————

  /// Resolve a phrase to a playable local path. Order of
  /// resolution:
  ///   1. asset bundle (committed at build time)
  ///   2. app docs runtime cache (per-device first-fetch)
  ///   3. Deepgram TTS via edge-function JWT — saves to (2) and
  ///      returns that path.
  /// Returns `null` if every tier fails.
  Future<String?> ensureCached(SurveyVoice voice, String text) async {
    final key = '${voice.code}:${_phraseHash(text)}';
    final inflight = _inflightFetches[key];
    if (inflight != null) return inflight;
    final task = _resolvePath(voice, text);
    _inflightFetches[key] = task;
    try {
      return await task;
    } finally {
      // Remove returns the (now-completed) Future as the previous
      // map value; we don't need to await it.
      // ignore: unawaited_futures
      _inflightFetches.remove(key);
    }
  }

  Future<String?> _resolvePath(SurveyVoice voice, String text) async {
    // Tier 1: bundled asset.
    final assetPath = surveyAudioAssetPath(voice, text);
    if (await _assetExists(assetPath)) return _Source.asset(assetPath);

    // Tier 2: runtime cache.
    final cached = await _localPathForCachedPhrase(voice, text);
    if (cached != null) return cached;

    // Tier 3: fetch + cache.
    return _fetchAndCache(voice, text);
  }

  Future<String?> _localPathForCachedPhrase(
    SurveyVoice voice,
    String text,
  ) async {
    if (kIsWeb) return null; // no docs folder on web; fetch every play
    final docs = await getApplicationDocumentsDirectory();
    final filePath = p.join(
      docs.path,
      'survey_audio_cache',
      voice.code,
      '${_phraseHash(text)}.mp3',
    );
    return File(filePath).existsSync() ? filePath : null;
  }

  Future<String?> _fetchAndCache(SurveyVoice voice, String text) async {
    final jwt = await _fetchDeepgramTempToken();
    if (jwt == null) return null;
    final response = await http.post(
      _ttsUri(voice),
      headers: <String, String>{
        'Authorization': 'Bearer $jwt',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, Object>{'text': text}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    if (kIsWeb) {
      // No filesystem on web; would need a blob-URL strategy.
      // Skip caching for now — web audio fetches every play, with
      // the browser's HTTP cache as the safety net.
      return null;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'survey_audio_cache', voice.code));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final filePath = p.join(dir.path, '${_phraseHash(text)}.mp3');
    final file = File(filePath);
    await file.writeAsBytes(response.bodyBytes);
    return filePath;
  }

  /// Hit the existing `deepgram-token` Supabase edge function.
  /// Same auth flow as observations/voice_service.dart's STT —
  /// requires the user to be signed in. Returns null on any
  /// failure path; callers degrade gracefully to silent.
  Future<String?> _fetchDeepgramTempToken() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return null;
    try {
      final url = Uri.parse(
        '${Env.supabaseUrl}/functions/v1/deepgram-token',
      );
      final response = await http.post(
        url,
        headers: <String, String>{
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['access_token'] as String?;
    } on Object {
      return null;
    }
  }

  // ——— Internals ———————————————————————————————————————————————

  Future<void> _stopAndPlay(
    SurveyVoice voice,
    String text, {
    double volume = 1.0,
  }) async {
    await _player.stop();
    final source = await ensureCached(voice, text);
    if (source == null) return; // graceful no-op
    await _player.setVolume(volume.clamp(0, 1));
    if (source.startsWith(_assetPrefix)) {
      // AssetSource expects a path relative to the assets/ root.
      final relative = source.substring(_assetPrefix.length);
      await _player.play(AssetSource(relative));
    } else {
      await _player.play(DeviceFileSource(source));
    }
  }

  Future<bool> _assetExists(String path) async {
    try {
      await rootBundle.load(path);
      return true;
    } on Object {
      return false;
    }
  }

  /// Pick a phrase from the canonical nudge pool, biased AWAY
  /// from the most recently played category.
  SurveyNudge? _pickNudge(SurveyNudgeCategory category) {
    final pool =
        kBasecampNudges.where((n) => n.category == category).toList();
    if (pool.isEmpty) return null;
    if (_lastNudgeCategory == category && pool.length > 1) {
      pool.removeAt(0);
    }
    return pool[_rng.nextInt(pool.length)];
  }
}

/// Tag prefix on `_resolvePath`'s asset-tier return so
/// `_stopAndPlay` can route between AssetSource + DeviceFileSource.
/// Kept lean — just check `startsWith('asset:')` instead of
/// invoking a fileExists per play.
const String _assetPrefix = 'asset:';

class _Source {
  static String asset(String path) => '$_assetPrefix$path';
}

/// Result of a `prewarmForSurvey` call — surfaces totals so the
/// teacher gets a clear "ready" or "audio failed for N phrases"
/// readout in the setup-flow snackbar.
class SurveyAudioPrewarmResult {
  const SurveyAudioPrewarmResult({
    required this.total,
    required this.generated,
    required this.alreadyCached,
    required this.failed,
  });
  final int total;
  final int generated;
  final int alreadyCached;
  final int failed;

  bool get allOk => failed == 0;
}

// =====================================================================
// Riverpod
// =====================================================================

final surveyAudioServiceProvider = Provider<SurveyAudioService>((ref) {
  final service = SurveyAudioService();
  ref.onDispose(service.dispose);
  return service;
});
