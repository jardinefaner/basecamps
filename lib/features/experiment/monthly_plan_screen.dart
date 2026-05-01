import 'dart:async';
import 'dart:convert';

import 'package:basecamp/database/database.dart' show Group;
import 'package:basecamp/features/adults/adults_repository.dart'
    show AdultRole, currentAdultProvider;
import 'package:basecamp/features/ai/ai_activity_addons.dart';
import 'package:basecamp/features/ai/ai_activity_composer.dart';
import 'package:basecamp/features/ai/openai_client.dart';
import 'package:basecamp/features/children/children_repository.dart'
    show groupsProvider;
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/adaptive_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Lab surface — **Monthly Plan.** Mon–Fri grid for a single month;
/// each cell holds at most one activity per group. No time-of-day,
/// no duration — that's what the week plan is for.
///
/// **Per-group activities.** A required group filter at the top
/// scopes the visible cells: each (date, group) pair owns one
/// activity. There's no "All" option — a teacher picks a group and
/// authors *that group's* month.
///
/// **Side rail per week.** First column is the sub-theme and
/// aggregated supplies for that week — sub-theme is free-text the
/// teacher types ("Colors", "Spring", "Numbers"), supplies are
/// computed from the activities visible in that week (deduped,
/// case-insensitive). Both update live as the row's cells fill in.
///
/// **Cell tap → formatted view.** Tapping a filled cell opens a
/// READ-only "what to do today" sheet — title, description, numbered
/// steps, materials, link, all rendered for an adult who's looking at
/// the day cold and needs to know exactly what to run. A pencil in
/// the top-right of that sheet drops into the editor for the
/// teacher who actually owns the lesson plan.
///
/// **Adjacent-month dates** render muted + non-interactive so the
/// grid stays rectangular (Google Calendar idiom).
///
/// Drafts live in memory only; sandbox until this graduates.
class MonthlyPlanScreen extends ConsumerStatefulWidget {
  const MonthlyPlanScreen({super.key});

  @override
  ConsumerState<MonthlyPlanScreen> createState() =>
      _MonthlyPlanScreenState();
}

class _MonthlyPlanScreenState extends ConsumerState<MonthlyPlanScreen> {
  /// First-of-month for the visible month.
  late DateTime _viewMonth = _firstOfMonth(DateTime.now());

  /// Currently-selected group filter. Required (no "All"). Defaults
  /// to the first group as soon as the groups stream resolves with at
  /// least one entry. Kept null until that point.
  String? _activeGroupId;

  /// Variants per cell, keyed by `"$groupId|$dayKey"`. Each cell can
  /// hold N variants — the manual one the user typed inline, plus
  /// any AI variants generated via the ✨ button. List order is
  /// creation order; [_activeVariantIndex] picks which one renders
  /// in the cell + opens in the formatted view.
  final Map<String, List<_MonthlyActivity>> _activities = {};

  /// Active variant index per cell. Defaults to 0 (the first/manual
  /// variant) when absent. Setting it switches what the cell shows.
  final Map<String, int> _activeVariantIndex = {};

  /// Cell that's currently in inline-edit mode (the multi-line
  /// TextField rendering inside the cell). Only one cell edits at a
  /// time. Null when nothing's editing.
  String? _editingCellKey;

  /// Cell that's currently focused (touch-tap on mobile, hover on
  /// web). Drives visibility of ✨ + × + dots so they don't clutter
  /// every cell at once.
  String? _focusedCellKey;

  /// Cell whose ✨ is currently mid-generation. While this matches
  /// a cell's key, the cell renders a spinner where the ✨ used to
  /// be and the button is disabled. Inline (no modal) so the user
  /// stays in the calendar view through the round-trip.
  String? _generatingCellKey;

  /// Sub-theme strings keyed by `weekMondayDayKey`. NOT group-scoped —
  /// the sub-theme is a thematic label for the week as a whole and
  /// shared across groups (a "Colors" week means colors for everyone).
  /// If usage shows that's wrong, easy to scope per-group later.
  final Map<String, String> _subThemes = {};

  /// Monthly themes keyed by `"$year-$month"`. Each visible month
  /// owns its own theme — flipping from April to May swaps in May's
  /// theme (or empty if not yet set). Drives AI generation context
  /// for cells in that month.
  final Map<String, String> _monthlyThemes = {};

  String _monthKey(DateTime d) => '${d.year}-${d.month}';
  String get _activeMonthlyTheme =>
      _monthlyThemes[_monthKey(_viewMonth)] ?? '';

  void _setMonthlyTheme(String value) {
    setState(() {
      final key = _monthKey(_viewMonth);
      if (value.trim().isEmpty) {
        _monthlyThemes.remove(key);
      } else {
        _monthlyThemes[key] = value;
      }
    });
  }

  // Per-group age range now lives on the Group row itself
  // (`audienceAgeLabel`) — no local state needed. Edit it from the
  // Children & Groups screen's group detail / edit sheet; the
  // monthly plan reads it via the `groupsProvider` stream.

  static DateTime _firstOfMonth(DateTime d) =>
      DateTime(d.year, d.month);

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';

  String _activityKey(DateTime d, String groupId) =>
      '$groupId|${_dayKey(d)}';

  /// Identity-gating predicate (v54). Same logic as the build
  /// method's local `canEdit` — re-derived here so async event
  /// handlers (tap dispatcher, AI variant handler, etc.) can check
  /// without threading the value through every callback.
  bool get _canEditActiveGroup {
    final me = ref.read(currentAdultProvider).asData?.value;
    if (me == null) return true; // unbound = full access
    final role = AdultRole.fromDb(me.adultRole);
    if (role != AdultRole.lead) return false;
    return me.anchoredGroupId != null &&
        _activeGroupId == me.anchoredGroupId;
  }

  // -----------------------------------------------------------------
  // Variant accessors
  // -----------------------------------------------------------------

  List<_MonthlyActivity> _variantsAt(DateTime d, String groupId) =>
      _activities[_activityKey(d, groupId)] ?? const [];

  int _activeIdxAt(DateTime d, String groupId) {
    final list = _variantsAt(d, groupId);
    if (list.isEmpty) return 0;
    final raw = _activeVariantIndex[_activityKey(d, groupId)] ?? 0;
    return raw.clamp(0, list.length - 1);
  }

  _MonthlyActivity? _activeAt(DateTime d, String groupId) {
    final list = _variantsAt(d, groupId);
    if (list.isEmpty) return null;
    return list[_activeIdxAt(d, groupId)];
  }

  void _shiftMonth(int deltaMonths) {
    setState(() {
      _viewMonth = DateTime(
        _viewMonth.year,
        _viewMonth.month + deltaMonths,
      );
    });
  }

  void _resetToThisMonth() {
    setState(() => _viewMonth = _firstOfMonth(DateTime.now()));
  }

  // -----------------------------------------------------------------
  // Cell actions
  // -----------------------------------------------------------------

  /// Called when a cell receives focus + the user wants to start
  /// authoring inline. Adds an empty variant if the cell has none,
  /// then flips into inline-edit mode for that variant. If a
  /// different cell was already in edit mode, that cell's edit is
  /// finalised first (drops its empty variant if the user typed
  /// nothing).
  void _enterInlineEdit(DateTime date) {
    final groupId = _activeGroupId;
    if (groupId == null) return;
    final key = _activityKey(date, groupId);
    if (_editingCellKey != null && _editingCellKey != key) {
      _exitInlineEdit();
    }
    setState(() {
      final list = _activities.putIfAbsent(key, () => []);
      if (list.isEmpty) {
        list.add(_MonthlyActivity());
        _activeVariantIndex[key] = 0;
      }
      _editingCellKey = key;
      _focusedCellKey = key;
    });
  }

