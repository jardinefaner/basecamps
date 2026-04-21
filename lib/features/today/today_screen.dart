import 'dart:async';

import 'package:basecamp/core/now_tick.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/attendance/attendance_repository.dart';
import 'package:basecamp/features/attendance/widgets/attendance_sheet.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/forms/parent_concern/parent_concern_repository.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/features/schedule/conflicts.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/widgets/activity_detail_sheet.dart';
import 'package:basecamp/features/schedule/widgets/add_activity_picker.dart';
import 'package:basecamp/features/schedule/widgets/new_activity_wizard.dart';
import 'package:basecamp/features/today/widgets/all_day_carousel.dart';
import 'package:basecamp/features/today/widgets/day_summary_strip.dart';
import 'package:basecamp/features/today/widgets/earlier_today_group.dart';
import 'package:basecamp/features/today/widgets/hero_now_card.dart';
import 'package:basecamp/features/today/widgets/schedule_item_card.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Today dashboard. Orchestrates the live clock, day-summary strip, a
/// hero "right now" card for the current activity, an upcoming list
/// with next-up/countdown cues and "log observations" prompts, and a
/// collapsible "earlier today" section for what already happened.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  Future<void> _openDetail(BuildContext context, ScheduleItem item) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ActivityDetailSheet(item: item),
    );
  }

  Future<void> _openAddPicker(BuildContext context, DateTime now) async {
    // Same picker the Schedule editor uses — keeps the add flow single
    // across both surfaces. The picker forwards a CreatedActivity up
    // through its own pop when a wizard actually creates something.
    final result = await showModalBottomSheet<CreatedActivity>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AddActivityPicker(initialDate: now),
    );
    if (result == null || !context.mounted) return;
    // Confirmation snackbar so the teacher sees that creation happened
    // even when the activity is dated outside today (in which case it
    // won't appear on the Today tab — e.g. a "next Monday" one-off).
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(_describeCreated(result)),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  String _describeCreated(CreatedActivity c) {
    final title = c.title.isEmpty ? 'Activity' : c.title;
    final dayPart = c.dayCount == 1 ? 'added' : 'added on ${c.dayCount} days';
    final range = c.startDate == null
        ? ''
        : (c.endDate == null
            ? ', starting ${DateFormat.MMMd().format(c.startDate!)}'
            : ', ${DateFormat.MMMd().format(c.startDate!)} → ${DateFormat.MMMd().format(c.endDate!)}');
    return '$title $dayPart$range';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watching this rebuilds the screen on every wall-clock minute so
    // countdowns and "NOW" status stay truthful without timers in the
    // widget tree.
    final nowAsync = ref.watch(nowTickProvider);
    final now = nowAsync.asData?.value ?? DateTime.now();

    final scheduleAsync = ref.watch(todayScheduleProvider);
    final theme = Theme.of(context);
    final dateLabel = DateFormat('EEEE · MMMM d').format(now);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddPicker(context, now),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('Today'),
            floating: true,
            snap: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.tune_outlined),
                tooltip: 'Schedule',
                onPressed: () => context.push('/today/schedule'),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
          ),
          scheduleAsync.when(
            loading: () => const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('Error: $err')),
            ),
            data: (items) => _Body(
              items: items,
              now: now,
              dateLabel: dateLabel,
              theme: theme,
              onOpenDetail: (item) => _openDetail(context, item),
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.items,
    required this.now,
    required this.dateLabel,
    required this.theme,
    required this.onOpenDetail,
  });

  final List<ScheduleItem> items;
  final DateTime now;
  final String dateLabel;
  final ThemeData theme;
  final ValueChanged<ScheduleItem> onOpenDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            _DateLabel(label: dateLabel),
            const SizedBox(height: AppSpacing.md),
            _EmptyState(onEdit: () => context.push('/today/schedule')),
          ]),
        ),
      );
    }

    final nowMinutes = now.hour * 60 + now.minute;
    final conflicts = conflictsByItemId(items);
    final activityCounts =
        ref.watch(todayActivityCountsProvider).asData?.value ??
            const <String, int>{};
    final concerns =
        ref.watch(todayConcernNotesProvider).asData?.value ??
            const <ParentConcernNote>[];
    final concernChildLinks =
        ref.watch(concernKidLinksProvider).asData?.value ??
            const <String, Set<String>>{};
    final allKids =
        ref.watch(childrenProvider).asData?.value ?? const <Child>[];
    final attendanceMap =
        ref.watch(todayAttendanceProvider).asData?.value ??
            const <String, AttendanceRecord>{};

    // -- Bucket items by time relative to now --
    ScheduleItem? currentItem;
    final upcoming = <ScheduleItem>[];
    final past = <ScheduleItem>[];
    final allDay = <ScheduleItem>[];
    for (final item in items) {
      if (item.isFullDay) {
        allDay.add(item);
        continue;
      }
      final endParts = item.endTime.split(':');
      final endMin = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
      if (nowMinutes >= item.startMinutes && nowMinutes < endMin) {
        currentItem = item;
      } else if (nowMinutes >= endMin) {
        past.add(item);
      } else {
        upcoming.add(item);
      }
    }

    final nextUp = upcoming.isEmpty ? null : upcoming.first;
    final nextUpMinutes = nextUp == null
        ? null
        : nextUp.startMinutes - nowMinutes;

    // -- Day-summary numbers --
    final uniqueSpecialists = <String>{
      for (final i in items)
        if (i.specialistId != null) i.specialistId!,
    };
    final childrenInActivityGroups = <String>{};
    for (final i in items) {
      // An "all groups" activity pulls in every child; a group-scoped one
      // pulls in just that group's children; an intentionally group-less
      // activity (staff prep etc.) pulls in nobody.
      if (i.isNoGroups) continue;
      for (final child in allKids) {
        if (i.isAllGroups) {
          childrenInActivityGroups.add(child.id);
        } else if (child.groupId != null && i.groupIds.contains(child.groupId)) {
          childrenInActivityGroups.add(child.id);
        }
      }
    }
    // Past activities with zero observations logged today.
    final pendingObs = past
        .where((i) => (activityCounts[i.title] ?? 0) == 0)
        .length;

    AttendanceSummary? attendanceFor(ScheduleItem item) {
      // Attendance strip is only useful for group-scoped activities.
      // All-groups = "everyone" — use the whole-day check-in flow
      // elsewhere; cluttering the hero with a strip for Morning
      // Circle (i.e. literally every kid) is noise. Staff-prep
      // activities have no children to track.
      if (item.groupIds.isEmpty || item.isAllGroups || item.isNoGroups) {
        return null;
      }
      var present = 0;
      var absent = 0;
      var total = 0;
      for (final k in allKids) {
        if (k.groupId == null || !item.groupIds.contains(k.groupId)) continue;
        total++;
        final status = attendanceMap[k.id]?.status;
        if (status == AttendanceStatus.present) {
          present++;
        } else if (status == AttendanceStatus.absent) {
          absent++;
        }
      }
      if (total == 0) return null;
      return AttendanceSummary(
        present: present,
        absent: absent,
        total: total,
      );
    }

    Future<void> openAttendance(ScheduleItem item) {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (_) => AttendanceSheet(
          groupIds: item.groupIds,
          date: now,
          activityTitle: item.title,
        ),
      );
    }

    ConcernMatch? concernForItem(ScheduleItem item) {
      // "All groups" activities aren't usefully tied to one child's
      // concern — they're for everyone. No-groups activities have no
      // children at all. Only narrow, group-scoped activities get the
      // flag.
      if (concerns.isEmpty ||
          item.groupIds.isEmpty ||
          item.isAllGroups ||
          item.isNoGroups) {
        return null;
      }
      final groupChildIds = <String>{
        for (final k in allKids)
          if (k.groupId != null && item.groupIds.contains(k.groupId)) k.id,
      };
      if (groupChildIds.isEmpty) return null;
      // Newest first — `concerns` is already sorted by updatedAt desc.
      for (final c in concerns) {
        final linked = concernChildLinks[c.id];
        if (linked == null || linked.isEmpty) continue;
        if (linked.any(groupChildIds.contains)) {
          return ConcernMatch(
            id: c.id,
            preview: _concernPreview(c),
          );
        }
      }
      return null;
    }

    return SliverPadding(
      padding: const EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.md,
        bottom: AppSpacing.xxxl * 2,
      ),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
        _DateLabel(label: dateLabel),
        const SizedBox(height: AppSpacing.sm),
        DaySummaryStrip(
          activities: items.length,
          children: childrenInActivityGroups.length,
          specialists: uniqueSpecialists.length,
          concerns: concerns.length,
          pendingObs: pendingObs,
          onTapConcerns: () =>
              context.push('/more/forms/parent-concern'),
          onTapPending: () => context.go('/observations'),
        ),
        const SizedBox(height: AppSpacing.lg),

        // All-day activities / notes float above the hero. One or many,
        // they share a single slot — multiple items cycle through a
        // carousel with autoplay so the vertical space stays constant.
        // No "NOW" chip here: "all day" already implies current-day
        // context, and the hero below owns the right-now moment.
        if (allDay.isNotEmpty) ...[
          AllDayCarousel(
            cards: [
              for (final item in allDay)
                ScheduleItemCard(
                  item: item,
                  isNow: false,
                  isPast: false,
                  conflicts: conflicts[item.id] ?? const [],
                  concernMatch: concernForItem(item),
                  attendance: attendanceFor(item),
                  onTap: () => onOpenDetail(item),
                  onOpenConcern: () => _goConcern(
                    context,
                    concernForItem(item)?.id,
                  ),
                  onOpenAttendance: () => openAttendance(item),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // Hero "right now" card — dominates the fold when an activity
        // is in progress.
        if (currentItem != null) ...[
          HeroNowCard(
            item: currentItem,
            now: now,
            observationCount: activityCounts[currentItem.title] ?? 0,
            attendance: attendanceFor(currentItem),
            onTap: () => onOpenDetail(currentItem!),
            onCapture: () => context.go('/observations'),
            onOpenAttendance: () => openAttendance(currentItem!),
          ),
          const SizedBox(height: AppSpacing.lg),
        ] else if (nextUp != null) ...[
          _BetweenActivitiesBanner(
            minutesUntilNext: nextUpMinutes ?? 0,
            nextTitle: nextUp.title,
          ),
          const SizedBox(height: AppSpacing.lg),
        ] else if (past.isNotEmpty && allDay.isEmpty) ...[
          _WrapUpBanner(
            onReview: () => context.go('/observations'),
            pendingCount: pendingObs,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],

        // Upcoming. First one gets the "IN N MIN" chip. No attendance
        // strip — it hasn't started yet, so "0/N present · N pending"
        // is always-true noise that clutters the view. The hero card
        // owns the attendance affordance once an activity becomes NOW.
        for (var i = 0; i < upcoming.length; i++) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: ScheduleItemCard(
              item: upcoming[i],
              isNow: false,
              isPast: false,
              conflicts: conflicts[upcoming[i].id] ?? const [],
              minutesUntilStart: i == 0 ? nextUpMinutes : null,
              concernMatch: concernForItem(upcoming[i]),
              onTap: () => onOpenDetail(upcoming[i]),
              onOpenConcern: () => _goConcern(
                context,
                concernForItem(upcoming[i])?.id,
              ),
            ),
          ),
        ],

        // Earlier today — collapsible so the morning doesn't clutter
        // the afternoon view.
        if (past.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          EarlierTodayGroup(
            count: past.length,
            children: [
              for (final item in past)
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.sm,
                  ),
                  child: ScheduleItemCard(
                    item: item,
                    isNow: false,
                    isPast: true,
                    conflicts: conflicts[item.id] ?? const [],
                    showLogObservationsPrompt:
                        (activityCounts[item.title] ?? 0) == 0,
                    concernMatch: concernForItem(item),
                    attendance: attendanceFor(item),
                    onTap: () => onOpenDetail(item),
                    onLogObservations: () => context.go('/observations'),
                    onOpenConcern: () => _goConcern(
                      context,
                      concernForItem(item)?.id,
                    ),
                    onOpenAttendance: () => openAttendance(item),
                  ),
                ),
            ],
          ),
        ],
        ]),
      ),
    );
  }

  void _goConcern(BuildContext context, String? concernId) {
    // With the structured concern↔child join we can jump straight to
    // the matching note rather than dumping the teacher onto the list
    // to hunt for it. Fall back to the list when no id is handed over
    // (shouldn't happen, but harmless).
    final route = concernId == null
        ? '/more/forms/parent-concern'
        : '/more/forms/parent-concern/$concernId';
    unawaited(context.push(route));
  }

  String _concernPreview(ParentConcernNote note) {
    final names = note.childNames.trim();
    final desc = note.concernDescription.trim();
    if (names.isNotEmpty && desc.isNotEmpty) {
      return '$names — $desc';
    }
    if (desc.isNotEmpty) return desc;
    if (names.isNotEmpty) return 'Concern noted for $names';
    return 'Active concern today';
  }
}

