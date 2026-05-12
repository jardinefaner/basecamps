// Survey list screen — the home of the BASECamp Student Survey
// tool. Shows every survey configured on this device for the
// active program (cloud-synced), with a primary "+ New survey"
// action. Tapping a card opens the results sheet for that
// survey; the kiosk is launched from there via "Start kiosk."
// Long-press / "⋮ → Delete survey" soft-deletes the row.

import 'package:basecamp/features/surveys/survey_models.dart';
import 'package:basecamp/features/surveys/survey_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class SurveyListScreen extends ConsumerWidget {
  const SurveyListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final surveys = ref.watch(surveysListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Surveys'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Set up a kiosk for a classroom. Children answer with marble drops; '
                'a teacher exits with a 4-digit PIN.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
      body: surveys.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              'Could not load surveys: $e',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ),
        data: (list) => list.isEmpty
            ? _EmptyState(theme: theme)
            : _SurveyList(surveys: list, theme: theme),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/surveys/new'),
        icon: const Icon(Icons.add),
        label: const Text('New survey'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.poll_outlined,
              size: 64,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No surveys yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tap “New survey” to set up a kiosk for a classroom.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SurveyList extends StatelessWidget {
  const _SurveyList({required this.surveys, required this.theme});

  final List<SurveyConfig> surveys;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxxl, // bottom slack so FAB doesn't overlap
      ),
      itemCount: surveys.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) => _SurveyCard(
        survey: surveys[i],
        theme: theme,
      ),
    );
  }
}

class _SurveyCard extends ConsumerWidget {
  const _SurveyCard({required this.survey, required this.theme});

  final SurveyConfig survey;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFmt = DateFormat.yMMMd().add_jm();
    return InkWell(
      borderRadius: AppSpacing.cardBorderRadius,
      // Tap a card → results sheet for this survey. The kiosk is
      // launched via the "Start kiosk" action on the results
      // screen so a teacher always sees what's been captured
      // before handing the device to the next child.
      onTap: () => context.push('/surveys/${survey.id}'),
      onLongPress: () => _confirmDelete(context, ref),
      child: Container(
        padding: AppSpacing.cardPadding,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: AppSpacing.cardBorderRadius,
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    survey.siteName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${survey.classroom} · ${survey.ageBand.label}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      _MetaChip(
                        icon: Icons.help_outline,
                        text: '${survey.questions.length} questions',
                      ),
                      _MetaChip(
                        icon: Icons.record_voice_over_outlined,
                        text: survey.voice.label,
                      ),
                      _MetaChip(
                        icon: Icons.access_time,
                        text: dateFmt.format(survey.createdAt.toLocal()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: Icon(
                Icons.more_vert,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              onSelected: (v) {
                if (v == 'delete') _confirmDelete(context, ref);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Delete survey'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this survey?'),
        content: Text(
          '${survey.siteName} · ${survey.classroom} will be hidden from '
          'the list. Existing kiosk sessions stay in the results sheet '
          'so historical data is preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(surveyRepositoryProvider).softDelete(survey.id);
    messenger.showSnackBar(
      SnackBar(content: Text('Deleted ${survey.siteName}')),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xs),
          Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
