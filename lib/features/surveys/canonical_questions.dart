// Canonical question set for the BASECamp Student Survey
// (TK – 3rd Grade, 2025-26). Source of truth for the questions,
// activity options, and IDs used by the kiosk + the bundled audio
// asset library.
//
// IDs are stable strings (not regenerated UUIDs) so an audio file
// rendered for `q_made_friends` keeps working across app builds.
// The asset generation script (`tool/generate_voices.dart`,
// shipped in slice 2.5) reads from this file as its source of
// truth — any change here = re-run the script + commit new MP3s.

import 'package:basecamp/features/surveys/survey_models.dart';

/// The 7 activity options for the multi-select question.
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

/// The full BASECamp Student Survey question set, in reading
/// order. 2 practice + 9 belonging Likert + 1 multi-select +
/// 4 learning Likert + 1 open-ended = **17 items** total.
///
/// Order matches the printed PDF the program uses today; the
/// kiosk advances through this list one item at a time per child.
const List<SurveyQuestion> kBasecampCanonicalQuestions = <SurveyQuestion>[
  // ——— Practice (2) ——————————————————————————————————————————
  SurveyQuestion(
    id: 'p_today_feeling',
    type: SurveyQuestionType.mood,
    prompt: 'Today, I am feeling…',
    isPractice: true,
  ),
  SurveyQuestion(
    id: 'p_pizza_pineapple',
    type: SurveyQuestionType.mood,
    prompt: 'I like pizza with pineapple on it.',
    isPractice: true,
  ),

  // ——— Belonging / relationships (7) ——————————————————————————
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

  // ——— Activities multi-select (1) ————————————————————————————
  SurveyQuestion(
    id: 'q_activities',
    type: SurveyQuestionType.multiSelect,
    prompt: 'Check any of the activities you did this year in BASECamp:',
    options: kBasecampActivityOptions,
  ),

  // ——— Learning + health (4) ——————————————————————————————————
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

  // ——— Open-ended close (1) ———————————————————————————————————
  SurveyQuestion(
    id: 'q_health_open',
    type: SurveyQuestionType.openEnded,
    prompt:
        'At BASECamp this year, something I learned about being healthy is…',
  ),
];

/// Section break headings that the audio narrator reads between
/// groups (mirrors the printed PDF's "Let's start with 2 practice
/// questions first!" / "Now let's do more together!" lines).
class SurveyTransition {
  const SurveyTransition({
    required this.id,
    required this.afterQuestionId,
    required this.text,
  });
  final String id;
  final String afterQuestionId;
  final String text;
}

/// Spoken transitions inserted between sections. Empty
/// `afterQuestionId` = play before the first question.
const List<SurveyTransition> kBasecampTransitions = <SurveyTransition>[
  SurveyTransition(
    id: 't_intro',
    afterQuestionId: '',
    text:
        'Welcome! We want to hear about what you learned this year. '
        'There are no wrong answers — just answer how you really feel. '
        "Let's start with 2 practice questions first!",
  ),
  SurveyTransition(
    id: 't_post_practice',
    afterQuestionId: 'p_pizza_pineapple',
    text: "Great job! Now let's do more together.",
  ),
  SurveyTransition(
    id: 't_all_done',
    afterQuestionId: 'q_health_open',
    text: 'All done — thank you! Pass it along to the next friend.',
  ),
];

/// Nudge phrase library — small encouragements the kiosk plays
/// at random (~10% probability per qualifying interaction) when
/// audio mode is `full`. Categories let the system pick a phrase
/// appropriate to the moment (just-picked-up vs just-dropped vs
/// idle-too-long).
class SurveyNudge {
  const SurveyNudge({
    required this.id,
    required this.category,
    required this.text,
  });
  final String id;
  final SurveyNudgeCategory category;
  final String text;
}

enum SurveyNudgeCategory {
  /// Played briefly when the chibi picks up a marble.
  pickup,

  /// Played briefly when a marble lands in the jar.
  drop,

  /// Played when the chibi switches between marbles while holding.
  switchMarble,

  /// Played when the chibi has been idle near the jar for >8 sec.
  idle,
}

/// The actual phrase pool. ~3-5 per category so a kid doesn't
/// hear the same nudge twice in a row.
const List<SurveyNudge> kBasecampNudges = <SurveyNudge>[
  // Pickup
  SurveyNudge(
    id: 'n_pickup_nice',
    category: SurveyNudgeCategory.pickup,
    text: 'Nice pick.',
  ),
  SurveyNudge(
    id: 'n_pickup_good',
    category: SurveyNudgeCategory.pickup,
    text: 'Good one.',
  ),
  SurveyNudge(
    id: 'n_pickup_thoughtful',
    category: SurveyNudgeCategory.pickup,
    text: 'Take your time.',
  ),

  // Drop
  SurveyNudge(
    id: 'n_drop_there',
    category: SurveyNudgeCategory.drop,
    text: 'There you go.',
  ),
  SurveyNudge(
    id: 'n_drop_didit',
    category: SurveyNudgeCategory.drop,
    text: 'You did it.',
  ),
  SurveyNudge(
    id: 'n_drop_nice',
    category: SurveyNudgeCategory.drop,
    text: 'Nice work.',
  ),

  // Switch marble
  SurveyNudge(
    id: 'n_switch_thinking',
    category: SurveyNudgeCategory.switchMarble,
    text: 'Pick the one that feels right.',
  ),
  SurveyNudge(
    id: 'n_switch_okay',
    category: SurveyNudgeCategory.switchMarble,
    text: 'No rush.',
  ),

  // Idle
  SurveyNudge(
    id: 'n_idle_ready',
    category: SurveyNudgeCategory.idle,
    text: 'Whenever you are ready.',
  ),
  SurveyNudge(
    id: 'n_idle_thinking',
    category: SurveyNudgeCategory.idle,
    text: 'Take a moment to think.',
  ),
];
