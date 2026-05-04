// The 22 prompt strings in this file mix straight + curly quotes
// and embedded "..." inside single-quoted strings. Suppressing the
// stylistic lints rather than letting analyzer noise drown out
// real warnings here.
// ignore_for_file: prefer_single_quotes, missing_whitespace_between_adjacent_strings, avoid_escaping_inner_quotes

import 'dart:convert';

import 'package:basecamp/features/ai/ai_activity_composer.dart';
import 'package:basecamp/features/ai/openai_client.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

/// On-demand AI supplements for an existing activity. The picker
/// surfaces every entry in [addonSpecs] grouped by [AddonCategory];
/// tapping one calls the OpenAI proxy with the activity + plan
/// context + that spec's per-addon prompt, and renders the model's
/// {sections: [...]} response back as labeled text blocks.
///
/// **Sandbox: nothing persists.** Closing the sheet drops the
/// generated content. When this graduates we'll back it with an
/// `activity_addons(library_item_id, kind, payload_json)` table
/// keyed off the activity-library row, and the picker will show
/// previously-generated addons as already-filled tiles.
///
/// Why a single shared registry rather than 22 hand-coded sheets:
/// every addon shares the same plumbing — call OpenAI with a
/// templated prompt, parse JSON, render sections — and the
/// per-addon variation collapses to (label, icon, prompt). Adding
/// the 23rd addon when this graduates is a one-line append to
/// [addonSpecs].

// =====================================================================
// Categories + specs
// =====================================================================

enum AddonCategory {
  beforeActivity('Before the activity'),
  duringActivity('During the activity'),
  afterActivity('After the activity'),
  extensions('Learn-through-play extensions'),
  documentation('Documentation & assessment'),
  funStuff('Fun extras');

  const AddonCategory(this.label);
  final String label;
}

class AddonSpec {
  const AddonSpec({
    required this.id,
    required this.label,
    required this.icon,
    required this.subtitle,
    required this.category,
    required this.prompt,
  });

  final String id;
  final String label;
  final IconData icon;
  final String subtitle;
  final AddonCategory category;

  /// Per-addon instruction appended to the user message. Each spec
  /// describes what to generate AND how to fit it into the shared
  /// {sections: [{heading, body}]} response shape so the renderer
  /// stays addon-agnostic.
  final String prompt;
}

/// Shared system prompt — defines the response schema once for
/// every addon. Per-addon specs only need to describe their content
/// and how it should map onto sections/headings/bodies.
const _systemPrompt = '''
You generate supplementary teaching content for an early-childhood
activity. The teacher gives you the activity (title, description,
objectives, steps, materials) plus group context (group name, age
range, monthly + weekly themes). Produce ONE specific kind of
supplement based on the request.

Return JSON with a single "sections" key — an array of objects with:
  "heading" (string, can be empty for prose-only items)
  "body" (string, required)

Bodies can be multi-paragraph. Use newline-separated bullets prefixed
with "• " when listing things. Use plain text only — no markdown
asterisks, no # headers. Keep the language warm, concrete, classroom-
friendly, and developmentally appropriate to the audience age.
''';

