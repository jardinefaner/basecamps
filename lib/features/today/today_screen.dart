import 'dart:async';

import 'package:basecamp/core/now_tick.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/attendance/attendance_repository.dart';
import 'package:basecamp/features/attendance/widgets/attendance_sheet.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/forms/parent_concern/parent_concern_repository.dart';
import 'package:basecamp/features/groups/group_detail_screen.dart';
import 'package:basecamp/features/groups/group_summary_repository.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/features/schedule/conflicts.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/widgets/activity_detail_sheet.dart';
import 'package:basecamp/features/schedule/widgets/add_activity_picker.dart';
import 'package:basecamp/features/schedule/widgets/new_activity_wizard.dart';
import 'package:basecamp/features/specialists/adult_timeline_repository.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:basecamp/features/today/adult_staffing.dart';
import 'package:basecamp/features/today/last_expanded_group.dart';
import 'package:basecamp/features/today/today_buckets.dart';
import 'package:basecamp/features/today/widgets/all_day_carousel.dart';
import 'package:basecamp/features/today/widgets/day_summary_strip.dart';
import 'package:basecamp/features/today/widgets/earlier_today_group.dart';
import 'package:basecamp/features/today/widgets/group_today_card.dart';
import 'package:basecamp/features/today/widgets/hero_now_card.dart';
import 'package:basecamp/features/today/widgets/lateness_flags_strip.dart';
import 'package:basecamp/features/today/widgets/schedule_item_card.dart';
import 'package:basecamp/features/today/widgets/staff_today_strip.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
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
    // Groups now own their own schedules — each group card handles
    // its own current/next. The hero slot is reserved for items that
    // dominate the whole program (Morning Circle, all-hands); narrow
    // group-scoped activities below the fold would duplicate what
    // the group stack already shows. Split current/upcoming/past
    // between "program-wide" (hero/banner/chronological) and "group-
    // scoped" (group cards consume them).
    final buckets = bucketTodayItems(items, nowMinutes);
    final current = buckets.current;
    final upcoming = buckets.upcoming;
    final past = buckets.past;
    final allDay = buckets.allDay;

    // Program-wide = all-groups OR explicitly no-groups (staff prep).
    // Anything with a concrete group list is the group stack's job.
    bool isProgramWide(ScheduleItem i) => i.isAllGroups || i.isNoGroups;

    final programCurrent = current.where(isProgramWide).toList();
    final programUpcoming = upcoming.where(isProgramWide).toList();
    final primaryCurrent =
        programCurrent.isEmpty ? null : programCurrent.first;
    final alsoNow = programCurrent.length > 1
        ? programCurrent.sublist(1)
        : const <ScheduleItem>[];

    final nextUp = programUpcoming.isEmpty ? null : programUpcoming.first;
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
        // Loud-when-needed strip: self-hides when zero kids are flagged.
        // Sits right below the date so a late child pulls the eye
        // before anything else on the screen.
        LatenessFlagsStrip(now: now),

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

        // Group stack — one collapsible card per group with that
        // NOW + NEXT + anchor leads. Additive to the hero/upcoming
        // group's at-a-glance; scan the groups first, drill into
        // the chronological list if you need the whole day. Groups
        // self-hide when none are set up yet — brand-new installs
        // fall through to the classic hero layout unchanged.
        _GroupStack(
          items: items,
          now: now,
          attendanceMap: attendanceMap,
          allKids: allKids,
          onOpenDetail: onOpenDetail,
          onOpenAttendance: openAttendance,
        ),

        // Hero "right now" card — dominates the fold when an activity
        // is in progress. When several activities overlap the primary
        // (earliest-started) is the hero; the rest surface compactly
        // in the Also-now strip right below so nothing gets dropped.
        if (primaryCurrent != null) ...[
          HeroNowCard(
            item: primaryCurrent,
            now: now,
            observationCount: activityCounts[primaryCurrent.title] ?? 0,
            attendance: attendanceFor(primaryCurrent),
            onTap: () => onOpenDetail(primaryCurrent),
            onCapture: () => context.go('/observations'),
            onOpenAttendance: () => openAttendance(primaryCurrent),
          ),
          if (alsoNow.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _AlsoNowStrip(
              items: alsoNow,
              now: now,
              onOpenDetail: onOpenDetail,
            ),
          ],
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

        // Upcoming — program-wide items only. Group-scoped upcoming
        // activities show up in their group card's "Next" line, so
        // repeating them here would duplicate. First program-wide
        // upcoming gets the "IN N MIN" chip.
        for (var i = 0; i < programUpcoming.length; i++) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: ScheduleItemCard(
              item: programUpcoming[i],
              isNow: false,
              isPast: false,
              conflicts: conflicts[programUpcoming[i].id] ?? const [],
              minutesUntilStart: i == 0 ? nextUpMinutes : null,
              concernMatch: concernForItem(programUpcoming[i]),
              onTap: () => onOpenDetail(programUpcoming[i]),
              onOpenConcern: () => _goConcern(
                context,
                concernForItem(programUpcoming[i])?.id,
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
        // Program stats drawer — counts + staff shift overview. Lives
        // at the bottom collapsed by default because these are review-
        // mode numbers (pre-open / end-of-day glance), not something
        // the teacher needs to scan while mid-day.
        const SizedBox(height: AppSpacing.md),
        _ProgramStatsDrawer(
          now: now,
          activityCount: items.length,
          childrenCount: childrenInActivityGroups.length,
          specialistCount: uniqueSpecialists.length,
          concernCount: concerns.length,
          pendingObs: pendingObs,
          onTapConcerns: () => context.push('/more/forms/parent-concern'),
          onTapPending: () => context.go('/observations'),
        ),
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

/// The group stack on Today — one collapsible [GroupTodayCard] per group,
/// each showing that group's NOW + NEXT + staffing. Listens to
/// `groupSummariesProvider` and `lastExpandedGroupProvider`; the latter
/// persists across app restarts so the teacher's group opens to the
/// same card they last looked at.
///
/// Self-hides when no groups exist yet (brand-new install) — the screen
/// falls back to the classic hero layout without the group section.
class _GroupStack extends ConsumerWidget {
  const _GroupStack({
    required this.items,
    required this.now,
    required this.attendanceMap,
    required this.allKids,
    required this.onOpenDetail,
    required this.onOpenAttendance,
  });

  final List<ScheduleItem> items;
  final DateTime now;
  final Map<String, AttendanceRecord> attendanceMap;
  final List<Child> allKids;
  final ValueChanged<ScheduleItem> onOpenDetail;
  final Future<void> Function(ScheduleItem) onOpenAttendance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summariesAsync = ref.watch(groupSummariesProvider);
    final summaries = summariesAsync.asData?.value ?? const <GroupSummary>[];
    if (summaries.isEmpty) return const SizedBox.shrink();

    final expandedId = ref.watch(lastExpandedGroupProvider);
    final nowMinutes = now.hour * 60 + now.minute;

    // Adult day-timeline resolution (v30). Watching these here keeps
    // the "who's leading this group right now" computation live —
    // edits to a block on the adult edit sheet rebuild the group card
    // without a screen re-mount.
    final specialists =
        ref.watch(specialistsProvider).asData?.value ?? const <Specialist>[];
    final blockRows = ref.watch(todayAdultBlocksProvider).asData?.value ??
        const <AdultDayBlock>[];
    final blocksBySpecialist = groupBlocksBySpecialist(blockRows);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in summaries) ...[
          GroupTodayCard(
            group: g,
            now: now,
            current: _currentFor(g, nowMinutes),
            next: _nextFor(g, nowMinutes),
            attendance: _attendanceFor(g),
            leadsNow: _leadsNowFor(
              group: g,
              nowMinutes: nowMinutes,
              specialists: specialists,
              blocksBySpecialist: blocksBySpecialist,
            ),
            expanded: expandedId == g.id,
            onToggle: () =>
                ref.read(lastExpandedGroupProvider.notifier).toggle(g.id),
            onOpenDetail: onOpenDetail,
            onOpenAttendance: onOpenAttendance,
            onOpenGroupDetail: () =>
                GroupDetailScreen.open(context, g.id),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }

  /// Resolves adults currently anchoring `group` — timeline-lead
  /// blocks straddling now plus static-anchor leads (for adults with
  /// no timeline). Returns the `Specialist` rows in lead-name order
  /// so the avatars render predictably.
  List<Specialist> _leadsNowFor({
    required GroupSummary group,
    required int nowMinutes,
    required List<Specialist> specialists,
    required Map<String, List<AdultTimelineBlock>> blocksBySpecialist,
  }) {
    final leadIds = leadsInGroupNow(
      groupId: group.id,
      nowMinutes: nowMinutes,
      specialists: specialists,
      blocksBySpecialist: blocksBySpecialist,
    );
    final byId = {for (final s in specialists) s.id: s};
    final leads = [
      for (final id in leadIds)
        if (byId[id] != null) byId[id]!,
    ]..sort((a, b) => a.name.compareTo(b.name));
    return leads;
  }

  /// The group's current in-progress activity, if any. A group-scoped
  /// item matches when `groupIds` contains the group's id; earliest-
  /// started wins the slot the same way the global hero does.
  ScheduleItem? _currentFor(GroupSummary group, int nowMinutes) {
    ScheduleItem? best;
    for (final item in items) {
      if (item.isFullDay) continue;
      if (!item.groupIds.contains(group.id)) continue;
      final start = item.startMinutes;
      final end = item.endMinutes;
      if (nowMinutes < start || nowMinutes >= end) continue;
      if (best == null || item.startMinutes < best.startMinutes) {
        best = item;
      }
    }
    return best;
  }

  /// The group's next upcoming activity. First future item whose
  /// groupIds include the group. Skips full-day items.
  ScheduleItem? _nextFor(GroupSummary group, int nowMinutes) {
    ScheduleItem? best;
    for (final item in items) {
      if (item.isFullDay) continue;
      if (!item.groupIds.contains(group.id)) continue;
      if (item.startMinutes <= nowMinutes) continue;
      if (best == null || item.startMinutes < best.startMinutes) {
        best = item;
      }
    }
    return best;
  }

  /// Today's attendance summary for the group — present/absent/total
  /// count rolled up from the kids assigned to this group. Null when
  /// the group has no kids yet (brand-new group).
  AttendanceSummary? _attendanceFor(GroupSummary group) {
    var present = 0;
    var absent = 0;
    var total = 0;
    for (final k in allKids) {
      if (k.groupId != group.id) continue;
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
}

/// Bottom-of-Today drawer collapsing the day-summary numbers and
/// staff-today strip behind a single tap. Keeps the fold quiet — the
/// counts are pre-open / end-of-day review material, not something
/// the teacher needs while mid-day. Expanding shows both in the
/// order they used to live at the top.
class _ProgramStatsDrawer extends StatelessWidget {
  const _ProgramStatsDrawer({
    required this.now,
    required this.activityCount,
    required this.childrenCount,
    required this.specialistCount,
    required this.concernCount,
    required this.pendingObs,
    required this.onTapConcerns,
    required this.onTapPending,
  });

  final DateTime now;
  final int activityCount;
  final int childrenCount;
  final int specialistCount;
  final int concernCount;
  final int pendingObs;
  final VoidCallback onTapConcerns;
  final VoidCallback onTapPending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      // Kill the default ExpansionTile divider; we already sit inside
      // a padded scroll view and the extra rule reads as noise.
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
        ),
        childrenPadding: const EdgeInsets.only(top: AppSpacing.sm),
        leading: Icon(
          Icons.insights_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(
          'Program stats',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '$activityCount activities · $childrenCount children · '
          '$specialistCount adults',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          DaySummaryStrip(
            activities: activityCount,
            children: childrenCount,
            specialists: specialistCount,
            concerns: concernCount,
            pendingObs: pendingObs,
            onTapConcerns: onTapConcerns,
            onTapPending: onTapPending,
          ),
          const SizedBox(height: AppSpacing.sm),
          StaffTodayStrip(now: now),
        ],
      ),
    );
  }
}

/// Compact "Also now" strip rendered directly under the hero when more
/// than one activity is currently in progress. One row per overlapping
/// activity; tapping a row opens its detail sheet (same behavior as
/// tapping the hero). Kept intentionally thin — the hero is the thing
/// dominating the fold; this is just "and these other things are also
/// happening right now, don't forget."
class _AlsoNowStrip extends StatelessWidget {
  const _AlsoNowStrip({
    required this.items,
    required this.now,
    required this.onOpenDetail,
  });

  final List<ScheduleItem> items;
  final DateTime now;
  final ValueChanged<ScheduleItem> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text(
              'ALSO NOW',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 0.5,
                color: theme.colorScheme.outlineVariant,
              ),
            _AlsoNowRow(
              item: items[i],
              now: now,
              onTap: () => onOpenDetail(items[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _AlsoNowRow extends StatelessWidget {
  const _AlsoNowRow({
    required this.item,
    required this.now,
    required this.onTap,
  });

  final ScheduleItem item;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nowMinutes = now.hour * 60 + now.minute;
    final minsLeft = item.endMinutes - nowMinutes;
    // "ends in 12 min" / "ends at 11:00" — short form because the row
    // is already crowded with the title + optional location.
    final endLabel = minsLeft <= 1
        ? 'ending now'
        : minsLeft <= 30
            ? 'ends in $minsLeft min'
            : 'ends ${_formatTime(item.endTime)}';
    final meta = <String>[
      endLabel,
      if (item.location != null && item.location!.trim().isNotEmpty)
        item.location!.trim(),
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (meta.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        meta,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  /// Formats an "HH:mm" wire-format time as a human 12-hour display
  /// ("11:00 AM"). Intentionally tiny — the row only ever shows end
  /// times for the "Also now" strip, so a dedicated util isn't worth
  /// the import.
  String _formatTime(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final period = h >= 12 ? 'PM' : 'AM';
    return '$hour12:${m.toString().padLeft(2, '0')} $period';
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
