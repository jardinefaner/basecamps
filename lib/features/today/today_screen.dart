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
import 'package:basecamp/features/today/last_expanded_group.dart';
import 'package:basecamp/features/today/today_buckets.dart';
import 'package:basecamp/features/today/today_mode.dart';
import 'package:basecamp/features/today/widgets/all_day_carousel.dart';
import 'package:basecamp/features/today/widgets/day_summary_strip.dart';
import 'package:basecamp/features/today/widgets/earlier_today_group.dart';
import 'package:basecamp/features/today/widgets/hero_now_card.dart';
import 'package:basecamp/features/today/widgets/lateness_flags_strip.dart';
import 'package:basecamp/features/today/widgets/schedule_item_card.dart';
import 'package:basecamp/features/today/widgets/staff_today_strip.dart';
import 'package:basecamp/features/today/widgets/today_agenda.dart';
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
            // Title carries today's date inline so a quick glance
            // confirms the day without scrolling. Weekday + short
            // date — the full year is visible enough elsewhere.
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Today'),
                Text(
                  dateLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            floating: true,
            snap: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.tune_outlined),
                tooltip: 'Schedule',
                onPressed: () => context.push('/today/schedule'),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Program settings',
                onPressed: () => context.push('/more/settings'),
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
    final buckets = bucketTodayItems(items, nowMinutes);
    final current = buckets.current;
    final upcoming = buckets.upcoming;
    final past = buckets.past;
    final allDay = buckets.allDay;

    // Selected group from the chip row. Null → first-available
    // fallback happens in _GroupChipRow; by the time we land here
    // we treat null as "show everything" (legacy behavior for
    // installs with no groups yet).
    final selectedGroupId = ref.watch(lastExpandedGroupProvider);

    // Filter by selection: group-scoped items for the selected group
    // PLUS program-wide items (Morning Circle for everyone). Staff-
    // prep (no-groups) items land in the selected view too because
    // they're relevant to anyone running the program that day.
    bool inSelectedView(ScheduleItem i) {
      if (selectedGroupId == null) return true;
      if (i.isAllGroups || i.isNoGroups) return true;
      return i.groupIds.contains(selectedGroupId);
    }

    final filteredCurrent = current.where(inSelectedView).toList();
    final filteredUpcoming = upcoming.where(inSelectedView).toList();
    final filteredPast = past.where(inSelectedView).toList();
    final primaryCurrent =
        filteredCurrent.isEmpty ? null : filteredCurrent.first;
    final alsoNow = filteredCurrent.length > 1
        ? filteredCurrent.sublist(1)
        : const <ScheduleItem>[];

    final nextUp =
        filteredUpcoming.isEmpty ? null : filteredUpcoming.first;
    final nextUpMinutes = nextUp == null
        ? null
        : nextUp.startMinutes - nowMinutes;

    // -- Day-summary numbers --
    // Scoped to the selected group when one is picked (a group only
    // cares about its own stats); program-wide otherwise. The chip
    // row sits directly above the stats strip so the relationship
    // reads visually — pick a group, the numbers follow.
    final scopedItems =
        selectedGroupId == null ? items : items.where(inSelectedView).toList();
    final uniqueAdults = <String>{
      for (final i in scopedItems)
        if (i.adultId != null) i.adultId!,
    };
    final childrenInActivityGroups = <String>{};
    for (final i in scopedItems) {
      // An "all groups" activity pulls in every child; a group-scoped one
      // pulls in just that group's children; an intentionally group-less
      // activity (staff prep etc.) pulls in nobody. When a group is
      // selected, we further clip to children in that group so the count
      // reads as "kids in this group touched by scheduled activities."
      if (i.isNoGroups) continue;
      for (final child in allKids) {
        if (selectedGroupId != null && child.groupId != selectedGroupId) {
          continue;
        }
        if (i.isAllGroups) {
          childrenInActivityGroups.add(child.id);
        } else if (child.groupId != null && i.groupIds.contains(child.groupId)) {
          childrenInActivityGroups.add(child.id);
        }
      }
    }
    // Concerns scoped to the selected group's children when a group
    // is picked. Uses the concern→child link map from the repository;
    // no link map entry means a concern that doesn't tie to a child,
    // which falls out of the per-group count (by design).
    final scopedConcerns = selectedGroupId == null
        ? concerns
        : concerns.where((c) {
            final linkedChildIds = concernChildLinks[c.id] ?? const <String>{};
            if (linkedChildIds.isEmpty) return false;
            for (final cid in linkedChildIds) {
              for (final k in allKids) {
                if (k.id == cid && k.groupId == selectedGroupId) {
                  return true;
                }
              }
            }
            return false;
          }).toList();
    // Past activities with zero observations logged today, scoped to
    // the selected view so the "pending" count matches what's actually
    // on screen below.
    final pendingObs = (selectedGroupId == null ? past : filteredPast)
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
        // Loud-when-needed strip: self-hides when zero kids are flagged
        // and no reviews are due. Sits at the top so a late child or
        // overdue review pulls the eye before anything else.
        LatenessFlagsStrip(now: now),

        // All-day activities / notes float above the per-group view.
        // Program-wide context (field trip banners, whole-day notes)
        // isn't tied to a specific group's chip selection.
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

        // Mode toggle — Groups view vs Agenda view. Coexist by
        // design; teachers pick based on the question they want
        // answered right now. Persists across launches via
        // todayModeProvider.
        _TodayModeToggle(mode: ref.watch(todayModeProvider)),
        const SizedBox(height: AppSpacing.md),

        // Group chip selector — horizontally scrollable row of groups.
        // Same in both modes: in Groups mode it drives the hero/
        // upcoming/earlier filter; in Agenda mode it scopes the
        // chronological feed to the selected group + program-wide +
        // that group's leads' breaks.
        const _GroupChipRow(),
        const SizedBox(height: AppSpacing.md),

        // Day stats sit under the group chip row so the numbers track
        // the selected group: pick "Butterflies" and the counts rescope
        // to that group only. With no group selected, the counts read
        // program-wide. Compact — one strip, five numbers, tappable.
        DaySummaryStrip(
          activities: scopedItems.length,
          children: childrenInActivityGroups.length,
          adults: uniqueAdults.length,
          concerns: scopedConcerns.length,
          pendingObs: pendingObs,
          onTapConcerns: () =>
              context.push('/more/forms/parent-concern'),
          onTapPending: () => context.go('/observations'),
        ),
        const SizedBox(height: AppSpacing.md),

        // Body branches on mode. Agenda mode renders the calendar
        // synthesizer's chronological feed; Groups mode keeps the
        // hero / upcoming / earlier layout below.
        if (ref.watch(todayModeProvider) == TodayMode.agenda) ...[
          TodayAgendaView(now: now),
          const SizedBox(height: AppSpacing.xl),
        ] else ...[

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

        // Upcoming — filtered to the selected group's schedule (plus
        // program-wide items). First gets the "IN N MIN" chip.
        for (var i = 0; i < filteredUpcoming.length; i++) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: ScheduleItemCard(
              item: filteredUpcoming[i],
              isNow: false,
              isPast: false,
              conflicts: conflicts[filteredUpcoming[i].id] ?? const [],
              minutesUntilStart: i == 0 ? nextUpMinutes : null,
              concernMatch: concernForItem(filteredUpcoming[i]),
              onTap: () => onOpenDetail(filteredUpcoming[i]),
              onOpenConcern: () => _goConcern(
                context,
                concernForItem(filteredUpcoming[i])?.id,
              ),
            ),
          ),
        ],

        // Earlier today — filtered to the selected group. Collapsible
        // so the morning doesn't clutter the afternoon view.
        if (filteredPast.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          EarlierTodayGroup(
            count: filteredPast.length,
            children: [
              for (final item in filteredPast)
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
        ], // end Groups-mode body
        // Staff-today strip at the bottom in both modes — still
        // collapsible, still handy for end-of-day roll review.
        const SizedBox(height: AppSpacing.md),
        StaffTodayStrip(now: now),
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

/// Groups vs Agenda mode toggle. Small pill row — "Groups" lens
/// for the per-group NOW / NEXT / EARLIER focus, "Agenda" lens for
/// the chronological feed that weaves activities + trips + (for
/// the selected group's leads) breaks.
class _TodayModeToggle extends ConsumerWidget {
  const _TodayModeToggle({required this.mode});

  final TodayMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SegmentedButton<TodayMode>(
      segments: const [
        ButtonSegment<TodayMode>(
          value: TodayMode.groups,
          label: Text('Groups'),
          icon: Icon(Icons.groups_2_outlined, size: 16),
        ),
        ButtonSegment<TodayMode>(
          value: TodayMode.agenda,
          label: Text('Agenda'),
          icon: Icon(Icons.schedule_outlined, size: 16),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (set) {
        if (set.isEmpty) return;
        unawaited(ref.read(todayModeProvider.notifier).set(set.first));
      },
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// Horizontally scrolling chip row — one chip per group plus a
/// long-press affordance per chip to open the group detail screen.
/// Selection drives the hero / upcoming / earlier filter on Today;
/// selection state persists across app launches via
/// `lastExpandedGroupProvider` (name kept from the pre-redesign
/// "last-expanded" semantics; same SharedPreferences key, same
/// meaning — which group the teacher is focused on).
///
/// Self-hides when no groups exist (brand-new install), in which
/// case the sections below fall through to the unfiltered schedule.
class _GroupChipRow extends ConsumerStatefulWidget {
  const _GroupChipRow();

  @override
  ConsumerState<_GroupChipRow> createState() => _GroupChipRowState();
}

class _GroupChipRowState extends ConsumerState<_GroupChipRow> {
  bool _autoSelected = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summariesAsync = ref.watch(groupSummariesProvider);
    final summaries =
        summariesAsync.asData?.value ?? const <GroupSummary>[];
    if (summaries.isEmpty) return const SizedBox.shrink();

    final selectedId = ref.watch(lastExpandedGroupProvider);

    // First launch / stale selection → default-select the first
    // group so the sections below have something to filter by. Done
    // as a post-frame side effect to avoid modifying provider state
    // during build.
    if (!_autoSelected &&
        (selectedId == null ||
            !summaries.any((g) => g.id == selectedId))) {
      _autoSelected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
          ref
              .read(lastExpandedGroupProvider.notifier)
              .toggle(summaries.first.id),
        );
      });
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          for (final g in summaries) ...[
            _GroupChip(
              summary: g,
              selected: g.id == selectedId,
              onSelected: () => ref
                  .read(lastExpandedGroupProvider.notifier)
                  .toggle(g.id),
              onLongPress: () =>
                  GroupDetailScreen.open(context, g.id),
              theme: theme,
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

/// Single chip in the group row. Color dot pulls from the group's
/// hex (falls back to primary) so the chip pops visually without
/// fighting the global theme. Long-press drills into the group's
/// detail screen — the common tap toggles selection.
class _GroupChip extends StatelessWidget {
  const _GroupChip({
    required this.summary,
    required this.selected,
    required this.onSelected,
    required this.onLongPress,
    required this.theme,
  });

  final GroupSummary summary;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback onLongPress;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final color = _parseHex(summary.group.colorHex) ??
        theme.colorScheme.primary;
    return GestureDetector(
      onLongPress: onLongPress,
      child: FilterChip(
        selected: selected,
        onSelected: (_) => onSelected(),
        showCheckmark: false,
        avatar: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        label: Text(
          '${summary.name} · ${summary.childCount}',
          style: theme.textTheme.labelMedium,
        ),
      ),
    );
  }

  Color? _parseHex(String? hex) {
    if (hex == null) return null;
    final h = hex.startsWith('#') ? hex.substring(1) : hex;
    if (h.length != 6 && h.length != 8) return null;
    final intVal = int.tryParse(h, radix: 16);
    if (intVal == null) return null;
    return Color(h.length == 6 ? 0xFF000000 | intVal : intVal);
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
