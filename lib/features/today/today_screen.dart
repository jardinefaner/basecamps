import 'dart:async';

import 'package:basecamp/core/now_tick.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adult_timeline_repository.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/attendance/attendance_repository.dart';
import 'package:basecamp/features/attendance/widgets/attendance_sheet.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/coverage/coverage_strip.dart';
import 'package:basecamp/features/curriculum/widgets/today_curriculum_strip.dart';
import 'package:basecamp/features/export/export_actions.dart';
import 'package:basecamp/features/forms/polymorphic/definitions/incident.dart';
import 'package:basecamp/features/forms/polymorphic/definitions/parent_concern.dart';
import 'package:basecamp/features/forms/polymorphic/form_definition.dart';
import 'package:basecamp/features/forms/polymorphic/form_submission_repository.dart';
import 'package:basecamp/features/forms/polymorphic/generic_form_screen.dart';
import 'package:basecamp/features/groups/group_detail_screen.dart';
import 'package:basecamp/features/groups/group_summary_repository.dart';
import 'package:basecamp/features/launcher/launcher_screen.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/features/observations/widgets/observation_composer.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/schedule/adult_shift_conflicts.dart';
import 'package:basecamp/features/schedule/conflicts.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/trip_conflicts.dart';
import 'package:basecamp/features/schedule/widgets/activity_detail_sheet.dart';
import 'package:basecamp/features/schedule/widgets/add_activity_picker.dart';
import 'package:basecamp/features/schedule/widgets/new_activity_wizard.dart';
import 'package:basecamp/features/schedule/widgets/new_full_day_event_wizard.dart';
import 'package:basecamp/features/today/last_expanded_group.dart';
import 'package:basecamp/features/today/ratio_check.dart';
import 'package:basecamp/features/today/today_buckets.dart';
import 'package:basecamp/features/today/today_mode.dart';
import 'package:basecamp/features/today/widgets/all_day_carousel.dart';
import 'package:basecamp/features/today/widgets/close_out_strip.dart';
import 'package:basecamp/features/today/widgets/day_summary_strip.dart';
import 'package:basecamp/features/today/widgets/earlier_today_group.dart';
import 'package:basecamp/features/today/widgets/hero_now_card.dart';
import 'package:basecamp/features/today/widgets/lateness_flags_strip.dart';
import 'package:basecamp/features/today/widgets/schedule_item_card.dart';
import 'package:basecamp/features/today/widgets/staff_today_strip.dart';
import 'package:basecamp/features/today/widgets/today_agenda.dart';
import 'package:basecamp/features/trips/trips_repository.dart';
import 'package:basecamp/features/trips/widgets/new_trip_wizard.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/bootstrap_setup_card.dart';
import 'package:basecamp/ui/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Notifier for [viewedDateProvider]. Two mutators — `set` (hop to an
/// arbitrary date) and `shift` (prev/next chevron) — plus `reset`
/// for the "Today" pill. All three normalize to midnight so equality
/// checks against `now` don't get tripped by the clock's minute
/// ticks.
class ViewedDateNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void set(DateTime date) {
    state = DateTime(date.year, date.month, date.day);
  }

  void shift(int days) {
    final next = state.add(Duration(days: days));
    state = DateTime(next.year, next.month, next.day);
  }

  void reset() {
    final now = DateTime.now();
    state = DateTime(now.year, now.month, now.day);
  }
}

/// Date the Today screen is currently displaying. Defaults to today;
/// teachers can cycle prev/next via the AppBar chevrons. Live-clock
/// features (hero NOW, close-out strip, lateness flags, etc.) only
/// fire when this matches today's date — for any other day we render
/// a simple chronological list instead.
///
/// Stored as a midnight DateTime so equality checks against "today"
/// don't get tripped by the clock's minute ticks.
final viewedDateProvider =
    NotifierProvider<ViewedDateNotifier, DateTime>(ViewedDateNotifier.new);

