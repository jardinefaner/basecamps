// Canonical question sets for the BASECamp Student Survey,
// 2025-26 edition. Two age-banded lists, picked by the setup form
// based on the survey's `SurveyAgeBand`:
//
//   * `kBasecampQuestionsTK3` — TK through 3rd grade. 3-point
//     Likert; 13 mood + 1 multi-select + 1 open-ended (15 items).
//   * `kBasecampQuestionsG46` — 4th through 6th grade. 5-point
//     Likert with three different scale variants; 13 mood + 1
//     multi-select + 1 open-ended + 10 SEL "describes me"
//     questions (25 items).
//
// IDs are stable strings (not regenerated UUIDs) so an audio
// file rendered for `q_made_friends` keeps working across app
// builds. Adding a new question = new id; renaming a question's
// prompt = same id (so cached audio keys to the new prompt only
// once you re-run the audio generator).

import 'package:basecamp/features/surveys/survey_models.dart';

// ═════════════════════════════════════════════════════════════════
// Activity recall (per-activity yes/no questions)
// ═════════════════════════════════════════════════════════════════

/// 7 activity prompts. Each runs as its OWN yes/no mood question
/// (`SurveyScale.twoPtYesNo`) instead of one giant multi-select
/// grid — that way Deepgram reads each one aloud, the kid sees
/// only ONE prompt at a time, and the BASECamp print/CSV gets
/// per-activity Yes/No columns directly.
///
/// The `id` values carry the original `act_*` slug as a stable
/// reference for analysis (they used to be the option ids on the
/// old multi-select question). The `prompt` is the read-aloud
/// version — first person past tense, kid-friendly cadence.
const List<SurveyQuestion> kBasecampActivityQuestions = <SurveyQuestion>[
  SurveyQuestion(
    id: 'q_act_supplies',
    type: SurveyQuestionType.mood,
    prompt: 'I helped hand out supplies.',
    scale: SurveyScale.twoPtYesNo,
  ),
  SurveyQuestion(
    id: 'q_act_invited_friends',
    type: SurveyQuestionType.mood,
    prompt: 'I asked a friend to do an activity with me.',
    scale: SurveyScale.twoPtYesNo,
  ),
  SurveyQuestion(
    id: 'q_act_line_leader',
    type: SurveyQuestionType.mood,
    prompt: 'I volunteered to be a line leader.',
    scale: SurveyScale.twoPtYesNo,
  ),
  SurveyQuestion(
    id: 'q_act_chose_group',
    type: SurveyQuestionType.mood,
    prompt: 'I chose a group activity for everyone to do.',
    scale: SurveyScale.twoPtYesNo,
  ),
  SurveyQuestion(
    id: 'q_act_helped_friend',
    type: SurveyQuestionType.mood,
    prompt: 'I helped a friend when they were having a bad day.',
    scale: SurveyScale.twoPtYesNo,
  ),
  SurveyQuestion(
    id: 'q_act_shared',
    type: SurveyQuestionType.mood,
    prompt: 'I shared my things with others.',
    scale: SurveyScale.twoPtYesNo,
  ),
  SurveyQuestion(
    id: 'q_act_reminded_rules',
    type: SurveyQuestionType.mood,
    prompt: 'I reminded others of the rules.',
    scale: SurveyScale.twoPtYesNo,
  ),
];

/// Backwards-compat: the old multi-select activity options list.
/// Kept so the CSV exporter's canonical-id ordering hook still
/// resolves. Prefer [kBasecampActivityQuestions] for new code.
const List<SurveyActivityOption> kBasecampActivityOptions =
    <SurveyActivityOption>[
  SurveyActivityOption(
    id: 'act_supplies',
    label: 'Helped hand out supplies',
  ),
  SurveyActivityOption(
    id: 'act_invited_friends',
    label: 'Asked my friends to participate in an activity with me',
  ),
  SurveyActivityOption(
    id: 'act_line_leader',
    label: 'Volunteered to be a line leader',
  ),
  SurveyActivityOption(
    id: 'act_chose_group',
    label: 'Chose a group activity for everyone to do',
  ),
  SurveyActivityOption(
    id: 'act_helped_friend',
    label: 'Helped a friend when they were having a bad day',
  ),
  SurveyActivityOption(
    id: 'act_shared',
    label: 'Shared my things with others',
  ),
  SurveyActivityOption(
    id: 'act_reminded_rules',
    label: 'Reminded others of rules',
  ),
];