  /// Live write into the active variant on every keystroke. The
  /// commit-on-blur pattern was fragile on mobile (tapping outside
  /// a TextField doesn't auto-unfocus on Flutter mobile, so blur
  /// never fired and content was lost). Writing on every keystroke
  /// means the variant is *always* up to date — even if the cell
  /// unmounts mid-edit (group switch, month change), the typed text
  /// survives.
  void _writeInlineEdit({
    required DateTime date,
    String? title,
    String? description,
  }) {
    final groupId = _activeGroupId;
    if (groupId == null) return;
    final key = _activityKey(date, groupId);
    final list = _activities[key];
    if (list == null || list.isEmpty) return;
    setState(() {
      final idx = _activeIdxAt(date, groupId);
      if (title != null) list[idx].title = title;
      if (description != null) list[idx].description = description;
    });
  }

  /// Exit edit mode without losing content (writes already happened
  /// per-keystroke via [_writeInlineEdit]). Drops the variant if it
  /// ended up entirely empty.
  void _exitInlineEdit() {
    final key = _editingCellKey;
    if (key == null) return;
    setState(() {
      _editingCellKey = null;
      final list = _activities[key];
      if (list == null || list.isEmpty) return;
      // Use the LAST element since edit mode always points at the
      // most recently appended (manual or AI) variant.
      final idx = (_activeVariantIndex[key] ?? 0)
          .clamp(0, list.length - 1);
      if (list[idx].isEmpty) {
        list.removeAt(idx);
        if (list.isEmpty) {
          _activities.remove(key);
          _activeVariantIndex.remove(key);
          _focusedCellKey = null;
        } else {
          _activeVariantIndex[key] = idx.clamp(0, list.length - 1);
        }
      }
    });
  }

