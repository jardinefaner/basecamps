// Survey domain models. Pure Dart, no Flutter, no Drift — these
// are the things the rest of the survey feature works in. The
// Drift `Survey` row gets converted to/from `SurveyConfig` at the
// repository boundary.
//
// Slice 1 introduces the configuration shape (what a teacher sets
// up); Slice 2 adds Response + Session helpers as the kiosk wires
// up.

import 'dart:convert';

/// Age tag — TK through 6th grade. Drives WHICH canonical
/// question list the survey uses (TK-3 vs 4-6) and the default
/// scale of each Likert question. Stored as a short code in the
/// DB.
enum SurveyAgeBand {
  tk('tk', 'TK'),
  k('k', 'Kindergarten'),
  g1('g1', '1st grade'),
  g2('g2', '2nd grade'),
  g3('g3', '3rd grade'),
  g4('g4', '4th grade'),
  g5('g5', '5th grade'),
  g6('g6', '6th grade');

  const SurveyAgeBand(this.code, this.label);
  final String code;
  final String label;

  /// `true` for the TK→G3 cohort which uses the 3-point scale
  /// canonical question set.
  bool get isYoungerCohort => switch (this) {
        SurveyAgeBand.tk ||
        SurveyAgeBand.k ||
        SurveyAgeBand.g1 ||
        SurveyAgeBand.g2 ||
        SurveyAgeBand.g3 =>
          true,
        _ => false,
      };

  /// `true` for the G4→G6 cohort which uses the 5-point scale
  /// canonical question set + the SEL "describes me" section.
  bool get isOlderCohort => !isYoungerCohort;

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

/// Likert scale variant for a single mood question. Bundles the
/// choice count + the captions printed under each thumb on the
/// kid-facing kiosk. Kept on the question (not the survey) so a
/// single survey can mix scales — e.g. the 4-6 paper uses
/// `fivePtNotGood` for practice 1 ("How are you feeling"),
/// `fivePtAgree` for the main Likert, and `fivePtLikeMe` for
/// the SEL "describes me" section.
///
/// The `count` is what the kiosk uses to decide how many faces
/// to spawn. The `labels` are reference strings — the kiosk's
/// painted faces don't render them today, but they're saved on
/// the question for later display + for the print card / CSV
/// export to use as column headers.
enum SurveyScale {
  /// 2-point yes/no — used by the activity-recall block, where
  /// each activity ("I helped hand out supplies.") is its own
  /// individual mood question with two faces: head-shake (No) and
  /// nod (Yes). Replaces the old single multi-select activities
  /// question, so each item gets a clean read-aloud + tap pass
  /// instead of a long crowded grid.
  twoPtYesNo(
    2,
    <String>['No', 'Yes'],
  ),

  /// 3-point "How are you feeling" — TK-3 practice 1.
  threePtNotGreat(
    3,
    <String>['Not great', 'Okay', 'Great!'],
  ),

  /// 3-point agreement — TK-3 default for every other Likert.
  threePtAgree(
    3,
    <String>['Disagree', 'Kind of agree', 'Agree!'],
  ),

  /// 5-point "How are you feeling" — 4-6 practice 1.
  fivePtNotGood(
    5,
    <String>['Really not good', 'Not good', 'OK', 'Good', 'Great!'],
  ),

  /// 5-point agreement — 4-6 default for the main Likert questions.
  fivePtAgree(
    5,
    <String>[
      'Strongly disagree',
      'Disagree',
      'Kind of agree',
      'Agree',
      'Strongly agree',
    ],
  ),

  /// 5-point "describes me" — 4-6 practice 3 + the SEL section.
  fivePtLikeMe(
    5,
    <String>[
      'Not like me',
      'A little like me',
      'Somewhat like me',
      'Mostly like me',
      'Exactly like me',
    ],
  );

  const SurveyScale(this.count, this.labels);

  /// 3 or 5 — number of options on the scale.
  final int count;

  /// Captions, one per option, in negative → positive order.
  final List<String> labels;

  String get code => name;

  static SurveyScale fromCode(String code) {
    return SurveyScale.values.firstWhere(
      (s) => s.code == code,
      orElse: () => SurveyScale.threePtAgree,
    );
  }
}

/// Which kiosk UI the children see when running the survey. Both
/// styles share canonical questions + the same `survey_responses`
/// write path; only the kid-facing surface differs.
///
/// Stored on the `surveys.style` column; default is `marbleJar`
/// for backward compatibility with surveys created before v60.
enum SurveyStyle {
  /// Flame chibi character + 5-face painted marbles + 3D mason
  /// jar with overflow physics. The original kiosk experience.
  marbleJar('marble_jar', 'Marble Jar', 'Chibi character drops painted marbles into a mason jar'),

