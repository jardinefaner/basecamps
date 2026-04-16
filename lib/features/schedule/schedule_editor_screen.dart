import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/widgets/add_activity_picker.dart';
import 'package:basecamp/features/schedule/widgets/copy_day_sheet.dart';
import 'package:basecamp/features/schedule/widgets/edit_template_sheet.dart';
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

class ScheduleEditorScreen extends ConsumerWidget {
  const ScheduleEditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(templatesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Weekly schedule')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openPicker(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: templatesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (templates) {
          final byDay = <int, List<ScheduleTemplate>>{};
          for (final t in templates) {
            byDay.putIfAbsent(t.dayOfWeek, () => []).add(t);
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
                  items: byDay[day] ?? const [],
                  onAdd: () => _openRecurring(context, initialDays: {day}),
                  onEdit: (t) => _openRecurring(context, template: t),
                  onCopy: () => _openCopy(context, day, byDay[day] ?? const []),
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
    ScheduleTemplate? template,
    Set<int>? initialDays,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditTemplateSheet(
        template: template,
        initialDays: initialDays,
      ),
    );
  }

  Future<void> _openCopy(
    BuildContext context,
    int sourceDay,
    List<ScheduleTemplate> items,
  ) async {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_dayLabels[sourceDay - 1]} has no activities to copy.'),
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
        sourceCount: items.length,
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
    required this.onAdd,
    required this.onEdit,
    required this.onCopy,
  });

  final int day;
  final List<ScheduleTemplate> items;
  final VoidCallback onAdd;
  final ValueChanged<ScheduleTemplate> onEdit;
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
            for (final t in items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: AppCard(
                  onTap: () => onEdit(t),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 80,
                        child: Text(
                          t.isFullDay
                              ? 'All day'
                              : '${_formatTime(t.startTime)}–${_formatTime(t.endTime)}',
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.title, style: theme.textTheme.titleMedium),
                            if (t.location != null && t.location!.isNotEmpty)
                              Text(
                                t.location!,
                                style: theme.textTheme.bodySmall,
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