  /// AI variant — INLINE generation, no modal sheet. The cell
  /// already has the source content; opening a modal would just be
  /// an extra step the user has to confirm before the model runs.
  /// Tap → spinner in the cell → new variant lands. Seamless.
  Future<void> _onCellAi(DateTime date) async {
    final groupId = _activeGroupId;
    if (groupId == null) return;
    final key = _activityKey(date, groupId);
    final active = _activeAt(date, groupId);
    if (active == null || active.isEmpty) return;
    setState(() => _generatingCellKey = key);
    try {
      final result = await generateAiVariant(
        activity: active.toAiActivity(),
        planContext: _aiContextForDate(date),
      );
      if (!mounted) return;
      setState(() {
        _generatingCellKey = null;
        _activities.putIfAbsent(key, () => []);
        final list = _activities[key]!
          ..add(_MonthlyActivity(
            title: result.title,
            description: result.description,
            objectives: result.objectives,
            steps: result.steps,
            materials: result.materials,
            link: result.link,
          ));
        // Switch active to the freshly-generated variant.
        _activeVariantIndex[key] = list.length - 1;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _generatingCellKey = null);
      // Surface via snackbar — quick, non-blocking, doesn't interrupt
      // the calendar view.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Couldn't generate: ${e.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), '')}",
          ),
        ),
      );
    }
  }

  /// Switch the active variant via dot tap or PageView swipe.
  void _switchVariant(DateTime date, int newIdx) {
    final groupId = _activeGroupId;
    if (groupId == null) return;
    final key = _activityKey(date, groupId);
    setState(() => _activeVariantIndex[key] = newIdx);
  }

  /// Delete the active variant. If it was the last one, the cell
  /// becomes empty.
  void _deleteActiveVariant(DateTime date) {
    final groupId = _activeGroupId;
    if (groupId == null) return;
    final key = _activityKey(date, groupId);
    setState(() {
      final list = _activities[key];
      if (list == null || list.isEmpty) return;
      final idx = _activeIdxAt(date, groupId);
      list.removeAt(idx);
      if (list.isEmpty) {
        _activities.remove(key);
        _activeVariantIndex.remove(key);
        _focusedCellKey = null;
      } else {
        _activeVariantIndex[key] = idx.clamp(0, list.length - 1);
      }
    });
  }

  /// Set/clear the focused cell (mobile tap or web hover). When
  /// focusing a different cell while a prior one was inline-editing,
  /// finalise that prior edit first so empty variants don't pile up.
  void _setFocusedCell(String? key) {
    if (_focusedCellKey == key) return;
    if (_editingCellKey != null && _editingCellKey != key) {
      _exitInlineEdit();
    }
    setState(() => _focusedCellKey = key);
  }

  /// Tap on a week's side rail — opens a bigger modal that surfaces
  /// the sub-theme (editable) + the aggregated supplies (read-only,
  /// scrollable) together. The cramped side-rail row is fine for at-a-
  /// glance review; this sheet is for "I need to see all of this
  /// week's supplies for shopping" or "let me set the sub-theme with
  /// some breathing room."
  Future<void> _openWeekDetails(List<DateTime> week) async {
    final mondayKey = _dayKey(week.first);
    await showAdaptiveSheet<void>(
      context: context,
      builder: (_) => _WeekDetailsSheet(
        weekRangeLabel: _weekRangeLabel(week),
        initialSubTheme: _subThemes[mondayKey] ?? '',
        onSubThemeChanged: (v) {
          setState(() {
            if (v.isEmpty) {
              _subThemes.remove(mondayKey);
            } else {
              _subThemes[mondayKey] = v;
            }
          });
        },
        materials: _aggregateMaterialsForWeek(week),
      ),
    );
  }

  String _weekRangeLabel(List<DateTime> week) {
    final mon = week.first;
    final fri = week.last;
    if (mon.month == fri.month) {
      return '${DateFormat.MMMd().format(mon)} – ${DateFormat.d().format(fri)}';
    }
    return '${DateFormat.MMMd().format(mon)} – ${DateFormat.MMMd().format(fri)}';
  }

  /// Bundle the visible context (monthly theme, week sub-theme,
  /// active group's age range + name) for AI generation. Caller
  /// passes whatever date the cell is for so we pick the right
  /// week's sub-theme.
  AiActivityContext _aiContextForDate(DateTime date) {
    final groupId = _activeGroupId;
    final groupsAsync = ref.read(groupsProvider);
    final groups = groupsAsync.maybeWhen<List<Group>>(
      data: (list) => list,
      orElse: () => const <Group>[],
    );
    final group = groupId == null || groups.isEmpty
        ? null
        : groups.firstWhere(
            (g) => g.id == groupId,
            orElse: () => groups.first,
          );
    // Find the Monday of the date's week to look up the sub-theme.
    final monday = date.subtract(Duration(days: date.weekday - 1));
    return AiActivityContext(
      monthlyTheme: _activeMonthlyTheme,
      // Pulled straight off the Group row — single source of truth.
      ageRange: group?.audienceAgeLabel,
      subTheme: _subThemes[_dayKey(monday)],
      groupName: group?.name,
    );
  }

  /// One-stop tap dispatcher for any day cell. Three branches:
  ///   * Empty cell → enter inline edit mode (the cell becomes a
  ///     mini-doc with a multi-line TextField; first line = title,
  ///     subsequent lines = description).
  ///   * Filled cell that's not yet focused → focus it (reveals
  ///     ✨ + × + dots).
  ///   * Filled cell that's already focused → open the formatted
  ///     "what to do today" view for the active variant.
  Future<void> _onDayCellTap(DateTime date) async {
    final groupId = _activeGroupId;
    if (groupId == null) return;
    final key = _activityKey(date, groupId);
    final variants = _variantsAt(date, groupId);
    if (variants.isEmpty) {
      // Read-only viewers (non-leads, leads viewing another group)
      // can't enter inline edit on an empty cell. The focus halo
      // still updates so they see which cell they tapped, but no
      // editor opens. Lead-on-anchored-group users get full edit.
      if (_canEditActiveGroup) {
        _enterInlineEdit(date);
      } else {
        _setFocusedCell(key);
      }
      return;
    }
    if (_focusedCellKey != key) {
      _setFocusedCell(key);
      return;
    }
    final active = _activeAt(date, groupId);
    if (active != null && !active.isEmpty) {
      await _onTapFilled(date, active);
    }
  }

  /// Tap on a filled cell — opens the read-only "what to do today"
  /// view. Inside that sheet, the user can drop into the editor via
  /// a pencil icon. The two surfaces are distinct on purpose: the
  /// formatted view is for *running* the day (someone who didn't
  /// author it); the editor is for *authoring* the day.
  Future<void> _onTapFilled(DateTime date, _MonthlyActivity activity) async {
    final groupId = _activeGroupId;
    if (groupId == null) return;
    await showAdaptiveSheet<void>(
      context: context,
      builder: (_) => _ActivityFormattedSheet(
        date: date,
        activity: activity,
        planContext: _aiContextForDate(date),
        onEdit: () async {
          // Pop the formatted sheet first so the editor stacks on
          // top of the calendar, not on top of the read view (back
          // gesture on mobile lands the user in the calendar, not
          // back in the formatted view).
          Navigator.of(context).pop();
          await _openEditor(date, groupId, activity);
        },
        onDelete: () {
          Navigator.of(context).pop();
          setState(() => _activities.remove(_activityKey(date, groupId)));
        },
      ),
    );
  }

  Future<void> _openEditor(
    DateTime date,
    String groupId,
    _MonthlyActivity activity,
  ) async {
    await showAdaptiveSheet<void>(
      context: context,
      builder: (_) => _MonthlyActivityEditor(
        date: date,
        activity: activity,
        planContext: _aiContextForDate(date),
        onChanged: () {
          if (mounted) setState(() {});
        },
        onDelete: () {
          setState(() => _activities.remove(_activityKey(date, groupId)));
          unawaited(Navigator.of(context).maybePop());
        },
      ),
    );
  }

  // -----------------------------------------------------------------
  // Aggregations
  // -----------------------------------------------------------------

  /// Weeks of the visible month, each as a Mon–Fri list. Pads with
  /// adjacent-month dates so every row is a complete week.
  List<List<DateTime>> _buildWeeks() {
    final first = DateTime(_viewMonth.year, _viewMonth.month);
    final last = DateTime(_viewMonth.year, _viewMonth.month + 1, 0);

    final firstMonday = first.subtract(Duration(days: first.weekday - 1));
    final lastFriday = last.weekday <= 5
        ? last.add(Duration(days: 5 - last.weekday))
        : last.subtract(Duration(days: last.weekday - 5));

    final weeks = <List<DateTime>>[];
    var monday = firstMonday;
    while (!monday.isAfter(lastFriday)) {
      weeks.add([
        for (var d = 0; d < 5; d++) monday.add(Duration(days: d)),
      ]);
      monday = monday.add(const Duration(days: 7));
    }
    return weeks;
  }

  /// Materials from every activity rendered in [week] for the active
  /// group, deduped case-insensitively. Empty when no activities have
  /// materials filled in. Strings come pre-split on commas so an
  /// activity's "paper, scissors, glue" contributes three entries.
  List<String> _aggregateMaterialsForWeek(List<DateTime> week) {
    final groupId = _activeGroupId;
    if (groupId == null) return const [];
    final seen = <String, String>{}; // lowercased → original casing
    for (final date in week) {
      // Aggregate from the ACTIVE variant only — the user's seeing
      // that one in the cell, so its materials are what they
      // actually need to gather. Inactive variants don't contribute
      // (otherwise the supply list would balloon with every AI
      // generation regardless of which one was kept).
      final active = _activeAt(date, groupId);
      if (active == null) continue;
      for (final raw in active.materials.split(',')) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) continue;
        seen.putIfAbsent(trimmed.toLowerCase(), () => trimmed);
      }
    }
    return seen.values.toList()..sort();
  }

  // -----------------------------------------------------------------
  // Build
  // -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupsProvider);
    final weeks = _buildWeeks();
    final monthLabel = DateFormat.yMMMM().format(_viewMonth);

    // Identity gating (v54). The signed-in user resolves to an
    // Adult row via currentAdultProvider; from there:
    //   * me == null           → unbound user (admin pre-rollout,
    //                            generic teacher who hasn't redeemed
    //                            an adult-bound invite). Full access
    //                            preserved — backward compatible.
    //   * me + role == lead    → locked to anchored group; can edit.
    //   * me + role != lead    → can browse any group, read-only.
    //
    // canEdit decides whether cells expose inline edit / AI / delete
    // affordances. The group filter is locked to the lead's
    // anchored group when applicable so they can't accidentally
    // edit a peer's plan.
    final me = ref.watch(currentAdultProvider).asData?.value;
    final myAdultRole =
        me == null ? null : AdultRole.fromDb(me.adultRole);
    final isLead = myAdultRole == AdultRole.lead;
    final myGroupId = me?.anchoredGroupId;
    final lockedToGroup = isLead && myGroupId != null;
    final canEdit = me == null ||
        (lockedToGroup && _activeGroupId == myGroupId);

    return Scaffold(
      appBar: AppBar(
        // Month label + chevrons live IN the AppBar now (was a
        // separate toolbar row eating ~50dp of vertical space on
        // mobile). Tapping the title resets to the current month.
        title: InkWell(
          onTap: _resetToThisMonth,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 4,
            ),
            child: Text(monthLabel),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _shiftMonth(-1),
          ),
          IconButton(
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _shiftMonth(1),
          ),
          IconButton(
            tooltip: 'This month',
            icon: const Icon(Icons.today_outlined),
            onPressed: _resetToThisMonth,
          ),
        ],
      ),
      body: Column(
        children: [
          // Monthly theme — top-most input. Per-month, used as AI
          // generation context. The bar keys itself by month so
          // flipping months remounts cleanly with the right value
          // and any in-flight suggestion chips reset.
          _MonthlyThemeBar(
            key: ValueKey(_monthKey(_viewMonth)),
            month: _viewMonth,
            value: _activeMonthlyTheme,
            onChanged: _setMonthlyTheme,
          ),
          // Group filter — required. Sits above the toolbar so it's
          // the first thing the user sees / picks.
          groupsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text('Error loading groups: $e'),
            ),
            data: (groups) {
              if (groups.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Text(
                    'No groups yet — add one in Children & Groups '
                    'before authoring a monthly plan.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                );
              }
              // Default-select. Leads land on their anchored group;
              // everyone else lands on the first group. Leads can
              // STILL switch into other groups (view-only) — this
              // is a coordination app where everyone sees the full
              // plan; the gating is on *edit*, not visibility. The
              // initial pre-select just gets them to their own
              // group fastest.
              if (_activeGroupId == null ||
                  !groups.any((g) => g.id == _activeGroupId)) {
                final preferred = lockedToGroup &&
                        groups.any((g) => g.id == myGroupId)
                    ? myGroupId
                    : groups.first.id;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() => _activeGroupId = preferred);
                });
              }
              return _GroupFilterBar(
                groups: groups,
                activeId: _activeGroupId,
                onSelect: (id) => setState(() => _activeGroupId = id),
              );
            },
          ),
          // Day-of-week header was previously rendered above the
          // horizontal scroll view, which on mobile drifted out of
          // alignment with the day columns once the user scrolled
          // (the body scrolled, the header didn't). The header has
          // moved INSIDE the scroll view alongside the grid below;
          // see the SizedBox child Column.
          const Divider(height: 1),
          // Grid uses fixed minimum cell sizes — day cells 160dp
          // wide × 120dp tall minimum, side rail 240dp wide. On a
          // phone the total exceeds the viewport on both axes, so
          // we wrap in nested ScrollViews (vertical outer +
          // horizontal inner) and let the user pan around like a
          // printed sheet. On wide windows the cells stretch up to
          // fill the viewport via Expanded inside the day Row.
          //
          // Why fixed-min rather than fit-to-viewport: a phone-fit
          // grid crunches each cell to ~30×45dp, which is too small
          // to read (and overflowed the children with a striped
          // error pattern). A fixed-min grid is bigger than the
          // phone but readable and tappable, which is the actual
          // job to be done.
          Expanded(
            child: _activeGroupId == null
                ? const SizedBox.shrink()
                : LayoutBuilder(
                    builder: (context, constraints) {
                      const minSideRailWidth = 240.0;
                      const minDayCellWidth = 160.0;
                      const headerRowHeight = 32.0;
                      const totalCols = 5;
                      const minTotalWidth = minSideRailWidth +
                          minDayCellWidth * totalCols;
                      final width = constraints.maxWidth >= minTotalWidth
                          ? constraints.maxWidth
                          : minTotalWidth;
                      return SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Padding(
                            padding:
                                const EdgeInsets.all(AppSpacing.sm),
                            child: SizedBox(
                              // Width is fixed (max of viewport vs the
                              // minimum). Height is INTRINSIC — each
                              // row sizes to its tallest cell's
                              // content so long descriptions, tall
                              // bullet lists, etc. all fit without
                              // truncation. The user explicitly
                              // wanted "all texts displayed."
                              width: width - AppSpacing.sm * 2,
                              child: Column(
                      children: [
                        // Day-of-week header — same column widths
                        // as the body rows so labels line up under
                        // their cells regardless of horizontal scroll
                        // position.
                        const SizedBox(
                          height: headerRowHeight,
                          child: _GridHeaderRow(
                            sideWidth: minSideRailWidth,
                          ),
                        ),
                        for (final week in weeks)
                          // Each row's height = max of its cells'
                          // intrinsic content heights, with a 120dp
                          // floor (ConstrainedBox inside the cell).
                          // Different weeks can therefore end up
                          // different heights, which is fine — a
                          // sparse week stays compact, a packed week
                          // grows to fit. No more "title gets a 3-
                          // line ellipsis" cropping.
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                              children: [
                                // Side rail: sub-theme + aggregated
                                // materials for this week. Fixed
                                // 240dp wide so it stays readable
                                // independent of how many days are
                                // in the row; day cells stretch via
                                // Expanded above the 160dp minimum.
                                SizedBox(
                                  width: minSideRailWidth,
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: _WeekSidePanel(
                                      weekMondayKey: _dayKey(week.first),
                                      subTheme: _subThemes[
                                              _dayKey(week.first)] ??
                                          '',
                                      onSubThemeChanged: (v) {
                                        setState(() {
                                          if (v.isEmpty) {
                                            _subThemes.remove(
                                                _dayKey(week.first));
                                          } else {
                                            _subThemes[_dayKey(week.first)] =
                                                v;
                                          }
                                        });
                                      },
                                      materials: _aggregateMaterialsForWeek(
                                        week,
                                      ),
                                      onTap: () => _openWeekDetails(week),
                                    ),
                                  ),
                                ),
                                for (final date in week)
                                  // Day cell — stretches via Expanded
                                  // above the 160dp minimum (the
                                  // outer SizedBox's width guarantees
                                  // the floor). On wide windows
                                  // these grow proportionally.
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(2),
                                      child: _DayCell(
                                        // Key includes the cell key
                                        // so the cell's local state
                                        // (PageController) doesn't
                                        // leak across cells when
                                        // groups switch.
                                        key: ValueKey(
                                          '${_activeGroupId!}|'
                                          '${_dayKey(date)}',
                                        ),
                                        date: date,
                                        isCurrentMonth: date.month ==
                                            _viewMonth.month,
                                        variants: _variantsAt(
                                            date, _activeGroupId!),
                                        activeIndex: _activeIdxAt(
                                            date, _activeGroupId!),
                                        isEditing: _editingCellKey ==
                                            _activityKey(
                                                date, _activeGroupId!),
                                        isFocused: _focusedCellKey ==
                                            _activityKey(
                                                date, _activeGroupId!),
                                        isGenerating:
                                            _generatingCellKey ==
                                                _activityKey(date,
                                                    _activeGroupId!),
                                        canEdit: canEdit,
                                        onTap: () => unawaited(
                                          _onDayCellTap(date),
                                        ),
                                        onFocusEnter: () =>
                                            _setFocusedCell(
                                                _activityKey(date,
                                                    _activeGroupId!)),
                                        onFocusExit: () {
                                          // Web hover-out clears
                                          // focus only if no inline
                                          // edit is in progress on
                                          // this cell.
                                          if (_editingCellKey !=
                                              _activityKey(date,
                                                  _activeGroupId!)) {
                                            _setFocusedCell(null);
                                          }
                                        },
                                        onWriteTitle: (v) =>
                                            _writeInlineEdit(
                                          date: date,
                                          title: v,
                                        ),
                                        onWriteDescription: (v) =>
                                            _writeInlineEdit(
                                          date: date,
                                          description: v,
                                        ),
                                        onSwitchVariant: (idx) =>
                                            _switchVariant(date, idx),
                                        onAi: () =>
                                            unawaited(_onCellAi(date)),
                                        onDeleteActive: () =>
                                            _deleteActiveVariant(date),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Models
// =====================================================================

class _MonthlyActivity {
  _MonthlyActivity({
    this.title = '',
    this.description = '',
    this.objectives = '',
    this.steps = '',
    this.materials = '',
    this.link = '',
  });

  String title;
  String description;
  String objectives;
  String steps;
  String materials;
  String link;

  bool get isEmpty =>
      title.trim().isEmpty &&
      description.trim().isEmpty &&
      objectives.trim().isEmpty &&
      steps.trim().isEmpty &&
      materials.trim().isEmpty &&
      link.trim().isEmpty;

  bool get hasAnyMetadata =>
      objectives.isNotEmpty ||
      steps.isNotEmpty ||
      materials.isNotEmpty ||
      link.isNotEmpty;

  /// Adapter for the AI add-ons + composer surfaces, both of which
  /// take the public [AiActivity] shape. Same fields, just a copy
  /// across the layer boundary so this private draft type doesn't
  /// leak into the AI module's API.
  AiActivity toAiActivity() {
    return AiActivity(
      title: title,
      description: description,
      objectives: objectives,
      steps: steps,
      materials: materials,
      link: link,
    );
  }
}

// =====================================================================
// Top bars
// =====================================================================

/// Group filter — horizontal chip row. Each group renders as a
/// ChoiceChip with name + audience-age suffix; tap to switch. The
/// row scrolls horizontally on narrow phones so 5+ groups don't
/// wrap into a tall multi-line block.
///
/// Coordination model: every signed-in user can switch through
/// every group's plan freely. The edit gating is per-cell (driven
/// by `canEdit` on the screen) — non-leads can browse but not
/// author. So this filter is pure navigation, no lock state.
class _GroupFilterBar extends StatelessWidget {
  const _GroupFilterBar({
    required this.groups,
    required this.activeId,
    required this.onSelect,
  });

  final List<Group> groups;
  final String? activeId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final g in groups)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: ChoiceChip(
                  label: Text(
                    (g.audienceAgeLabel ?? '').isEmpty
                        ? g.name
                        : '${g.name} · ${g.audienceAgeLabel}',
                  ),
                  selected: activeId == g.id,
                  onSelected: (_) => onSelect(g.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GridHeaderRow extends StatelessWidget {
  const _GridHeaderRow({required this.sideWidth});

  final double sideWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
    return Row(
      children: [
        SizedBox(
          width: sideWidth,
          child: Center(
            child: Text('Theme · Supplies', style: labelStyle),
          ),
        ),
        for (final label in dayLabels)
          Expanded(
            child: Center(child: Text(label, style: labelStyle)),
          ),
      ],
    );
  }
}

// =====================================================================
// Side rail — sub-theme + materials per week
// =====================================================================

class _WeekSidePanel extends StatefulWidget {
  const _WeekSidePanel({
    required this.weekMondayKey,
    required this.subTheme,
    required this.onSubThemeChanged,
    required this.materials,
    required this.onTap,
  });

  final String weekMondayKey;
  final String subTheme;
  final ValueChanged<String> onSubThemeChanged;
  final List<String> materials;

  /// Tap on the panel — opens the week-details sheet. Not wired to
  /// the inline TextField (so typing into the sub-theme inline still
  /// works without bouncing into a modal).
  final VoidCallback onTap;

  @override
  State<_WeekSidePanel> createState() => _WeekSidePanelState();
}

class _WeekSidePanelState extends State<_WeekSidePanel> {
  late final TextEditingController _subThemeCtrl =
      TextEditingController(text: widget.subTheme);

  @override
  void didUpdateWidget(covariant _WeekSidePanel old) {
    super.didUpdateWidget(old);
    // External writes (different week reusing this state slot) sync
    // back into the controller.
    if (widget.subTheme != _subThemeCtrl.text) {
      _subThemeCtrl.text = widget.subTheme;
    }
  }

  @override
  void dispose() {
    _subThemeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: 0.6),
          width: 0.5,
        ),
      ),
      child: InkWell(
        // Tap on the panel body opens the week-details modal. The
        // inner TextField gets pointer events first (so typing
        // doesn't bounce to the modal), and the supplies list is
        // also tappable for the modal as a side effect.
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sub-theme — single-line text input. No chrome (matches
            // the WYSIWYG idiom from the experiment), placeholder
            // visible when empty.
            TextField(
              controller: _subThemeCtrl,
              onChanged: widget.onSubThemeChanged,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: 'Sub-theme',
                hintStyle: theme.textTheme.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w700,
                ),
                isDense: true,
                isCollapsed: true,
                filled: false,
                fillColor: Colors.transparent,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Supplies',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            // Aggregated supplies — laid out in TWO columns inside
            // the side rail so a long week's supplies list doesn't
            // push the whole row vertically as much. The list
            // splits left-to-right (item 0, 1, 2 → left column;
            // item 3, 4, 5 → right) — half the rows for the same
            // count of supplies. Empty state stays as a single
            // muted dash.
            if (widget.materials.isEmpty)
              Text(
                '—',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              )
            else
              _SuppliesTwoColumns(items: widget.materials),
          ],
        ),
        ),
      ),
    );
  }
}

/// Two-column bulleted layout for the side rail's supplies list.
/// **Column-major** fill — the left column fills top-to-bottom
/// first; once it's exhausted, items spill into the right column.
/// That matches how a printed list reads (newspaper-style) and
/// keeps the most important supplies in the leftmost column.
///
/// No truncation — full text wraps to multiple lines if needed,
/// matches the user's "all texts visible" rule for the calendar.
class _SuppliesTwoColumns extends StatelessWidget {
  const _SuppliesTwoColumns({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Column-major split: left column gets ceil(N/2) items, right
    // column gets the remaining floor(N/2). For odd counts the
    // left column carries the extra (visual balance from the top).
    final mid = (items.length + 1) ~/ 2;
    final left = items.sublist(0, mid);
    final right = items.sublist(mid);
    Widget bulletColumn(List<String> entries) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                '• $m',
                style: theme.textTheme.bodySmall,
                // No maxLines / no ellipsis — long materials wrap
                // and the cell grows to accommodate. Matches the
                // monthly plan's "show all texts" rule.
              ),
            ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: bulletColumn(left)),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: bulletColumn(right)),
      ],
    );
  }
}

