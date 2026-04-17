import 'dart:async';

import 'package:basecamp/core/now_tick.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/forms/parent_concern/parent_concern_repository.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/features/schedule/conflicts.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/widgets/activity_detail_sheet.dart';
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
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_outlined),
            tooltip: 'Schedule',
            onPressed: () => context.push('/today/schedule'),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: scheduleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (items) => _Body(
          items: items,
          now: now,
          dateLabel: dateLabel,
          theme: theme,
          onOpenDetail: (item) => _openDetail(context, item),
        ),
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
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _DateLabel(label: dateLabel),
          const SizedBox(height: AppSpacing.md),
          _EmptyState(onEdit: () => context.push('/today/schedule')),
        ],
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
    final concernKidLinks =
        ref.watch(concernKidLinksProvider).asData?.value ??
            const <String, Set<String>>{};
    final allKids =
        ref.watch(kidsProvider).asData?.value ?? const <Kid>[];

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
    final kidsInActivityPods = <String>{};
    for (final i in items) {
      // An "all pods" activity pulls in every kid; a pod-scoped one
      // pulls in just that pod's kids; an intentionally pod-less
      // activity (staff prep etc.) pulls in nobody.
      if (i.isNoPods) continue;
      for (final kid in allKids) {
        if (i.isAllPods) {
          kidsInActivityPods.add(kid.id);
        } else if (kid.podId != null && i.podIds.contains(kid.podId)) {
          kidsInActivityPods.add(kid.id);
        }
      }
    }
    // Past activities with zero observations logged today.
    final pendingObs = past
        .where((i) => (activityCounts[i.title] ?? 0) == 0)
        .length;

    ConcernMatch? concernForItem(ScheduleItem item) {
      // "All groups" activities aren't usefully tied to one child's
      // concern — they're for everyone. No-groups activities have no
      // children at all. Only narrow, group-scoped activities get the
      // flag.
      if (concerns.isEmpty ||
          item.podIds.isEmpty ||
          item.isAllPods ||
          item.isNoPods) {
        return null;
      }
      final podKidIds = <String>{
        for (final k in allKids)
          if (k.podId != null && item.podIds.contains(k.podId)) k.id,
      };
      if (podKidIds.isEmpty) return null;
      // Newest first — `concerns` is already sorted by updatedAt desc.
      for (final c in concerns) {
        final linked = concernKidLinks[c.id];
        if (linked == null || linked.isEmpty) continue;
        if (linked.any(podKidIds.contains)) {
          return ConcernMatch(
            id: c.id,
            preview: _concernPreview(c),
          );
        }
      }
      return null;
    }

    return ListView(
      padding: const EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.md,
        bottom: AppSpacing.xxxl * 2,
      ),
      children: [
        _DateLabel(label: dateLabel),
        const SizedBox(height: AppSpacing.sm),
        DaySummaryStrip(
          activities: items.length,
          kids: kidsInActivityPods.length,
          specialists: uniqueSpecialists.length,
          concerns: concerns.length,
          pendingObs: pendingObs,
          onTapConcerns: () =>
              context.push('/more/forms/parent-concern'),
          onTapPending: () => context.go('/observations'),
        ),
        const SizedBox(height: AppSpacing.lg),

        // All-day activities float above the hero — short, banner-like.
        for (final item in allDay) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: ScheduleItemCard(
              item: item,
              isNow: true,
              isPast: false,
              conflicts: conflicts[item.id] ?? const [],
              concernMatch: concernForItem(item),
              onTap: () => onOpenDetail(item),
              onOpenConcern: () => _goConcern(
                context,
                concernForItem(item)?.id,
              ),
            ),
          ),
        ],

        // Hero "right now" card — dominates the fold when an activity
        // is in progress.
        if (currentItem != null) ...[
          HeroNowCard(
            item: currentItem,
            now: now,
            observationCount: activityCounts[currentItem.title] ?? 0,
            onTap: () => onOpenDetail(currentItem!),
            onCapture: () => context.go('/observations'),
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

        // Upcoming. First one gets the "IN N MIN" chip.
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
                    onTap: () => onOpenDetail(item),
                    onLogObservations: () => context.go('/observations'),
                    onOpenConcern: () => _goConcern(
                context,
                concernForItem(item)?.id,
              ),
                  ),
                ),
            ],
          ),
        ],
      ],
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
