// Survey domain models. Pure Dart, no Flutter, no Drift — these
// are the things the rest of the survey feature works in. The
// Drift `Survey` row gets converted to/from `SurveyConfig` at the
// repository boundary.
//
// Slice 1 introduces the configuration shape (what a teacher sets
// up); Slice 2 adds Response + Session helpers as the kiosk wires
// up.

import 'dart:convert';

/// 5-band age tag — TK through 3rd grade. Drives default question
/// wording + UI sizing. Stored as a short code in the DB.
enum SurveyAgeBand {
  tk('tk', 'TK'),
  k('k', 'Kindergarten'),
  g1('g1', '1st grade'),
  g2('g2', '2nd grade'),
  g3('g3', '3rd grade');

  const SurveyAgeBand(this.code, this.label);
  final String code;
  final String label;

  static SurveyAgeBand fromCode(String code) {
    return SurveyAgeBand.values.firstWhere(
      (b) => b.code == code,
      orElse: () => SurveyAgeBand.tk,
    );
  }
}

/// Audio mode the teacher picks during setup. The kiosk respects
/// this when deciding what to play.
enum SurveyAudioMode {
  full('full', 'Questions + nudges'),
  questionsOnly('questions_only', 'Questions only'),
  silent('silent', 'Silent');

  const SurveyAudioMode(this.code, this.label);
  final String code;
  final String label;

  static SurveyAudioMode fromCode(String code) {
    return SurveyAudioMode.values.firstWhere(
      (m) => m.code == code,
      orElse: () => SurveyAudioMode.full,
    );
  }
}

/// Deepgram **Aura-2** voice id. We bundle audio for all 10
/// voices in `assets/audio/<voiceId>/...` so any choice resolves
/// locally without an API call at runtime. The teacher picks one
/// in setup and it's the voice the kiosk plays for the entire
/// survey.
///
/// Aura-2 is Deepgram's newer (Q4'24) higher-fidelity TTS model;
/// every voice id here exists in that catalog. The legacy Aura-1
/// "angus" is gone in 2 — we use **atlas** (warm, casual male) as
/// the closest replacement.
enum SurveyVoice {
  asteria('asteria', 'Asteria', VoiceGender.female, 'Warm, friendly US'),
  luna('luna', 'Luna', VoiceGender.female, 'Younger, cheerful US'),
  stella('stella', 'Stella', VoiceGender.female, 'Bright, expressive US'),
  athena('athena', 'Athena', VoiceGender.female, 'Calm, measured UK'),
  hera('hera', 'Hera', VoiceGender.female, 'Smooth, soothing US'),
  orion('orion', 'Orion', VoiceGender.male, 'Approachable US'),
  arcas('arcas', 'Arcas', VoiceGender.male, 'Natural, casual US'),
  atlas('atlas', 'Atlas', VoiceGender.male, 'Warm, casual US'),
  perseus('perseus', 'Perseus', VoiceGender.male, 'Confident US'),
  orpheus('orpheus', 'Orpheus', VoiceGender.male, 'Professional US');

  const SurveyVoice(this.code, this.label, this.gender, this.tagline);
  final String code;
  final String label;
  final VoiceGender gender;
  final String tagline;

  static SurveyVoice fromCode(String code) {
    return SurveyVoice.values.firstWhere(
      (v) => v.code == code,
      orElse: () => SurveyVoice.asteria,
    );
  }

  static List<SurveyVoice> get female => SurveyVoice.values
      .where((v) => v.gender == VoiceGender.female)
      .toList();
  static List<SurveyVoice> get male => SurveyVoice.values
      .where((v) => v.gender == VoiceGender.male)
      .toList();
}

enum VoiceGender { female, male }

/// What kind of question this is. Drives both the kiosk UI and the
/// shape of the response stored in `survey_responses`.
enum SurveyQuestionType {
  /// 3-point Likert: disagree / kind of agree / agree. Played as
  /// the marble-drop interaction.
  mood('mood'),

  /// "Check any of these" multiple choice. Played as a 7-card
  /// grid (slice 3).
  multiSelect('multi_select'),

  /// Open-ended voice answer. Played as a tap-to-record mic UI
  /// + Deepgram STT transcription (slice 3.5).
  openEnded('open_ended');

  const SurveyQuestionType(this.code);
  final String code;

  static SurveyQuestionType fromCode(String code) {
    return SurveyQuestionType.values.firstWhere(
      (t) => t.code == code,
      orElse: () => SurveyQuestionType.mood,
    );
  }
}

/// One question in a survey. Mood questions just need a prompt;
/// multi-select carries `options`; open-ended just shows the
/// prompt + the mic.
class SurveyQuestion {
  const SurveyQuestion({
    required this.id,
    required this.type,
    required this.prompt,
    this.options = const <SurveyActivityOption>[],
    this.isPractice = false,
  });

  final String id;
  final SurveyQuestionType type;
  final String prompt;

  /// For `multiSelect` only — the activity options shown as cards.
  final List<SurveyActivityOption> options;

  /// `true` for the 2 warm-up questions at the start. Saved with
  /// the response so the CSV export can hide them by default.
  final bool isPractice;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type.code,
        'prompt': prompt,
        if (options.isNotEmpty)
          'options': options.map((o) => o.toJson()).toList(),
        if (isPractice) 'isPractice': true,
      };

  // We keep `fromJson` as a static helper instead of a named ctor
  // because Dart's named ctors can't shadow the const generative
  // ctor's positional/named-arg shape cleanly here.
  // ignore: prefer_constructors_over_static_methods
  static SurveyQuestion fromJson(Map<String, dynamic> json) {
    return SurveyQuestion(
      id: json['id'] as String,
      type: SurveyQuestionType.fromCode(json['type'] as String),
      prompt: json['prompt'] as String,
      options: (json['options'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (o) => SurveyActivityOption.fromJson(o as Map<String, dynamic>),
          )
          .toList(),
      isPractice: (json['isPractice'] as bool?) ?? false,
    );
  }
}

/// One option for a multi-select question.
class SurveyActivityOption {
  const SurveyActivityOption({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
      };

  // Symmetric to `SurveyQuestion.fromJson` — see note there.
  // ignore: prefer_constructors_over_static_methods
  static SurveyActivityOption fromJson(Map<String, dynamic> json) {
    return SurveyActivityOption(
      id: json['id'] as String,
      label: json['label'] as String,
    );
  }
}

/// In-memory shape of a survey configuration. The Drift `Survey`
/// row is `toRow(...) → SurveysCompanion` and back via `fromRow`.
class SurveyConfig {
  const SurveyConfig({
    required this.id,
    required this.siteName,
    required this.classroom,
    required this.ageBand,
    required this.pinHash,
    required this.audioMode,
    required this.voice,
    required this.questions,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String siteName;
  final String classroom;
  final SurveyAgeBand ageBand;
  final String pinHash; // hex sha256
  final SurveyAudioMode audioMode;
  final SurveyVoice voice;
  final List<SurveyQuestion> questions;
  final DateTime createdAt;
  final DateTime updatedAt;

  String questionsJson() => jsonEncode(
        questions.map((q) => q.toJson()).toList(),
      );

  static List<SurveyQuestion> parseQuestions(String json) {
    final decoded = jsonDecode(json) as List<dynamic>;
    return decoded
        .map((q) => SurveyQuestion.fromJson(q as Map<String, dynamic>))
        .toList();
  }
}