/// Calendar-day equality — year/month/day only, ignoring wall-clock
/// drift. Used to decide whether Today's live-clock widgets fire.
bool isSameCalendarDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Today dashboard. Orchestrates the live clock, day-summary strip, a
/// hero "right now" card for the current activity, an upcoming list
/// with next-up/countdown cues and "log observations" prompts, and a
/// collapsible "earlier today" section for what already happened.
///
/// Supports day-cycling: the AppBar's prev/next chevrons shift the
/// [viewedDateProvider] so a teacher can browse past or future days'
/// schedules. When viewing a non-today date, live-clock affordances
/// (hero NOW, close-out strip, lateness flags, "also now" strip) are
/// suppressed in favor of a plain chronological list.
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

  /// FAB tap → bottom sheet offering the seven creation flows the
  /// app supports. Each row pops the sheet first and then invokes
  /// the matching wizard or composer — keeps the navigator stack
  /// clean so a back-swipe out of, say, the trip wizard lands back
  /// on Today rather than on a dismissed bottom sheet.
  Future<void> _openCreateMenu(
    BuildContext context,
    DateTime now,
    WidgetRef ref,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      // Seven list tiles + title + drag handle overflow the default
      // half-screen cap on shorter devices. isScrollControlled lets
      // the sheet size to content; wrapping the column in a
      // SingleChildScrollView keeps it safe when the device is
      // even shorter than the intrinsic height of the menu.
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        Future<void> runAfterPop(Future<void> Function() action) async {
          Navigator.of(ctx).pop();
          // Defer to the next frame so the sheet is fully dismissed
          // before we push/show the follow-up surface. Prevents the
          // "Navigator popped while a route was being added" race.
          await Future<void>.delayed(Duration.zero);
          await action();
        }

        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xs,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: Text(
                    'Add…',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_mosaic_outlined),
                  title: const Text('Activity'),
                  onTap: () => runAfterPop(
                    () => _openAddPicker(context, now),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.visibility_outlined),
                  title: const Text('Observation'),
                  onTap: () => runAfterPop(
                    () => _openObservationComposer(context),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.chat_outlined),
                  title: const Text('Concern note'),
                  onTap: () => runAfterPop(() async {
                    if (!context.mounted) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        fullscreenDialog: true,
                        builder: (_) => const GenericFormScreen(
                          definition: parentConcernForm,
                        ),
                      ),
                    );
                  }),
                ),
                ListTile(
                  leading: Icon(
                    Icons.report_problem_outlined,
                    color: theme.colorScheme.error,
                  ),
                  title: const Text('Incident'),
                  subtitle: const Text('Injury or behavior on a child'),
                  onTap: () => runAfterPop(() async {
                    if (!context.mounted) return;
                    await Navigator.of(context, rootNavigator: true).push<void>(
                      MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (_) => const GenericFormScreen(
                          definition: incidentForm,
                        ),
                      ),
                    );
                  }),
                ),
                ListTile(
                  leading: const Icon(Icons.map_outlined),
                  title: const Text('Trip'),
                  onTap: () => runAfterPop(() async {
                    if (!context.mounted) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        fullscreenDialog: true,
                        builder: (_) => const NewTripWizardScreen(),
                      ),
                    );
                  }),
                ),
                ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Event (full-day)'),
                  onTap: () => runAfterPop(() async {
                    if (!context.mounted) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        fullscreenDialog: true,
                        builder: (_) => const NewFullDayEventWizardScreen(),
                      ),
                    );
                  }),
                ),
                ListTile(
                  leading: const Icon(Icons.assignment_outlined),
                  title: const Text('Start a form…'),
                  onTap: () => runAfterPop(() async {
                    if (!context.mounted) return;
                    unawaited(context.push('/more/forms'));
                  }),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Opens the observation composer as a modal bottom sheet. The
  /// composer already pulls current-activity context from
  /// [todayScheduleProvider] + [lastExpandedGroupProvider], so there's
  /// nothing to pass in — just render it. `viewInsets.bottom` keeps
  /// the keyboard from covering the input when the teacher starts
  /// typing.
  Future<void> _openObservationComposer(
    BuildContext context, {
    ScheduleItem? forActivity,
    List<String> prefillChildIds = const [],
    String? prefillGroupId,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        // Wrap the composer in a local Scaffold so its "Saved —
        // tap the entry above" snackbar renders INSIDE the sheet
        // (where the teacher's looking) instead of on Today's
        // messenger behind the modal backdrop, where it's invisible.
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: ObservationComposer(
              forActivity: forActivity,
              prefillChildIds: prefillChildIds,
              prefillGroupId: prefillGroupId,
            ),
          ),
        );
      },
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
    // widget tree. Even when the teacher is browsing a non-today date
    // we keep the tick alive — the AppBar's "Today" pill needs to
    // notice when midnight rolls over and (more importantly) switching
    // back to today needs up-to-date `now` for the live widgets.
    final nowAsync = ref.watch(nowTickProvider);
    final now = nowAsync.asData?.value ?? DateTime.now();

    final viewedDate = ref.watch(viewedDateProvider);
    final isToday = isSameCalendarDate(viewedDate, now);
    // When viewing today, the schedule stream should resolve against
    // the actual current calendar date (so a midnight rollover flips
    // day semantics even if the StateProvider hasn't been re-seeded).
    // For any other date we ask for that specific day's rows.
    final scheduleDate = isToday
        ? DateTime(now.year, now.month, now.day)
        : viewedDate;
    final scheduleAsync = ref.watch(scheduleForDateProvider(scheduleDate));
    final theme = Theme.of(context);
    final dateLabel = DateFormat('EEEE · MMMM d').format(viewedDate);

    // PopScope(canPop: false) sits at the app root (Today is the root
    // now, post nav-shell-removal). Absorbs the Android back button /
    // edge swipe so teachers don't accidentally exit mid-capture;
    // in-flight observations were being lost to errant back gestures.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // No-op on purpose. PopScope blocks the pop; we just don't
        // offer any escape hatch here. The moment we start routing the
        // back gesture somewhere (e.g. double-tap to exit) teachers
        // hit it accidentally.
      },
      child: Scaffold(
        // Wide drawer — the launcher hosts search + people grids +
        // destinations + library pills, all of which feel cramped in the
        // Drawer default 304dp. 88% of the screen width gives the
        // content room to breathe without fully hiding Today.
        //
        // Suppressed on layouts that already show the launcher as a
        // permanent sidebar (web / wide windows). Two launchers fighting
        // for the same screen — one slide-in, one fixed left rail —
        // confuses the trigger affordance and wastes the hamburger
        // slot. Mobile / narrow windows keep the slide-in Drawer.
        drawer: Breakpoints.hasPersistentSidebar(context)
            ? null
            : Drawer(
                width: MediaQuery.of(context).size.width * 0.88,
                child: const LauncherScreen(),
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openCreateMenu(context, now, ref),
          icon: const Icon(Icons.add),
          label: const Text('Add'),
        ),
        // On wide viewports (expanded+), clamp the scrolling column to
        // ~720dp centered — a phone-layout stretched edge-to-edge on a
        // desktop window looks like empty gutters; a reading-width
        // column reads native. Side gutters take the scaffold's
        // surfaceContainerLowest backdrop underneath.
        backgroundColor: Breakpoints.isWide(context)
            ? theme.colorScheme.surfaceContainerLowest
            : null,
        body: _maybeClampToReadingColumn(
          context,
          CustomScrollView(
            slivers: [
            SliverAppBar(
              // Hide the leading menu button when the permanent sidebar
              // is on screen — there's no Drawer to open and the
              // hamburger would just sit there pointing at empty space.
              // Narrow layouts keep the explicit Builder + IconButton so
              // the onPressed has a context sitting below the Scaffold
              // (Scaffold.of walks up; the build's outer context is
              // above the Scaffold we returned).
              automaticallyImplyLeading: false,
              leading: Breakpoints.hasPersistentSidebar(context)
                  ? null
                  : Builder(
                      builder: (ctx) => IconButton(
                        icon: const Icon(Icons.menu),
                        tooltip: 'Menu',
                        onPressed: () => Scaffold.of(ctx).openDrawer(),
                      ),
                    ),
              // Plain "Today" title — date + cycle controls live in
              // the AppBar's `bottom` slot below so the title row
              // doesn't fight for space with the prev/next/gear/etc
              // actions. Tapping the title resets the cycle back to
              // the current calendar day (replaces the "Today" pill
              // that used to sit in the band).
              title: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: isToday
                    ? null
                    : () =>
                        ref.read(viewedDateProvider.notifier).reset(),
                child: const Text('Today'),
              ),
              // Tinted bar when viewing a non-today date — a glance
              // signal that you're looking at history (or future) and
              // an invitation to tap the title to come back.
              backgroundColor: isToday
                  ? null
                  : theme.colorScheme.tertiaryContainer,
              foregroundColor: isToday
                  ? null
                  : theme.colorScheme.onTertiaryContainer,
              floating: true,
              snap: true,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: _DateCycleBar(
                  dateLabel: dateLabel,
                  isToday: isToday,
                  onPrev: () =>
                      ref.read(viewedDateProvider.notifier).shift(-1),
                  onNext: () =>
                      ref.read(viewedDateProvider.notifier).shift(1),
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.tune_outlined),
                  tooltip: 'Schedule',
                  onPressed: () => context.push('/today/schedule'),
                ),
                // Gear icon opens a PopupMenuButton with settings / forms.
                // Forms was previously only reachable via /more — needs
                // its own entry here so teachers don't lose access now
                // that the /more top-level branch is retired.
                PopupMenuButton<String>(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'More',
                  onSelected: (v) {
                    switch (v) {
                      case 'settings':
                        unawaited(context.push('/more/settings'));
                      case 'forms':
                        unawaited(context.push('/more/forms'));
                      case 'export':
                        // Export the day the teacher's looking at —
                        // most natural: reviewing last Friday, hitting
                        // export should give a PDF of that day, not
                        // today's (often empty-so-far) view.
                        unawaited(exportDay(context, ref, viewedDate));
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'settings',
                      child: Text('Program settings'),
                    ),
                    PopupMenuItem(
                      value: 'forms',
                      child: Text('Forms & surveys'),
                    ),
                    PopupMenuItem(
                      value: 'export',
                      child: Row(
                        children: [
                          Icon(Icons.picture_as_pdf_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Export today'),
                        ],
                      ),
                    ),
                  ],
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
                viewedDate: scheduleDate,
                isToday: isToday,
                theme: theme,
                onOpenDetail: (item) => _openDetail(context, item),
                onCaptureFor: (item) => _openObservationComposer(
                  context,
                  forActivity: item,
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

/// If the viewport is at least [Breakpoint.expanded] wide, wraps
/// [child] in a [Center] + [ConstrainedBox] so the Today column
/// reads like an article (max ~720dp) instead of stretching edge-
/// to-edge. On phones/narrower tablets this is a no-op so the
/// existing compact layout is unchanged.
Widget _maybeClampToReadingColumn(BuildContext context, Widget child) {
  if (!Breakpoints.isWide(context)) return child;
  return Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: child,
    ),
  );
}

/// AppBar bottom band: prev / center date / next. Sits underneath
/// the title row so the date label has full width to breathe.
/// "Reset to today" lives on the AppBar title's tap — tap "Today"
/// at the top to come back from any cycled date.
class _DateCycleBar extends StatelessWidget {
  const _DateCycleBar({
    required this.dateLabel,
    required this.isToday,
    required this.onPrev,
    required this.onNext,
  });

  final String dateLabel;
  final bool isToday;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // When the bar tints (off-today) the title-row foreground
    // already shifts to onTertiaryContainer; the date row inherits
    // that tone via DefaultTextStyle on the AppBar's bottom slot.
    final dateColor = isToday
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onTertiaryContainer;
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous day',
              onPressed: onPrev,
              visualDensity: VisualDensity.compact,
              color: dateColor,
            ),
            Expanded(
              child: Center(
                child: Text(
                  dateLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: dateColor,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next day',
              onPressed: onNext,
              visualDensity: VisualDensity.compact,
              color: dateColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.items,
    required this.now,
    required this.viewedDate,
    required this.isToday,
    required this.theme,
    required this.onOpenDetail,
    required this.onCaptureFor,
  });

  final List<ScheduleItem> items;

  /// Wall-clock "now" — always the real current time, even when the
  /// teacher is browsing a non-today date. Live-clock widgets consume
  /// this via [isToday] gating.
  final DateTime now;

  /// Midnight of the calendar day currently on screen. Equals
  /// midnight-of-`now` when [isToday]; otherwise the cycled day.
  /// Fed to per-day helpers (attendance sheet, trip membership,
  /// weekday-gated availability) so non-today views still resolve
  /// their contextual data against the right calendar day.
  final DateTime viewedDate;

  /// True when [viewedDate] is today's calendar date. Gates every
  /// live-clock widget (hero NOW, "Also now" strip, close-out strip,
  /// lateness flags, "between activities" banner, etc.) — non-today
  /// views collapse to a plain chronological list.
  final bool isToday;

  final ThemeData theme;
  final ValueChanged<ScheduleItem> onOpenDetail;

  /// Open the observation composer scoped to a specific schedule
  /// item. Nullable `item` passes through to "composer figures it
  /// out" (current-time + selected-group fallback); non-null locks
  /// the composer to that activity so observations tagged from a
  /// past-activity card carry the right schedule-source-id.
  final ValueChanged<ScheduleItem?> onCaptureFor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      // AppBar already carries the date, so no redundant label here.
      // BootstrapSetupCard self-hides on populated installs; empty
      // state copy adapts for today vs. other days just below.
      return SliverPadding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            // Self-hides unless BOTH adults and groups are empty.
            // Keeps a populated-but-unscheduled day from seeing a
            // setup nudge it doesn't need.
            const BootstrapSetupCard(),
            // Curriculum strip on the empty-state path too — a day
            // with nothing scheduled still benefits from seeing
            // "this week's curriculum is X" so the teacher can pull
            // a card off the strip into Today instead of hunting it
            // out of the curriculum view.
            TodayCurriculumStrip(date: viewedDate),
            _EmptyState(
              isToday: isToday,
              onEdit: () => context.push('/today/schedule'),
            ),
          ]),
        ),
      );
    }

    final nowMinutes = now.hour * 60 + now.minute;
    final conflicts = conflictsByItemId(items);

    // Shift-window conflicts (slice A): group availability rows by
    // adult once and run the detector against today's schedule.
    final allAvail =
        ref.watch(allAvailabilityProvider).asData?.value ??
        const <AdultAvailabilityData>[];
    final adultsList =
        ref.watch(adultsProvider).asData?.value ?? const <Adult>[];
    final availabilityByAdult = <String, List<AdultAvailabilityData>>{};
    for (final row in allAvail) {
      (availabilityByAdult[row.adultId] ??= <AdultAvailabilityData>[]).add(row);
    }
    final adultsById = <String, Adult>{
      for (final a in adultsList) a.id: a,
    };
    final shiftConflicts = detectAdultShiftConflicts(
      items: items,
      availabilityByAdult: availabilityByAdult,
      adultsById: adultsById,
      isoWeekday: now.weekday,
    );

    // Trip conflicts (slice B): today's trips + their group
    // memberships, intersected with the day's activities.
    final allTrips = ref.watch(tripsProvider).asData?.value ?? const <Trip>[];
    final tripGroupsMap =
        ref.watch(_allTripGroupsByTripProvider).asData?.value ??
        const <String, List<String>>{};
    final allGroups =
        ref.watch(groupsProvider).asData?.value ?? const <Group>[];
    final groupsById = <String, Group>{
      for (final g in allGroups) g.id: g,
    };
    final todayTrips = allTrips.where((t) {
      final start = DateTime(t.date.year, t.date.month, t.date.day);
      final end = t.endDate == null
          ? start
          : DateTime(
              t.endDate!.year,
              t.endDate!.month,
              t.endDate!.day,
            );
      final day = DateTime(now.year, now.month, now.day);
      return !day.isBefore(start) && !day.isAfter(end);
    }).toList();
    final tripConflictResult = detectTripConflicts(
      scheduleItems: items,
      todayTrips: todayTrips,
      groupsByTrip: tripGroupsMap,
      groupsById: groupsById,
    );

    ConflictsFor conflictsFor(String id) => ConflictsFor(
      activity: conflicts[id] ?? const <ConflictInfo>[],
      shift: shiftConflicts[id] ?? const <ShiftConflict>[],
      trip: tripConflictResult.byActivityId[id] ?? const <TripConflict>[],
    );
    final activityCounts =
        ref.watch(todayActivityCountsProvider).asData?.value ??
        const <String, int>{};
    // Polymorphic parent_concern submissions, scoped to today using
    // the same logic the bespoke `watchForDay` used: a concern_date in
    // the form data that lands on this day, OR (concern_date null)
    // updated today. Build the structured (concern → child ids) link
    // map from each row's `data.child_ids` so per-activity flagging
    // matches the bespoke join-table semantics.
    final allConcernSubmissions = ref
            .watch(formSubmissionsByTypeProvider('parent_concern'))
            .asData
            ?.value ??
        const <FormSubmission>[];
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final concerns = <FormSubmission>[];
    final concernChildLinks = <String, Set<String>>{};
    for (final sub in allConcernSubmissions) {
      final data = decodeFormData(sub);
      final rawDate = data['concern_date'];
      DateTime? concernDate;
      if (rawDate is String && rawDate.isNotEmpty) {
        concernDate = DateTime.tryParse(rawDate);
      }
      final ts = sub.updatedAt;
      final inDay = concernDate != null
          ? !concernDate.isBefore(dayStart) && concernDate.isBefore(dayEnd)
          : !ts.isBefore(dayStart) && ts.isBefore(dayEnd);
      if (inDay) concerns.add(sub);
      final raw = data['child_ids'];
      if (raw is List && raw.isNotEmpty) {
        concernChildLinks[sub.id] = <String>{
          for (final v in raw)
            if (v is String) v,
        };
      }
    }
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
    final primaryCurrent = filteredCurrent.isEmpty
        ? null
        : filteredCurrent.first;
    final alsoNow = filteredCurrent.length > 1
        ? filteredCurrent.sublist(1)
        : const <ScheduleItem>[];

    final nextUp = filteredUpcoming.isEmpty ? null : filteredUpcoming.first;
    final nextUpMinutes = nextUp == null
        ? null
        : nextUp.startMinutes - nowMinutes;

    // -- Day-summary numbers --
    // Scoped to the selected group when one is picked (a group only
    // cares about its own stats); program-wide otherwise. The chip
    // row sits directly above the stats strip so the relationship
    // reads visually — pick a group, the numbers follow.
    final scopedItems = selectedGroupId == null
        ? items
        : items.where(inSelectedView).toList();
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
        } else if (child.groupId != null &&
            i.groupIds.contains(child.groupId)) {
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

    // -- Close-out strip inputs (end-of-day nudge) --
    // Close-of-program is the max endTime across today's timed items
    // (all-day items don't give us a useful anchor). Null → strip
    // hides. Computed from the unfiltered schedule so a teacher
    // focused on one group still sees the whole-program close.
    final timedEndMinutes = <int>[
      for (final i in items)
        if (!i.isFullDay) i.endMinutes,
    ];
    final programCloseMinutes = closeOfProgramMinutes(timedEndMinutes);
    final showCloseOut = shouldShowCloseOutStrip(
      nowMinutes: nowMinutes,
      closeMinutes: programCloseMinutes,
    );
    // Pull the pending-obs / draft-form / unsigned-concern counts
    // only when the window is open — no wasted work in the morning.
    final draftForms = showCloseOut
        ? (ref
                  .watch(formSubmissionsByStatusProvider(FormStatus.draft))
                  .asData
                  ?.value ??
              const <FormSubmission>[])
        : const <FormSubmission>[];
    // Concerns whose supervisor signature is still empty — same
    // close-out nudge as the bespoke version, just reading from the
    // polymorphic data blob. The signature field in the form
    // definition stores a {signature, signaturePath, signedAt} map
    // under `supervisor_signature`; an unsigned row has both the typed
    // name and the drawn-pad path empty/missing.
    final unsignedConcerns = !showCloseOut
        ? 0
        : allConcernSubmissions.where((sub) {
            final data = decodeFormData(sub);
            final sig = data['supervisor_signature'];
            if (sig is! Map) return true;
            final typed = (sig['signature'] as String?)?.trim() ?? '';
            final drawn = (sig['signaturePath'] as String?)?.trim() ?? '';
            return typed.isEmpty && drawn.isEmpty;
          }).length;
    // Program-wide "missing obs" count — the close-out strip isn't
    // scoped to the selected group, it's a whole-day tidy-up.
    final programPendingObs = past
        .where((i) => (activityCounts[i.title] ?? 0) == 0)
        .length;
    // First past activity missing observations — tap target for
    // the "N past activities missing observations" row. Null → fall
    // back to /observations.
    ScheduleItem? firstPendingObsItem;
    for (final i in past) {
      if ((activityCounts[i.title] ?? 0) == 0) {
        firstPendingObsItem = i;
        break;
      }
    }

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
          // Attendance is per-day — on a non-today view, resolve
          // against the cycled date so a teacher reviewing last
          // Friday doesn't accidentally edit today's attendance row.
          date: isToday ? now : viewedDate,
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

    // Timed items (non-all-day) sorted chronologically — used by the
    // non-today branch as a plain list, and handy to have pre-sorted
    // everywhere else too. Selection filter applies in both branches
    // for consistency with the chip-row selection.
    final timedSorted = [
      for (final i in items)
        if (!i.isFullDay && inSelectedView(i)) i,
    ]..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

    return SliverPadding(
      padding: const EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.md,
        bottom: AppSpacing.xxxl * 2,
      ),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          // Fresh-program nudge. Self-hides unless BOTH adults and
          // groups are empty, so populated programs see no extra
          // chrome here — but a brand-new install still gets the
          // bootstrap card on the Today screen even if someone
          // happened to schedule an activity first.
          const BootstrapSetupCard(),

          // Curriculum context. Self-hides on programs without an
          // active theme; otherwise renders a tappable "Bug week ·
          // Week 2" chip + the sequence's core question + today's
          // daily-ritual cards. Sits at the very top so the day's
          // overarching frame ("what arc are we in?") reads before
          // any operational signal.
          TodayCurriculumStrip(date: viewedDate),

          // Loud-when-needed strip: self-hides when zero kids are
          // flagged and no reviews are due. Live-clock only — lateness
          // is a "right now" signal, not useful when browsing another
          // day's schedule.
          if (isToday) LatenessFlagsStrip(now: now),

          // Coverage right now (v48 slice 2). Shows per-classroom
          // who's scheduled to be there per the role-block timeline.
          // Informational only — no enforcement. Today-only because
          // the resolver is "this minute"; browsing tomorrow's
          // schedule shouldn't show stale coverage.
          if (isToday) ...[
            const CoverageStrip(),
            const SizedBox(height: AppSpacing.md),
          ],

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
                    conflicts: conflictsFor(item.id).activity,
                    shiftConflicts: conflictsFor(item.id).shift,
                    tripConflicts: conflictsFor(item.id).trip,
                    concernMatch: concernForItem(item),
                    // Attendance provider only streams today's rows —
                    // feeding its numbers into a card that's really
                    // showing last Friday would be misleading. Hide
                    // the strip on non-today views; tapping still
                    // opens the sheet scoped to the viewed date.
                    attendance: isToday ? attendanceFor(item) : null,
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

          // Mode toggle — only meaningful on today. Non-today views
          // always render as a plain chronological list; the Groups /
          // Agenda split is a live-day affordance.
          if (isToday) ...[
            _TodayModeToggle(mode: ref.watch(todayModeProvider)),
            const SizedBox(height: AppSpacing.md),
          ],

          // End-of-day close-out strip. Only appears in the 60-min
          // window before program close and the 30-min tail after.
          // Muted in tone — it's a nudge to wrap up, not an alert.
          // Live-clock gated — makes no sense while browsing another
          // day.
          if (isToday && showCloseOut) ...[
            CloseOutStrip(
              counts: CloseOutCounts(
                pendingObs: programPendingObs,
                draftForms: draftForms.length,
                unsignedConcerns: unsignedConcerns,
              ),
              onTapPendingObs: () {
                if (firstPendingObsItem != null) {
                  onOpenDetail(firstPendingObsItem);
                } else {
                  unawaited(context.push('/observations'));
                }
              },
              onTapDraftForms: () => unawaited(context.push('/more/forms')),
              onTapUnsignedConcerns: () =>
                  unawaited(context.push('/more/forms/parent-concern')),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // Group chip selector — horizontally scrollable row of groups.
          // Same in both modes: in Groups mode it drives the hero/
          // upcoming/earlier filter; in Agenda mode it scopes the
          // chronological feed to the selected group + program-wide +
          // that group's leads' breaks.
          const _GroupChipRow(),
          const _SelectedGroupWarning(),
          const SizedBox(height: AppSpacing.md),

          // Day stats sit under the group chip row so the numbers track
          // the selected group: pick "Butterflies" and the counts rescope
          // to that group only. With no group selected, the counts read
          // program-wide. Compact — one strip, five numbers, tappable.
          // On non-today views the pendingObs count leans on "past"
          // bucket semantics that don't apply, so it's zeroed out;
          // the other counts are plain day-scoped totals.
          DaySummaryStrip(
            activities: scopedItems.length,
            children: childrenInActivityGroups.length,
            adults: uniqueAdults.length,
            concerns: scopedConcerns.length,
            pendingObs: isToday ? pendingObs : 0,
            onTapConcerns: () => context.push('/more/forms/parent-concern'),
            onTapPending: () => unawaited(context.push('/observations')),
          ),
          const SizedBox(height: AppSpacing.md),

          // Body branches on viewed date + mode. Non-today dates
          // always render a plain chronological list of timed items;
          // today keeps the mode toggle (Agenda feed vs. Groups
          // hero / upcoming / earlier).
          if (!isToday) ...[
            for (final item in timedSorted) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: ScheduleItemCard(
                  item: item,
                  isNow: false,
                  isPast: false,
                  conflicts: conflictsFor(item.id).activity,
                  shiftConflicts: conflictsFor(item.id).shift,
                  tripConflicts: conflictsFor(item.id).trip,
                  concernMatch: concernForItem(item),
                  onTap: () => onOpenDetail(item),
                  onOpenConcern: () => _goConcern(
                    context,
                    concernForItem(item)?.id,
                  ),
                ),
              ),
            ],
          ] else if (ref.watch(todayModeProvider) == TodayMode.agenda) ...[
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
                // Hero pulls the same ConflictsFor bundle the schedule
                // cards use — a red "⚠ Conflicts" pill appears in the
                // header when any of the three lists is non-empty, and
                // tapping it opens the same ConflictSheet.
                conflicts: conflictsFor(primaryCurrent.id).activity,
                shiftConflicts: conflictsFor(primaryCurrent.id).shift,
                tripConflicts: conflictsFor(primaryCurrent.id).trip,
                onTap: () => onOpenDetail(primaryCurrent),
                onCapture: () => onCaptureFor(primaryCurrent),
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
                onReview: () => unawaited(context.push('/observations')),
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
                  conflicts: conflictsFor(filteredUpcoming[i].id).activity,
                  shiftConflicts: conflictsFor(filteredUpcoming[i].id).shift,
                  tripConflicts: conflictsFor(filteredUpcoming[i].id).trip,
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
                        conflicts: conflictsFor(item.id).activity,
                        shiftConflicts: conflictsFor(item.id).shift,
                        tripConflicts: conflictsFor(item.id).trip,
                        showLogObservationsPrompt:
                            (activityCounts[item.title] ?? 0) == 0,
                        concernMatch: concernForItem(item),
                        attendance: attendanceFor(item),
                        onTap: () => onOpenDetail(item),
                        onLogObservations: () => onCaptureFor(item),
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
          // Staff-today strip is live shift state ("who's on the
          // clock right now"). Useful today, noise on other days.
          if (isToday) ...[
            const SizedBox(height: AppSpacing.md),
            StaffTodayStrip(now: now),
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

  String _concernPreview(FormSubmission sub) {
    final data = decodeFormData(sub);
    // The bespoke row had a `childNames` free-text column that we'd
    // splice into the headline. The polymorphic version derives that
    // from the structured chip picker — no separate free-text field —
    // so we lean on `concern_description` (always present, required by
    // the form definition) and fall back when it's empty.
    final desc = (data['concern_description'] as String?)?.trim() ?? '';
    if (desc.isNotEmpty) return desc;
    return 'Active concern today';
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
                    color: theme.colorScheme.onSecondaryContainer.withValues(
                      alpha: 0.75,
                    ),
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
    final summaries = summariesAsync.asData?.value ?? const <GroupSummary>[];
    if (summaries.isEmpty) return const SizedBox.shrink();

    final selectedId = ref.watch(lastExpandedGroupProvider);

    // First launch / stale selection → default-select the first
    // group so the sections below have something to filter by. Done
    // as a post-frame side effect to avoid modifying provider state
    // during build.
    if (!_autoSelected &&
        (selectedId == null || !summaries.any((g) => g.id == selectedId))) {
      _autoSelected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
          ref
              .read(lastExpandedGroupProvider.notifier)
              .toggle(summaries.first.id),
        );
      });
    }

    // Pull staffing + ratio inputs once here so each chip's checks are
    // pure functions against the shared snapshot instead of a Riverpod
    // watch per chip. Missing data (first paint before any stream
    // resolves) falls back to "assume staffed / empty ratio" — no
    // false-positive error tints while the providers warm up.
    final allAdults =
        ref.watch(adultsProvider).asData?.value ?? const <Adult>[];
    final allAvail =
        ref.watch(allAvailabilityProvider).asData?.value ??
        const <AdultAvailabilityData>[];
    final todayBlocks =
        ref.watch(todayAdultBlocksProvider).asData?.value ??
        const <AdultDayBlock>[];
    final allKids =
        ref.watch(childrenProvider).asData?.value ?? const <Child>[];
    // Same clock source as the rest of Today — the chip ratios tick
    // with the hero / upcoming / earlier sections on the wall-clock
    // minute rather than drifting on their own.
    final nowAsync = ref.watch(nowTickProvider);
    final now = nowAsync.asData?.value ?? DateTime.now();
    final weekday = now.weekday;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          for (final g in summaries) ...[
            Builder(
              builder: (_) {
                final childrenInGroup = <Child>[
                  for (final k in allKids)
                    if (k.groupId == g.id) k,
                ];
                final ratio = computeGroupRatioNow(
                  groupId: g.id,
                  childrenInGroup: childrenInGroup,
                  allAdults: allAdults,
                  allAvailability: allAvail,
                  todayBlocks: todayBlocks,
                  now: now,
                );
                final isStaffed = isGroupStaffedToday(
                  groupId: g.id,
                  weekday: weekday,
                  adults: allAdults,
                  todayDayBlocks: todayBlocks,
                  availability: allAvail,
                );
                return _GroupChip(
                  summary: g,
                  selected: g.id == selectedId,
                  isStaffed: isStaffed,
                  ratio: ratio,
                  onSelected: () => ref
                      .read(lastExpandedGroupProvider.notifier)
                      .toggle(g.id),
                  onLongPress: () => GroupDetailScreen.open(context, g.id),
                  theme: theme,
                );
              },
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
    required this.isStaffed,
    required this.ratio,
    required this.onSelected,
    required this.onLongPress,
    required this.theme,
  });

  final GroupSummary summary;
  final bool selected;

  /// Whether a lead is on the clock for this group today. When false
  /// the chip tints with errorContainer and shows a warning prefix —
  /// a data-quality nudge for "a group with no lead today probably
  /// isn't intended that way." Selection ring still wins when both
  /// are true (teacher actively working on the problem group).
  final bool isStaffed;

  /// Live ratio snapshot for this group. Drives the "kids:adults"
  /// suffix on the label and, when `isUnderRatio` is true, promotes
  /// the chip to the errorContainer warning state. Unstaffed takes
  /// priority over under-ratio in the label because it's the
  /// stronger, more specific signal ("no lead" vs "bad count").
  final GroupRatioNow ratio;

  final VoidCallback onSelected;
  final VoidCallback onLongPress;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final color =
        _parseHex(summary.group.colorHex) ?? theme.colorScheme.primary;
    // Two warning paths collapse into one visual state: an unstaffed
    // group (no lead on shift) or a ratio violation (too many kids per
    // adult). Unstaffed wins the label copy because "no lead" is the
    // more actionable, specific message than "14:0".
    final kids = ratio.childrenInGroupNow;
    final adults = ratio.adultsOnShiftForGroupNow;
    final hasKids = kids > 0;
    final showWarning = !isStaffed || ratio.isUnderRatio;

    // Label rules:
    //  * Empty group → just the name. Ratio is meaningless with no
    //    kids assigned, so we don't shout "0:2" at the teacher.
    //  * Unstaffed → "Name · no lead" (strongest signal).
    //  * Otherwise → "Name · k:a" (plain suffix, muted when OK).
    final String label;
    if (!hasKids) {
      label = summary.name;
    } else if (!isStaffed) {
      label = '${summary.name} · no lead';
    } else {
      label = '${summary.name} · $kids:$adults';
    }

    final onWarnColor = theme.colorScheme.onErrorContainer;
    // Muted sub-text color for the " · k:a" suffix so it doesn't
    // shout at a glance on normal chips. In warning state the whole
    // label adopts `onErrorContainer` and the muted sub-text step
    // is redundant — the warning palette already speaks for itself.
    final baseStyle = theme.textTheme.labelMedium;
    final normalNameColor = theme.textTheme.labelMedium?.color;
    final normalSuffixColor = theme.colorScheme.onSurfaceVariant;

    // Unstaffed chips get the errorContainer tint regardless of
    // selection. The selection check-ring (FilterChip paints one
    // automatically when `selected` is true) still reads over the
    // top — "this one has a problem AND I'm focused on it" is the
    // most common reason to look at an unstaffed chip at all.
    return GestureDetector(
      onLongPress: onLongPress,
      child: FilterChip(
        selected: selected,
        onSelected: (_) => onSelected(),
        showCheckmark: false,
        backgroundColor:
            showWarning ? theme.colorScheme.errorContainer : null,
        avatar: showWarning
            ? Icon(
                Icons.warning_amber_rounded,
                size: 14,
                color: onWarnColor,
              )
            : Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
        label: showWarning
            ? Text(
                label,
                style: baseStyle?.copyWith(color: onWarnColor),
              )
            : _NormalChipLabel(
                name: summary.name,
                suffix: hasKids ? ' · $kids:$adults' : null,
                baseStyle: baseStyle,
                nameColor: normalNameColor,
                suffixColor: normalSuffixColor,
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

/// Two-span chip label for the "OK" case: group name in the default
/// chip-text color, ratio suffix (" · 14:2") in a muted sub-text
/// color so the numeric detail is legible without shouting at every
/// glance. `suffix` null collapses to a single name span (empty
/// group — no ratio worth showing).
class _NormalChipLabel extends StatelessWidget {
  const _NormalChipLabel({
    required this.name,
    required this.suffix,
    required this.baseStyle,
    required this.nameColor,
    required this.suffixColor,
  });

  final String name;
  final String? suffix;
  final TextStyle? baseStyle;
  final Color? nameColor;
  final Color? suffixColor;

  @override
  Widget build(BuildContext context) {
    if (suffix == null) {
      return Text(name, style: baseStyle?.copyWith(color: nameColor));
    }
    return Text.rich(
      TextSpan(
        style: baseStyle?.copyWith(color: nameColor),
        children: [
          TextSpan(text: name),
          TextSpan(
            text: suffix,
            style: baseStyle?.copyWith(color: suffixColor),
          ),
        ],
      ),
    );
  }
}

/// Reveal card for the currently-selected group's warning flags —
/// lives directly below the chip row so tapping a flagged chip doesn't
/// just filter Today silently, it explains WHY the warning icon is
/// there and offers a next step.
///
/// Two reason flavors (either or both can fire):
///   * unstaffed → "No lead on shift today" + "Anchor a lead" CTA
///   * under-ratio → "14 kids · 1 adult — under 8:1" + "Group detail" CTA
///
/// Self-hides for healthy groups, empty groups, and the "no group
/// selected" state.
class _SelectedGroupWarning extends ConsumerWidget {
  const _SelectedGroupWarning();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(lastExpandedGroupProvider);
    if (selectedId == null) return const SizedBox.shrink();
    final summariesAsync = ref.watch(groupSummariesProvider);
    final summaries = summariesAsync.asData?.value ?? const <GroupSummary>[];
    GroupSummary? selected;
    for (final g in summaries) {
      if (g.id == selectedId) {
        selected = g;
        break;
      }
    }
    if (selected == null) return const SizedBox.shrink();

    // Same data sources the chip row uses. Missing streams fall back
    // to empties — safer than spinning up a full-page error state
    // for a banner that self-hides anyway.
    final allAdults =
        ref.watch(adultsProvider).asData?.value ?? const <Adult>[];
    final allAvail =
        ref.watch(allAvailabilityProvider).asData?.value ??
        const <AdultAvailabilityData>[];
    final todayBlocks =
        ref.watch(todayAdultBlocksProvider).asData?.value ??
        const <AdultDayBlock>[];
    final allKids =
        ref.watch(childrenProvider).asData?.value ?? const <Child>[];
    final nowAsync = ref.watch(nowTickProvider);
    final now = nowAsync.asData?.value ?? DateTime.now();

    final childrenInGroup = <Child>[
      for (final k in allKids)
        if (k.groupId == selected.id) k,
    ];
    final ratio = computeGroupRatioNow(
      groupId: selected.id,
      childrenInGroup: childrenInGroup,
      allAdults: allAdults,
      allAvailability: allAvail,
      todayBlocks: todayBlocks,
      now: now,
    );
    final isStaffed = isGroupStaffedToday(
      groupId: selected.id,
      weekday: now.weekday,
      adults: allAdults,
      todayDayBlocks: todayBlocks,
      availability: allAvail,
    );

    final showUnstaffed = !isStaffed;
    // Ratio warning is redundant when already unstaffed (0 adults
    // always over-ratio) — show just the stronger signal in that
    // case so the banner stays one-idea-per-row.
    final showRatio = !showUnstaffed && ratio.isUnderRatio;
    if (!showUnstaffed && !showRatio) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: theme.colorScheme.onErrorContainer,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    showUnstaffed
                        ? 'No lead on shift today'
                        : 'Under 8:1 ratio',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    showUnstaffed
                        ? 'No anchored lead is available for '
                            '${selected.name} right now. Anchor '
                            'one, or check their availability.'
                        : '${selected.name} has '
                            '${ratio.childrenInGroupNow} kids with '
                            '${ratio.adultsOnShiftForGroupNow} '
                            'adult${ratio.adultsOnShiftForGroupNow == 1 ? '' : 's'} '
                            'on shift — over the 8:1 state ratio.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: () => GroupDetailScreen.open(context, selected!.id),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onErrorContainer,
              ),
              child: const Text('Open'),
            ),
          ],
        ),
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
  const _EmptyState({required this.onEdit, required this.isToday});

  final VoidCallback onEdit;

  /// Copy is slightly different on other days — "Nothing scheduled
  /// today" is tone-deaf when the teacher is looking at next Thursday.
  final bool isToday;

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
              isToday
                  ? 'Nothing scheduled today'
                  : 'Nothing scheduled',
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

/// Stream of `{tripId: [groupId, …]}`. Thin wrapper around
/// `TripsRepository.watchAllGroupsByTrip()` so the Today screen can
/// run the trip-conflict detector without threading the repo call
/// through a FutureBuilder.
final _allTripGroupsByTripProvider = StreamProvider<Map<String, List<String>>>((
  ref,
) {
  ref.watch(activeProgramIdProvider);
  return ref.watch(tripsRepositoryProvider).watchAllGroupsByTrip();
});
