import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _dayShortLabels = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

/// Week grid: 7 day-columns and time-slot-rows. Auto-fits the viewport so
/// all seven days are visible without horizontal scroll. Identical
/// activities on consecutive days merge into a single horizontally-spanning
/// card.
class WeekGridView extends StatelessWidget {
  const WeekGridView({
    required this.weekStart,
    required this.itemsByDay,
    required this.conflictsByDay,
    required this.onItemTap,
    super.key,
  });

  final DateTime weekStart;
  final Map<int, List<ScheduleItem>> itemsByDay;
  final Map<int, Set<String>> conflictsByDay;
  final ValueChanged<ScheduleItem> onItemTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final slotSet = <_TimeSlot>{};
    for (final items in itemsByDay.values) {
      for (final item in items) {
        if (item.isFullDay) continue;
        slotSet.add(_TimeSlot(item.startTime, item.endTime));
      }
    }
    final slots = slotSet.toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

    final hasFullDayByDay = <int, List<ScheduleItem>>{};
    for (var d = 1; d <= 7; d++) {
      final items = itemsByDay[d] ?? const <ScheduleItem>[];
      final fullDay = items.where((i) => i.isFullDay).toList();
      if (fullDay.isNotEmpty) hasFullDayByDay[d] = fullDay;
    }