const addonSpecs = <AddonSpec>[
  // ---------- Before the activity ----------
  AddonSpec(
    id: 'preActivityHooks',
    label: 'Pre-activity hooks',
    icon: Icons.lightbulb_outline,
    subtitle: '"I wonder…" curiosity questions',
    category: AddonCategory.beforeActivity,
    prompt: 'Generate 2-3 "I wonder..." curiosity questions a teacher '
        'can drop at snack time or transition to spark anticipation '
        'for the activity. One section per question; heading is '
        'empty, body is the question text.',
  ),
  AddonSpec(
    id: 'vocabularyPreviews',
    label: 'Vocabulary preview',
    icon: Icons.translate_outlined,
    subtitle: 'Key words + definitions + hand motions',
    category: AddonCategory.beforeActivity,
    prompt: 'Pull 3-5 key words from the activity. One section per '
        'word; heading is the word; body is a kid-friendly definition '
        '(one sentence) plus a suggested hand motion or gesture the '
        'teacher can use while saying the word.',
  ),
  AddonSpec(
    id: 'differentiationVariants',
    label: 'Differentiation variants',
    icon: Icons.tune_outlined,
    subtitle: 'Three difficulty levels',
    category: AddonCategory.beforeActivity,
    prompt: 'Three variants of the activity at different difficulty '
        'levels. Three sections: '
        '1) heading "Just starting" — body adapts the activity for '
        'children still building foundational skills. '
        '2) heading "Right on track" — body is the activity as-is or '
        'with light scaffolding. '
        '3) heading "Ready for more" — body extends the activity for '
        'children who finish quickly or need a challenge.',
  ),
  AddonSpec(
    id: 'materialsChecklists',
    label: 'Materials & prep checklists',
    icon: Icons.checklist_outlined,
    subtitle: 'Shopping, night-before, 5-min setup',
    category: AddonCategory.beforeActivity,
    prompt: 'Three checklists. Three sections: '
        '1) heading "Shopping list" — body is a bullet list of '
        'materials to buy or gather. '
        '2) heading "Night before" — body is a bullet list of prep '
        'steps to do at home. '
        '3) heading "5 minutes before kids arrive" — body is a quick '
        'morning setup checklist.',
  ),
  // ---------- During the activity ----------
  AddonSpec(
    id: 'discussionLadder',
    label: 'Discussion prompt ladder',
    icon: Icons.stairs_outlined,
    subtitle: 'Concrete → connection → stretch',
    category: AddonCategory.duringActivity,
    prompt: 'Three-step discussion prompt ladder. Three sections: '
        '1) heading "Concrete" — body is a question about what '
        'children directly observed during the activity. '
        '2) heading "Connection" — body links the activity to '
        "children's prior experience or feelings. "
        '3) heading "Stretch" — body is a "what would happen if..." '
        'or hypothetical question to push critical thinking.',
  ),
  AddonSpec(
    id: 'teacherScripts',
    label: 'Teacher scripts',
    icon: Icons.theater_comedy_outlined,
    subtitle: 'For tricky moments mid-activity',
    category: AddonCategory.duringActivity,
    prompt: 'Three short teacher scripts for tricky moments. Three '
        'sections: '
        '1) heading "When a child is frustrated" — body is 2-3 '
        'sentences a teacher can say to redirect calmly. '
        '2) heading "When a child finishes too fast" — body is 2-3 '
        'sentences offering a meaningful extension. '
        '3) heading "When a child refuses to participate" — body is '
        '2-3 sentences gently inviting them in without pressure.',
  ),
  AddonSpec(
    id: 'realTimePivots',
    label: 'Real-time pivots',
    icon: Icons.alt_route_outlined,
    subtitle: '3 quick rescues if it bombs',
    category: AddonCategory.duringActivity,
    prompt: 'Three quick activity-rescue pivots. Three sections; '
        'heading is the symptom (e.g. "Energy too low", "Too '
        'chaotic", "Children disengaged"); body is a 1-2 sentence '
        'rescue the teacher can pivot to in under a minute.',
  ),
  // ---------- After the activity ----------
  AddonSpec(
    id: 'reflectionCircle',
    label: 'Reflection circle',
    icon: Icons.replay_outlined,
    subtitle: '3-5 closing questions',
    category: AddonCategory.afterActivity,
    prompt: 'Generate 3-5 closing reflection questions specific to '
        'the activity. One section per question; heading is empty, '
        'body is the question.',
  ),
  AddonSpec(
    id: 'reviewGames',
    label: 'Review game',
    icon: Icons.quiz_outlined,
    subtitle: 'Movement-based, no paper',
    category: AddonCategory.afterActivity,
    prompt: 'One movement-based review game (e.g. thumbs-up/'
        'thumbs-down statements, stand-on-this-side polls, freeze-'
        'dance vocabulary). One section; heading is the game name; '
        'body explains how to play and gives 5-7 specific prompts/'
        'statements tied to the activity content.',
  ),
  AddonSpec(
    id: 'storyProblems',
    label: 'Story problems from data',
    icon: Icons.calculate_outlined,
    subtitle: "Math problems with kids' real numbers",
    category: AddonCategory.afterActivity,
    prompt: 'Three short math story problems that use placeholders '
        'from the activity (e.g. "[Child name]\'s heart rate went '
        'from [X] to [Y]…"). Use bracketed placeholders the teacher '
        'fills in with actual numbers. One section per problem; '
        'heading is empty, body is the problem.',
  ),
  AddonSpec(
    id: 'parentNote',
    label: 'Parent connection note',
    icon: Icons.family_restroom_outlined,
    subtitle: 'Short blurb to text or post tonight',
    category: AddonCategory.afterActivity,
    prompt: 'One short paragraph (2-3 sentences) a teacher can text '
        "or post to parents tonight. Mentions what the class did, "
        'then includes "Ask your child:" with 1-2 specific open-'
        'ended questions to extend learning at the dinner table. One '
        'section; heading is empty, body is the paragraph.',
  ),
  // ---------- Extensions ----------
  AddonSpec(
    id: 'dramaticPlay',
    label: 'Dramatic play scenario',
    icon: Icons.masks_outlined,
    subtitle: 'Pretend play with character roles',
    category: AddonCategory.extensions,
    prompt: 'A dramatic-play scenario related to the activity. Two '
        'sections: '
        '1) heading "Setup" — body describes the imaginary scene, '
        'props, and space layout. '
        '2) heading "Roles" — body lists 3-5 character roles, each '
        "with a one-line description of what that character does.",
  ),
  AddonSpec(
    id: 'branchingStory',
    label: 'Choose-your-adventure',
    icon: Icons.auto_stories_outlined,
    subtitle: 'Branching story tied to the theme',
    category: AddonCategory.extensions,
    prompt: "A short branching story tied to the activity's theme. "
        'Three sections: '
        '1) heading "Opening" — body sets up a character and their '
        'first choice (2-3 sentences ending with "What should they '
        'do?"). '
        '2) heading "Path A" — body continues if children pick A, '
        'ending with another choice. '
        '3) heading "Path B" — body continues if they pick B, also '
        'ending with another choice.',
  ),
  AddonSpec(
    id: 'movementGames',
    label: 'Movement game',
    icon: Icons.directions_run_outlined,
    subtitle: 'Simon Says / freeze dance / hopscotch',
    category: AddonCategory.extensions,
    prompt: "One movement game tied to the activity's content. One "
        'section; heading is the game name; body explains how to '
        'play and provides 5-7 specific prompts or rules tied to '
        'the content.',
  ),
  AddonSpec(
    id: 'songsChants',
    label: 'Song or chant',
    icon: Icons.music_note_outlined,
    subtitle: 'Custom for the theme',
    category: AddonCategory.extensions,
    prompt: 'A short song or chant (4-8 lines) tied to the activity. '
        'One section; heading is the suggested tune (e.g. "To the '
        'tune of Twinkle Twinkle"); body is the lyrics with each '
        'line on its own newline.',
  ),
  // ---------- Documentation ----------
  AddonSpec(
    id: 'observationPrompts',
    label: 'Observation prompts',
    icon: Icons.visibility_outlined,
    subtitle: 'Specific things to watch for',
    category: AddonCategory.documentation,
    prompt: '3-5 specific things a teacher should watch for during '
        'the activity (e.g. "Note which children use comparison '
        'words like \'bigger,\' \'longer\'"). One section per '
        'prompt; heading is empty, body is the prompt.',
  ),
  AddonSpec(
    id: 'portfolioSheet',
    label: 'Portfolio sheet',
    icon: Icons.draw_outlined,
    subtitle: 'Drawing prompt + sentence frames',
    category: AddonCategory.documentation,
    prompt: 'A portfolio reflection sheet for the activity. Two '
        'sections: '
        '1) heading "Drawing prompt" — body is a one-sentence prompt '
        'for what to draw. '
        '2) heading "Sentence frames" — body is 3-4 fill-in-the-'
        "blank sentence frames (e.g. \"Today I learned ___. I felt "
        '___ when ___.").',
  ),
  AddonSpec(
    id: 'skillsTracking',
    label: 'Skills tracking',
    icon: Icons.checklist_rtl_outlined,
    subtitle: 'Standards mapping for admin / parents',
    category: AddonCategory.documentation,
    prompt: '3-5 specific kindergarten/early-grade skills the '
        'activity touches on (e.g. "K.CC.A.2 — Counts forward '
        'beginning from a given number"). One section per skill; '
        'heading is the standard code or short name; body is a '
        'brief description of how the activity addresses it.',
  ),
  // ---------- Fun extras ----------
  AddonSpec(
    id: 'expertSimulation',
    label: 'Expert simulation',
    icon: Icons.school_outlined,
    subtitle: 'Character backstory + sample answers',
    category: AddonCategory.funStuff,
    prompt: 'An "ask the expert" simulation. Two sections: '
        '1) heading "Expert backstory" — body invents a relevant '
        'expert character (name, role, fun fact) the teacher can '
        'role-play. '
        '2) heading "Sample answers" — body lists 3-5 anticipated '
        "kid questions with the expert's answers, written in "
        'character.',
  ),
  AddonSpec(
    id: 'socialStory',
    label: 'Social story',
    icon: Icons.groups_outlined,
    subtitle: 'For tricky social situations',
    category: AddonCategory.funStuff,
    prompt: 'A short social story (4-6 short paragraphs) addressing '
        'a likely social challenge during the activity (sharing, '
        'taking turns, including others). One section; heading is '
        'empty; body is the story with each paragraph on its own '
        'newline.',
  ),
  AddonSpec(
    id: 'readingPassage',
    label: 'Reading passage',
    icon: Icons.menu_book_outlined,
    subtitle: 'Personalized story (bracketed names)',
    category: AddonCategory.funStuff,
    prompt: 'A short, kid-friendly reading passage (3-5 sentences) '
        'about doing the activity. Use bracketed placeholders '
        '[child name] / [child name 2] for kids the teacher fills '
        'in later. One section; heading is empty, body is the '
        'passage.',
  ),
  AddonSpec(
    id: 'weekCelebration',
    label: 'End-of-week celebration',
    icon: Icons.celebration_outlined,
    subtitle: '15-min "show what you know" event',
    category: AddonCategory.funStuff,
    prompt: "A 15-minute end-of-week celebration plan tied to the "
        "activity's theme. Three sections: "
        '1) heading "Setup" — body describes the format (gallery '
        "walk, quiz show, parent demo, etc.) and what's needed. "
        '2) heading "Schedule" — body breaks the 15 minutes into '
        '3-4 timed segments. '
        '3) heading "Wow moment" — body describes one memorable '
        'closing beat.',
  ),
];

