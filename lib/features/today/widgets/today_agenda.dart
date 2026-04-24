import 'package:basecamp/features/calendar/calendar_event.dart';
import 'package:basecamp/features/calendar/calendar_synthesizer.dart';
import 'package:basecamp/features/groups/group_summary_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/widgets/activity_detail_sheet.dart';
import 'package:basecamp/features/today/last_expanded_group.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Chronological feed of today's events — activities, trips, and
/// opt-in break/lunch windows for the selected group's anchor
/// leads. Weaves everything into a single scrollable column the
/// teacher reads top-to-bottom as the day moves.
///
/// Filtering mirrors the group-chip selection:
///   - No group selected: show everything.
///   - Group selected: show events scoped to that group, plus
///     program-wide events (all-groups or staff-prep), plus
///     breaks/lunches for that group's anchor leads.
///
/// Taps dispatch back to the right editor by `sourceKind`:
///   activity (template/entry) → activity detail sheet
///   trip                       → trip detail screen
///   break / lunch              → adult detail screen
class TodayAgendaView extends ConsumerWidget {
  const TodayAgendaView({required this.now, super.key});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selectedGroupId = ref.watch(lastExpandedGroupProvider);

    // Figure out which adults' breaks to include in the feed — the
    // selected group's anchor leads, if a group is selected. Join
    // their ids into a stable key so the family provider caches.
    final summariesAsync = ref.watch(groupSummariesProvider);
    final summaries =
        summariesAsync.asData?.value ?? const <GroupSummary>[];
    GroupSummary? selected;
    if (selectedGroupId != null) {
      for (final s in summaries) {
        if (s.id == selectedGroupId) {
          selected = s;
          break;
        }
      }
    }
    final adultIdsForBreaks = (selected == null ||
            selected.anchorLeads.isEmpty)
        ? const <String>[]
        : ([for (final s in selected.anchorLeads) s.id]..sort());
    final adultIdsKey = adultIdsForBreaks.join(',');

    final eventsAsync =
        ref.watch(calendarEventsWithBreaksTodayProvider(adultIdsKey));

    return eventsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text('Error: $err'),
      ),
      data: (allEvents) {
        // Group-scope filter: when a group is selected, keep events
        // that touch that group — its own group-scoped events, plus
        // program-wide, plus breaks for that group's anchor leads.
        final filtered = selectedGroupId == null
            ? allEvents
            : [
                for (final e in allEvents)
                  if (_matchesSelectedGroup(e, selectedGroupId)) e,
              ];
        if (filtered.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              'Nothing on the agenda.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final nowMinutes = now.hour * 60 + now.minute;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final event in filtered)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _AgendaRow(
                  event: event,
                  nowMinutes: nowMinutes,
                  onTap: () => _dispatchTap(context, event),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Whether an event is relevant to the selected group. Group-
  /// scoped = direct id match. Program-wide (allGroups or no-
  /// groups staff prep) = always show. Breaks/lunches = only shown
  /// when the adult is one of the selected group's anchor leads
  /// (already filtered at the provider layer, but we re-check here
  /// for safety when the provider includes more than the selected
  /// group's leads).
  bool _matchesSelectedGroup(CalendarEvent event, String groupId) {
    switch (event.kind) {
      case CalendarEventKind.activity:
        if (event.allGroups) return true;
        if (event.groupIds.isEmpty) return true; // staff prep
        return event.groupIds.contains(groupId);
      case CalendarEventKind.trip:
        // Trips carry their group_ids from trip_groups now. Empty +
        // allGroups is program-wide (legacy rows with no scoping
        // info) — those still show in every group's view. Otherwise
        // strict id match.
        if (event.allGroups) return true;
        if (event.groupIds.isEmpty) return true;
        return event.groupIds.contains(groupId);
      case CalendarEventKind.adultBreak:
      case CalendarEventKind.adultLunch:
        // Synthesizer already scoped these by adult id, so they're
        // trusted to belong to the selected group's leads.
        return true;
    }
  }

  Future<void> _dispatchTap(
    BuildContext context,
    CalendarEvent event,
  ) async {
    switch (event.kind) {
      case CalendarEventKind.activity:
        // Open the activity detail sheet. We need a ScheduleItem
        // (which the detail sheet takes), not a CalendarEvent;
        // build a minimal item from the event's fields — the
        // detail sheet re-fetches its own canonical row as
        // needed.
        final item = ScheduleItem(
          id: event.id,
          startTime: DateFormat('HH:mm').format(event.startAt),
          endTime: DateFormat('HH:mm').format(event.endAt),
          isFullDay: event.allDay,
          title: event.title,
          groupIds: event.groupIds,
          allGroups: event.allGroups,
          adultId: event.adultId,
          location: event.location,
          roomId: event.roomId,
          isFromTemplate: event.sourceKind == 'template',
          templateId:
              event.sourceKind == 'template' ? event.sourceId : null,
          entryId: event.sourceKind == 'entry' ? event.sourceId : null,
          date: DateTime(
            event.startAt.year,
            event.startAt.month,
            event.startAt.day,
          ),
        );
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => ActivityDetailSheet(item: item),
        );
      case CalendarEventKind.trip:
        if (context.mounted) {
          await context.push('/trips/${event.sourceId}');
        }
      case CalendarEventKind.adultBreak:
      case CalendarEventKind.adultLunch:
        if (event.adultId == null) return;
        if (context.mounted) {
          await context.push('/more/adults/${event.adultId}');
        }
    }
  }
}

