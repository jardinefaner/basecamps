import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _dayShortLabels = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

/// Week grid: day-columns across the top, time-slot rows down. Consecutive
/// days with an identical activity merge into a single card that spans those
/// columns (the span is self-evident from the calendar — no day-range label
/// needed). Nothing truncates: cells grow to fit the content, and the whole
/// grid is inside an [InteractiveViewer] so you can zoom out for a full-week
/// glance or zoom in to read detail without tapping anything.
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

    // 1. Distinct (startTime, endTime) pairs across the week.
    final slotSet = <_TimeSlot>{};
    for (final items in itemsByDay.values) {
      for (final item in items) {
        if (item.isFullDay) continue;
        slotSet.add(_TimeSlot(item.startTime, item.endTime));
      }
    }
    final slots = slotSet.toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

    // 2. Full-day items (per day) — rendered in a dedicated strip.
    final fullDayByDay = <int, List<ScheduleItem>>{};
    for (var d = 1; d <= 7; d++) {
      final items = itemsByDay[d] ?? const <ScheduleItem>[];
      final full = items.where((i) => i.isFullDay).toList();
      if (full.isNotEmpty) fullDayByDay[d] = full;
    }

    if (slots.isEmpty && fullDayByDay.isEmpty) {
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

    // 3. Build day-of-week × slot matrix of items for merge detection.
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

    // 4. Compute merge runs per slot.
    final blocksBySlot = <int, List<_Block>>{};
    for (var slot = 0; slot < slots.length; slot++) {
      final rowBlocks = <_Block>[];
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
        rowBlocks.add(
          _Block(
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
      if (rowBlocks.isNotEmpty) blocksBySlot[slot] = rowBlocks;
    }

    const timeColumnWidth = 72.0;

    final grid = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeaderRow(
          weekStart: weekStart,
          timeColumnWidth: timeColumnWidth,
        ),
        if (fullDayByDay.isNotEmpty)
          _FullDayRow(
            fullDayByDay: fullDayByDay,
            timeColumnWidth: timeColumnWidth,
            onTap: onItemTap,
          ),
        for (var slot = 0; slot < slots.length; slot++)
          _SlotRow(
            time: slots[slot],
            timeColumnWidth: timeColumnWidth,
            blocks: blocksBySlot[slot] ?? const [],
            onTap: onItemTap,
          ),
      ],
    );

    return InteractiveViewer(
      minScale: 0.4,
      maxScale: 3,
      boundaryMargin: const EdgeInsets.all(200),
      child: grid,
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

// ---------- Row widgets ----------

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.weekStart, required this.timeColumnWidth});

  final DateTime weekStart;
  final double timeColumnWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
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
          SizedBox(width: timeColumnWidth),
          for (var d = 0; d < 7; d++)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _dayShortLabels[d],
                    style: theme.textTheme.labelMedium,
                  ),
                  Text(
                    '${weekStart.add(Duration(days: d)).day}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FullDayRow extends StatelessWidget {
  const _FullDayRow({
    required this.fullDayByDay,
    required this.timeColumnWidth,
    required this.onTap,
  });

  final Map<int, List<ScheduleItem>> fullDayByDay;
  final double timeColumnWidth;
  final ValueChanged<ScheduleItem> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: timeColumnWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                'All day',
                style: theme.textTheme.labelMedium,
              ),
            ),
          ),
          for (var d = 0; d < 7; d++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: (fullDayByDay[d + 1] ?? const []).isEmpty
                    ? const _EmptyCell()
                    : _FullDayCard(
                        items: fullDayByDay[d + 1]!,
                        onTap: () => onTap(fullDayByDay[d + 1]!.first),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.time,
    required this.timeColumnWidth,
    required this.blocks,
    required this.onTap,
  });

  final _TimeSlot time;
  final double timeColumnWidth;
  final List<_Block> blocks;
  final ValueChanged<ScheduleItem> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: timeColumnWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                '${_formatTime(time.start)}\n${_formatTime(time.end)}',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ),
          ..._buildCells(),
        ],
      ),
    );
  }

  List<Widget> _buildCells() {
    final cells = <Widget>[];
    var d = 0;
    while (d < 7) {
      final block = _blockStartingAt(d);
      if (block != null) {
        cells.add(
          Expanded(
            flex: block.endDay - block.startDay + 1,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: _GridBlockCard(
                block: block,
                onTap: () => onTap(block.first),
              ),
            ),
          ),
        );
        d = block.endDay + 1;
      } else {
        cells.add(
          const Expanded(
            child: Padding(
              padding: EdgeInsets.all(3),
              child: _EmptyCell(),
            ),
          ),
        );
        d++;
      }
    }
    return cells;
  }

  _Block? _blockStartingAt(int day) {
    for (final b in blocks) {
      if (b.startDay == day) return b;
    }
    return null;
  }
}

class _EmptyCell extends StatelessWidget {
  const _EmptyCell();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
    );
  }
}

// ---------- Cards ----------

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
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  first.title,
                  style: theme.textTheme.titleSmall,
                  softWrap: true,
                ),
              ),
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
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitleParts.join(' · '),
                style: subStyle,
                softWrap: true,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------- Supporting types ----------

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
    required this.startDay,
    required this.endDay,
    required this.items,
    required this.inConflict,
  });

  final int startDay;
  final int endDay;
  final List<ScheduleItem> items;
  final bool inConflict;

  ScheduleItem get first => items.first;
}

String _formatTime(String hhmm) {
  final parts = hhmm.split(':');
  final h = int.parse(parts[0]);
  final m = parts[1];
  final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
  final period = h < 12 ? 'a' : 'p';
  return m == '00' ? '$hour12$period' : '$hour12:$m$period';
}
