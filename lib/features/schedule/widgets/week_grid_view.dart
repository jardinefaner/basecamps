import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _dayShortLabels = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

/// Week grid laid out as day-columns × time-slot-rows. Each cell is an
/// AppCard matching the list view's styling. When an activity is identical
/// across consecutive days (same title, time, pods, specialist, location),
/// the cells merge into a single wide card that spans those columns — so
/// "Morning Circle" every day reads as one horizontal block like
/// `[ Morning Circle ——————————— MON – FRI ]` rather than five tall stubs.
class WeekGridView extends StatelessWidget {
  const WeekGridView({
    required this.itemsByDay,
    required this.conflictsByDay,
    required this.onEditById,
    super.key,
  });

  final Map<int, List<ScheduleItem>> itemsByDay;
  final Map<int, Set<String>> conflictsByDay;
  final ValueChanged<String> onEditById;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 1. Collect the distinct (startTime, endTime) pairs across the week.
    final slotSet = <_TimeSlot>{};
    for (final items in itemsByDay.values) {
      for (final item in items) {
        if (item.isFullDay) continue;
        slotSet.add(_TimeSlot(item.startTime, item.endTime));
      }
    }
    final slots = slotSet.toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

    if (slots.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            'Nothing scheduled yet. Add some recurring activities to see\n'
            'them laid out as a week.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // 2. Build the (day × slot) matrix.
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

    // 3. Compute merge blocks per row (slot). A run of consecutive days with
    //    equivalent items in the same slot becomes one horizontally-spanning
    //    block.
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

    // 4. Render: day columns across the top, time-slot rows down the left,
    //    positioned cards filling the matrix. Merged blocks span columns.
    const timeColumnWidth = 92.0;
    const headerHeight = 32.0;
    const cellWidth = 132.0;
    const cellHeight = 72.0;
    const gutter = 6.0;
    const totalWidth = timeColumnWidth + 7 * cellWidth;
    final totalHeight = headerHeight + slots.length * cellHeight;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: SizedBox(
          width: totalWidth,
          height: totalHeight,
          child: Stack(
            children: [
              // Day column headers.
              for (var d = 0; d < 7; d++)
                Positioned(
                  top: 0,
                  left: timeColumnWidth + d * cellWidth,
                  width: cellWidth,
                  height: headerHeight,
                  child: Center(
                    child: Text(
                      _dayShortLabels[d],
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                ),

              // Time slot row labels.
              for (var i = 0; i < slots.length; i++)
                Positioned(
                  top: headerHeight + i * cellHeight,
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
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                  ),
                ),

              // Merged activity blocks.
              for (final block in blocks)
                Positioned(
                  top: headerHeight +
                      block.slotIdx * cellHeight +
                      gutter / 2,
                  left: timeColumnWidth +
                      block.startDay * cellWidth +
                      gutter / 2,
                  width:
                      (block.endDay - block.startDay + 1) * cellWidth - gutter,
                  height: cellHeight - gutter,
                  child: _GridBlockCard(
                    block: block,
                    onTap: () => onEditById(
                      block.items.first.templateId ?? block.items.first.id,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
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
  final int startDay; // 0..6
  final int endDay; // inclusive
  final List<ScheduleItem> items;
  final bool inConflict;

  bool get isMerged => endDay > startDay;
  ScheduleItem get first => items.first;

  String get dayRangeLabel {
    if (!isMerged) return _dayShortLabels[startDay];
    return '${_dayShortLabels[startDay]} – ${_dayShortLabels[endDay]}';
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
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
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
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (block.isMerged) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  block.dayRangeLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
              if (block.inConflict) ...[
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: theme.colorScheme.error,
                ),
              ],
            ],
          ),
          if (subtitleParts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
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