// ═════════════════════════════════════════════════════════════════
// TK – 3rd Grade · 3-point scale
// ═════════════════════════════════════════════════════════════════

/// 15-item TK→G3 survey. 3-point Likert across the board (with
/// a friendlier "Not great / Okay / Great" set on the practice
/// mood-feeling question). Mirrors the 2025-26 paper exactly.
const List<SurveyQuestion> kBasecampQuestionsTK3 = <SurveyQuestion>[
  // ——— Practice (2) — warm-up so the kid gets the mechanics
  SurveyQuestion(
    id: 'p_today_feeling',
    type: SurveyQuestionType.mood,
    prompt: 'Today, I am feeling…',
    isPractice: true,
    scale: SurveyScale.threePtNotGreat,
  ),
  SurveyQuestion(
    id: 'p_pizza_pineapple',
    type: SurveyQuestionType.mood,
    prompt: 'I like pizza with pineapple on it.',
    isPractice: true,
  ),

  // ——— Belonging / relationships (7)
  SurveyQuestion(
    id: 'q_made_friends',
    type: SurveyQuestionType.mood,
    prompt: 'I made new friends in program this year.',
  ),
  SurveyQuestion(
    id: 'q_friends_help',
    type: SurveyQuestionType.mood,
    prompt: 'I have friends here who help me if I am having a hard time.',
  ),
  SurveyQuestion(
    id: 'q_fun_learning',
    type: SurveyQuestionType.mood,
    prompt: 'I have fun learning at BASECamp.',
  ),
  SurveyQuestion(
    id: 'q_teachers_care',
    type: SurveyQuestionType.mood,
    prompt: 'My BASECamp teachers care about me.',
  ),
  SurveyQuestion(
    id: 'q_teachers_greet',
    type: SurveyQuestionType.mood,
    prompt: 'My BASECamp teachers greet me.',
  ),
  SurveyQuestion(
    id: 'q_happy_here',
    type: SurveyQuestionType.mood,
    prompt: 'I am happy to be here.',
  ),
  SurveyQuestion(
    id: 'q_safe_here',
    type: SurveyQuestionType.mood,
    prompt: 'I feel safe here.',
  ),

  // ——— Activity recall (7) — per-activity yes/no questions in
  //                            place of the old multi-select grid.
  ...kBasecampActivityQuestions,

  // ——— Learning + health (4)
  SurveyQuestion(
    id: 'q_kept_learning',
    type: SurveyQuestionType.mood,
    prompt: 'I kept learning even when it was hard.',
  ),
  SurveyQuestion(
    id: 'q_asking_questions',
    type: SurveyQuestionType.mood,
    prompt:
        "I felt comfortable asking questions when I didn't understand something.",
  ),
  SurveyQuestion(
    id: 'q_new_food',
    type: SurveyQuestionType.mood,
    prompt:
        'Because of BASECamp, I tried new food choices that were healthy for me.',
  ),
  SurveyQuestion(
    id: 'q_more_movement',
    type: SurveyQuestionType.mood,
    prompt:
        'Because of BASECamp, I participate in more physical activity & movement '
        '(like sports, capoeira, etc.)',
  ),

  // ——— Open-ended close (1)
  SurveyQuestion(
    id: 'q_health_open',
    type: SurveyQuestionType.openEnded,
    prompt:
        'At BASECamp this year, something I learned about being healthy is…',
  ),
];

// ═════════════════════════════════════════════════════════════════
// 4th – 6th Grade · 5-point scale + SEL section
// ═════════════════════════════════════════════════════════════════