// =====================================================================
// Day cell
// =====================================================================

class _DayCell extends StatefulWidget {
  const _DayCell({
    required this.date,
    required this.isCurrentMonth,
    required this.variants,
    required this.activeIndex,
    required this.isEditing,
    required this.isFocused,
    required this.isGenerating,
    required this.canEdit,
    required this.onTap,
    required this.onFocusEnter,
    required this.onFocusExit,
    required this.onWriteTitle,
    required this.onWriteDescription,
    required this.onSwitchVariant,
    required this.onAi,
    required this.onDeleteActive,
    super.key,
  });

  final DateTime date;
  final bool isCurrentMonth;
  final List<_MonthlyActivity> variants;
  final int activeIndex;
  final bool isEditing;
  final bool isFocused;
  final bool isGenerating;

  /// Identity gating (v54). When false, the cell is read-only — no
  /// inline edit, no AI / × affordances. Tapping a filled cell
  /// still opens the formatted view (read-only is browseable, just
  /// not authorable). Driven by the screen's `canEdit` derived
  /// from currentAdultProvider + lead-anchored-group check.
  final bool canEdit;
  final VoidCallback onTap;
  final VoidCallback onFocusEnter;
  final VoidCallback onFocusExit;
  // Two narrow callbacks instead of one commit-on-blur — see
  // _writeInlineEdit's doc-comment on the screen state. Each writes
  // immediately to the active variant so the typed content survives
  // even if the cell unmounts mid-edit (group switch, scroll-off).
  final ValueChanged<String> onWriteTitle;
  final ValueChanged<String> onWriteDescription;
  final ValueChanged<int> onSwitchVariant;
  final VoidCallback onAi;
  final VoidCallback onDeleteActive;

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell> {
  // Two controllers — one per field — so the title genuinely
  // renders bold while the user types it (single-buffer + split-on-
  // commit had no visual distinction between title and description
  // mid-edit). Two focus nodes too: ↵ on title moves focus to the
  // description field for the natural "type title, hit enter,
  // describe" flow.
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final FocusNode _titleFocus = FocusNode();
  late final FocusNode _descFocus = FocusNode();

  bool get _isToday {
    final now = DateTime.now();
    return widget.date.year == now.year &&
        widget.date.month == now.month &&
        widget.date.day == now.day;
  }

  @override
  void initState() {
    super.initState();
    final seedTitle = _activeVariant?.title ?? '';
    final seedDesc = _activeVariant?.description ?? '';
    _titleCtrl = TextEditingController(text: seedTitle);
    _descCtrl = TextEditingController(text: seedDesc);
    if (widget.isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _titleFocus.requestFocus();
      });
    }
  }

  _MonthlyActivity? get _activeVariant {
    if (widget.variants.isEmpty) return null;
    return widget.variants[
        widget.activeIndex.clamp(0, widget.variants.length - 1)];
  }

  @override
  void didUpdateWidget(covariant _DayCell old) {
    super.didUpdateWidget(old);
    // Sync the title/description controllers from the active variant
    // when an external write changes its content (advanced editor in
    // a sheet, etc.) — but only when we're NOT actively editing, so
    // we don't trample an in-progress keystroke.
    final active = _activeVariant;
    if (!widget.isEditing && active != null) {
      if (_titleCtrl.text != active.title) _titleCtrl.text = active.title;
      if (_descCtrl.text != active.description) {
        _descCtrl.text = active.description;
      }
    }
    // Edit state flipped on → grab focus on the title field. If the
    // variant already had content, keep the controllers' values
    // (they survive across rebuilds because they're State-level
    // fields). Also scroll the cell into view so the keyboard
    // doesn't cover it on mobile — a cell deep in a 6-week month
    // could otherwise be entirely behind the keyboard the moment
    // focus lands.
    if (widget.isEditing && !old.isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _titleFocus.requestFocus();
        unawaited(_scrollIntoView());
      });
    }
  }

  Future<void> _scrollIntoView() async {
    if (!mounted) return;
    // Scrollable.ensureVisible walks the parent chain and scrolls
    // each ancestor scrollable so that this widget is visible.
    // alignment 0.3 puts the cell roughly a third of the way down
    // the viewport — leaves room above for the toolbar/header and
    // pulls the cell well clear of the keyboard below.
    await Scrollable.ensureVisible(
      context,
      alignment: 0.3,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
    // Keyboard typically animates in over ~250ms — re-ensure once
    // it's up, since the viewport just shrunk and our cell may
    // have been pushed under it.
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    await Scrollable.ensureVisible(
      context,
      alignment: 0.3,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _titleFocus.dispose();
    _descFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isOutOfMonth = !widget.isCurrentMonth;
    final hasContent =
        widget.variants.any((v) => !v.isEmpty);
    final showAffordances = !isOutOfMonth &&
        widget.isFocused &&
        !widget.isEditing &&
        widget.canEdit;

    final dateColor = isOutOfMonth
        ? cs.onSurfaceVariant.withValues(alpha: 0.4)
        : (_isToday ? cs.primary : cs.onSurfaceVariant);

    final cellShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(
        color: _isToday
            ? cs.primary.withValues(alpha: 0.5)
            : (widget.isFocused
                ? cs.primary.withValues(alpha: 0.4)
                : cs.outlineVariant.withValues(alpha: 0.6)),
        width: (_isToday || widget.isFocused) ? 1 : 0.5,
      ),
    );

    // Cell tone matches the side rail's theme/supplies panel —
    // surfaceContainerLow with a subtle outline. The earlier
    // surface tone made cells visually disconnected from the side
    // rail; same tone reads as one continuous grid.
    //
    // ConstrainedBox(minHeight: 120) is the floor under sparse
    // weeks — empty rows still get the readable cell height. Tall
    // content (long descriptions, many variants) grows the cell
    // (and thus the row) above this floor; the IntrinsicHeight in
    // the parent Row handles that propagation.
    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 120),
      child: Material(
      color: isOutOfMonth
          ? cs.surfaceContainerLowest.withValues(alpha: 0.4)
          : cs.surfaceContainerLow,
      shape: cellShape,
      child: InkWell(
        onTap: isOutOfMonth ? null : widget.onTap,
        customBorder: cellShape,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 2, top: 2),
                    child: Text(
                      '${widget.date.day}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: dateColor,
                        fontWeight: _isToday
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // No Expanded around the inline editor or variant
                  // stack — the cell uses MainAxisSize.min so it
                  // grows to fit content, and the parent
                  // IntrinsicHeight propagates that up to the Row.
                  if (widget.isEditing)
                    _buildInlineEditor(theme)
                  else if (!isOutOfMonth && hasContent)
                    _buildVariantPager(theme),
                ],
              ),
              // ✨ + × affordances overlay — visible when the cell
              // is focused (hover on web, tap-to-focus on mobile)
              // AND has content. Pinned to bottom-right (✨) and
              // top-right (×) so they don't crowd the preview.
              if (showAffordances && hasContent) ...[
                Positioned(
                  top: 0,
                  right: 0,
                  child: _CellAffordanceButton(
                    icon: Icons.close,
                    tone: _AffordanceTone.muted,
                    onTap: widget.onDeleteActive,
                    tooltip: 'Delete this variant',
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: _CellAffordanceButton(
                    icon: Icons.auto_awesome_outlined,
                    tone: _AffordanceTone.primary,
                    onTap: widget.isGenerating ? null : widget.onAi,
                    tooltip: 'AI variant',
                    loading: widget.isGenerating,
                  ),
                ),
              ],
              // Variant dots — always visible when >1 variant exists
              // (navigation, not affordance). Centered at the bottom.
              if (!isOutOfMonth && widget.variants.length > 1)
                Positioned(
                  bottom: 2,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _VariantDots(
                      count: widget.variants.length,
                      active: widget.activeIndex,
                      onTap: widget.onSwitchVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );

    // MouseRegion provides the hover-to-focus path on web. On touch
    // devices it's a no-op (no hover events fire); the parent's tap
    // dispatcher handles focus instead.
    return MouseRegion(
      onEnter: isOutOfMonth ? null : (_) => widget.onFocusEnter(),
      onExit: isOutOfMonth ? null : (_) => widget.onFocusExit(),
      child: body,
    );
  }

  /// Two-TextField inline editor. Title field is single-line + bold
  /// (with `textInputAction: next` so ↵ moves focus to the
  /// description); description is multi-line + body-weight. Each
  /// field's `onChanged` writes IMMEDIATELY into the active variant
  /// — no commit-on-blur (mobile doesn't reliably blur on tap-out)
  /// and no buffer-split-on-commit (the title only got bold AFTER
  /// commit, which made the live edit feel flat).
  Widget _buildInlineEditor(ThemeData theme) {
    final cs = theme.colorScheme;
    final titleStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final descStyle = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final mutedColor = cs.onSurfaceVariant.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleCtrl,
            focusNode: _titleFocus,
            onChanged: widget.onWriteTitle,
            style: titleStyle,
            textInputAction: TextInputAction.next,
            // ↵ on title moves to the description field — natural
            // "type title, hit return, describe" flow.
            onSubmitted: (_) => _descFocus.requestFocus(),
            decoration: InputDecoration(
              isDense: true,
              isCollapsed: true,
              filled: false,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: 'Activity Name',
              hintStyle: titleStyle?.copyWith(color: mutedColor),
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: TextField(
              controller: _descCtrl,
              focusNode: _descFocus,
              onChanged: widget.onWriteDescription,
              style: descStyle,
              maxLines: null,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                isDense: true,
                isCollapsed: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Describe…',
                hintStyle: descStyle?.copyWith(color: mutedColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Variants stack via [IndexedStack] — the cell sizes to the
  /// tallest variant's content, so switching between them via the
  /// dots is layout-stable (no row-height jitter as the user
  /// flips). Trade-off: lost the PageView swipe-between-variants
  /// gesture; user said full text > swipe, since PageView demands
  /// bounded height which fights "all text visible." Revisit if
  /// swipe re-enters the priority list.
  Widget _buildVariantPager(ThemeData theme) {
    return IndexedStack(
      index: widget.activeIndex,
      children: [
        for (final v in widget.variants) _CellPreview(activity: v),
      ],
    );
  }
}

class _CellPreview extends StatelessWidget {
  const _CellPreview({required this.activity});

  final _MonthlyActivity activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // Bottom 14dp reserves space for the variant dots overlay so
      // the description's last line doesn't sit underneath them.
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (activity.title.isNotEmpty)
            Text(
              activity.title,
              // No maxLines / ellipsis — the user explicitly wanted
              // all text shown. The cell will grow to fit.
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          if (activity.description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              activity.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// -- Cell-internal affordance widgets -----------------------------

/// Two visual tones for the cell's overlay buttons. The user
/// flagged the week plan's red × as too loud; we use neutral
/// `surface + outlineVariant` for `muted` (×) and a tinted
/// `primaryContainer` for `primary` (✨). Same shape across both
/// so the icons read as one set.
enum _AffordanceTone { muted, primary }

class _CellAffordanceButton extends StatelessWidget {
  const _CellAffordanceButton({
    required this.icon,
    required this.tone,
    required this.onTap,
    required this.tooltip,
    this.loading = false,
  });

  final IconData icon;
  final _AffordanceTone tone;
  final VoidCallback? onTap;
  final String tooltip;

  /// While true, renders a CircularProgressIndicator in place of
  /// [icon]. Used by the AI variant flow to show inline progress
  /// without opening a modal.
  final bool loading;

  static const double _size = 22;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (bg, fg, border) = switch (tone) {
      _AffordanceTone.primary => (
          cs.primaryContainer,
          cs.onPrimaryContainer,
          cs.primary.withValues(alpha: 0.4),
        ),
      _AffordanceTone.muted => (
          cs.surface,
          cs.onSurfaceVariant,
          cs.outlineVariant,
        ),
    };
    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_size / 2),
          side: BorderSide(color: border, width: 0.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(_size / 2),
          onTap: loading ? null : onTap,
          child: SizedBox(
            width: _size,
            height: _size,
            child: loading
                ? Padding(
                    padding: const EdgeInsets.all(4),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: fg,
                    ),
                  )
                : Icon(icon, size: 14, color: fg),
          ),
        ),
      ),
    );
  }
}

/// Variant-carousel dots — one per variant, filled = active. Each
/// dot is a tap target so the user can switch directly without
/// swiping the PageView.
class _VariantDots extends StatelessWidget {
  const _VariantDots({
    required this.count,
    required this.active,
    required this.onTap,
  });

  final int count;
  final int active;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == active
                      ? cs.primary
                      : cs.onSurfaceVariant.withValues(alpha: 0.3),
                ),
              ),
            ),
          ),
      ],
    );
  }
}


