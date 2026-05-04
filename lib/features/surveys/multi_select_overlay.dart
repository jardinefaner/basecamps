// Multi-select activity question overlay (Slice 3) — replaces
// the slice-2 "Coming next slice" placeholder for questions of
// type `multiSelect`.
//
// UX (per the kiosk design walkthrough):
//   * 7 large cards with simple line-art icons + activity text
//   * Tap to "stick" — card flips to show the survey accent color
//     and a checkmark; multiple selections allowed
//   * "These are mine!" button at the bottom commits and advances
//   * Skip button (right next to commit) for kids who didn't do
//     any of the listed activities
//
// Designed to sit ON TOP OF the existing marble world (which
// continues to animate behind it). The kid still gets the
// chibi + jar context; just the input mode changes for this one
// question.

import 'dart:async';

import 'package:basecamp/features/surveys/survey_audio_service.dart';
import 'package:basecamp/features/surveys/survey_models.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MultiSelectQuestionOverlay extends ConsumerStatefulWidget {
  const MultiSelectQuestionOverlay({
    required this.question,
    required this.voice,
    required this.audioMode,
    required this.onCommit,
    required this.onSkip,
    super.key,
  });

  /// The question being answered. Carries the prompt + the 7
  /// option cards.
  final SurveyQuestion question;

  /// Voice + audio mode plumbed through so we can read the
  /// prompt aloud + (optionally) read each option name on tap.
  final SurveyVoice voice;
  final SurveyAudioMode audioMode;

  /// Called when the kid hits "These are mine!" with the list of
  /// selected option ids (may be empty if they tapped commit
  /// without picking anything — same effect as Skip).
  final ValueChanged<List<String>> onCommit;

  /// Called when the kid hits Skip (no answer recorded).
  final VoidCallback onSkip;

  @override
  ConsumerState<MultiSelectQuestionOverlay> createState() =>
      _MultiSelectQuestionOverlayState();
}

class _MultiSelectQuestionOverlayState
    extends ConsumerState<MultiSelectQuestionOverlay> {
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    // Read the prompt aloud once when the overlay appears,
    // matching the marble world's per-question audio cue.
    if (widget.audioMode != SurveyAudioMode.silent) {
      final audio = ref.read(surveyAudioServiceProvider);
      unawaited(audio.playQuestion(widget.voice, widget.question.prompt));
    }
  }

  void _toggle(SurveyActivityOption option) {
    setState(() {
      if (_selected.contains(option.id)) {
        _selected.remove(option.id);
      } else {
        _selected.add(option.id);
      }
    });
    // Optionally read the option label on tap for kids who can't
    // read yet — same audio mode gating as the prompt.
    if (widget.audioMode != SurveyAudioMode.silent) {
      final audio = ref.read(surveyAudioServiceProvider);
      unawaited(audio.playTransition(widget.voice, option.label));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface.withValues(alpha: 0.97),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              // Prompt header — same warmth as the question plate
              // in the marble world but full-width here.
              Text(
                widget.question.prompt,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Tap the ones that fit. You can pick more than one.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 280,
                    childAspectRatio: 1.6,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                  ),
                  itemCount: widget.question.options.length,
                  itemBuilder: (context, i) {
                    final option = widget.question.options[i];
                    return _ActivityCard(
                      option: option,
                      selected: _selected.contains(option.id),
                      onTap: () => _toggle(option),
                      iconForId: multiSelectIconForId,
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onSkip,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: const Text('Skip'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () =>
                          widget.onCommit(_selected.toList(growable: false)),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: Text(
                        _selected.isEmpty
                            ? 'These are mine!'
                            : 'These are mine! '
                                '(${_selected.length})',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Per-activity icon — keyed off the canonical option id so the
/// asset is stable across renames of the label text. Falls back
/// to a generic check icon for unknown ids (e.g. teacher-edited
/// custom activities). Exported so the results sheet's chip
/// cluster can reuse the same iconography.
IconData multiSelectIconForId(String id) {
  switch (id) {
    case 'act_supplies':
      return Icons.inventory_2_outlined;
    case 'act_invited_friends':
      return Icons.group_add_outlined;
    case 'act_line_leader':
      return Icons.flag_outlined;
    case 'act_chose_group':
      return Icons.groups_outlined;
    case 'act_helped_friend':
      return Icons.favorite_outline;
    case 'act_shared':
      return Icons.handshake_outlined;
    case 'act_reminded_rules':
      return Icons.menu_book_outlined;
    default:
      return Icons.check_circle_outline;
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.option,
    required this.selected,
    required this.onTap,
    required this.iconForId,
  });

  final SurveyActivityOption option;
  final bool selected;
  final VoidCallback onTap;
  final IconData Function(String) iconForId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surface,
        border: Border.all(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: selected ? 2 : 0.5,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected
                        ? theme.colorScheme.primary
                            .withValues(alpha: 0.12)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    iconForId(option.id),
                    size: 24,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    option.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: selected
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                AnimatedScale(
                  scale: selected ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  child: Icon(
                    Icons.check_circle,
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
