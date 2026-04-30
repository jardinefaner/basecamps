import 'package:basecamp/core/format/time.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/week_days.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _dayShortLabels = ['MON', 'TUE', 'WED', 'THU', 'FRI'];

/// Week grid with a frozen time column on the left and horizontally
/// scrollable day columns on the right. Each time-slot row keeps its time
/// label pinned (outside the scroll view) and renders the five weekday
/// cells (Mon–Fri — the program doesn't run weekends) in a horizontal
/// scroll view. Every row's horizontal scroll view shares state via a
/// small linked-controller group, so scrolling any row scrolls the
/// header and every other row in lock-step.
class WeekGridView extends StatefulWidget {
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
  State<WeekGridView> createState() => _WeekGridViewState();
}

class _WeekGridViewState extends State<WeekGridView> {
  static const _cellWidth = 180.0;
  static const _timeColumnWidth = 64.0;
  static const _headerHeight = 44.0;

  final _LinkedScrollGroup _group = _LinkedScrollGroup();
  late final ScrollController _headerCtrl = _group.newController();
  late final ScrollController _fullDayCtrl = _group.newController();
  final Map<int, ScrollController> _rowCtrls = {};

  ScrollController _ctrlForRow(int index) {
    return _rowCtrls.putIfAbsent(index, _group.newController);
  }

  @override
  void dispose() {
    _group.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Distinct (startTime, endTime) pairs across the week, sorted.
    final slotSet = <_TimeSlot>{};
    for (final items in widget.itemsByDay.values) {
      for (final item in items) {
        if (item.isFullDay) continue;
        slotSet.add(_TimeSlot(item.startTime, item.endTime));
      }
    }
    final slots = slotSet.toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

    // Full-day items per day (rendered in the all-day strip).
    final fullDayByDay = <int, List<ScheduleItem>>{};
    for (var d = 1; d <= scheduleDayCount; d++) {
      final items = widget.itemsByDay[d] ?? const <ScheduleItem>[];
      final full = items.where((i) => i.isFullDay).toList();
      if (full.isNotEmpty) fullDayByDay[d] = full;
    }

    if (slots.isEmpty && fullDayByDay.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            'Nothing scheduled this week.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // (Day × slot) matrix → merge runs per row.
    final matrix = List.generate(
      scheduleDayCount,
      (_) => List<ScheduleItem?>.filled(slots.length, null),
    );
    for (var d = 0; d < scheduleDayCount; d++) {
      final items = widget.itemsByDay[d + 1] ?? const <ScheduleItem>[];
      for (final item in items) {
        if (item.isFullDay) continue;
        final idx = slots.indexOf(_TimeSlot(item.startTime, item.endTime));
        if (idx >= 0) matrix[d][idx] = item;
      }
    }
    final blocksBySlot = <int, List<_Block>>{};
    for (var slot = 0; slot < slots.length; slot++) {
      final row = <_Block>[];
      var d = 0;
      while (d < scheduleDayCount) {
        final item = matrix[d][slot];
        if (item == null) {
          d++;
          continue;
        }
        var end = d;
        while (end + 1 < scheduleDayCount) {
          final next = matrix[end + 1][slot];
          if (next == null || !_areEquivalent(item, next)) break;
          end++;
        }
        final spanned = <ScheduleItem>[
          for (var i = d; i <= end; i++) matrix[i][slot]!,
        ];
        row.add(
          _Block(
            startDay: d,
            endDay: end,
            items: spanned,
            inConflict: _blockHasConflict(
              conflictsByDay: widget.conflictsByDay,
              startDay: d,
              items: spanned,
            ),
          ),
        );
        d = end + 1;
      }
      if (row.isNotEmpty) blocksBySlot[slot] = row;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeaderRow(
          controller: _headerCtrl,
          weekStart: widget.weekStart,
          cellWidth: _cellWidth,
          timeColumnWidth: _timeColumnWidth,
          height: _headerHeight,
        ),
        if (fullDayByDay.isNotEmpty)
          _FullDayRow(
            controller: _fullDayCtrl,
            fullDayByDay: fullDayByDay,
            cellWidth: _cellWidth,
            timeColumnWidth: _timeColumnWidth,
            onTap: widget.onItemTap,
          ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var slot = 0; slot < slots.length; slot++)
                  _SlotRow(
                    time: slots[slot],
                    blocks: blocksBySlot[slot] ?? const [],
                    controller: _ctrlForRow(slot),
                    cellWidth: _cellWidth,
                    timeColumnWidth: _timeColumnWidth,
                    onTap: widget.onItemTap,
                  ),
              ],
            ),
          ),
        ),
      ],
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
    if (a.adultId != b.adultId) return false;
    if (a.location != b.location) return false;
    final aGroups = a.groupIds.toSet();
    final bGroups = b.groupIds.toSet();
    if (aGroups.length != bGroups.length) return false;
    for (final id in aGroups) {
      if (!bGroups.contains(id)) return false;
    }
    return true;
  }
}