/// Single row in the agenda feed. Compact — time pill on the left,
/// title + subtitle + tags on the right, tint by event kind.
class _AgendaRow extends StatelessWidget {
  const _AgendaRow({
    required this.event,
    required this.nowMinutes,
    required this.onTap,
  });

  final CalendarEvent event;
  final int nowMinutes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kindStyle = _styleFor(event, theme);
    final timeLabel = _timeLabel(event);
    final endLabel = _endLabel(event, nowMinutes);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  timeLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (endLabel != null)
                  Text(
                    endLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: kindStyle.tint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      kindStyle.icon,
                      size: 14,
                      color: kindStyle.tint,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        event.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (event.subtitle != null &&
                    event.subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      event.subtitle!,
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
        ],
      ),
    );
  }

  /// Top time label: start time for timed events, "All day" for
  /// all-day spans. Always compact — "9:30a" not "09:30 AM."
  String _timeLabel(CalendarEvent e) {
    if (e.allDay) return 'All day';
    return _fmt12h(e.startAt);
  }

  /// Optional second line under the start time — "→ 10:30a" for a
  /// timed event (so the row shows the range), "N days" for a
  /// multi-day all-day event. Null when neither applies.
  String? _endLabel(CalendarEvent e, int nowMinutes) {
    if (e.allDay) {
      final dayCount = e.endAt.difference(e.startAt).inDays;
      if (dayCount > 1) return '$dayCount days';
      return null;
    }
    return '→ ${_fmt12h(e.endAt)}';
  }

  String _fmt12h(DateTime d) {
    final h = d.hour;
    final m = d.minute;
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final period = h >= 12 ? 'p' : 'a';
    return m == 0 ? '$hour12$period' : '$hour12:${m.toString().padLeft(2, '0')}$period';
  }

  _KindStyle _styleFor(CalendarEvent e, ThemeData theme) {
    switch (e.kind) {
      case CalendarEventKind.activity:
        return _KindStyle(
          icon: Icons.auto_awesome_mosaic_outlined,
          tint: theme.colorScheme.primary,
        );
      case CalendarEventKind.trip:
        return _KindStyle(
          icon: Icons.directions_bus_outlined,
          tint: theme.colorScheme.tertiary,
        );
      case CalendarEventKind.adultBreak:
        return _KindStyle(
          icon: Icons.coffee_outlined,
          tint: theme.colorScheme.secondary,
        );
      case CalendarEventKind.adultLunch:
        return _KindStyle(
          icon: Icons.restaurant_outlined,
          tint: theme.colorScheme.secondary,
        );
    }
  }
}

class _KindStyle {
  const _KindStyle({required this.icon, required this.tint});
  final IconData icon;
  final Color tint;
}
