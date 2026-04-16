import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

const _dayHeaders = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

/// Week grid: 7 columns (Mon–Sun) with time axis on the left, activity
/// blocks positioned by start/end time. Tap a block to edit.
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

    // Figure out the time range based on content, padded outward to whole
    // hours. Fall back to a useful default if there's nothing scheduled.
    var minHour = 8;
    var maxHour = 17;
    for (final items in itemsByDay.values) {
      for (final item in items) {
        if (item.isFullDay) continue;
        final sh = item.startMinutes ~/ 60;
        final eh = (item.endMinutes + 59) ~/ 60;
        if (sh < minHour) minHour = sh;
        if (eh > maxHour) maxHour = eh;
      }
    }
    if (minHour >= maxHour) {
      minHour = 8;
      maxHour = 17;
    }
    final hours = [for (var h = minHour; h <= maxHour; h++) h];
    const pxPerHour = 64.0;
    const timeAxisWidth = 44.0;
    final totalHeight = (maxHour - minHour) * pxPerHour;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Ensure each day column has a minimum readable width; if the screen
        // is narrow, allow horizontal scroll instead of squishing further.
        const minColumnWidth = 88.0;
        final desiredColumnWidth =
            (constraints.maxWidth - timeAxisWidth) / 7;
        final columnWidth = desiredColumnWidth < minColumnWidth
            ? minColumnWidth
            : desiredColumnWidth;
        final gridWidth = timeAxisWidth + columnWidth * 7;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: gridWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DayHeaderRow(
                  columnWidth: columnWidth,
                  timeAxisWidth: timeAxisWidth,
                  itemsByDay: itemsByDay,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: SizedBox(
                      height: totalHeight,
                      child: Row(
                        children: [
                          _TimeAxis(
                            hours: hours,
                            pxPerHour: pxPerHour,
                            width: timeAxisWidth,
                          ),
                          for (var day = 1; day <= 7; day++)
                            _DayColumn(
                              width: columnWidth,
                              height: totalHeight,
                              hours: hours,
                              pxPerHour: pxPerHour,
                              items: itemsByDay[day] ?? const [],
                              conflictingIds:
                                  conflictsByDay[day] ?? const {},
                              onEditById: onEditById,
                              showLeftBorder: day > 1,
                              showRightBorder: day == 7,
                              outlineColor: theme.colorScheme.outlineVariant,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DayHeaderRow extends StatelessWidget {
  const _DayHeaderRow({
    required this.columnWidth,
    required this.timeAxisWidth,
    required this.itemsByDay,
  });

  final double columnWidth;
  final double timeAxisWidth;
  final Map<int, List<ScheduleItem>> itemsByDay;

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
          SizedBox(width: timeAxisWidth),
          for (var day = 1; day <= 7; day++)
            SizedBox(
              width: columnWidth,
              child: Column(
                children: [
                  Text(
                    _dayHeaders[day - 1],
                    style: theme.textTheme.labelMedium,
                  ),
                  Text(
                    '${(itemsByDay[day] ?? const []).length}',
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

class _TimeAxis extends StatelessWidget {
  const _TimeAxis({
    required this.hours,
    required this.pxPerHour,
    required this.width,
  });

  final List<int> hours;
  final double pxPerHour;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Stack(
        children: [
          for (var i = 0; i < hours.length - 1; i++)
            Positioned(
              top: i * pxPerHour - 6,
              right: 4,
              child: Text(
                _formatHour(hours[i]),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatHour(int h) {
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final period = h < 12 ? 'a' : 'p';
    return '$hour12$period';
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.width,
    required this.height,
    required this.hours,
    required this.pxPerHour,
    required this.items,
    required this.conflictingIds,
    required this.onEditById,
    required this.showLeftBorder,
    required this.showRightBorder,
    required this.outlineColor,
  });

  final double width;
  final double height;
  final List<int> hours;
  final double pxPerHour;
  final List<ScheduleItem> items;
  final Set<String> conflictingIds;
  final ValueChanged<String> onEditById;
  final bool showLeftBorder;
  final bool showRightBorder;
  final Color outlineColor;

  @override
  Widget build(BuildContext context) {
    final minHour = hours.first;
    final timed = items.where((i) => !i.isFullDay).toList();

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          // Column borders + hour grid lines.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  left: showLeftBorder
                      ? BorderSide(color: outlineColor, width: 0.5)
                      : BorderSide.none,
                  right: showRightBorder
                      ? BorderSide(color: outlineColor, width: 0.5)
                      : BorderSide.none,
                ),
              ),
            ),
          ),
          for (var i = 1; i < hours.length; i++)
            Positioned(
              top: i * pxPerHour,
              left: 0,
              right: 0,
              child: Container(
                height: 0.5,
                color: outlineColor,
              ),
            ),
          // Activity blocks.
          for (final item in timed)
            Positioned(
              top: (item.startMinutes - minHour * 60) / 60 * pxPerHour,
              left: 2,
              right: 2,
              height: ((item.endMinutes - item.startMinutes) / 60 * pxPerHour)
                  .clamp(20.0, double.infinity),
              child: _Block(
                item: item,
                inConflict: conflictingIds.contains(item.id),
                onTap: () => onEditById(item.templateId ?? item.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.item,
    required this.inConflict,
    required this.onTap,
  });

  final ScheduleItem item;
  final bool inConflict;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = inConflict
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.primaryContainer;
    final fg = inConflict
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onPrimaryContainer;
    final borderColor =
        inConflict ? theme.colorScheme.error : theme.colorScheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border(
            left: BorderSide(color: borderColor, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              _formatTime(item.startTime),
              style: theme.textTheme.labelSmall?.copyWith(
                color: fg.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
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
