import 'package:basecamp/features/schedule/conflicts.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/week_days.dart';
import 'package:basecamp/features/schedule/widgets/add_activity_picker.dart';
import 'package:basecamp/features/schedule/widgets/conflict_sheet.dart';
import 'package:basecamp/features/schedule/widgets/copy_day_sheet.dart';
import 'package:basecamp/features/schedule/widgets/edit_template_sheet.dart';
import 'package:basecamp/features/schedule/widgets/new_activity_wizard.dart';
import 'package:basecamp/features/schedule/widgets/week_grid_view.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

const List<String> _dayLabels = scheduleDayLabels;
const List<String> _dayShortLabels = scheduleDayShortLabels;

enum _ViewMode { list, grid }

DateTime _mondayOf(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

class ScheduleEditorScreen extends ConsumerStatefulWidget {
  const ScheduleEditorScreen({super.key});

  @override
  ConsumerState<ScheduleEditorScreen> createState() =>
      _ScheduleEditorScreenState();
}

class _ScheduleEditorScreenState
    extends ConsumerState<ScheduleEditorScreen> {
  _ViewMode _mode = _ViewMode.list;
  late DateTime _weekStart = _mondayOf(DateTime.now());

  DateTime get _weekEnd => _weekStart.add(const Duration(days: 6));

  void _prevWeek() =>
      setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7)));
  void _nextWeek() =>
      setState(() => _weekStart = _weekStart.add(const Duration(days: 7)));
  void _thisWeek() =>
      setState(() => _weekStart = _mondayOf(DateTime.now()));

  Future<void> _pickWeek() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _weekStart,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) {
      setState(() => _weekStart = _mondayOf(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheduleAsync = ref.watch(scheduleForWeekProvider(_weekStart));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule'),
        actions: [
          IconButton(
            tooltip: _mode == _ViewMode.list ? 'Grid view' : 'List view',
            icon: Icon(
              _mode == _ViewMode.list
                  ? Icons.grid_view_outlined
                  : Icons.view_agenda_outlined,
            ),
            onPressed: () => setState(() {
              _mode = _mode == _ViewMode.list ? _ViewMode.grid : _ViewMode.list;
            }),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openPicker,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: Column(
        children: [
          _WeekNavigator(
            weekStart: _weekStart,
            weekEnd: _weekEnd,
            onPrev: _prevWeek,
            onNext: _nextWeek,
            onPick: _pickWeek,
            onThisWeek: _thisWeek,
          ),
          Expanded(
            child: scheduleAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error: $err')),
              data: (byDay) {
                final conflicts = <int, Set<String>>{
                  for (var d = 1; d <= scheduleDayCount; d++)
                    d: detectConflictingIds(
                      byDay[d] ?? const <ScheduleItem>[],
                    ),
                };
                if (_mode == _ViewMode.grid) {
                  return Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.md,
                      right: AppSpacing.md,
                      top: AppSpacing.sm,
                      bottom: AppSpacing.xxxl * 2,
                    ),
                    child: WeekGridView(
                      weekStart: _weekStart,
                      itemsByDay: byDay,
                      conflictsByDay: conflicts,
                      onItemTap: _handleItemTap,
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.lg,
                    right: AppSpacing.lg,
                    top: AppSpacing.md,
                    bottom: AppSpacing.xxxl * 2,
                  ),
                  children: [
                    for (var offset = 0; offset < scheduleDayCount; offset++)
                      _DaySection(
                        date: _weekStart.add(Duration(days: offset)),
                        items: byDay[offset + 1] ??
                            const <ScheduleItem>[],
                        allWeekItems: byDay,
                        conflictingIds:
                            conflicts[offset + 1] ?? const {},
                        onAdd: () => _openRecurring(initialDays: {offset + 1}),
                        onItemTap: _handleItemTap,
                        onCopy: () => _openCopy(
                          offset + 1,
                          (byDay[offset + 1] ?? const <ScheduleItem>[])
                              .length,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AddActivityPicker(initialDate: _weekStart),
    );
  }

  Future<void> _openRecurring({Set<int>? initialDays}) async {
    // Creation uses a step-by-step wizard — the previous all-fields
    // sheet was too much for first-timers. Editing an existing row
    // still opens the dense sheet (see _handleItemTap), which is the
    // right shape for quick tweaks.
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => NewActivityWizardScreen(initialDays: initialDays),
      ),
    );
  }

  Future<void> _handleItemTap(ScheduleItem item) async {
    // Template-sourced item → edit the template. Per-date entry → detail sheet
    // with a delete option (editing entries isn't wired yet).
    if (item.templateId != null && item.isFromTemplate) {
      final template = await ref
          .read(scheduleRepositoryProvider)
          .getTemplate(item.templateId!);
      if (template == null || !mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        isDismissible: false,
        builder: (_) => EditTemplateSheet(
          template: template,
          occurrenceDate: item.date,
        ),
      );
      return;
    }

    final entryId = item.entryId;
    if (entryId == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OneOffEntrySheet(item: item, entryId: entryId),
    );
  }

  Future<void> _openCopy(int sourceDay, int sourceCount) async {
    if (sourceCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_dayLabels[sourceDay - 1]} has no activities to copy.',
          ),
        ),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CopyDaySheet(
        sourceDay: sourceDay,
        sourceCount: sourceCount,
        onCopied: (targetDays, countPerDay) {
          final sortedNames = (targetDays.toList()..sort())
              .map((d) => _dayShortLabels[d - 1])
              .join(', ');
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Copied $countPerDay '
                '${countPerDay == 1 ? "activity" : "activities"} to $sortedNames',
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WeekNavigator extends StatelessWidget {
  const _WeekNavigator({
    required this.weekStart,
    required this.weekEnd,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
    required this.onThisWeek,
  });

  final DateTime weekStart;
  final DateTime weekEnd;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPick;
  final VoidCallback onThisWeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thisWeekStart = _mondayOf(DateTime.now());
    final isCurrentWeek = weekStart.isAtSameMomentAs(thisWeekStart);
    final sameMonth = weekStart.month == weekEnd.month;
    final label = sameMonth
        ? '${DateFormat.MMM().format(weekStart)} '
            '${weekStart.day} – ${weekEnd.day}, ${weekStart.year}'
        : '${DateFormat.MMMd().format(weekStart)} – '
            '${DateFormat.MMMd().format(weekEnd)}, ${weekStart.year}';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous week',
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrev,
          ),
          Expanded(
            child: TextButton(
              onPressed: onPick,
              child: Text(
                label,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
          if (!isCurrentWeek)
            TextButton(
              onPressed: onThisWeek,
              child: const Text('This week'),
            ),
          IconButton(
            tooltip: 'Next week',
            icon: const Icon(Icons.chevron_right),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _DaySection extends ConsumerWidget {
  const _DaySection({
    required this.date,
    required this.items,
    required this.allWeekItems,
    required this.conflictingIds,
    required this.onAdd,
    required this.onItemTap,
    required this.onCopy,
  });

  final DateTime date;
  final List<ScheduleItem> items;
  final Map<int, List<ScheduleItem>> allWeekItems;
  final Set<String> conflictingIds;
  final VoidCallback onAdd;
  final ValueChanged<ScheduleItem> onItemTap;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dayOfWeek = date.weekday;
    final dayLabel = _dayLabels[dayOfWeek - 1].toUpperCase();
    final dateLabel = DateFormat.MMMd().format(date);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xs,
              bottom: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Text(dayLabel, style: theme.textTheme.labelMedium),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  dateLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '·',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${items.length}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (conflictingIds.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: theme.colorScheme.error,
                  ),
                ],
                const Spacer(),
                IconButton(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 20),
                  tooltip: 'Add to ${_dayLabels[dayOfWeek - 1]}',
                  visualDensity: VisualDensity.compact,
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz, size: 20),
                  tooltip: 'More',
                  onSelected: (value) {
                    if (value == 'copy') onCopy();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'copy',
                      enabled: items.isNotEmpty,
                      child: const Row(
                        children: [
                          Icon(Icons.copy_outlined, size: 18),
                          SizedBox(width: AppSpacing.sm),
                          Text('Copy to...'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xs,
              ),
              child: Text(
                'No activities',
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _EditorItemCard(
                  item: item,
                  inConflict: conflictingIds.contains(item.id),
                  allItemsForDay: items,
                  onTap: () => onItemTap(item),
                ),
              ),
        ],
      ),
    );
  }
}

class _EditorItemCard extends StatelessWidget {
  const _EditorItemCard({
    required this.item,
    required this.inConflict,
    required this.allItemsForDay,
    required this.onTap,
  });

  final ScheduleItem item;
  final bool inConflict;
  final List<ScheduleItem> allItemsForDay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              item.isFullDay
                  ? 'All day'
                  : '${_formatTime(item.startTime)}–${_formatTime(item.endTime)}',
              style: theme.textTheme.labelMedium,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: theme.textTheme.titleMedium),
                if (item.location != null && item.location!.isNotEmpty)
                  Text(
                    item.location!,
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          if (item.isOneOff)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'ONE-OFF',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          if (inConflict)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: InkResponse(
                radius: 18,
                onTap: () async {
                  final conflicts =
                      conflictsByItemId(allItemsForDay)[item.id] ?? const [];
                  if (conflicts.isEmpty) return;
                  await showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => ConflictSheet(
                      item: item,
                      conflicts: conflicts,
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                ),
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

  String _formatTime(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.parse(parts[0]);
    final m = parts[1];
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final period = h < 12 ? 'a' : 'p';
    return m == '00' ? '$hour12$period' : '$hour12:$m$period';
  }
}

class _OneOffEntrySheet extends ConsumerWidget {
  const _OneOffEntrySheet({required this.item, required this.entryId});

  final ScheduleItem item;
  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final insets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.md,
        bottom: AppSpacing.xl + insets,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('One-off event', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            item.title,
            style: theme.textTheme.bodyLarge,
          ),
          Text(
            item.isFullDay
                ? 'All day'
                : '${item.startTime} – ${item.endTime}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          OutlinedButton.icon(
            onPressed: () async {
              await ref
                  .read(scheduleRepositoryProvider)
                  .deleteEntry(entryId);
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: Icon(
              Icons.delete_outline,
              color: theme.colorScheme.error,
            ),
            label: Text(
              'Delete event',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
