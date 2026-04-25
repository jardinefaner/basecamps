import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/export/export_actions.dart';
import 'package:basecamp/features/lesson_sequences/lesson_sequences_repository.dart';
import 'package:basecamp/features/lesson_sequences/sequence_conflict_check.dart';
import 'package:basecamp/features/lesson_sequences/widgets/edit_lesson_sequence_sheet.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/widgets/library_picker_screen.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/responsive.dart';
import 'package:basecamp/ui/undo_delete.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// `/more/sequences/:id` — ordered list of library cards inside a
/// sequence. Reorder via drag handles (ReorderableListView); add new
/// items via the library picker; remove with undo. A trailing "Use
/// this sequence" action spreads the items across consecutive
/// weekdays from a chosen start date.
class LessonSequenceDetailScreen extends ConsumerWidget {
  const LessonSequenceDetailScreen({required this.sequenceId, super.key});

  final String sequenceId;

  Future<void> _openEditSheet(
    BuildContext context,
    LessonSequence sequence,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditLessonSequenceSheet(sequence: sequence),
    );
  }

  Future<void> _addItem(BuildContext context, WidgetRef ref) async {
    final picked = await Navigator.of(context).push<ActivityLibraryData>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const LibraryPickerScreen(),
      ),
    );
    if (picked == null) return;
    await ref.read(lessonSequencesRepositoryProvider).addItem(
          sequenceId: sequenceId,
          libraryItemId: picked.id,
        );
  }

  Future<void> _removeItem(
    BuildContext context,
    WidgetRef ref,
    SequenceItemWithLibrary row,
  ) async {
    await confirmDeleteWithUndo(
      context: context,
      title: 'Remove "${row.library.title}"?',
      message: 'The library card itself stays. Only this sequence '
          'entry is removed.',
      onDelete: () async {
        final repo = ref.read(lessonSequencesRepositoryProvider);
        await repo.deleteItem(row.item.id);
      },
      undoLabel: '"${row.library.title}" removed from sequence',
      onUndo: () async {
        final repo = ref.read(lessonSequencesRepositoryProvider);
        await repo.restoreItem(row.item);
      },
    );
  }

  Future<void> _onReorder(
    WidgetRef ref,
    List<SequenceItemWithLibrary> rows,
    int oldIndex,
    int newIndex,
  ) async {
    // ReorderableListView passes newIndex *before* the remove-and-insert
    // — when dragging down, newIndex is off-by-one high. Normalize
    // first so the resulting ordering matches what the user sees.
    var target = newIndex;
    if (newIndex > oldIndex) target -= 1;
    final ids = rows.map((r) => r.item.id).toList();
    final moved = ids.removeAt(oldIndex);
    ids.insert(target, moved);
    await ref
        .read(lessonSequencesRepositoryProvider)
        .reorderItems(sequenceId, ids);
  }

  Future<void> _useSequence(
    BuildContext context,
    WidgetRef ref,
    List<SequenceItemWithLibrary> rows,
  ) async {
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add at least one activity before using the sequence.',
          ),
        ),
      );
      return;
    }
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Pick a start date',
    );
    if (picked == null || !context.mounted) return;

    final scheduleRepo = ref.read(scheduleRepositoryProvider);
    final weekdays = _consecutiveWeekdays(picked, rows.length);

    // Build proposed entries once, use them both for conflict
    // pre-check and for the eventual writes. Keeps the two paths in
    // lock-step so the warning dialog can't lie.
    final proposals = <ProposedSequenceEntry>[
      for (var i = 0; i < rows.length; i++)
        _proposalFor(rows[i].library, weekdays[i], i + 1),
    ];

    // Fetch the current schedule for every target date in parallel.
    final existingByDate = <DateTime, List<ScheduleItem>>{};
    for (final p in proposals) {
      final items =
          await scheduleRepo.watchScheduleForDate(p.date).first;
      existingByDate[p.date] = items;
    }

    final conflicts = detectSequenceConflicts(
      proposals: proposals,
      existingByDate: existingByDate,
    );

    if (conflicts.isNotEmpty) {
      if (!context.mounted) return;
      final proceed = await _showConflictDialog(context, conflicts);
      if (proceed != true) return;
      if (!context.mounted) return;
    }

    var scheduled = 0;
    for (final p in proposals) {
      await scheduleRepo.addOneOffEntry(
        date: p.date,
        startTime: p.startTime,
        endTime: p.endTime,
        title: p.title,
        adultId: p.adultId,
        location: p.location,
        notes: p.notes,
        sourceLibraryItemId: p.sourceLibraryItemId,
        sourceUrl: p.sourceUrl,
      );
      scheduled += 1;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Scheduled $scheduled '
          '${scheduled == 1 ? 'activity' : 'activities'} starting '
          '${DateFormat.MMMd().format(weekdays.first)}.',
        ),
      ),
    );
  }

  static ProposedSequenceEntry _proposalFor(
    ActivityLibraryData lib,
    DateTime date,
    int position,
  ) {
    final durationMin = lib.defaultDurationMin ?? 45;
    const startMinutes = 10 * 60; // 10:00am — same default as the writer.
    final endMinutes = startMinutes + durationMin;
    return ProposedSequenceEntry(
      position: position,
      date: date,
      startTime: _hhmm(startMinutes),
      endTime: _hhmm(endMinutes),
      title: lib.title,
      adultId: lib.adultId,
      location: lib.location,
      notes: lib.notes,
      sourceLibraryItemId: lib.id,
      sourceUrl: lib.sourceUrl,
    );
  }

  /// Shows the pre-check dialog listing proposed entries that clash
  /// with existing schedule. Returns true if the teacher chooses to
  /// schedule anyway; false / null when they cancel.
  Future<bool?> _showConflictDialog(
    BuildContext context,
    List<SequenceConflict> conflicts,
  ) {
    // Flatten to bullets. Cap at 5, with an "... and N more" suffix
    // when the list overflows.
    const maxBullets = 5;
    final bullets = <String>[];
    for (final c in conflicts) {
      final dayLabel = 'Day ${c.position}';
      for (final reason in c.reasons) {
        bullets.add("$dayLabel: '${c.title}' $reason");
      }
    }
    final shown = bullets.take(maxBullets).toList();
    final overflow = bullets.length - shown.length;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scheduling this sequence will create conflicts:'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text('• $line'),
                ),
              if (overflow > 0)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    '… and $overflow more',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Schedule anyway'),
          ),
        ],
      ),
    );
  }

  /// Returns [count] consecutive weekday dates starting at [start]
  /// (moving forward to Monday if start lands on Sat/Sun). Weekends
  /// are always skipped.
  static List<DateTime> _consecutiveWeekdays(DateTime start, int count) {
    final result = <DateTime>[];
    var cursor = DateTime(start.year, start.month, start.day);
    while (cursor.weekday > 5) {
      cursor = cursor.add(const Duration(days: 1));
    }
    while (result.length < count) {
      result.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
      while (cursor.weekday > 5) {
        cursor = cursor.add(const Duration(days: 1));
      }
    }
    return result;
  }

  static String _hhmm(int totalMinutes) {
    final h = (totalMinutes ~/ 60).toString().padLeft(2, '0');
    final m = (totalMinutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sequenceAsync = ref.watch(lessonSequenceProvider(sequenceId));
    final itemsAsync =
        ref.watch(lessonSequenceItemsJoinedProvider(sequenceId));

    return Scaffold(
      appBar: AppBar(
        title: sequenceAsync.when(
          loading: () => const Text('Sequence'),
          error: (_, _) => const Text('Sequence'),
          data: (s) => Text(s?.name ?? 'Sequence'),
        ),
        actions: [
          IconButton(
            tooltip: 'Export',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => exportSequence(context, ref, sequenceId),
          ),
          sequenceAsync.maybeWhen(
            data: (s) => s == null
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Edit sequence',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _openEditSheet(context, s),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      // On wide viewports the "Use this sequence" action lives in the
      // right-hand metadata panel instead — a FAB would double up. We
      // still expose it as a FAB on narrow screens.
      floatingActionButton: Breakpoints.isWide(context)
          ? null
          : itemsAsync.maybeWhen(
              data: (rows) => FloatingActionButton.extended(
                onPressed: rows.isEmpty
                    ? null
                    : () => _useSequence(context, ref, rows),
                icon: const Icon(Icons.event_available_outlined),
                label: const Text('Use this sequence'),
              ),
              orElse: () => null,
            ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (rows) {
          final listPane = _ItemsPane(
            rows: rows,
            sequenceAsync: sequenceAsync,
            onAdd: () => _addItem(context, ref),
            onRemove: (row) => _removeItem(context, ref, row),
            onReorder: (oldIndex, newIndex) =>
                _onReorder(ref, rows, oldIndex, newIndex),
            compactHeader: !Breakpoints.isWide(context),
          );
          if (!Breakpoints.isWide(context)) {
            return listPane;
          }
          // Wide: split pane. List on the left (roughly 55%),
          // metadata + scheduling action on the right (45%). The
          // ReorderableListView inside listPane still gets a bounded
          // height from the Row's Expanded, which is what it needs.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 55, child: listPane),
              const VerticalDivider(width: 1),
              Expanded(
                flex: 45,
                child: _SequenceMetaPane(
                  sequenceAsync: sequenceAsync,
                  rows: rows,
                  onUseSequence: rows.isEmpty
                      ? null
                      : () => _useSequence(context, ref, rows),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Left (or full-width on narrow) pane: the ordered list of items
/// plus its "Add activity" row. Separated out so the wide split-pane
/// Row can hand this chunk a bounded-height [Expanded] container —
/// [ReorderableListView] requires one to work.
class _ItemsPane extends StatelessWidget {
  const _ItemsPane({
    required this.rows,
    required this.sequenceAsync,
    required this.onAdd,
    required this.onRemove,
    required this.onReorder,
    required this.compactHeader,
  });

  final List<SequenceItemWithLibrary> rows;
  final AsyncValue<LessonSequence?> sequenceAsync;
  final VoidCallback onAdd;
  final ValueChanged<SequenceItemWithLibrary> onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;

  /// Narrow screens keep the header row (description + "Add activity"
  /// button). On wide the description lives in the right pane, so we
  /// only show a minimal add-activity row here.
  final bool compactHeader;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: compactHeader
                    ? sequenceAsync.maybeWhen(
                        data: (s) => Text(
                          (s?.description ?? '').isEmpty
                              ? '${rows.length} '
                                  '${rows.length == 1 ? 'activity' : 'activities'}'
                              : s!.description!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        orElse: () => const SizedBox.shrink(),
                      )
                    : Text(
                        '${rows.length} '
                        '${rows.length == 1 ? 'activity' : 'activities'}',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
              ),
              OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add activity'),
              ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? _EmptyItems(onAdd: onAdd)
              : ReorderableListView.builder(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.lg,
                    right: AppSpacing.lg,
                    top: AppSpacing.sm,
                    bottom: AppSpacing.xxxl * 2,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    return Padding(
                      key: ValueKey(r.item.id),
                      padding: const EdgeInsets.only(
                        bottom: AppSpacing.md,
                      ),
                      child: _ItemRow(
                        position: i + 1,
                        row: r,
                        onRemove: () => onRemove(r),
                      ),
                    );
                  },
                  onReorder: onReorder,
                ),
        ),
      ],
    );
  }
}

/// Right-hand pane on wide viewports. Surfaces the sequence's
/// identity (name, description), the item count, and the primary
/// "Use this sequence" action. Kept intentionally low-density — it's
/// a reading surface paired with the list.
class _SequenceMetaPane extends StatelessWidget {
  const _SequenceMetaPane({
    required this.sequenceAsync,
    required this.rows,
    required this.onUseSequence,
  });

  final AsyncValue<LessonSequence?> sequenceAsync;
  final List<SequenceItemWithLibrary> rows;
  final VoidCallback? onUseSequence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: sequenceAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (err, _) => Text('Error: $err'),
        data: (s) {
          if (s == null) return const SizedBox.shrink();
          final description = (s.description ?? '').trim();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'About this sequence',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(s.name, style: theme.textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${rows.length} '
                '${rows.length == 1 ? 'activity' : 'activities'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(description, style: theme.textTheme.bodyLarge),
              ],
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: onUseSequence,
                icon: const Icon(Icons.event_available_outlined),
                label: const Text('Use this sequence'),
              ),
              if (onUseSequence == null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Add at least one activity to schedule.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.position,
    required this.row,
    required this.onRemove,
  });

  final int position;
  final SequenceItemWithLibrary row;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lib = row.library;
    final sub = <String>[];
    if (lib.defaultDurationMin != null) {
      sub.add('${lib.defaultDurationMin} min');
    }
    if (lib.location != null && lib.location!.isNotEmpty) {
      sub.add(lib.location!);
    }
    return AppCard(
      child: Row(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$position',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lib.title, style: theme.textTheme.titleSmall),
                if (sub.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      sub.join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 20),
          ),
          Icon(
            Icons.drag_handle,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _EmptyItems extends StatelessWidget {
  const _EmptyItems({required this.onAdd});

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
              Icons.bookmarks_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No activities yet',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Add library cards in the order you want them to run. '
              'Drag the handles to reorder later.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Pick from library'),
            ),
          ],
        ),
      ),
    );
  }
}
