import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
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

class ScheduleEditorScreen extends ConsumerWidget {
  const ScheduleEditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(templatesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Weekly schedule')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Activity'),
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
                  onAdd: () => _openSheet(context, initialDays: {day}),
                  onEdit: (t) => _openSheet(context, template: t),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openSheet(
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
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.day,
    required this.items,
    required this.onAdd,
    required this.onEdit,
  });

  final int day;
  final List<ScheduleTemplate> items;
  final VoidCallback onAdd;
  final ValueChanged<ScheduleTemplate> onEdit;

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
                          '${_formatTime(t.startTime)}–${_formatTime(t.endTime)}',
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