// =====================================================================
// Result types + generator
// =====================================================================

class AddonSection {
  const AddonSection({required this.body, this.heading = ''});
  final String heading;
  final String body;
}

class AddonResult {
  const AddonResult({required this.spec, required this.sections});
  final AddonSpec spec;
  final List<AddonSection> sections;
}

Future<AddonResult> generateAddon({
  required AddonSpec spec,
  required AiActivity activity,
  AiActivityContext? planContext,
}) async {
  if (!OpenAiClient.isAvailable) {
    throw const _AddonsUnavailable();
  }

  final activityBlock = [
    if (activity.title.isNotEmpty) 'Activity title: ${activity.title}',
    if (activity.description.isNotEmpty)
      'Description: ${activity.description}',
    if (activity.objectives.isNotEmpty)
      'Objectives: ${activity.objectives}',
    if (activity.steps.isNotEmpty) 'Steps:\n${activity.steps}',
    if (activity.materials.isNotEmpty)
      'Materials: ${activity.materials}',
  ].join('\n\n');

  final ctxLine = planContext?.promptLine ?? '';

  final body = await OpenAiClient.chat({
    'model': 'gpt-4o-mini',
    // Slightly higher temperature than the card generator — addons
    // are creative supplements where some variability is desirable.
    'temperature': 0.6,
    'response_format': {'type': 'json_object'},
    'messages': [
      {'role': 'system', 'content': _systemPrompt},
      {
        'role': 'user',
        'content': [
          if (ctxLine.isNotEmpty) ctxLine,
          activityBlock,
          spec.prompt,
        ].where((s) => s.isNotEmpty).join('\n\n'),
      },
    ],
  });

  final choices = body['choices'] as List<dynamic>?;
  if (choices == null || choices.isEmpty) {
    throw const _AddonsEmpty();
  }
  final message = (choices.first as Map<String, dynamic>)['message']
      as Map<String, dynamic>?;
  final content = message?['content'] as String?;
  if (content == null || content.trim().isEmpty) {
    throw const _AddonsEmpty();
  }

  final parsed = jsonDecode(content) as Map<String, dynamic>;
  final sectionsJson = parsed['sections'] as List<dynamic>? ?? const [];
  final sections = <AddonSection>[];
  for (final raw in sectionsJson) {
    if (raw is! Map<String, dynamic>) continue;
    final heading = (raw['heading'] as String? ?? '').trim();
    final body = (raw['body'] as String? ?? '').trim();
    if (body.isEmpty) continue;
    sections.add(AddonSection(heading: heading, body: body));
  }
  return AddonResult(spec: spec, sections: sections);
}

