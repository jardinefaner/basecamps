import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/forms/parent_concern/parent_concern_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class ParentConcernNotesScreen extends ConsumerWidget {
  const ParentConcernNotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(parentConcernNotesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Parent concern notes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            context.push('/more/forms/parent-concern/new'),
        icon: const Icon(Icons.edit_note_outlined),
        label: const Text('New note'),
      ),
      body: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (notes) {
          if (notes.isEmpty) return const _EmptyState();
          return ListView.separated(
            padding: const EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              top: AppSpacing.md,
              bottom: AppSpacing.xxxl * 2,
            ),
            itemCount: notes.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, i) => _NoteTile(note: notes[i]),
          );
        },
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note});

  final ParentConcernNote note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = note.childNames.trim().isEmpty
        ? '(Unnamed child)'
        : note.childNames;
    final subtitleParts = <String>[];
    if (note.parentName.trim().isNotEmpty) {
      subtitleParts.add(note.parentName);
    }
    if (note.concernDate != null) {
      subtitleParts.add(DateFormat.MMMd().add_y().format(note.concernDate!));
    }

    final signed = note.staffSignature != null &&
        note.staffSignature!.trim().isNotEmpty;

    return AppCard(
      onTap: () =>
          context.push('/more/forms/parent-concern/${note.id}'),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 48,
            decoration: BoxDecoration(
              color: signed
                  ? theme.colorScheme.primary
                  : theme.colorScheme.tertiary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (subtitleParts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitleParts.join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (note.concernDescription.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      note.concernDescription,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  signed ? 'Signed' : 'Draft',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
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
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No concern notes yet',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Log a parent or guardian concern — the form walks you '
              'through what happened, what you did, and next steps.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