class _DateLabel extends StatelessWidget {
  const _DateLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelMedium,
      ),
    );
  }
}

class _BetweenActivitiesBanner extends StatelessWidget {
  const _BetweenActivitiesBanner({
    required this.minutesUntilNext,
    required this.nextTitle,
  });

  final int minutesUntilNext;
  final String nextTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = minutesUntilNext <= 1
        ? 'Starting in 1 min'
        : 'Starting in $minutesUntilNext min';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.hourglass_bottom,
            size: 18,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Between activities',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer
                        .withValues(alpha: 0.75),
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$label · $nextTitle',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
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

class _WrapUpBanner extends StatelessWidget {
  const _WrapUpBanner({
    required this.onReview,
    required this.pendingCount,
  });

  final VoidCallback onReview;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = pendingCount == 0
        ? 'All activities logged. Nice work.'
        : pendingCount == 1
            ? '1 activity still needs observations.'
            : '$pendingCount activities still need observations.';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            Icons.nightlight_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "That's a wrap",
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (pendingCount > 0)
            TextButton(
              onPressed: onReview,
              child: const Text('Review'),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onEdit});

  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.schedule_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Nothing scheduled today',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Set up a weekly schedule or add one-off activities.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.tune_outlined),
              label: const Text('Edit schedule'),
            ),
          ],
        ),
      ),
    );
  }
}