/// 25-item G4→G6 survey. 5-point Likert. Three scale variants:
/// `fivePtNotGood` for practice 1 ("How are you feeling"),
/// `fivePtAgree` for the main belonging + learning + health
/// questions, and `fivePtLikeMe` for practice 3 + the SEL
/// "describes me" section at the end.
const List<SurveyQuestion> kBasecampQuestionsG46 = <SurveyQuestion>[
  // ——— Practice (3) — extra one for the older cohort introducing
  // the "describes me" scale they'll see in the SEL section.
  SurveyQuestion(
    id: 'p_today_feeling_5',
    type: SurveyQuestionType.mood,
    prompt: 'Today, I am feeling…',
    isPractice: true,
    scale: SurveyScale.fivePtNotGood,
  ),
  SurveyQuestion(
    id: 'p_pizza_pineapple_5',
    type: SurveyQuestionType.mood,
    prompt: 'I like pizza with pineapple on it.',
    isPractice: true,
    scale: SurveyScale.fivePtAgree,
  ),
  SurveyQuestion(
    id: 'p_say_hi_to_dogs',
    type: SurveyQuestionType.mood,
    prompt: 'I say hi to every dog I meet.',
    isPractice: true,
    scale: SurveyScale.fivePtLikeMe,
  ),

  // ——— Belonging / relationships (9 — adds two G4-6 questions
  //                                    not on the TK-3 paper)
  SurveyQuestion(
    id: 'q_made_friends',
    type: SurveyQuestionType.mood,
    prompt: 'I made new friends in program this year.',
    scale: SurveyScale.fivePtAgree,
  ),
  SurveyQuestion(
    id: 'q_friends_help',
    type: SurveyQuestionType.mood,
    prompt: 'I have friends here who help me if I am having a hard time.',
    scale: SurveyScale.fivePtAgree,
  ),
  SurveyQuestion(
    id: 'q_helped_others',
    type: SurveyQuestionType.mood,
    prompt: 'I tried to help others when they needed it.',
    scale: SurveyScale.fivePtAgree,
  ),
  SurveyQuestion(
    id: 'q_compromised',
    type: SurveyQuestionType.mood,
    prompt:
        "I compromised (or worked it out) with others when we didn't want "
        'the same thing.',
    scale: SurveyScale.fivePtAgree,
  ),
  SurveyQuestion(
    id: 'q_fun_learning',
    type: SurveyQuestionType.mood,
    prompt: 'I have fun learning at BASECamp.',
    scale: SurveyScale.fivePtAgree,
  ),
  SurveyQuestion(
    id: 'q_teachers_care',
    type: SurveyQuestionType.mood,
    prompt: 'My BASECamp teachers care about me.',
    scale: SurveyScale.fivePtAgree,
  ),
  SurveyQuestion(
    id: 'q_teachers_greet',
    type: SurveyQuestionType.mood,
    prompt: 'My BASECamp teachers greet me.',
    scale: SurveyScale.fivePtAgree,
  ),
  SurveyQuestion(
    id: 'q_happy_here',
    type: SurveyQuestionType.mood,
    prompt: 'I am happy to be here.',
    scale: SurveyScale.fivePtAgree,
  ),
  SurveyQuestion(
    id: 'q_safe_here',
    type: SurveyQuestionType.mood,
    prompt: 'I feel safe here.',
    scale: SurveyScale.fivePtAgree,
  ),

  // ——— Activity recall (7) — per-activity yes/no questions
  //                            (same set TK-3 uses).
  ...kBasecampActivityQuestions,

  // ——— Learning + health (4)
  SurveyQuestion(
    id: 'q_kept_learning',
    type: SurveyQuestionType.mood,
    prompt: 'I kept learning even when it was hard.',
    scale: SurveyScale.fivePtAgree,
  ),
  SurveyQuestion(
    id: 'q_asking_questions',
    type: SurveyQuestionType.mood,
    prompt:
        "I felt comfortable asking questions when I didn't understand "
        'something.',
    scale: SurveyScale.fivePtAgree,
  ),
  SurveyQuestion(
    id: 'q_new_food',
    type: SurveyQuestionType.mood,
    prompt:
        'Because of BASECamp, I tried new food choices that were healthy '
        'for me.',
    scale: SurveyScale.fivePtAgree,
  ),
  SurveyQuestion(
    id: 'q_more_movement',
    type: SurveyQuestionType.mood,
    prompt:
        'Because of BASECamp, I participate in more physical activity & '
        'movement (like sports, capoeira, etc.)',
    scale: SurveyScale.fivePtAgree,
  ),

  // ——— Open-ended (1)
  SurveyQuestion(
    id: 'q_health_open',
    type: SurveyQuestionType.openEnded,
    prompt:
        'At BASECamp this year, something I learned about being healthy is…',
  ),

  // ——— SEL "describes me" section (10) — only on the 4-6 paper.
  // Every question uses `fivePtLikeMe`. The narrator reads the
  // "Circle how much each sentence describes you. In the
  // Auditorium this year…" preamble before the first one (carried
  // by the kBasecampTransitions list, not as a question).
  SurveyQuestion(
    id: 'sel_recognise_self_emotions',
    type: SurveyQuestionType.mood,
    prompt:
        'I could tell when I was feeling happy, sad, angry, or scared.',
    scale: SurveyScale.fivePtLikeMe,
  ),
  SurveyQuestion(
    id: 'sel_mood_awareness',
    type: SurveyQuestionType.mood,
    prompt:
        'I could tell when my mood was affecting how I acted or talked '
        'to others.',
    scale: SurveyScale.fivePtLikeMe,
  ),
  SurveyQuestion(
    id: 'sel_fix_mistakes',
    type: SurveyQuestionType.mood,
    prompt: 'When I made mistakes, I tried to fix things.',
    scale: SurveyScale.fivePtLikeMe,
  ),
  SurveyQuestion(
    id: 'sel_persistence',
    type: SurveyQuestionType.mood,
    prompt:
        "If I couldn't do something the first time, I kept trying.",
    scale: SurveyScale.fivePtLikeMe,
  ),
  SurveyQuestion(
    id: 'sel_empathy',
    type: SurveyQuestionType.mood,
    prompt: "I care about other people's feelings.",
    scale: SurveyScale.fivePtLikeMe,
  ),
  SurveyQuestion(
    id: 'sel_diversity',
    type: SurveyQuestionType.mood,
    prompt: 'I learned about people who were different than me.',
    scale: SurveyScale.fivePtLikeMe,
  ),
  SurveyQuestion(
    id: 'sel_recognise_others_emotions',
    type: SurveyQuestionType.mood,
    prompt:
        'I could tell when others were feeling happy, sad, angry, or '
        'scared.',
    scale: SurveyScale.fivePtLikeMe,
  ),
  SurveyQuestion(
    id: 'sel_consequence_thinking',
    type: SurveyQuestionType.mood,
    prompt: 'I thought about how my choices might affect me later on.',
    scale: SurveyScale.fivePtLikeMe,
  ),
  SurveyQuestion(
    id: 'sel_planning',
    type: SurveyQuestionType.mood,
    prompt: 'I made plans before I took action.',
    scale: SurveyScale.fivePtLikeMe,
  ),
  SurveyQuestion(
    id: 'sel_help_seeking',
    type: SurveyQuestionType.mood,
    prompt: "I asked for help when I didn't know what to do.",
    scale: SurveyScale.fivePtLikeMe,
  ),
];

