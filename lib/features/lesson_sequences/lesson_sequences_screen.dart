import 'package:basecamp/features/lesson_sequences/lesson_sequences_repository.dart';
import 'package:basecamp/features/lesson_sequences/widgets/edit_lesson_sequence_sheet.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// `/more/sequences` — named ordered bundles of library cards. Each
/// sequence opens to a detail screen where the teacher can reorder
/// items, add new ones, and "use this sequence" to spread the items
/// across consecutive weekdays.
class LessonSequencesScreen extends ConsumerWidget {
  const LessonSequencesScreen({super.key});

  Future<void> _openCreateSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const EditLessonSequenceSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sequencesAsync = ref.watch(lessonSequencesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Lesson sequences')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreateSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Sequence'),
      ),
      body: sequencesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (seqs) {
          if (seqs.isEmpty) {
            return _EmptyState(onAdd: () => _openCreateSheet(context));
          }
          return ListView.separated(
            padding: const EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              top: AppSpacing.md,
              bottom: AppSpacing.xxxl * 2,
            ),
            itemCount: seqs.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, i) {
              final s = seqs[i];
              return _SequenceTile(
                name: s.name,
                description: s.description,
                onTap: () => context.push('/more/sequences/${s.id}'),
              );
            },
          );
        },
      ),
    );
  }
}

class _SequenceTile extends ConsumerWidget {
  const _SequenceTile({
    required this.name,
    required this.description,
    required this.onTap,
  });

  final String name;
  final String? description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.format_list_numbered_outlined,
              color: theme.colorScheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.titleMedium),
                if (description != null && description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      description!,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

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
              Icons.format_list_numbered_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No lesson sequences yet',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Create one to bundle activities that go together — '
              'a "Bug Week" unit, a kindness series, or any set of '
              'library cards you want to run in order.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add sequence'),
            ),
          ],
        ),
      ),
    );
  }
}
