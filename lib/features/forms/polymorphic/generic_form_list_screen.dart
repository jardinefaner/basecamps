import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/forms/polymorphic/form_definition.dart';
import 'package:basecamp/features/forms/polymorphic/form_submission_repository.dart';
import 'package:basecamp/features/forms/polymorphic/generic_form_screen.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// List screen for all submissions of a given form type. Title +
/// subtitle from the definition; FAB creates a new draft.
///
/// Follow-up form types (behavior_monitoring, etc.) hide the FAB —
/// those get created from their parent form's detail screen, never
/// standalone. The list still shows every submission so teachers can
/// scan activity.
class GenericFormListScreen extends ConsumerWidget {
  const GenericFormListScreen({required this.definition, super.key});

  final FormDefinition definition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final submissionsAsync =
        ref.watch(formSubmissionsByTypeProvider(definition.typeKey));
    final standalone = definition.parentTypeKey == null;
    return Scaffold(
      appBar: AppBar(title: Text(definition.shortTitle)),
      floatingActionButton: standalone
          ? FloatingActionButton.extended(
              onPressed: () => _newSubmission(context),
              icon: const Icon(Icons.add),
              label: const Text('New'),
            )
          : null,
      body: submissionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (rows) {
          if (rows.isEmpty) {
            return _Empty(
              definition: definition,
              standalone: standalone,
              onNew: () => _newSubmission(context),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              top: AppSpacing.md,
              bottom: AppSpacing.xxxl * 2,
            ),
            itemCount: rows.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, i) {
              final row = rows[i];
              return _SubmissionTile(
                submission: row,
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => GenericFormScreen(
                      definition: definition,
                      submissionId: row.id,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _newSubmission(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => GenericFormScreen(definition: definition),
      ),
    );
  }
}

class _SubmissionTile extends StatelessWidget {
  const _SubmissionTile({required this.submission, required this.onTap});

  final FormSubmission submission;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = decodeFormData(submission);
    final status = FormStatus.fromDb(submission.status);
    final stamp = submission.submittedAt ?? submission.createdAt;
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _StatusChip(status: status),
              const SizedBox(width: AppSpacing.sm),
              Text(
                DateFormat.yMMMd().add_jm().format(stamp),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _previewTitle(data),
            style: theme.textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (_previewSubtitle(data) != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _previewSubtitle(data)!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  /// Best-effort row title — takes whichever of a few conventional
  /// keys is present. Form definitions can evolve this later (a
  /// `titleKey` on FormDefinition) if the defaults stop fitting.
  String _previewTitle(Map<String, dynamic> data) {
    for (final k in const [
      'vehicle_make_model',
      'child_names',
      'concern_description',
      'notes',
    ]) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '(untitled)';
  }

  String? _previewSubtitle(Map<String, dynamic> data) {
    final v = data['driver_name'] ?? data['supervisor'];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final FormStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, bg, fg) = switch (status) {
      FormStatus.draft => (
          'DRAFT',
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurfaceVariant,
        ),
      FormStatus.active => (
          'ACTIVE',
          theme.colorScheme.tertiaryContainer,
          theme.colorScheme.onTertiaryContainer,
        ),
      FormStatus.completed => (
          'COMPLETED',
          theme.colorScheme.secondaryContainer,
          theme.colorScheme.onSecondaryContainer,
        ),
      FormStatus.archived => (
          'ARCHIVED',
          theme.colorScheme.surfaceContainerLow,
          theme.colorScheme.onSurfaceVariant,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.definition,
    required this.standalone,
    required this.onNew,
  });

  final FormDefinition definition;
  final bool standalone;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              definition.icon,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No ${definition.shortTitle.toLowerCase()} yet',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              definition.subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (standalone) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onNew,
                icon: const Icon(Icons.add),
                label: Text('New ${definition.shortTitle.toLowerCase()}'),
              ),
            ] else ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Created as a follow-up from a parent form.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