    if (slots.isEmpty && hasFullDayByDay.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            'Nothing scheduled this week. Add activities to see\n'
            'the pattern laid out here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // Build the time-slot matrix.
    final matrix = List.generate(
      7,
      (_) => List<ScheduleItem?>.filled(slots.length, null),
    );
    for (var d = 0; d < 7; d++) {
      final items = itemsByDay[d + 1] ?? const <ScheduleItem>[];
      for (final item in items) {
        if (item.isFullDay) continue;
        final idx = slots.indexOf(_TimeSlot(item.startTime, item.endTime));
        if (idx >= 0) matrix[d][idx] = item;
      }
    }

    // Compute merge blocks.
    final blocks = <_Block>[];
    for (var slot = 0; slot < slots.length; slot++) {
      var d = 0;
      while (d < 7) {
        final item = matrix[d][slot];
        if (item == null) {
          d++;
          continue;
        }
        var end = d;
        while (end + 1 < 7) {
          final next = matrix[end + 1][slot];
          if (next == null || !_areEquivalent(item, next)) break;
          end++;
        }
        final spannedItems = <ScheduleItem>[
          for (var i = d; i <= end; i++) matrix[i][slot]!,
        ];
        blocks.add(
          _Block(
            slotIdx: slot,
            startDay: d,
            endDay: end,
            items: spannedItems,
            inConflict: _blockHasConflict(
              conflictsByDay: conflictsByDay,
              startDay: d,
              items: spannedItems,
            ),
          ),
        );
        d = end + 1;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const timeColumnWidth = 72.0;
        const headerHeight = 44.0;
        const fullDayRowHeight = 56.0;
        const cellHeight = 68.0;
        const gutter = 4.0;

        final columnsWidth = constraints.maxWidth - timeColumnWidth;
        final cellWidth = columnsWidth / 7;

        final fullDayRowActive = hasFullDayByDay.isNotEmpty;
        final contentTop =
            headerHeight + (fullDayRowActive ? fullDayRowHeight : 0);
        final totalHeight = contentTop + slots.length * cellHeight;

        return SingleChildScrollView(
          child: SizedBox(
            width: constraints.maxWidth,
            height: totalHeight,
            child: Stack(
              children: [
                // Day column headers with dates.
                for (var d = 0; d < 7; d++)
                  Positioned(
                    top: 0,
                    left: timeColumnWidth + d * cellWidth,
                    width: cellWidth,
                    height: headerHeight,
                    child: _DayHeader(
                      date: weekStart.add(Duration(days: d)),
                      label: _dayShortLabels[d],
                    ),
                  ),

                // Full-day strip (only shown when any day has full-day items).
                if (fullDayRowActive) ...[
                  for (var d = 0; d < 7; d++)
                    if ((hasFullDayByDay[d + 1] ?? const []).isNotEmpty)
                      Positioned(
                        top: headerHeight + gutter / 2,
                        left: timeColumnWidth + d * cellWidth + gutter / 2,
                        width: cellWidth - gutter,
                        height: fullDayRowHeight - gutter,
                        child: _FullDayCard(
                          items: hasFullDayByDay[d + 1]!,
                          onTap: () => onItemTap(
                            hasFullDayByDay[d + 1]!.first,
                          ),
                        ),
                      ),
                  Positioned(
                    top: headerHeight,
                    left: 0,
                    width: timeColumnWidth,
                    height: fullDayRowHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'All day',
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                    ),
                  ),
                ],

                // Time-slot row labels.
                for (var i = 0; i < slots.length; i++)
                  Positioned(
                    top: contentTop + i * cellHeight,
                    left: 0,
                    width: timeColumnWidth,
                    height: cellHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${_formatTime(slots[i].start)}\n${_formatTime(slots[i].end)}',
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ),
                  ),

                // Merged activity blocks.
                for (final block in blocks)
                  Positioned(
                    top:
                        contentTop + block.slotIdx * cellHeight + gutter / 2,
                    left: timeColumnWidth +
                        block.startDay * cellWidth +
                        gutter / 2,
                    width: (block.endDay - block.startDay + 1) * cellWidth -
                        gutter,
                    height: cellHeight - gutter,
                    child: _GridBlockCard(
                      block: block,
                      onTap: () => onItemTap(block.first),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _blockHasConflict({
    required Map<int, Set<String>> conflictsByDay,
    required int startDay,
    required List<ScheduleItem> items,
  }) {
    for (var i = 0; i < items.length; i++) {
      final day = startDay + i + 1;
      if ((conflictsByDay[day] ?? const <String>{}).contains(items[i].id)) {
        return true;
      }
    }
    return false;
  }

  bool _areEquivalent(ScheduleItem a, ScheduleItem b) {
    if (a.title != b.title) return false;
    if (a.startTime != b.startTime) return false;
    if (a.endTime != b.endTime) return false;
    if (a.isFullDay != b.isFullDay) return false;
    if (a.specialistId != b.specialistId) return false;
    if (a.location != b.location) return false;
    final aPods = a.podIds.toSet();
    final bPods = b.podIds.toSet();
    if (aPods.length != bPods.length) return false;
    for (final id in aPods) {
      if (!bPods.contains(id)) return false;
    }
    return true;
  }
}

@immutable
class _TimeSlot {
  const _TimeSlot(this.start, this.end);

  final String start;
  final String end;

  int get startMinutes => _minutes(start);

  @override
  bool operator ==(Object other) =>
      other is _TimeSlot && start == other.start && end == other.end;

  @override
  int get hashCode => Object.hash(start, end);

  static int _minutes(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
}

class _Block {
  const _Block({
    required this.slotIdx,
    required this.startDay,
    required this.endDay,
    required this.items,
    required this.inConflict,
  });

  final int slotIdx;
  final int startDay;
  final int endDay;
  final List<ScheduleItem> items;
  final bool inConflict;

  bool get isMerged => endDay > startDay;
  ScheduleItem get first => items.first;

  String get dayRangeLabel => isMerged
      ? '${_dayShortLabels[startDay]}–${_dayShortLabels[endDay]}'
      : _dayShortLabels[startDay];
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date, required this.label});

  final DateTime date;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        Text(
          '${date.day}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _FullDayCard extends StatelessWidget {
  const _FullDayCard({required this.items, required this.onTap});

  final List<ScheduleItem> items;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = items.first;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            first.title,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (items.length > 1)
            Text(
              '+${items.length - 1} more',
              style: theme.textTheme.labelSmall,
            ),
        ],
      ),
    );
  }
}

class _GridBlockCard extends ConsumerWidget {
  const _GridBlockCard({required this.block, required this.onTap});

  final _Block block;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final first = block.first;

    final subtitleParts = <String>[];
    if (first.podIds.isNotEmpty) {
      final names = <String>[];
      for (final podId in first.podIds) {
        final pod = ref.watch(podProvider(podId)).asData?.value;
        if (pod != null) names.add(pod.name);
      }
      if (names.isNotEmpty) subtitleParts.add(names.join(' + '));
    }
    if (first.specialistId != null) {
      final specialist =
          ref.watch(specialistProvider(first.specialistId!)).asData?.value;
      if (specialist != null) subtitleParts.add(specialist.name);
    }
    if (first.location != null && first.location!.isNotEmpty) {
      subtitleParts.add(first.location!);
    }

    final subStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  first.title,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (block.isMerged) ...[
                const SizedBox(width: AppSpacing.xs),
                Text(
                  block.dayRangeLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (block.inConflict) ...[
                const SizedBox(width: 2),
                Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: theme.colorScheme.error,
                ),
              ],
            ],
          ),
          if (subtitleParts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                subtitleParts.join(' · '),
                style: subStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

String _formatTime(String hhmm) {
  final parts = hhmm.split(':');
  final h = int.parse(parts[0]);
  final m = parts[1];
  final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
  final period = h < 12 ? 'a' : 'p';
  return m == '00' ? '$hour12$period' : '$hour12:$m$period';
}
