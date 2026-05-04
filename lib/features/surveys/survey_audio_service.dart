// Survey audio service (Slice 2.5) — plays pre-rendered MP3s for
// the BASECamp Student Survey kiosk. Question prompts, nudges,
// and voice samples all flow through this one service.
//
// **Asset-based**, by design. Audio is rendered ONCE locally with
// `dart run tool/generate_voices.dart` (which calls Deepgram with
// the developer's API key) and shipped as bundle assets. The
// runtime never holds the long-lived Deepgram key — same security
// pattern as Supabase / OpenAI in this app.
//
// **Graceful no-op**: if an asset is missing (the script hasn't
// been run yet, or the user is on a build without bundled audio),
// `play(...)` resolves to no audio playing. The kiosk continues
// silently. This means we can ship the runtime + integration code
// without blocking on actually generating MP3 files.

import 'dart:convert';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:basecamp/features/surveys/canonical_questions.dart';
import 'package:basecamp/features/surveys/survey_models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where in the asset tree a phrase's MP3 lives. The hash makes
/// this stable across phrasings — re-rendering the same text
/// produces the same path, so the asset bundle never has stale
/// duplicates.
String surveyAudioAssetPath(SurveyVoice voice, String text) {
  final digest = sha256.convert(utf8.encode(text.trim()));
  // First 16 hex chars is plenty unique for ~50 phrases per voice.
  final hash = digest.toString().substring(0, 16);
  return 'assets/audio/${voice.code}/$hash.mp3';
}

/// Default sample text the voice picker uses for previews.
const String kSampleText = "Hi! Let's get started.";

class SurveyAudioService {
  SurveyAudioService();

  /// Single shared player — playing a new audio cancels whatever
  /// was playing before (a question read interrupts a stale nudge,
  /// for example).
  final AudioPlayer _player = AudioPlayer();

  /// Cooldown timestamp — no nudge plays before this. Cleared
  /// each time a new question starts so the kid gets a fresh
  /// "post-question silence" window.
  DateTime _nudgeCooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Last category played (so we don't repeat the same category
  /// twice in a row). Reset on each question advance.
  SurveyNudgeCategory? _lastNudgeCategory;

  final math.Random _rng = math.Random();

  /// Play a question prompt. Always interrupts whatever's
  /// currently playing. Resets the nudge cooldown so a kid hears
  /// the question cleanly before any encouragement plays.
  Future<void> playQuestion(SurveyVoice voice, String text) async {
    await _stopAndPlay(voice, text);
    _nudgeCooldownUntil =
        DateTime.now().add(const Duration(seconds: 5));
    _lastNudgeCategory = null;
  }

  /// Play a transition line (the inter-section narration like
  /// "Let's start with 2 practice questions first!").
  Future<void> playTransition(SurveyVoice voice, String text) async {
    await _stopAndPlay(voice, text);
  }

  /// Play a one-shot voice sample for the picker.
  Future<void> playSample(SurveyVoice voice) async {
    await _stopAndPlay(voice, kSampleText);
  }

  /// **Maybe** play a nudge — 10% probability per call, with a
  /// minimum 12-second cooldown between nudges and a 5-second
  /// quiet window right after every question.
  /// Returns `true` if a nudge actually started playing.
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

  /// Pick a phrase from the canonical nudge pool, biased AWAY
  /// from the most recently played category so a child doesn't
  /// hear the same kind of nudge twice in a row.
  SurveyNudge? _pickNudge(SurveyNudgeCategory category) {
    final pool =
        kBasecampNudges.where((n) => n.category == category).toList();
    if (pool.isEmpty) return null;
    if (_lastNudgeCategory == category && pool.length > 1) {
      // Drop the first one (most recent in source order) to
      // skew variety without tracking exact last-played-id.
      pool.removeAt(0);
    }
    return pool[_rng.nextInt(pool.length)];
  }

  Future<void> _stopAndPlay(
    SurveyVoice voice,
    String text, {
    double volume = 1.0,
  }) async {
    await _player.stop();
    final assetPath = surveyAudioAssetPath(voice, text);
    final exists = await _assetExists(assetPath);
    if (!exists) return; // graceful no-op when not generated yet
    // AssetSource expects a path relative to `assets/`, so strip
    // that prefix before passing to the player.
    final relative = assetPath.replaceFirst('assets/', '');
    await _player.setVolume(volume.clamp(0, 1));
    await _player.play(AssetSource(relative));
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }

  /// Best-effort check that an asset exists at [path]. Uses
  /// `rootBundle.load` and catches the throw on miss. Catching
  /// `Object` here (rather than the specific FlutterError thrown
  /// for missing assets) makes the lint happy and also tolerates
  /// any other load failure mode (locked file, decode error, etc.).
  Future<bool> _assetExists(String path) async {
    try {
      await rootBundle.load(path);
      return true;
    } on Object {
      return false;
    }
  }
}

// =====================================================================
// Riverpod
// =====================================================================

/// Singleton service for the lifetime of the app. Disposes its
/// underlying AudioPlayer when the provider tree is torn down.
final surveyAudioServiceProvider = Provider<SurveyAudioService>((ref) {
  final service = SurveyAudioService();
  ref.onDispose(service.dispose);
  return service;
});