class _AddonsUnavailable implements Exception {
  const _AddonsUnavailable();
  @override
  String toString() => 'AI: Sign in to generate add-ons.';
}

class _AddonsEmpty implements Exception {
  const _AddonsEmpty();
  @override
  String toString() => 'AI: The model returned no add-on content.';
}

// =====================================================================
// Inline section — embed inside an existing sheet's scroll body
// =====================================================================

/// Inline add-ons section. Drop this at the bottom of any sheet
/// that's already showing an activity (the formatted preview, the
/// editor, etc.) and it self-manages picker → loading → result
/// state inline. No separate modal — keeps the scroll context with
/// the activity above so the user can reference it.
///
/// **Persistence (v58).** When the caller passes [previouslyGenerated]
/// (the persisted add-ons map for the activity) and an [onGenerated]
/// callback, generated results are saved on the activity row through
/// the callback. Reopening the sheet shows already-generated add-ons
/// as filled tiles the user can re-open or regenerate. Sandbox
/// callsites (the experiment screen) leave both null and fall back
/// to the old in-memory behavior.
class AiActivityAddonsSection extends StatefulWidget {
  const AiActivityAddonsSection({
    required this.activity,
    this.planContext,
    this.previouslyGenerated,
    this.onGenerated,
    this.onRemoved,
    this.onActiveChanged,
    super.key,
  });