// ---------- Linked scroll group ----------

/// Small helper: creates ScrollControllers that all mirror each other's
/// offset. When any one of them scrolls, the rest jump to the same offset.
class _LinkedScrollGroup {
  final List<ScrollController> _controllers = [];
  bool _syncing = false;

  ScrollController newController() {
    final c = ScrollController();
    c.addListener(() => _sync(c));
    _controllers.add(c);
    return c;
  }

  void _sync(ScrollController leader) {
    if (_syncing) return;
    _syncing = true;
    for (final c in _controllers) {
      if (c == leader) continue;
      if (!c.hasClients) continue;
      if (c.offset == leader.offset) continue;
      c.jumpTo(leader.offset);
    }
    _syncing = false;
  }

  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    _controllers.clear();
  }
}

// ---------- Row widgets ----------

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.controller,
    required this.weekStart,
    required this.cellWidth,
    required this.timeColumnWidth,
    required this.height,
  });

  final ScrollController controller;
  final DateTime weekStart;
  final double cellWidth;
  final double timeColumnWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: height,
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
          Expanded(
            child: SingleChildScrollView(
              controller: controller,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: SizedBox(
                width: cellWidth * scheduleDayCount,
                height: height,
                child: Row(
                  children: [
                    for (var d = 0; d < scheduleDayCount; d++)
                      SizedBox(
                        width: cellWidth,
                        child: Center(
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
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FullDayRow extends StatelessWidget {
  const _FullDayRow({
    required this.controller,
    required this.fullDayByDay,
    required this.cellWidth,
    required this.timeColumnWidth,
    required this.onTap,
  });

  final ScrollController controller;
  final Map<int, List<ScheduleItem>> fullDayByDay;
  final double cellWidth;
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
              child: Text('All day', style: theme.textTheme.labelMedium),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: controller,
              physics: const ClampingScrollPhysics(),
              child: SizedBox(
                width: cellWidth * scheduleDayCount,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var d = 0; d < scheduleDayCount; d++)
                      SizedBox(
                        width: cellWidth,
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: (fullDayByDay[d + 1] ?? const []).isEmpty
                              ? const _EmptyCell()
                              : _FullDayCard(
                                  items: fullDayByDay[d + 1]!,
                                  onTap: () =>
                                      onTap(fullDayByDay[d + 1]!.first),
                                ),
                        ),
                      ),
                  ],
                ),
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
    required this.blocks,
    required this.controller,
    required this.cellWidth,
    required this.timeColumnWidth,
    required this.onTap,
  });

  final _TimeSlot time;
  final List<_Block> blocks;
  final ScrollController controller;
  final double cellWidth;
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
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: Text(
                '${Hhmm.formatCompact(time.start)}\n${Hhmm.formatCompact(time.end)}',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: controller,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: SizedBox(
                width: cellWidth * scheduleDayCount,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _buildCells(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCells() {
    final cells = <Widget>[];
    var d = 0;
    while (d < scheduleDayCount) {
      final block = _blockStartingAt(d);
      if (block != null) {
        final span = block.endDay - block.startDay + 1;
        cells.add(
          SizedBox(
            width: cellWidth * span,
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
          SizedBox(
            width: cellWidth,
            child: const Padding(
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
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            first.title,
            style: theme.textTheme.titleMedium,
            softWrap: true,
          ),
          if (items.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '+${items.length - 1} more',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// Same visual language as the list-view card — title + groups/adult/
/// location stacked, no truncation. Time is intentionally absent because
/// the frozen left column already shows it.
class _GridBlockCard extends ConsumerWidget {
  const _GridBlockCard({required this.block, required this.onTap});

  final _Block block;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final first = block.first;

    final subtitleParts = <String>[];
    if (first.groupIds.isNotEmpty) {
      final names = <String>[];
      for (final groupId in first.groupIds) {
        final group = ref.watch(groupProvider(groupId)).asData?.value;
        if (group != null) names.add(group.name);
      }
      if (names.isNotEmpty) subtitleParts.add(names.join(' + '));
    }
    if (first.adultId != null) {
      final adult = ref.watch(adultProvider(first.adultId!)).asData?.value;
      if (adult != null) subtitleParts.add(adult.name);
    }
    if (first.location != null && first.location!.isNotEmpty) {
      subtitleParts.add(first.location!);
    }

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
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
                  style: theme.textTheme.titleMedium,
                  softWrap: true,
                ),
              ),
              if (block.inConflict) ...[
                const SizedBox(width: 2),
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
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subtitleParts.join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