// ═════════════════════════════════════════════════════════════════
// Selector
// ═════════════════════════════════════════════════════════════════

/// Returns the right canonical question list for [band]. The
/// setup form passes the result to `surveyRepository.create`,
/// which freezes it onto the survey row's `questionsJson`.
List<SurveyQuestion> canonicalQuestionsForBand(SurveyAgeBand band) {
  return band.isYoungerCohort
      ? kBasecampQuestionsTK3
      : kBasecampQuestionsG46;
}

/// Backwards-compat alias. Existing callers (and any survey
/// created before per-band lists landed) get the TK-3 list. New
/// code should call [canonicalQuestionsForBand] with the actual
/// age band.
const List<SurveyQuestion> kBasecampCanonicalQuestions =
    kBasecampQuestionsTK3;

// ═════════════════════════════════════════════════════════════════
// Transitions + nudges (read aloud between sections)
// ═════════════════════════════════════════════════════════════════

/// Section breaks the audio narrator reads between groups.
/// Mirrors the printed PDF's "Let's start with X practice
/// questions first!" / "Great job! Now let's…" beats.
class SurveyTransition {
  const SurveyTransition({
    required this.id,
    required this.text,
  });

  final String id;
  final String text;
}

const List<SurveyTransition> kBasecampTransitions = <SurveyTransition>[
  SurveyTransition(
    id: 'intro_practice_2',
    text: "Let's start with 2 practice questions first!",
  ),
  SurveyTransition(
    id: 'intro_practice_3',
    text: "Let's start with 3 practice questions first!",
  ),
  SurveyTransition(
    id: 'after_practice',
    text: "Great job! Now let's answer some real questions.",
  ),
  SurveyTransition(
    id: 'sel_intro',
    text:
        'Circle how much each sentence describes you. '
        'In the Auditorium this year…',
  ),
  SurveyTransition(
    id: 'all_done',
    text: 'All done — thank you so much!',
  ),
];