  final AiActivity activity;
  final AiActivityContext? planContext;

  /// Persisted add-ons for this activity, keyed by spec id, with
  /// each entry the same `[{heading, body}, ...]` shape the
  /// repository decodes. When non-null, the picker shows filled
  /// tiles for already-generated entries.
  final Map<String, List<Map<String, String>>>? previouslyGenerated;

  /// Called after a successful generate (or regenerate). Receives
  /// the spec id + sections payload — caller persists. When null,
  /// generation is in-memory only (sandbox).
  final void Function(String specId, List<AddonSection> sections)? onGenerated;

  /// Called when the user explicitly removes a previously-generated
  /// add-on. When null, removal isn't surfaced as an action.
  final void Function(String specId)? onRemoved;

  /// Fires when the section transitions between "showing the picker"
  /// (false) and "loading or showing a generated result" (true).
  /// Parent sheets use this to collapse adjacent sections (objectives,
  /// steps, materials) so an open add-on has full vertical space —
  /// otherwise the result content gets squeezed below the activity's
  /// own metadata. Sandbox callsites can leave this null.
  final ValueChanged<bool>? onActiveChanged;

  @override
  State<AiActivityAddonsSection> createState() =>
      _AiActivityAddonsSectionState();
}

class _AiActivityAddonsSectionState
    extends State<AiActivityAddonsSection> {
  AddonSpec? _generating;
  AddonResult? _result;
  String? _error;

  /// True iff something other than the picker is on screen — either
  /// a result is showing or we're mid-generation. The parent uses
  /// this to hide its own sections so the add-on view has air.
  bool get _isActive => _generating != null || _result != null;

  @override
  void initState() {
    super.initState();
    // Auto-open the first saved add-on when the section mounts, so
    // a returning user lands on their saved content directly. We
    // set `_result` straight on `this` (NOT through setState) —
    // initState runs before the first build, so the first frame
    // already renders the result; the picker is never shown.
    //
    // The parent-side `onActiveChanged(true)` notification still
    // has to defer to a post-frame callback because firing it
    // during initState would call setState on the parent before
    // its first build completes. One frame later, the parent
    // collapses its metadata sections (objectives / steps /
    // materials / link). The picker → result flicker that the
    // earlier post-frame-only version had is gone — the only
    // post-frame work now is the parent's collapse.
    final saved = widget.previouslyGenerated;
    if (saved != null && saved.isNotEmpty) {
      final firstSpecId = saved.keys.first;
      final spec = addonSpecs.firstWhere(
        (s) => s.id == firstSpecId,
        orElse: () => addonSpecs.first,
      );
      if (spec.id == firstSpecId) {
        _result = AddonResult(
          spec: spec,
          sections: [
            for (final m in saved[firstSpecId]!)
              AddonSection(
                heading: m['heading'] ?? '',
                body: m['body'] ?? '',
              ),
          ],
        );
        // Notify the parent so it can collapse metadata. Deferred
        // so we don't call setState on it before its first build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          widget.onActiveChanged?.call(true);
        });
      }
    }
  }

  /// Wraps `setState` so any change to `_generating` / `_result` is
  /// followed by a parent notification when the active flag flips.
  /// Captures the pre-mutation flag, lets the mutation run, then
  /// fires the callback only on transitions.
  void _setStateAndNotify(VoidCallback fn) {
    final wasActive = _isActive;
    setState(fn);
    final nowActive = _isActive;
    if (wasActive != nowActive) {
      widget.onActiveChanged?.call(nowActive);
    }
  }

  Future<void> _generate(AddonSpec spec) async {
    _setStateAndNotify(() {
      _generating = spec;
      _error = null;
      _result = null;
    });
    try {
      final result = await generateAddon(
        spec: spec,
        activity: widget.activity,
        planContext: widget.planContext,
      );
      if (!mounted) return;
      // Persist if the caller wired it up.
      widget.onGenerated?.call(spec.id, result.sections);
      _setStateAndNotify(() {
        _generating = null;
        _result = result;
      });
    } on Object catch (e) {
      if (!mounted) return;
      _setStateAndNotify(() {
        _generating = null;
        // Drop the exception class prefix so users see plain English.
        _error = e.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), '');
      });
    }
  }

  /// Open a previously-generated add-on without re-running the
  /// model. Reconstructs an [AddonResult] from the persisted JSON.
  void _openPersisted(AddonSpec spec, List<Map<String, String>> raw) {
    final sections = [
      for (final m in raw)
        AddonSection(
          heading: m['heading'] ?? '',
          body: m['body'] ?? '',
        ),
    ];
    _setStateAndNotify(() {
      _result = AddonResult(spec: spec, sections: sections);
      _error = null;
    });
  }

  void _backToPicker() {
    _setStateAndNotify(() {
      _result = null;
      _error = null;
    });
  }

  void _remove(AddonSpec spec) {
    widget.onRemoved?.call(spec.id);
    if (_result?.spec.id == spec.id) {
      _setStateAndNotify(() => _result = null);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_generating != null) {
      return _InlineLoading(spec: _generating!);
    }
    if (_result != null) {
      final hasPersisted =
          widget.previouslyGenerated?.containsKey(_result!.spec.id) ?? false;
      return _InlineResult(
        result: _result!,
        onBack: _backToPicker,
        onRegenerate: () => _generate(_result!.spec),
        onRemove: hasPersisted && widget.onRemoved != null
            ? () => _remove(_result!.spec)
            : null,
      );
    }
    return _InlinePicker(
      error: _error,
      onPicked: _generate,
      previouslyGenerated: widget.previouslyGenerated,
      onOpenPersisted: _openPersisted,
      persisted: widget.previouslyGenerated != null,
    );
  }
}

