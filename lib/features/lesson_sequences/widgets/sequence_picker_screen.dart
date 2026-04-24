import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/lesson_sequences/lesson_sequences_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fullscreen picker used when inserting a sequence into a week.
/// Pops with the selected [LessonSequence], or `null` when the
/// teacher backs out.
class SequencePickerScreen extends ConsumerWidget {
  const SequencePickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seqsAsync = ref.watch(lessonSequencesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Pick a sequence')),
      body: seqsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (seqs) {
          if (seqs.isEmpty) {
            return _EmptyPicker(onBack: () => Navigator.of(context).pop());
          }
          return ListView.separated(
            padding: const EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              top: AppSpacing.md,
              bottom: AppSpacing.xxxl,
            ),
            itemCount: seqs.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, i) {
              final s = seqs[i];
              return _SequenceTile(
                sequence: s,
                onTap: () => Navigator.of(context).pop(s),
              );
            },
          );
        },
      ),
    );
  }
}

class _SequenceTile extends StatelessWidget {
  const _SequenceTile({required this.sequence, required this.onTap});

  final LessonSequence sequence;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
                Text(sequence.name, style: theme.textTheme.titleMedium),
                if (sequence.description != null &&
                    sequence.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      sequence.description!,
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

class _EmptyPicker extends StatelessWidget {
  const _EmptyPicker({required this.onBack});

  final VoidCallback onBack;

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
              'Create one from the Lesson sequences section first.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton(
              onPressed: onBack,
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}
