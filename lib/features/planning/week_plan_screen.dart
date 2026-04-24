import 'dart:async';

import 'package:basecamp/features/export/export_actions.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/week_days.dart';
import 'package:basecamp/features/schedule/widgets/activity_detail_sheet.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// `/week-plan` — Monday-to-Friday column layout showing every
/// scheduled item on each day. Tap a card → [ActivityDetailSheet].
/// Long-press-drag a card onto another column to move it: template-
/// backed cards shift the recurring weekday (all future weeks),
/// entry-backed cards shift just that one occurrence's date.
/// Trailing "Duplicate last week" action copies one-off entries from
/// the prior week forward onto their mirror day (templates already
/// recur, so they're skipped).
class WeekPlanScreen extends ConsumerStatefulWidget {
  const WeekPlanScreen({super.key});

  @override
  ConsumerState<WeekPlanScreen> createState() => _WeekPlanScreenState();
}

class _WeekPlanScreenState extends ConsumerState<WeekPlanScreen> {
  late DateTime _monday;

  @override
  void initState() {
    super.initState();
    _monday = _mondayOf(DateTime.now());
  }

  static DateTime _mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    // weekday 1 = Monday, 7 = Sunday. Subtract to land on Monday.
    return day.subtract(Duration(days: day.weekday - 1));
  }

  void _shiftWeek(int deltaWeeks) {
    setState(() {
      _monday = _monday.add(Duration(days: 7 * deltaWeeks));
    });
  }

  String _rangeLabel() {
    final friday = _monday.add(const Duration(days: 4));
    final sameMonth = _monday.month == friday.month;
    if (sameMonth) {
      return '${DateFormat.MMMMd().format(_monday)} – '
          '${DateFormat.d().format(friday)}';
    }
    return '${DateFormat.MMMd().format(_monday)} – '
        '${DateFormat.MMMd().format(friday)}';
  }

  Future<void> _duplicateLastWeek() async {
    final repo = ref.read(scheduleRepositoryProvider);
    final sourceMonday = _monday.subtract(const Duration(days: 7));
    final messenger = ScaffoldMessenger.of(context);
    final count = await repo.duplicateWeekTemplates(
      sourceMonday: sourceMonday,
      destMonday: _monday,
    );
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'Nothing one-off to duplicate from last week. '
                    '(Templates already recur.)'
                : 'Duplicated $count '
                    '${count == 1 ? 'entry' : 'entries'} from last week.',
          ),
        ),
      );
  }

  Future<void> _openDetail(ScheduleItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ActivityDetailSheet(item: item),
    );
  }

  /// Handle a drop: figure out whether the payload is a template-move
  /// or entry-move, confirm with the teacher, then write and snack.
  Future<void> _onDrop({
    required ScheduleItem item,
    required DateTime sourceDate,
    required DateTime targetDate,
  }) async {
    // No-op when dropped back on its own day.
    if (_sameDay(sourceDate, targetDate)) return;

    // Cancellation/override entries are attached to a specific
    // template on a specific date — they can't be "moved" in any
    // meaningful sense. Surface the toast and stop.
    final isTemplate = item.isFromTemplate && item.templateId != null;
    final isEntry = !item.isFromTemplate && item.entryId != null;
    if (!isTemplate && !isEntry) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'This is a one-day override — edit the original instead.',
            ),
          ),
        );
      return;
    }

    final targetWeekdayLabel = DateFormat.EEEE().format(targetDate);
    final targetWeekdayPlural = '${targetWeekdayLabel}s';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Move "${item.title}"?'),
        content: Text(
          isTemplate
              ? 'Move "${item.title}" to $targetWeekdayPlural? '
                  'Every future week’s occurrence will shift too.'
              : 'Move "${item.title}" to '
                  '${DateFormat.MMMMd().format(targetDate)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Move'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final repo = ref.read(scheduleRepositoryProvider);
    if (isTemplate) {
      await repo.moveTemplateToDay(
        templateId: item.templateId!,
        newDayOfWeek: targetDate.weekday,
      );
    } else {
      await repo.moveEntryToDate(
        entryId: item.entryId!,
        newDate: targetDate,
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text('Moved to $targetWeekdayLabel.')),
      );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheduleAsync = ref.watch(scheduleForWeekProvider(_monday));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Week plan'),
        actions: [
          TextButton.icon(
            onPressed: _duplicateLastWeek,
            icon: const Icon(Icons.content_copy_outlined, size: 18),
            label: const Text('Duplicate last week'),
          ),
          IconButton(
            tooltip: 'Export week',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => exportWeek(context, ref, _monday),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Column(
        children: [
          _WeekNavRow(
            label: _rangeLabel(),
            onPrev: () => _shiftWeek(-1),
            onNext: () => _shiftWeek(1),
            onReset: () => setState(
              () => _monday = _mondayOf(DateTime.now()),
            ),
          ),
          Expanded(
            child: scheduleAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error: $err')),
              data: (byDay) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    // Narrow layout → horizontal scroll. Fixed 220dp
                    // columns keep the cards readable on phones.
                    const columnWidth = 220.0;
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.md,
                      ),
                      child: SizedBox(
                        width: columnWidth * scheduleDayCount,
                        height: constraints.maxHeight - AppSpacing.md * 2,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < scheduleDayCount; i++)
                              Padding(
                                padding: EdgeInsets.only(
                                  right: i == scheduleDayCount - 1
                                      ? 0
                                      : AppSpacing.md,
                                ),
                                child: SizedBox(
                                  width: columnWidth - AppSpacing.md,
                                  child: _DayColumn(
                                    date: _monday.add(Duration(days: i)),
                                    items: byDay[i + 1] ?? const [],
                                    onTapItem: _openDetail,
                                    onAcceptDrop: _onDrop,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      backgroundColor: theme.colorScheme.surface,
    );
  }
}

class _WeekNavRow extends StatelessWidget {
  const _WeekNavRow({
    required this.label,
    required this.onPrev,
    required this.onNext,
    required this.onReset,
  });

  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Previous week',
              onPressed: onPrev,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Center(
                child: TextButton(
                  onPressed: onReset,
                  child: Text(
                    label,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next week',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}

/// Payload for a card drag between columns. Holds just the schedule
/// item plus its source date — the target column contributes its own
/// date when the drop resolves.
class _MoveDragPayload {
  const _MoveDragPayload({required this.item, required this.sourceDate});
  final ScheduleItem item;
  final DateTime sourceDate;
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.date,
    required this.items,
    required this.onTapItem,
    required this.onAcceptDrop,
  });

  final DateTime date;
  final List<ScheduleItem> items;
  final ValueChanged<ScheduleItem> onTapItem;
  final Future<void> Function({
    required ScheduleItem item,
    required DateTime sourceDate,
    required DateTime targetDate,
  }) onAcceptDrop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isToday = _isSameDay(date, DateTime.now());
    // Items already come sorted by isFullDay then startMinutes from
    // the repository. Keep that order as-is.
    return DragTarget<_MoveDragPayload>(
      onWillAcceptWithDetails: (details) {
        // Reject self-drops outright so the column doesn't highlight
        // when you hover your own source column.
        return !_isSameDay(details.data.sourceDate, date);
      },
      onAcceptWithDetails: (details) {
        // Fire-and-forget: the callback drives dialogs + snackbars
        // on its own; the drop itself doesn't await the write.
        unawaited(onAcceptDrop(
          item: details.data.item,
          sourceDate: details.data.sourceDate,
          targetDate: date,
        ));
      },
      builder: (context, candidateData, _) {
        final isHovered = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isHovered
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
                : Colors.transparent,
          ),
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat.EEEE().format(date).toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isToday
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat.MMMd().format(date),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: isToday ? theme.colorScheme.primary : null,
                        fontWeight: isToday ? FontWeight.w700 : null,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? _EmptyDayPlaceholder()
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                        itemCount: items.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (_, i) => _DraggablePlanCard(
                          item: items[i],
                          columnDate: date,
                          onTap: () => onTapItem(items[i]),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _EmptyDayPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Center(
        child: Text(
          'Nothing scheduled',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Wraps [_PlanCard] in a [LongPressDraggable] so long-press starts a
/// move drag and taps still route to the detail sheet. Template and
/// addition-entry cards are draggable; cancellation/override entries
/// (which have `item.entryId` but `isFromTemplate == true`) aren't
/// meaningfully movable, but we let the drop handler surface the
/// explanatory toast rather than silently ignoring the gesture.
class _DraggablePlanCard extends StatelessWidget {
  const _DraggablePlanCard({
    required this.item,
    required this.columnDate,
    required this.onTap,
  });

  final ScheduleItem item;
  final DateTime columnDate;
  final VoidCallback onTap;

  bool get _isDraggable {
    // Pure templates → draggable (move weekday).
    // One-off additions → draggable (move date).
    // Cancellation/override rows surface as isFromTemplate == true
    // with a non-null entryId; skip those.
    if (item.isFromTemplate && item.entryId != null) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final card = _PlanCard(item: item, onTap: onTap);
    if (!_isDraggable) {
      // Still tappable; long-press just shows a toast-style hint.
      return GestureDetector(
        onLongPress: () {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              const SnackBar(
                content: Text(
                  'This is a one-day override — edit the original instead.',
                ),
              ),
            );
        },
        child: card,
      );
    }
    return LongPressDraggable<_MoveDragPayload>(
      data: _MoveDragPayload(item: item, sourceDate: columnDate),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Transform.scale(
          scale: 1.04,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _PlanCard(item: item, onTap: () {}),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: _PlanCard(item: item, onTap: () {}),
      ),
      child: card,
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.item, required this.onTap});

  final ScheduleItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeLabel = item.isFullDay
        ? 'All day'
        : '${_formatTime(item.startTime)}–${_formatTime(item.endTime)}';
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            timeLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.title,
            style: theme.textTheme.titleSmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (item.location != null && item.location!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              item.location!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  static String _formatTime(String hhmm) {
    final parts = hhmm.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour =
        hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final minuteStr = minute.toString().padLeft(2, '0');
    if (minute == 0) return '$displayHour$period';
    return '$displayHour:$minuteStr$period';
  }
}