class _InlinePicker extends StatelessWidget {
  const _InlinePicker({
    required this.error,
    required this.onPicked,
    required this.persisted,
    this.previouslyGenerated,
    this.onOpenPersisted,
  });

  final String? error;
  final ValueChanged<AddonSpec> onPicked;

  /// True when the parent passed an `onGenerated` callback — i.e.
  /// the caller is wiring real persistence. Drives the subtitle copy
  /// (no more "sandbox only, nothing saves" lie).
  final bool persisted;

  final Map<String, List<Map<String, String>>>? previouslyGenerated;
  final void Function(AddonSpec spec, List<Map<String, String>> raw)?
      onOpenPersisted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final generated = previouslyGenerated ?? const {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text('Add-ons', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          persisted
              ? 'AI-generated supplements. Once you tap one and it '
                  'generates, the result saves with this activity — '
                  'open it again later without re-running the model.'
              : 'AI-generated supplements. Tap one to see what the '
                  'model comes up with — sandbox only, nothing saves.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer
                  .withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
        for (final cat in AddonCategory.values) ...[
          const SizedBox(height: AppSpacing.md),
          _CategoryHeader(label: cat.label),
          const SizedBox(height: AppSpacing.xs),
          for (final spec in addonSpecs.where((s) => s.category == cat))
            _AddonTile(
              spec: spec,
              filled: generated.containsKey(spec.id),
              onTap: () {
                final saved = generated[spec.id];
                if (saved != null && onOpenPersisted != null) {
                  onOpenPersisted!(spec, saved);
                } else {
                  onPicked(spec);
                }
              },
            ),
        ],
      ],
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _AddonTile extends StatelessWidget {
  const _AddonTile({
    required this.spec,
    required this.onTap,
    this.filled = false,
  });
  final AddonSpec spec;
  final VoidCallback onTap;

  /// True when the caller passed a previously-generated result for
  /// this spec — render with a "saved" check and a tinted icon
  /// background so the user can see at a glance which add-ons have
  /// already been generated for this activity.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: filled
                    ? cs.primaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(
                spec.icon,
                size: 22,
                color: filled ? cs.onPrimaryContainer : cs.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          spec.label,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (filled) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Icon(
                          Icons.check_circle,
                          size: 14,
                          color: cs.primary,
                        ),
                      ],
                    ],
                  ),
                  Text(
                    filled ? 'Saved — tap to view' : spec.subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineLoading extends StatelessWidget {
  const _InlineLoading({required this.spec});
  final AddonSpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(spec.icon, size: 28, color: theme.colorScheme.primary),
          const SizedBox(height: AppSpacing.sm),
          Text(spec.label, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.md),
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Generating…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineResult extends StatelessWidget {
  const _InlineResult({
    required this.result,
    required this.onBack,
    required this.onRegenerate,
    this.onRemove,
  });

  final AddonResult result;
  final VoidCallback onBack;
  final VoidCallback onRegenerate;

  /// When non-null, render a delete affordance that drops the
  /// persisted add-on. Only relevant for callsites that wired
  /// persistence (the formatted sheet + editor); sandbox callsites
  /// have nothing to delete.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back to add-ons',
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(result.spec.icon, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                result.spec.label,
                style: theme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onRemove != null)
              IconButton(
                tooltip: 'Remove this add-on',
                icon: const Icon(Icons.delete_outline),
                onPressed: onRemove,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
              ),
            IconButton(
              tooltip: 'Regenerate',
              icon: const Icon(Icons.refresh),
              onPressed: onRegenerate,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (result.sections.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text(
              'The model returned no sections — try Regenerate.',
              style: theme.textTheme.bodyMedium,
            ),
          )
        else
          for (var i = 0; i < result.sections.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == result.sections.length - 1
                    ? 0
                    : AppSpacing.md,
              ),
              child: _SectionView(section: result.sections[i]),
            ),
      ],
    );
  }
}

class _SectionView extends StatelessWidget {
  const _SectionView({required this.section});
  final AddonSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (section.heading.isNotEmpty) ...[
          Text(
            section.heading,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        Text(
          section.body,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
        ),
      ],
    );
  }
}
