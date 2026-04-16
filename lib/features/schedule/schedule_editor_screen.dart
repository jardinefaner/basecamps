import 'package:basecamp/features/schedule/conflicts.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/widgets/add_activity_picker.dart';
import 'package:basecamp/features/schedule/widgets/copy_day_sheet.dart';
import 'package:basecamp/features/schedule/widgets/edit_template_sheet.dart';
import 'package:basecamp/features/schedule/widgets/week_grid_view.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _dayLabels = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _dayShortLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

enum _ViewMode { list, grid }

class ScheduleEditorScreen extends ConsumerStatefulWidget {
  const ScheduleEditorScreen({super.key});

  @override
  ConsumerState<ScheduleEditorScreen> createState() =>
      _ScheduleEditorScreenState();
}

class _ScheduleEditorScreenState
    extends ConsumerState<ScheduleEditorScreen> {
  _ViewMode _mode = _ViewMode.list;

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(templateItemsByDayProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly schedule'),
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
        onPressed: () => _openPicker(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (byDay) {
          final conflicts = <int, Set<String>>{
            for (var d = 1; d <= 7; d++)
              d: detectConflictingIds(byDay[d] ?? const <ScheduleItem>[]),
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
                itemsByDay: byDay,
                conflictsByDay: conflicts,
                onEditById: (id) => _editById(context, ref, id),
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
              for (var day = 1; day <= 7; day++)
                _DaySection(
                  day: day,
                  items: byDay[day] ?? const <ScheduleItem>[],
                  conflictingIds: conflicts[day] ?? const {},
                  onAdd: () => _openRecurring(context, initialDays: {day}),
                  onEditById: (id) => _editById(context, ref, id),
                  onCopy: () => _openCopy(
                    context,
                    ref,
                    day,
                    (byDay[day] ?? const <ScheduleItem>[]).length,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const AddActivityPicker(),
    );
  }

  Future<void> _openRecurring(
    BuildContext context, {
    Set<int>? initialDays,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditTemplateSheet(initialDays: initialDays),
    );
  }

  Future<void> _editById(
    BuildContext context,
    WidgetRef ref,
    String templateId,
  ) async {
    final template =
        await ref.read(scheduleRepositoryProvider).getTemplate(templateId);
    if (template == null || !context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditTemplateSheet(template: template),
    );
  }

  Future<void> _openCopy(
    BuildContext context,
    WidgetRef ref,
    int sourceDay,
    int sourceCount,
  ) async {
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

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.day,
    required this.items,
    required this.conflictingIds,
    required this.onAdd,
    required this.onEditById,
    required this.onCopy,
  });

  final int day;
  final List<ScheduleItem> items;
  final Set<String> conflictingIds;
  final VoidCallback onAdd;
  final ValueChanged<String> onEditById;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                Text(
                  _dayLabels[day - 1].toUpperCase(),
                  style: theme.textTheme.labelMedium,
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
                  tooltip: 'Add to ${_dayLabels[day - 1]}',
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
                child: AppCard(
                  onTap: () => onEditById(item.templateId ?? item.id),
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
                            Text(
                              item.title,
                              style: theme.textTheme.titleMedium,
                            ),
                            if (item.location != null &&
                                item.location!.isNotEmpty)
                              Text(
                                item.location!,
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      if (conflictingIds.contains(item.id))
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.sm),
                          child: Icon(
                            Icons.warning_amber_rounded,
                            size: 18,
                            color: theme.colorScheme.error,
                          ),
                        ),
                      Icon(
                        Icons.chevron_right,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
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