// ═════════════════════════════════════════════════════════════════
// Nudges (gentle "you got this" prompts)
// ═════════════════════════════════════════════════════════════════

/// Categories the kiosk picks from when deciding what nudge to
/// play during idle / interaction beats.
enum SurveyNudgeCategory {
  /// While the kid is hovering / picking up an emoji marble.
  pickup,

  /// Right after they drop one in the basket / jar.
  drop,

  /// When they switch which marble they're holding.
  switchMarble,

  /// Long idle without interaction — gently keeps things moving.
  idle,
}

class SurveyNudge {
  const SurveyNudge({
    required this.id,
    required this.text,
    required this.category,
  });

  final String id;
  final String text;
  final SurveyNudgeCategory category;
}

const List<SurveyNudge> kBasecampNudges = <SurveyNudge>[
  // pickup
  SurveyNudge(
    id: 'pickup_thinking',
    text: "Take your time, friend.",
    category: SurveyNudgeCategory.pickup,
  ),
  SurveyNudge(
    id: 'pickup_no_wrong',
    text: "There's no wrong answer.",
    category: SurveyNudgeCategory.pickup,
  ),
  SurveyNudge(
    id: 'pickup_listen',
    text: "Listen to your gut!",
    category: SurveyNudgeCategory.pickup,
  ),
  // drop
  SurveyNudge(
    id: 'drop_nice',
    text: "Nice one!",
    category: SurveyNudgeCategory.drop,
  ),
  SurveyNudge(
    id: 'drop_keep_going',
    text: "Keep going, you're doing great.",
    category: SurveyNudgeCategory.drop,
  ),
  SurveyNudge(
    id: 'drop_good',
    text: "Good answer!",
    category: SurveyNudgeCategory.drop,
  ),
  // switch
  SurveyNudge(
    id: 'switch_change_mind',
    text: "It's okay to change your mind!",
    category: SurveyNudgeCategory.switchMarble,
  ),
  SurveyNudge(
    id: 'switch_take_a_sec',
    text: "Take a second to think.",
    category: SurveyNudgeCategory.switchMarble,
  ),
  // idle
  SurveyNudge(
    id: 'idle_pick_one',
    text: "Pick one when you're ready!",
    category: SurveyNudgeCategory.idle,
  ),
  SurveyNudge(
    id: 'idle_thinking_okay',
    text: "Take your time. There's no rush.",
    category: SurveyNudgeCategory.idle,
  ),
];