// =====================================================================
// Formatted "what to do today" sheet — read-only; pencil → editor
// =====================================================================

/// Read-only, formatted view of an activity. Designed for the person
/// who didn't author the lesson plan and is looking at today's day
/// cold — has to know exactly what to run. The editor is reachable
/// via the pencil in the top-right.
class _ActivityFormattedSheet extends StatelessWidget {
  const _ActivityFormattedSheet({
    required this.date,
    required this.activity,
    required this.planContext,
    required this.onEdit,
    required this.onDelete,
  });

  final DateTime date;
  final _MonthlyActivity activity;
  final AiActivityContext? planContext;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mq = MediaQuery.of(context);
    final dateLabel = DateFormat('EEE MMM d').format(date);
    final steps = _splitSteps(activity.steps);
    final materials = activity.materials
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header — date label + pencil (edit) on the right.
              // Keeps the "ownership" affordance visible without
              // shoving an extra row of buttons at the bottom of the
              // sheet.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      dateLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit activity',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEdit,
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (activity.title.isNotEmpty)
                Text(
                  activity.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (activity.description.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  activity.description,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
                ),
              ],
              if (activity.objectives.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                const _SectionHeader(label: 'Objectives'),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  activity.objectives,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
              ],
              if (steps.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                const _SectionHeader(label: 'Steps'),
                const SizedBox(height: AppSpacing.sm),
                for (var i = 0; i < steps.length; i++)
                  Padding(
                    padding:
                        const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Numbered bullet rendered in primary so the
                        // step pop is always visible — the running
                        // adult can scan vertically.
                        SizedBox(
                          width: 28,
                          child: Text(
                            '${i + 1}.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            steps[i],
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              if (materials.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                const _SectionHeader(label: 'Materials'),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final m in materials)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: cs.outlineVariant,
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          m,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ],
              if (activity.link.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                const _SectionHeader(label: 'Reference'),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  activity.link,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xxl),
              // AI add-ons — embedded inline so the user can see
              // the activity above for reference while picking. The
              // section self-manages picker → loading → result
              // state internally.
              Divider(
                height: 1,
                color: cs.outlineVariant,
              ),
              const SizedBox(height: AppSpacing.lg),
              AiActivityAddonsSection(
                activity: activity.toAiActivity(),
                planContext: planContext,
              ),
              const SizedBox(height: AppSpacing.xxl),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.error,
                  side: BorderSide(
                    color: cs.error.withValues(alpha: 0.5),
                  ),
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete activity'),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Split a free-text steps blob into individual lines, stripping
  /// any leading numbering ("1. ", "1) ", "•"). The model + the
  /// editor both use newline-separated entries; this normalises both
  /// shapes for the formatted view.
  List<String> _splitSteps(String raw) {
    return raw
        .split('\n')
        .map((s) => s.trim())
        .map((s) => s.replaceFirst(
              RegExp(r'^(\d+[\.\)]\s*|[•\-\*]\s+)'),
              '',
            ))
        .where((s) => s.isNotEmpty)
        .toList();
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

// =====================================================================
// Editor sheet — adaptive (bottom on mobile, side panel on web)
// =====================================================================

class _MonthlyActivityEditor extends StatefulWidget {
  const _MonthlyActivityEditor({
    required this.date,
    required this.activity,
    required this.planContext,
    required this.onChanged,
    required this.onDelete,
  });

  final DateTime date;
  final _MonthlyActivity activity;
  final AiActivityContext? planContext;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  State<_MonthlyActivityEditor> createState() =>
      _MonthlyActivityEditorState();
}

class _MonthlyActivityEditorState extends State<_MonthlyActivityEditor> {
  late final TextEditingController _title =
      TextEditingController(text: widget.activity.title)
        ..addListener(_pushTitle);
  late final TextEditingController _description =
      TextEditingController(text: widget.activity.description)
        ..addListener(_pushDescription);
  late final TextEditingController _objectives =
      TextEditingController(text: widget.activity.objectives)
        ..addListener(_pushObjectives);
  late final TextEditingController _steps =
      TextEditingController(text: widget.activity.steps)
        ..addListener(_pushSteps);
  late final TextEditingController _materials =
      TextEditingController(text: widget.activity.materials)
        ..addListener(_pushMaterials);
  late final TextEditingController _link =
      TextEditingController(text: widget.activity.link)
        ..addListener(_pushLink);

  void _pushTitle() {
    widget.activity.title = _title.text;
    widget.onChanged();
  }

  void _pushDescription() {
    widget.activity.description = _description.text;
    widget.onChanged();
  }

  void _pushObjectives() {
    widget.activity.objectives = _objectives.text;
    widget.onChanged();
  }

  void _pushSteps() {
    widget.activity.steps = _steps.text;
    widget.onChanged();
  }

  void _pushMaterials() {
    widget.activity.materials = _materials.text;
    widget.onChanged();
  }

  void _pushLink() {
    widget.activity.link = _link.text;
    widget.onChanged();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _objectives.dispose();
    _steps.dispose();
    _materials.dispose();
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final theme = Theme.of(context);
    final dateLabel = DateFormat('EEE MMM d').format(widget.date);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdaptiveSheetHeader(title: dateLabel),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _title,
                autofocus: widget.activity.title.isEmpty,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Activity Name',
                  helperText: 'Required',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _description,
                maxLines: 4,
                minLines: 2,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'Describe',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant,
              ),
              _DetailsDisclosure(
                initiallyExpanded: widget.activity.hasAnyMetadata,
                children: [
                  TextField(
                    controller: _objectives,
                    maxLines: null,
                    minLines: 2,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      labelText: 'Objectives',
                      helperText: 'What children will learn or practice',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _steps,
                    maxLines: null,
                    minLines: 3,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      labelText: 'Steps',
                      helperText: 'Step-by-step how to run it',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _materials,
                    maxLines: null,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      labelText: 'Materials',
                      helperText: 'Comma-separated — these aggregate '
                          'into the side rail',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _link,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Reference Link',
                      hintText: 'https://…',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant,
              ),
              const SizedBox(height: AppSpacing.lg),
              // Same inline AI add-ons section as the formatted
              // preview — exposes them at edit-time too so authors
              // can iterate without leaving the editor.
              AiActivityAddonsSection(
                activity: widget.activity.toAiActivity(),
                planContext: widget.planContext,
              ),
              const SizedBox(height: AppSpacing.xl),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(
                    color: theme.colorScheme.error.withValues(alpha: 0.5),
                  ),
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete activity'),
                onPressed: widget.onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailsDisclosure extends StatefulWidget {
  const _DetailsDisclosure({
    required this.children,
    this.initiallyExpanded = false,
  });

  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  State<_DetailsDisclosure> createState() => _DetailsDisclosureState();
}

class _DetailsDisclosureState extends State<_DetailsDisclosure> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: [
                AnimatedRotation(
                  duration: const Duration(milliseconds: 180),
                  turns: _expanded ? 0.25 : 0,
                  child: Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'More details',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.children,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// =====================================================================
// Top-of-screen bars (monthly theme + active group's age range)
// =====================================================================

/// Monthly theme input — top-most bar above the group filter. Drives
/// AI generation context for every cell in the visible month. Uses
/// the standard input chrome here (not the WYSIWYG no-chrome
/// pattern) because this is a deliberate top-of-page form field, not
/// a doc-feel inline edit.
class _MonthlyThemeBar extends StatefulWidget {
  const _MonthlyThemeBar({
    required this.month,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final DateTime month;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_MonthlyThemeBar> createState() => _MonthlyThemeBarState();
}

class _MonthlyThemeBarState extends State<_MonthlyThemeBar> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.value);
  bool _suggesting = false;
  List<String> _suggestions = const [];
  String? _suggestError;

  @override
  void didUpdateWidget(covariant _MonthlyThemeBar old) {
    super.didUpdateWidget(old);
    if (widget.value != _ctrl.text) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _suggest() async {
    if (_suggesting) return;
    setState(() {
      _suggesting = true;
      _suggestError = null;
      _suggestions = const [];
    });
    try {
      final list = await _suggestMonthlyThemes(widget.month);
      if (!mounted) return;
      setState(() {
        _suggesting = false;
        _suggestions = list;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _suggesting = false;
        _suggestError =
            e.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), '');
      });
    }
  }

  void _pickSuggestion(String s) {
    _ctrl.text = s;
    widget.onChanged(s);
    setState(() => _suggestions = const []);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthLabel = DateFormat.MMMM().format(widget.month);
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Suggest button moved INTO the TextField as a suffixIcon —
          // a beside-the-field button on its own row was too much
          // chrome on mobile (eaten ~50dp). Visible only when the
          // field is empty (gives the user a quick "give me ideas"
          // affordance without sitting on top of typed input).
          TextField(
            controller: _ctrl,
            onChanged: widget.onChanged,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: Icon(
                Icons.workspace_premium_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              labelText: 'Monthly theme',
              hintText: "e.g. Nature, Mother's Day, Growing things",
              helperText: 'Used as context when AI generates activities',
              suffixIcon: widget.value.isEmpty
                  ? IconButton(
                      tooltip: 'Suggest themes for $monthLabel',
                      onPressed: _suggesting ? null : _suggest,
                      icon: _suggesting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.auto_awesome_outlined,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                    )
                  : null,
            ),
          ),
          if (_suggestError != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _suggestError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Suggested themes for $monthLabel',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final s in _suggestions)
                  ActionChip(
                    label: Text(s),
                    onPressed: () => _pickSuggestion(s),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Asks the model for ~4 short, season-appropriate monthly themes
/// for [month]. Returns an empty list on any failure. Uses the
/// existing OpenAI proxy via the AI client.
Future<List<String>> _suggestMonthlyThemes(DateTime month) async {
  final monthName = DateFormat.MMMM().format(month);
  final body = await OpenAiClient.chat({
    'model': 'gpt-4o-mini',
    'temperature': 0.7,
    'response_format': {'type': 'json_object'},
    'messages': [
      {
        'role': 'system',
        'content':
            'You suggest seasonal monthly themes for early-childhood '
            'classrooms. Return JSON: {"themes": ["...", "...", "...", '
            '"..."]} — exactly 4 short, classroom-friendly themes '
            'appropriate to the month (seasons, holidays, natural '
            'events). Each theme is a short noun or noun phrase like '
            '"Spring blooms" or "Friendship". No descriptions, just '
            'the labels.',
      },
      {
        'role': 'user',
        'content': 'Suggest 4 monthly themes for $monthName.',
      },
    ],
  });
  final choices = body['choices'] as List<dynamic>?;
  final message = choices?.isNotEmpty == true
      ? (choices!.first as Map<String, dynamic>)['message']
          as Map<String, dynamic>?
      : null;
  final content = message?['content'] as String?;
  if (content == null || content.trim().isEmpty) return const [];
  final parsed = jsonDecode(content) as Map<String, dynamic>;
  final themes = parsed['themes'] as List<dynamic>? ?? const [];
  return [
    for (final t in themes)
      if (t is String && t.trim().isNotEmpty) t.trim(),
  ];
}


// =====================================================================
// Week-details modal (sub-theme + supplies, given more breathing room)
// =====================================================================

/// Modal version of the side rail. Same fields, but rendered with
/// room to breathe — useful when shopping for the week's supplies or
/// authoring a sub-theme with more deliberation than the cramped
/// inline rail allows.
class _WeekDetailsSheet extends StatefulWidget {
  const _WeekDetailsSheet({
    required this.weekRangeLabel,
    required this.initialSubTheme,
    required this.onSubThemeChanged,
    required this.materials,
  });

  final String weekRangeLabel;
  final String initialSubTheme;
  final ValueChanged<String> onSubThemeChanged;
  final List<String> materials;

  @override
  State<_WeekDetailsSheet> createState() => _WeekDetailsSheetState();
}

class _WeekDetailsSheetState extends State<_WeekDetailsSheet> {
  late final TextEditingController _subTheme =
      TextEditingController(text: widget.initialSubTheme);

  @override
  void dispose() {
    _subTheme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdaptiveSheetHeader(title: 'Week of ${widget.weekRangeLabel}'),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _subTheme,
                onChanged: widget.onSubThemeChanged,
                autofocus: widget.initialSubTheme.isEmpty,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Sub-theme',
                  helperText: 'A thematic label for this week — '
                      'used as AI generation context',
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const _SectionHeader(label: 'Supplies'),
              const SizedBox(height: AppSpacing.sm),
              if (widget.materials.isEmpty)
                Text(
                  "No supplies yet — they'll appear here once activities "
                  'in this week list materials.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final m in widget.materials)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          m,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