  /// Tap-thumb scale + woven basket with marble-physics pile +
  /// over-rim overflow + random overspill around the basket.
  /// The graduated basket-survey experiment.
  basket('basket', 'Basket', 'Drag painted marbles into a woven basket');

  const SurveyStyle(this.code, this.label, this.description);
  final String code;
  final String label;
  final String description;

  static SurveyStyle fromCode(String code) {
    return SurveyStyle.values.firstWhere(
      (s) => s.code == code,
      orElse: () => SurveyStyle.marbleJar,
    );
  }
}

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

/// One question in a survey. Mood questions carry a `scale`;
/// multi-select carries `options`; open-ended just shows the
/// prompt + the mic.
class SurveyQuestion {
  const SurveyQuestion({
    required this.id,
    required this.type,
    required this.prompt,
    this.options = const <SurveyActivityOption>[],
    this.isPractice = false,
    this.scale = SurveyScale.threePtAgree,
  });

  final String id;
  final SurveyQuestionType type;
  final String prompt;

  /// For `multiSelect` only — the activity options shown as cards.
  final List<SurveyActivityOption> options;

  /// `true` for the warm-up questions at the start. Saved with the
  /// response so the CSV export can hide them by default.
  final bool isPractice;

  /// Likert scale variant for mood questions. Drives both the
  /// number of choices spawned in the kiosk and the printable
  /// caption labels (Disagree / Strongly Disagree / Not like me /
  /// etc). 4-6 surveys mix multiple scales within a single run
  /// (mood + agree + describes-me) so this lives on the
  /// question, not the survey.
  final SurveyScale scale;

  /// Backwards-compat shortcut. New code should read [scale.count]
  /// directly.
  int get choiceCount => scale.count;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type.code,
        'prompt': prompt,
        if (options.isNotEmpty)
          'options': options.map((o) => o.toJson()).toList(),
        if (isPractice) 'isPractice': true,
        // Only emit when non-default to keep older JSON parsers
        // (and existing surveys' questionsJson) happy.
        if (scale != SurveyScale.threePtAgree) 'scale': scale.code,
      };

  // We keep `fromJson` as a static helper instead of a named ctor
  // because Dart's named ctors can't shadow the const generative
  // ctor's positional/named-arg shape cleanly here.
  // ignore: prefer_constructors_over_static_methods
  static SurveyQuestion fromJson(Map<String, dynamic> json) {
    // `scale` is the new field. For older payloads that still
    // carry the legacy `choiceCount` int, infer the scale: 5
    // → fivePtAgree, anything else → threePtAgree.
    SurveyScale scale;
    if (json.containsKey('scale')) {
      scale = SurveyScale.fromCode(json['scale'] as String);
    } else {
      final legacyCount = json['choiceCount'] as int? ?? 3;
      scale = legacyCount == 5
          ? SurveyScale.fivePtAgree
          : SurveyScale.threePtAgree;
    }
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
      scale: scale,
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
    required this.style,
    required this.questions,
    required this.createdAt,
    required this.updatedAt,
    this.schools = const <String>[],
  });

  final String id;
  final String siteName;
  final String classroom;
  final SurveyAgeBand ageBand;
  final String pinHash; // hex sha256
  final SurveyAudioMode audioMode;
  final SurveyVoice voice;

  /// Which kiosk UI to render. Read from the `surveys.style`
  /// column; controls how `/surveys/:id/play` dispatches.
  final SurveyStyle style;
  final List<SurveyQuestion> questions;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Pre-configured school names that populate the kiosk's
  /// pre-flight gate dropdown. Empty = free-text fallback.
  /// Order is the teacher's order (no auto-sort) so the most
  /// common school can sit at the top.
  final List<String> schools;

  String questionsJson() => jsonEncode(
        questions.map((q) => q.toJson()).toList(),
      );

  static List<SurveyQuestion> parseQuestions(String json) {
    final decoded = jsonDecode(json) as List<dynamic>;
    return decoded
        .map((q) => SurveyQuestion.fromJson(q as Map<String, dynamic>))
        .toList();
  }

  String schoolsJsonString() => jsonEncode(schools);

  static List<String> parseSchools(String json) {
    if (json.trim().isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const <String>[];
      return decoded
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } on FormatException {
      return const <String>[];
    }
  }
}
