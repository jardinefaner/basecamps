// Offline TTS asset generator for the BASECamp Student Survey
// kiosk. Runs LOCALLY at build time — never on a user's device.
//
// Reads the canonical phrase set from
// `lib/features/surveys/canonical_questions.dart` (questions +
// transitions + nudges + the picker sample) and renders each
// phrase × each of the 10 Aura voices to MP3 via Deepgram. Files
// land in `assets/audio/<voiceCode>/<hash>.mp3` where `hash` is
// the first 16 hex chars of `sha256(text.trim())`. The runtime
// `SurveyAudioService` looks up by the same hash so the bundle
// just works.
//
// **One-time per phrase change.** Re-run this script when the
// canonical phrase list changes in `canonical_questions.dart`.
// The hash means unchanged phrases skip the API call (we check
// existing files before fetching).
//
// Cost back-of-napkin
//   ~39 phrases × 10 voices × ~50 chars × $0.015/1000 chars
//   ≈ $0.30 to render the entire library. One-time.
//
// Usage
//   1. Get a Deepgram API key (https://console.deepgram.com).
//   2. Set DEEPGRAM_API_KEY in your shell:
//        export DEEPGRAM_API_KEY=...
//   3. From the repo root:
//        dart run tool/generate_voices.dart
//   4. Append the new asset paths to pubspec.yaml under
//      `flutter > assets:`. The script prints the lines you need
//      at the end.
//   5. Commit `assets/audio/` so all developers + CI builds get
//      the same audio.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:basecamp/features/surveys/canonical_questions.dart';
import 'package:basecamp/features/surveys/survey_audio_service.dart';
import 'package:basecamp/features/surveys/survey_models.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final apiKey = Platform.environment['DEEPGRAM_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln(
      'DEEPGRAM_API_KEY env var not set. '
      'Get a key at https://console.deepgram.com and export it.',
    );
    exit(1);
  }

  // Build the phrase list from the canonical sources.
  final phrases = <String>{
    kSampleText,
    for (final q in kBasecampCanonicalQuestions) q.prompt,
    for (final q in kBasecampCanonicalQuestions)
      for (final opt in q.options) opt.label,
    for (final t in kBasecampTransitions) t.text,
    for (final n in kBasecampNudges) n.text,
  };

  stdout.writeln('Generating ${phrases.length} phrases × '
      '${SurveyVoice.values.length} voices = '
      '${phrases.length * SurveyVoice.values.length} files');

  final assetsRoot = Directory('assets/audio');
  await assetsRoot.create(recursive: true);

  var generated = 0;
  var skipped = 0;
  var failed = 0;
  for (final voice in SurveyVoice.values) {
    final voiceDir = Directory('assets/audio/${voice.code}');
    await voiceDir.create(recursive: true);
    for (final phrase in phrases) {
      final assetPath = surveyAudioAssetPath(voice, phrase);
      final file = File(assetPath);
      if (file.existsSync()) {
        skipped += 1;
        continue;
      }
      try {
        final bytes = await _renderTts(
          apiKey: apiKey,
          voiceCode: voice.code,
          text: phrase,
        );
        await file.writeAsBytes(bytes);
        generated += 1;
        stdout.writeln('  + ${voice.code} / "${_summarize(phrase)}"');
      } on Object catch (e) {
        failed += 1;
        stderr.writeln('  ! ${voice.code} / "${_summarize(phrase)}": $e');
      }
    }
  }

  stdout.writeln('Done. Generated $generated, skipped $skipped (already '
      'existed), failed $failed.');
  if (failed > 0) {
    exitCode = 2;
  }
  if (generated > 0) {
    _printPubspecHint();
  }
}

/// POST to Deepgram TTS, return raw MP3 bytes.
Future<List<int>> _renderTts({
  required String apiKey,
  required String voiceCode,
  required String text,
}) async {
  // Deepgram Aura. The model id is `aura-<voice>-en`. MP3 output.
  final uri = Uri.parse(
    'https://api.deepgram.com/v1/speak'
    '?model=aura-$voiceCode-en'
    '&encoding=mp3',
  );
  final response = await http.post(
    uri,
    headers: <String, String>{
      'Authorization': 'Token $apiKey',
      'Content-Type': 'application/json',
    },
    body: jsonEncode(<String, Object>{'text': text}),
  );
  if (response.statusCode != 200) {
    throw Exception(
      'Deepgram returned ${response.statusCode}: ${response.body}',
    );
  }
  return response.bodyBytes;
}

String _summarize(String s) {
  if (s.length <= 40) return s;
  return '${s.substring(0, 37)}...';
}

void _printPubspecHint() {
  stdout
    ..writeln()
    ..writeln('— Add these lines under `flutter > assets:` in pubspec.yaml —');
  for (final voice in SurveyVoice.values) {
    stdout.writeln('    - assets/audio/${voice.code}/');
  }
}
