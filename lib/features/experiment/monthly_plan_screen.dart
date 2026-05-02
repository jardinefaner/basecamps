import 'dart:async';
import 'dart:convert';

import 'package:basecamp/database/database.dart' show Group, MonthlyActivity;
import 'package:basecamp/features/adults/adults_repository.dart'
    show AdultRole, currentAdultProvider;
import 'package:basecamp/features/ai/ai_activity_addons.dart';
import 'package:basecamp/features/ai/ai_activity_composer.dart';
import 'package:basecamp/features/ai/openai_client.dart';
import 'package:basecamp/features/children/children_repository.dart'
    show groupsProvider;
import 'package:basecamp/features/experiment/monthly_plan_repository.dart';
import 'package:basecamp/features/sync/sync_engine.dart' show syncEngineProvider;
import 'package:basecamp/features/sync/sync_specs.dart' show kAllSpecs;
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/adaptive_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
///
/// v59 — global view mode. The header has a single AI toggle next
/// to the month nav: original ↔ AI for the whole calendar. Flipping
/// to AI also opportunistically generates AI variants for any cell
/// that has typed content but no AI yet (with a progress bar +
/// cancel). Per-cell ✨ remains for individual regeneration.
enum _ViewMode {
  /// Show every cell's variant 0 (the user-typed original).
  original,

  /// Show every cell's last variant — the AI take, when one exists.
  /// Cells with only an original fall back to the original; no
  /// ghosting (we'd rather show real content than gray-out).
  ai,
}

/// v60.2 — which inline-edit field should receive focus on entry.
/// Defaults to title in most flows; tap-on-description sets
/// `description` so the user lands on the right field without
/// having to tab/tap again.
enum _CellFocusTarget { title, description }

/// v60.6 — payload for the drag-edge span gesture. The user
/// long-presses the right-edge handle on a head cell and drags to
/// a target day; the dropped cell receives this payload via its
/// `DragTarget<_SpanDragData>` and routes to the screen's
/// extend/trim handler.
class _SpanDragData {
  const _SpanDragData({
    required this.headId,
    required this.spanId,
    required this.headDate,
    required this.groupId,
  });

  /// Row id of the head variant — what `extendSpanThroughDate`
  /// expects. The head's spanId may be null (single-day variant
  /// about to become a span); the repo mints one on first extend.
  final String headId;

  /// Pre-existing span id, when the source cell already has
  /// continuations. Null when the source is single-day. Used by
  /// the drop handler to decide trim-vs-extend (only existing
  /// spans can be trimmed).
  final String? spanId;

  /// The head row's date. Drops at-or-before this date are
  /// rejected (you can't extend backwards through the head).
  final DateTime headDate;

  /// Group id — drops onto cells in a different group are
  /// rejected (cross-group span moves aren't a coherent operation).
  final String groupId;
}

class MonthlyPlanScreen extends ConsumerStatefulWidget {
  const MonthlyPlanScreen({super.key});

  @override
  ConsumerState<MonthlyPlanScreen> createState() =>
      _MonthlyPlanScreenState();
}

class _MonthlyPlanScreenState extends ConsumerState<MonthlyPlanScreen> {
  /// First-of-month for the visible month. Persisted via
  /// SharedPreferences so a reload returns to the month the user
  /// was looking at — restored asynchronously in initState (the
  /// initial render uses today's month, then the post-load
  /// setState swaps in the saved month if there was one). Saved
  /// every time the user navigates a month.
  late DateTime _viewMonth = _firstOfMonth(DateTime.now());

  /// Currently-selected group filter. Required (no "All"). Defaults
  /// to the first group as soon as the groups stream resolves with at
  /// least one entry. Kept null until that point. Persisted via
  /// SharedPreferences alongside `_viewMonth`.
  String? _activeGroupId;

  // ---- Persisted view state (v60.5) ---------------------------
  // Reload restores the user to whichever (month, group) they were
  // viewing. Without this, every reload kicks them back to the
  // current month + first group, losing context — annoying when
  // they're planning a future month.

  static const _kPrefViewYearMonth = 'monthly_plan/view_ym';
  static const _kPrefActiveGroupId = 'monthly_plan/active_group';

  Future<void> _restoreViewState() async {
    final prefs = await SharedPreferences.getInstance();
    final ym = prefs.getString(_kPrefViewYearMonth);
    final group = prefs.getString(_kPrefActiveGroupId);
    if (!mounted) return;
    setState(() {
      if (ym != null) {
        final parts = ym.split('-');
        if (parts.length == 2) {
          final year = int.tryParse(parts[0]);
          final month = int.tryParse(parts[1]);
          if (year != null && month != null && month >= 1 && month <= 12) {
            _viewMonth = DateTime(year, month);
          }
        }
      }
      // Group restored optimistically; the post-frame validation in
      // build() falls back to the lead's anchored group / first
      // group when the saved one no longer exists in the program.
      if (group != null && group.isNotEmpty) {
        _activeGroupId = group;
      }
    });
  }

  Future<void> _persistViewMonth(DateTime month) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kPrefViewYearMonth,
      '${month.year}-${month.month.toString().padLeft(2, '0')}',
    );
  }

  Future<void> _persistActiveGroup(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null || id.isEmpty) {
      await prefs.remove(_kPrefActiveGroupId);
    } else {
      await prefs.setString(_kPrefActiveGroupId, id);
    }
  }

  // v56 (Slice 2): variants moved to the cloud. Reads go through
  // monthlyActivitiesProvider (StreamProviderFamily keyed by
  // (groupId, date)) and writes go through
  // monthlyPlanRepository.addVariant / updateVariant / deleteVariant.
  // The realtime channel keeps two teachers' carousels in sync.
  //
  // v59: per-cell variant index removed. View is now global — the
  // header toggle flips the WHOLE calendar between original and AI.
  // _activeIdxAt computes its return value from _viewMode rather
  // than a per-cell stash. Inline editing edits whichever variant
  // is in view.

  /// Global view mode. Toggling re-renders every cell — AI shows
  /// the latest AI variant when one exists; original shows variant
  /// 0. Cells with no AI yet fall back to the original even in AI
  /// view (no ghosting — we just show what's there).
  _ViewMode _viewMode = _ViewMode.original;

  // ---- Batch AI state ------------------------------------------
  // When the user flips from original → AI, we opportunistically
  // fill in AI variants for every cell that has content but lacks
  // one. These fields drive the progress bar at the top of the
  // calendar; cancel sets _batchCancelRequested true and the loop
  // bails on its next iteration boundary.
  bool _batching = false;
  int _batchCount = 0;
  int _batchTotal = 0;
  bool _batchCancelRequested = false;

  /// Cell that's currently in inline-edit mode (the multi-line
  /// TextField rendering inside the cell). Only one cell edits at a
  /// time. Null when nothing's editing.
  String? _editingCellKey;

  /// Drift row id of the variant currently in inline-edit mode.
  /// Companion to `_editingCellKey`: `_editingCellKey` says "which
  /// cell" and `_editingVariantId` says "which row inside that cell".
  /// Null when nothing's editing OR when we're editing an empty cell
  /// that hasn't received a keystroke yet (lazy-create — see
  /// `_writeInlineEdit`).
  String? _editingVariantId;

  /// Pending lazy-create future. When the user enters edit mode on
  /// an empty cell, we DON'T insert a draft row eagerly — instead,
  /// the first keystroke kicks off `addVariant` and stashes the
  /// future here so concurrent keystrokes from the same edit session
  /// share one in-flight insert (no duplicate draft rows). Cleared
  /// on commit / exit / when the future resolves and `_editingVariantId`
  /// gets stamped.
  Future<String>? _pendingDraftInsert;

  /// Counter of in-flight `_writeInlineEdit` calls. Each call
  /// increments on entry, decrements in its `finally`. When this
  /// reaches zero, any waiter on `_drainInFlightWrites` is released.
  ///
  /// Why a counter (not just `_lastInlineWrite`): the latest-future
  /// approach failed when `_exitInlineEdit` ran *during* the
  /// `_pendingDraftInsert` await (i.e. before any keystroke chain
  /// had resumed past it). At that moment `_lastInlineWrite` was
  /// still null, so the exit didn't wait — but the queued chains
  /// were about to resume, write title="Reading" to the row, and
  /// re-mark dirty. The exit's own soft-delete then ran first,
  /// the writes landed on a tombstoned row, the row was filtered
  /// out of the variant stream, and the user saw their text vanish.
  /// Counting in-flight calls + a Completer fixes that: exit waits
  /// until every chain (including ones still suspended on the
  /// pending insert) has fully completed.
  int _writeInlineEditInFlight = 0;
  Completer<void>? _writeInlineEditDrain;

  /// Cell that's currently focused (touch-tap on mobile, hover on
  /// web). Drives visibility of ✨ + × + dots so they don't clutter
  /// every cell at once.
  String? _focusedCellKey;

  /// Cell whose ✨ is currently mid-generation. While this matches
  /// a cell's key, the cell renders a spinner where the ✨ used to
  /// be and the button is disabled. Inline (no modal) so the user
  /// stays in the calendar view through the round-trip.
  String? _generatingCellKey;

  @override
  void initState() {
    super.initState();
    // Restore the user's last-viewed (month, group) from
    // SharedPreferences so a reload doesn't kick them back to
    // today + first group. Async — the initial render uses the
    // defaults and the post-load setState swaps in saved values
    // if there were any.
    unawaited(_restoreViewState());
  }

  // Theme + sub-theme state moved to the cloud (v55, Slice 1).
  // Reads go through monthlyThemeProvider / weeklySubThemeProvider
  // (StreamProviderFamily — auto-updates when another teacher edits)
  // and writes go through monthlyPlanRepository.setTheme /
  // setSubTheme. The repo is composite-id keyed by program + period
  // so two clients setting at the same time converge on the same
  // row rather than racing into duplicates.

  /// "yyyy-MM" — calendar key used as the second half of the
  /// monthly_themes composite id, and as the family key on
  /// `monthlyThemeProvider`. Zero-padded so it aligns with the
  /// cloud column shape.
  String _yearMonth(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

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

  /// Inverse of [_activityKey] — extract the date portion from a
  /// composite cell key. Used by [_exitInlineEdit] which has the key
  /// in hand but needs to consult the variants stream for the cell.
  DateTime _dateFromKey(String key) {
    final parts = key.split('|');
    final ymd = parts.last.split('-');
    return DateTime(
      int.parse(ymd[0]),
      int.parse(ymd[1]),
      int.parse(ymd[2]),
    );
  }

  /// Inverse of [_activityKey] — extract the group portion. Group
  /// ids never contain `|` (they're Drift's text() ids, ULID-style),
  /// so split-on-pipe is unambiguous.
  String _groupFromKey(String key) => key.split('|').first;

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
  //
  // All accessors go through the cloud-backed
  // `monthlyActivitiesProvider`. Synchronous handlers (tap dispatch,
  // AI variant, delete) read via `ref.read(...).asData?.value` —
  // safe because the provider hydrates from local Drift first
  // (no network latency on cached data) and the worst-case
  // pre-hydration "" value is just an empty list, identical to "no
  // variants yet."

  List<_MonthlyActivity> _variantsAt(DateTime d, String groupId) {
    final raw = ref
            .read(
              monthlyActivitiesProvider(
                (groupId: groupId, date: _dayKey(d)),
              ),
            )
            .asData
            ?.value ??
        const <MonthlyActivity>[];
    return [for (final r in raw) _MonthlyActivity.fromDrift(r)];
  }

  int _activeIdxAt(DateTime d, String groupId) {
    final list = _variantsAt(d, groupId);
    if (list.isEmpty) return 0;
    // v59 — view mode-driven. Original view = first variant (the
    // user's typed text); AI view = last variant (the AI take, if
    // one exists; otherwise falls back to first via clamp).
    return switch (_viewMode) {
      _ViewMode.original => 0,
      _ViewMode.ai => list.length - 1,
    };
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
    unawaited(_persistViewMonth(_viewMonth));
  }

  void _resetToThisMonth() {
    setState(() => _viewMonth = _firstOfMonth(DateTime.now()));
    unawaited(_persistViewMonth(_viewMonth));
  }

  // -----------------------------------------------------------------
  // Cell actions
  // -----------------------------------------------------------------

  /// Called when a cell receives focus + the user wants to start
  /// authoring inline.
  ///
  /// **Lazy-create.** No Drift row is inserted on enter — that path
  /// used to leave orphan empty rows behind whenever the user
  /// tapped a cell, didn't type, then closed the app / switched
  /// programs / lost focus through any path that didn't go through
  /// `_exitInlineEdit`. The first keystroke is what mints the row
  /// (see [_writeInlineEdit]); an empty enter-and-bail leaves
  /// nothing behind because nothing was created.
  ///
  /// On a non-empty cell we still set `_editingVariantId` to the
  /// active variant's id — the user is editing existing content,
  /// not creating a new draft.
  Future<void> _enterInlineEdit(DateTime date) async {
    final groupId = _activeGroupId;
    if (groupId == null) return;
    final key = _activityKey(date, groupId);
    if (_editingCellKey != null && _editingCellKey != key) {
      await _exitInlineEdit();
    }
    final variants = _variantsAt(date, groupId);
    final existingId = variants.isEmpty
        ? null
        : variants[_activeIdxAt(date, groupId)].id;
    setState(() {
      _editingCellKey = key;
      _editingVariantId = existingId; // null on a fresh empty cell
      _pendingDraftInsert = null;
      _focusedCellKey = key;
    });
  }

  /// Per-keystroke push to the repo. **Lazy-create on first
  /// keystroke**: if `_editingVariantId` is null, the user has
  /// entered an empty cell and just typed — mint the row now and
  /// pin its id so subsequent keystrokes update in place.
  /// `_pendingDraftInsert` collapses concurrent first-keystroke
  /// races into one in-flight insert.
  ///
  /// **Persist even after exit.** Earlier versions bailed when
  /// `_editingCellKey` flipped to null mid-flight, orphaning every
  /// queued write that hadn't resumed past the await — that's how
  /// "Reading" persisted as "R". Now we always run the write: the
  /// user typed it, save it. The `_writeInlineEditInFlight` counter
  /// + `_writeInlineEditDrain` Completer let `_exitInlineEdit`
  /// block on ALL pending chains (not just the latest known
  /// future) before deciding whether to soft-delete an empty
  /// variant.
  Future<void> _writeInlineEdit({
    required DateTime date,
    String? title,
    String? description,
  }) async {
    _writeInlineEditInFlight += 1;
    try {
      var id = _editingVariantId;
      if (id == null) {
        final groupId = _activeGroupId;
        if (groupId == null) return;
        _pendingDraftInsert ??= ref
            .read(monthlyPlanRepositoryProvider)
            .addVariant(groupId: groupId, date: _dayKey(date));
        id = await _pendingDraftInsert;
        if (id == null) return;
        // setState only when we're still in edit mode; otherwise just
        // capture the id locally and let the write below run. The
        // setState is purely UI state for "which row's id is the
        // editing target" — irrelevant if we're no longer editing.
        if (mounted &&
            _editingCellKey != null &&
            _editingVariantId == null) {
          setState(() => _editingVariantId = id);
        }
      }
      await ref.read(monthlyPlanRepositoryProvider).updateVariant(
            id: id,
            title: title,
            description: description,
          );
    } finally {
      _writeInlineEditInFlight -= 1;
      if (_writeInlineEditInFlight == 0) {
        _writeInlineEditDrain?.complete();
        _writeInlineEditDrain = null;
      }
    }
  }

  /// Block until every in-flight `_writeInlineEdit` call has fully
  /// completed (Drift write + push enqueue done). Returns
  /// immediately when nothing is in flight. Used by
  /// `_exitInlineEdit` to make sure the row's final content has
  /// landed before deciding whether the variant ended up empty
  /// (and thus should be soft-deleted).
  Future<void> _drainInFlightInlineWrites() {
    if (_writeInlineEditInFlight == 0) {
      return Future<void>.value();
    }
    _writeInlineEditDrain ??= Completer<void>();
    return _writeInlineEditDrain!.future;
  }

  /// Exit edit mode. If a draft row was created during this session
  /// and is still empty, hard-delete it so the cell reverts to its
  /// empty visual. Lazy-create means most empty enter-and-bail
  /// sessions leave nothing to clean up.
  ///
  /// **Drains in-flight writes.** Per-keystroke `updateVariant`
  /// calls are queued in Drift; if we flip `_editingCellKey` to
  /// null before they all complete, the cell's `didUpdateWidget`
  /// runs while the stream is still emitting earlier states and
  /// can sync the controller from a stale value. Awaiting both the
  /// pending draft insert AND the latest queued write here lets
  /// the stream settle on the final state before we release the
  /// edit-mode gate.
  Future<void> _exitInlineEdit() async {
    final key = _editingCellKey;
    if (key == null) return;
    // Resolve a pending draft insert (rare race: the user is
    // exiting while a first keystroke's addVariant is still in
    // flight). Awaiting here ensures we get the id and can clean
    // it up if it ended up empty.
    final pending = _pendingDraftInsert;
    if (pending != null && _editingVariantId == null) {
      try {
        _editingVariantId = await pending;
      } on Object {
        _editingVariantId = null;
      }
      if (!mounted) return;
    }
    // Drain every in-flight `_writeInlineEdit` call before deciding
    // whether the row is empty. Without this, an exit firing during
    // the very-fast typing window can land BEFORE the queued
    // updateVariant calls run, soft-delete the row, and the queued
    // writes then land on a tombstoned row that the variant stream
    // filters out — the user's text vanishes. Counting in-flight
    // calls + Completer makes this deterministic regardless of
    // microtask ordering.
    try {
      await _drainInFlightInlineWrites();
    } on Object {
      // A failed write doesn't block exit — we just continue with
      // whatever made it through.
    }
    if (!mounted) return;
    final id = _editingVariantId;
    final isLast =
        _variantsAt(_dateFromKey(key), _groupFromKey(key)).length <= 1;
    final activeUi = _activeAt(_dateFromKey(key), _groupFromKey(key));
    final isEmpty =
        id != null && activeUi != null && activeUi.id == id && activeUi.isEmpty;
    if (isEmpty) {
      await ref.read(monthlyPlanRepositoryProvider).deleteVariant(id);
      if (!mounted) return;
    }
    setState(() {
      _editingCellKey = null;
      _editingVariantId = null;
      _pendingDraftInsert = null;
      if (isEmpty && isLast) {
        _focusedCellKey = null;
      }
    });
    // Force-flush any pending debounced pushes for this cell
    // before the user can navigate away (close tab, switch
    // program, lock device). Otherwise a quick exit-and-close can
    // leave the latest edits locally-dirty but never pushed —
    // which surfaces in incognito / a fresh device as missing
    // bits the user thought they saved.
    unawaited(
      ref.read(syncEngineProvider).flushPendingPushes(kAllSpecs),
    );
  }

  /// AI variant — INLINE generation, no modal sheet. v56 with
  /// replace-not-append (v58): if the cell already has an AI
  /// variant, refresh it in place; otherwise insert one. The cell
  /// holds at most two variants — the original (the user's typed
  /// content, position 0) and the AI take (position 1+). Multiple
  /// ✨ taps don't accumulate dead rows.
  Future<void> _onCellAi(DateTime date) async {
    final groupId = _activeGroupId;
    if (groupId == null) return;
    final variants = _variantsAt(date, groupId);
    if (variants.isEmpty) return;
    // Source for the AI prompt is the ORIGINAL — the user's first
    // input. Toggling to the AI view doesn't change what the prompt
    // refines; we always refine the original so re-running ✨
    // doesn't drift from what the teacher actually typed.
    final original = variants.first;
    if (original.isEmpty) return;
    final key = _activityKey(date, groupId);
    setState(() => _generatingCellKey = key);
    try {
      final result = await generateAiVariant(
        activity: original.toAiActivity(),
        planContext: _aiContextForDate(date),
      );
      if (!mounted) return;
      // Find an existing AI variant (anything past position 0).
      final existingAi = variants.length > 1 ? variants.last : null;
      final repo = ref.read(monthlyPlanRepositoryProvider);
      if (existingAi != null) {
        // Update in place — same row id, fresh content. Other
        // clients see a single UPDATE on the realtime channel
        // rather than an insert + delete pair.
        await repo.updateVariant(
          id: existingAi.id,
          title: result.title,
          description: result.description,
          objectives: result.objectives,
          steps: result.steps,
          materials: result.materials,
          link: result.link,
        );
      } else {
        await repo.addVariant(
          groupId: groupId,
          date: _dayKey(date),
          title: result.title,
          description: result.description,
          objectives: result.objectives,
          steps: result.steps,
          materials: result.materials,
          link: result.link,
        );
      }
      if (!mounted) return;
      setState(() {
        _generatingCellKey = null;
        // v59 — view-mode-driven active variant. Flip to AI view
        // so the user sees the freshly-generated take immediately
        // without any per-cell index bookkeeping.
        _viewMode = _ViewMode.ai;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _generatingCellKey = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Couldn't generate: ${e.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), '')}",
          ),
        ),
      );
    }
  }

  // _switchVariant deleted in v59 — variant choice is now global.
  // Cells render per the screen's _viewMode; the per-cell swap
  // affordance is gone and the dots/per-cell index map are gone
  // with it.

  /// v59 — global view mode toggle. Tap the header icon: flips
  /// the calendar between original and AI views. When flipping TO
  /// AI, opportunistically fill any cells that have typed content
  /// but no AI variant — that's the user's "cells with no AI,
  /// generate AI" ask. Going back to original is a pure visual
  /// flip; existing AI variants stick around for next time.
  Future<void> _toggleViewMode() async {
    if (_viewMode == _ViewMode.ai) {
      setState(() => _viewMode = _ViewMode.original);
      return;
    }
    setState(() => _viewMode = _ViewMode.ai);
    await _fillAiGaps();
  }

  /// Iterate every visible (in-month) cell for the active group.
  /// For each cell that has typed content (variant 0 non-empty)
  /// but no AI variant yet, run an AI generation and persist the
  /// result. Sequential — predictable progress reporting + avoids
  /// hammering the model rate limits. Cancellable via the progress
  /// bar's × button (sets `_batchCancelRequested` true).
  Future<void> _fillAiGaps() async {
    final groupId = _activeGroupId;
    if (groupId == null) return;
    // Snapshot cells needing work BEFORE the loop so the count
    // doesn't drift if the user types into a cell mid-batch.
    final pending = <DateTime>[];
    for (final week in _buildWeeks()) {
      for (final date in week) {
        if (date.month != _viewMonth.month) continue;
        final variants = _variantsAt(date, groupId);
        if (variants.isEmpty) continue;
        if (variants.first.isEmpty) continue; // no original to refine
        if (variants.length > 1) continue; // already has AI
        pending.add(date);
      }
    }
    if (pending.isEmpty) return;
    setState(() {
      _batching = true;
      _batchTotal = pending.length;
      _batchCount = 0;
      _batchCancelRequested = false;
    });
    final repo = ref.read(monthlyPlanRepositoryProvider);
    try {
      for (final date in pending) {
        if (_batchCancelRequested) break;
        try {
          final variants = _variantsAt(date, groupId);
          if (variants.isEmpty) continue;
          final original = variants.first;
          if (original.isEmpty) continue;
          if (variants.length > 1) continue; // user generated mid-batch
          final result = await generateAiVariant(
            activity: original.toAiActivity(),
            planContext: _aiContextForDate(date),
          );
          if (!mounted) return;
          await repo.addVariant(
            groupId: groupId,
            date: _dayKey(date),
            title: result.title,
            description: result.description,
            objectives: result.objectives,
            steps: result.steps,
            materials: result.materials,
            link: result.link,
          );
          if (!mounted) return;
        } on Object catch (e) {
          // Continue past individual failures — one rate-limit hit
          // shouldn't abort the whole batch. The cell stays at its
          // previous state; the user can retry that one via its
          // own ✨ button.
          debugPrint('Batch AI failed for ${_dayKey(date)}: $e');
        }
        if (!mounted) return;
        setState(() => _batchCount += 1);
      }
    } finally {
      if (mounted) {
        setState(() {
          _batching = false;
          _batchCount = 0;
          _batchTotal = 0;
          _batchCancelRequested = false;
        });
      }
    }
  }

  void _cancelBatch() {
    setState(() => _batchCancelRequested = true);
  }

  /// True iff at least one in-month cell in the active group has
  /// any AI variant. Drives the header icon's glyph + tooltip
  /// (when false, the icon offers "generate for all"; when true,
  /// it offers a view flip).
  bool get _anyCellHasAi {
    final groupId = _activeGroupId;
    if (groupId == null) return false;
    for (final week in _buildWeeks()) {
      for (final date in week) {
        if (date.month != _viewMonth.month) continue;
        if (_variantsAt(date, groupId).length > 1) return true;
      }
    }
    return false;
  }

  /// v60.6 — drag-edge span handler. The user long-presses the
  /// drag handle on a head cell's right edge and drops on a target
  /// day. Three cases:
  ///   * Drop on a future day → extend the span's tail through
  ///     that date (Mon–Fri only; weekends skipped).
  ///   * Drop on a past day inside the existing span → trim the
  ///     span back to that date (soft-deletes continuation rows
  ///     past it).
  ///   * Drop on the head day or earlier → no-op (can't drag the
  ///     tail past the head).
  Future<void> _onSpanDrop({
    required _SpanDragData source,
    required DateTime targetDate,
  }) async {
    if (source.groupId != _activeGroupId) return;
    final target = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
    );
    final repo = ref.read(monthlyPlanRepositoryProvider);
    if (target.isAfter(source.headDate)) {
      // Extend (or no-op if target is already inside the span and
      // not past the tail — the repo handles that).
      await repo.extendSpanThroughDate(
        headId: source.headId,
        throughDate: target,
      );
    } else if (source.spanId != null &&
        !target.isAtSameMomentAs(source.headDate)) {
      // Trim back. Only meaningful if there's already a span.
      await repo.trimSpanThroughDate(
        spanId: source.spanId!,
        throughDate: target,
      );
    }
  }

  /// Soft-delete the active variant (deletedAt stamp + null clear).
  /// Drift's stream filters tombstones, so the variant disappears
  /// from the local view; cloud realtime propagates to other
  /// clients.
  Future<void> _deleteActiveVariant(DateTime date) async {
    final groupId = _activeGroupId;
    if (groupId == null) return;
    final variants = _variantsAt(date, groupId);
    if (variants.isEmpty) return;
    final idx = _activeIdxAt(date, groupId);
    final id = variants[idx].id;
    await ref.read(monthlyPlanRepositoryProvider).deleteVariant(id);
    if (!mounted) return;
    setState(() {
      // After deletion the list will shrink by 1 (post-stream-emit).
      // If the cell becomes empty, drop focus. View-mode handles
      // the per-cell active index automatically.
      final newLen = variants.length - 1;
      if (newLen <= 0) {
        _focusedCellKey = null;
      }
    });
  }

  /// Set/clear the focused cell (mobile tap or web hover). When
  /// focusing a different cell while a prior one was inline-editing,
  /// finalise that prior edit first so empty variants don't pile up.
  void _setFocusedCell(String? key) {
    if (_focusedCellKey == key) return;
    if (_editingCellKey != null && _editingCellKey != key) {
      unawaited(_exitInlineEdit());
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
    final repo = ref.read(monthlyPlanRepositoryProvider);
    final initial =
        ref.read(weeklySubThemeProvider(mondayKey)).asData?.value ?? '';
    await showAdaptiveSheet<void>(
      context: context,
      builder: (_) => _WeekDetailsSheet(
        weekRangeLabel: _weekRangeLabel(week),
        initialSubTheme: initial,
        onSubThemeChanged: (v) {
          // Per-keystroke write — the repo's setSubTheme upserts
          // the (program, monday) row. The realtime channel
          // propagates to other clients; locally Drift's stream
          // re-emits and any cell watching this monday's
          // sub-theme rebuilds with the new value.
          unawaited(repo.setSubTheme(mondayDate: mondayKey, subTheme: v));
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
    // Read the latest cached values straight off the providers
    // (synchronous, doesn't subscribe — this is fine inside a
    // one-shot prompt builder; the UI itself watches the same
    // providers separately).
    final monthlyTheme = ref
        .read(monthlyThemeProvider(_yearMonth(date)))
        .asData
        ?.value;
    final subTheme = ref
        .read(weeklySubThemeProvider(_dayKey(monday)))
        .asData
        ?.value;
    // v57 — span continuity. If the active variant on this date is
    // part of a multi-day arc, give the AI a "Day N of M" hint plus
    // the head's title so the generated content threads with the
    // rest of the span instead of producing a standalone activity
    // for the same day.
    final spanInfo = _spanInfoForDate(date, groupId);
    return AiActivityContext(
      monthlyTheme: monthlyTheme ?? '',
      // Pulled straight off the Group row — single source of truth.
      ageRange: group?.audienceAgeLabel,
      subTheme: subTheme,
      groupName: group?.name,
      spanInfo: spanInfo,
    );
  }

  /// Compute "Day N of M, continuing: [head title]" for the active
  /// variant at (date, groupId), if it belongs to a span. Returns
  /// null for single-day variants. Reads synchronously from the
  /// activities provider snapshot (which is always populated for
  /// the active month — the screen subscribes per-cell).
  String? _spanInfoForDate(DateTime date, String? groupId) {
    if (groupId == null) return null;
    final active = _activeAt(date, groupId);
    final spanId = active?.spanId;
    if (active == null || spanId == null) return null;
    // The repo's watchSpan stream is the canonical source for
    // (head + length); we read it through ref.read for a one-shot
    // sync snapshot. The provider hydrates from local Drift so the
    // snapshot is up-to-date; if it hasn't yet emitted (rare), we
    // bail out of the span hint rather than guess.
    final span = ref.read(monthlySpanProvider(spanId)).asData?.value ??
        const <MonthlyActivity>[];
    if (span.isEmpty) return null;
    final total = span.length;
    final dayN = active.spanPosition + 1;
    final head = span.first;
    final headTitle = (head.title ?? '').trim();
    if (headTitle.isEmpty) {
      return 'Day $dayN of $total of a multi-day arc';
    }
    return 'Day $dayN of $total, continuing the arc: $headTitle';
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
        unawaited(_enterInlineEdit(date));
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
        onDelete: () async {
          Navigator.of(context).pop();
          // Delete the active variant only — other variants in the
          // cell stay. Matches the cell-level × affordance.
          await _deleteActiveVariant(date);
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
        onDelete: () async {
          await ref
              .read(monthlyPlanRepositoryProvider)
              .deleteVariant(activity.id);
          if (!mounted) return;
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
  ///
  /// **Skips the leading week when the month starts on a weekend.**
  /// If the 1st is Saturday or Sunday, the Mon–Fri week containing
  /// it has zero in-month working days — five out-of-month cells
  /// the user can't click into. We jump to the next Monday instead.
  /// Same logic isn't needed at the trailing edge: when the last
  /// day of the month is Sat/Sun, lastFriday rolls back to the
  /// previous Friday (which is in-month), so the last visible week
  /// still has clickable cells.
  List<List<DateTime>> _buildWeeks() {
    final first = DateTime(_viewMonth.year, _viewMonth.month);
    final last = DateTime(_viewMonth.year, _viewMonth.month + 1, 0);

    final DateTime firstMonday;
    if (first.weekday <= 5) {
      // Mon–Fri month start — back up to that week's Monday.
      firstMonday = first.subtract(Duration(days: first.weekday - 1));
    } else {
      // Sat (weekday=6) or Sun (weekday=7) month start — advance
      // to the next Monday so the leading week has at least one
      // in-month day.
      firstMonday = first.add(Duration(days: 8 - first.weekday));
    }
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
  /// group, deduped case-insensitively. Empty when no variants in
  /// the week have materials filled in. Strings come pre-split on
  /// commas so an activity's "paper, scissors, glue" contributes
  /// three entries.
  ///
  /// **Aggregates across all variants per cell.** v58 — toggling
  /// between original ↔ AI no longer changes the supply rail. The
  /// supplies for a cell come from any variant that has them
  /// populated, unioned + deduped. Common case: original is short
  /// text and AI fills materials → AI's materials show up
  /// regardless of which view is currently active. If both
  /// variants have materials, the union covers both.
  ///
  /// v57 span dedupe still applies: a multi-day arc's head
  /// contributes once even when its continuation rows live in the
  /// same week.
  List<String> _aggregateMaterialsForWeek(List<DateTime> week) {
    final groupId = _activeGroupId;
    if (groupId == null) return const [];
    final seen = <String, String>{}; // lowercased → original casing
    final visitedSpans = <String>{};
    for (final date in week) {
      final variants = _variantsAt(date, groupId);
      if (variants.isEmpty) continue;
      // Span check — use the active variant's spanId (or first
      // variant's if no active is set) as the span identity for
      // the cell. If we've already aggregated this span on an
      // earlier day in the week, skip the whole cell.
      final spanId = variants.first.spanId;
      if (spanId != null) {
        if (visitedSpans.contains(spanId)) continue;
        visitedSpans.add(spanId);
      }
      // Union materials across every variant in the cell — toggle
      // view doesn't gate the supply rail.
      for (final v in variants) {
        for (final raw in v.materials.split(',')) {
          final trimmed = raw.trim();
          if (trimmed.isEmpty) continue;
          seen.putIfAbsent(trimmed.toLowerCase(), () => trimmed);
        }
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
          // v59 — global AI toggle. Single icon that does double
          // duty: flips view mode for every cell, AND on the
          // original→AI flip fills any cells that have content
          // but no AI yet ("cells with no AI, generate AI"). The
          // glyph reflects what tapping does next, not what's
          // currently shown:
          //   * In original view → ✨ (offers AI; tap fills gaps
          //     and flips to AI view).
          //   * In AI view → ✏︎ pencil-edit (offers original; tap
          //     just flips back).
          //   * While batching → spinner instead of icon, button
          //     disabled (the cancel × lives on the progress bar).
          if (canEdit)
            IconButton(
              tooltip: switch (_viewMode) {
                _ViewMode.original =>
                  _anyCellHasAi ? 'Show AI versions' : 'Generate AI for all',
                _ViewMode.ai => 'Show originals',
              },
              icon: _batching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _viewMode == _ViewMode.ai
                          ? Icons.edit_note_outlined
                          : Icons.auto_awesome_outlined,
                    ),
              onPressed: _batching
                  ? null
                  : () => unawaited(_toggleViewMode()),
            ),
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
          // Batch-AI progress strip — visible only while filling
          // gaps. Shows "Generating N of M" + a determinate bar +
          // an × cancel. When done (or cancelled) it collapses
          // back to nothing.
          if (_batching)
            Material(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_outlined,
                      size: 16,
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimaryContainer,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _batchCancelRequested
                                ? 'Cancelling…'
                                : 'Generating AI for $_batchCount of '
                                    '$_batchTotal cells…',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: _batchTotal == 0
                                  ? 0
                                  : _batchCount / _batchTotal,
                              minHeight: 3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cancel',
                      icon: const Icon(Icons.close, size: 16),
                      onPressed:
                          _batchCancelRequested ? null : _cancelBatch,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
          // Monthly theme — top-most input. Per-month, used as AI
          // generation context. The bar keys itself by month so
          // flipping months remounts cleanly with the right value
          // and any in-flight suggestion chips reset. Reads + writes
          // go through monthlyPlanRepository (cloud-backed v55) so
          // every member of the program sees the same theme
          // without anyone "owning" it.
          Consumer(
            builder: (context, ref, _) {
              final yearMonth = _yearMonth(_viewMonth);
              final value =
                  ref.watch(monthlyThemeProvider(yearMonth)).asData?.value ??
                      '';
              return _MonthlyThemeBar(
                key: ValueKey(yearMonth),
                month: _viewMonth,
                value: value,
                onChanged: (v) {
                  unawaited(
                    ref
                        .read(monthlyPlanRepositoryProvider)
                        .setTheme(yearMonth: yearMonth, theme: v),
                  );
                },
                onCommit: () => unawaited(
                  ref
                      .read(syncEngineProvider)
                      .flushPendingPushes(kAllSpecs),
                ),
              );
            },
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
                  unawaited(_persistActiveGroup(preferred));
                });
              }
              return _GroupFilterBar(
                groups: groups,
                activeId: _activeGroupId,
                onSelect: (id) {
                  setState(() => _activeGroupId = id);
                  unawaited(_persistActiveGroup(id));
                },
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
                                    child: Consumer(
                                      builder: (context, ref, _) {
                                        final mondayKey = _dayKey(week.first);
                                        final subTheme = ref
                                                .watch(
                                                  weeklySubThemeProvider(
                                                      mondayKey),
                                                )
                                                .asData
                                                ?.value ??
                                            '';
                                        return _WeekSidePanel(
                                          weekMondayKey: mondayKey,
                                          subTheme: subTheme,
                                          onSubThemeChanged: (v) {
                                            unawaited(
                                              ref
                                                  .read(
                                                      monthlyPlanRepositoryProvider)
                                                  .setSubTheme(
                                                    mondayDate: mondayKey,
                                                    subTheme: v,
                                                  ),
                                            );
                                          },
                                          onSubThemeCommit: () => unawaited(
                                            ref
                                                .read(syncEngineProvider)
                                                .flushPendingPushes(kAllSpecs),
                                          ),
                                          materials:
                                              _aggregateMaterialsForWeek(week),
                                          onTap: () => _openWeekDetails(week),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                for (final date in week)
                                  // Day cell — stretches via Expanded
                                  // above the 160dp minimum (the
                                  // outer SizedBox's width guarantees
                                  // the floor). Each cell wraps in a
                                  // Consumer so it watches its own
                                  // (groupId, date) variants stream
                                  // — another teacher's edit lands
                                  // here directly without rebuilding
                                  // the whole calendar.
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(2),
                                      child: Consumer(
                                        builder: (context, ref, _) {
                                          final cellKey = (
                                            groupId: _activeGroupId!,
                                            date: _dayKey(date),
                                          );
                                          final raw = ref
                                                  .watch(
                                                    monthlyActivitiesProvider(
                                                        cellKey),
                                                  )
                                                  .asData
                                                  ?.value ??
                                              const <MonthlyActivity>[];
                                          final variants = [
                                            for (final r in raw)
                                              _MonthlyActivity.fromDrift(r),
                                          ];
                                          // v59 — active index from
                                          // global view mode. AI →
                                          // last variant; original
                                          // → variant 0. No per-cell
                                          // index lookup any more.
                                          final activeIdx =
                                              _activeIdxAt(date, _activeGroupId!);
                                          return _DayCell(
                                            key: ValueKey(
                                              '${_activeGroupId!}|'
                                              '${_dayKey(date)}',
                                            ),
                                            date: date,
                                            groupId: _activeGroupId!,
                                            isCurrentMonth: date.month ==
                                                _viewMonth.month,
                                            variants: variants,
                                            activeIndex: activeIdx,
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
                                            unawaited(_writeInlineEdit(
                                          date: date,
                                          title: v,
                                        )),
                                        onWriteDescription: (v) =>
                                            unawaited(_writeInlineEdit(
                                          date: date,
                                          description: v,
                                        )),
                                        onAi: () =>
                                            unawaited(_onCellAi(date)),
                                        onDeleteActive: () =>
                                            _deleteActiveVariant(date),
                                        onEditActive: () =>
                                            unawaited(_enterInlineEdit(date)),
                                        onCommitEdit: () =>
                                            unawaited(_exitInlineEdit()),
                                        onSpanDrop: (source, targetDate) =>
                                            unawaited(_onSpanDrop(
                                          source: source,
                                          targetDate: targetDate,
                                        )),
                                      );
                                        },
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

/// UI working type for an activity variant. v56 (Slice 2): backed by
/// a Drift `MonthlyActivity` row — the `id` field is the row's
/// primary key, and edits route back to the repository's
/// `updateVariant` so the cloud sync engine pushes the changes.
///
/// Was previously a mutable in-memory class; now it's an immutable
/// view onto a Drift row. The `Empty` factory keeps the "no draft yet"
/// case simple where we need a placeholder without a cloud row (rare
/// — the inline-edit path inserts a draft row immediately).
class _MonthlyActivity {
  const _MonthlyActivity({
    required this.id,
    this.title = '',
    this.description = '',
    this.objectives = '',
    this.steps = '',
    this.materials = '',
    this.link = '',
    this.spanId,
    this.spanPosition = 0,
  });

  /// Convert a Drift row to the UI working type, normalizing nulls
  /// to empty strings so `.isEmpty` semantics work without
  /// scattering null-checks everywhere.
  factory _MonthlyActivity.fromDrift(MonthlyActivity row) {
    return _MonthlyActivity(
      id: row.id,
      title: row.title ?? '',
      description: row.description ?? '',
      objectives: row.objectives ?? '',
      steps: row.steps ?? '',
      materials: row.materials ?? '',
      link: row.link ?? '',
      spanId: row.spanId,
      spanPosition: row.spanPosition,
    );
  }

  /// Row id from `monthly_activities`. Used by every edit / delete
  /// callback to address the right cloud row.
  final String id;
  final String title;
  final String description;
  final String objectives;
  final String steps;
  final String materials;
  final String link;

  /// v57 — span identity. Null = single-day activity. Non-null
  /// means this row belongs to a multi-day arc; siblings share the
  /// same spanId and order by [spanPosition].
  final String? spanId;

  /// v57 — position within the span. 0 = head (carries the full
  /// content); 1+ = continuation days.
  final int spanPosition;

  bool get isSpanHead => spanId != null && spanPosition == 0;
  bool get isSpanContinuation => spanId != null && spanPosition > 0;

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
    this.onSubThemeCommit,
  });

  final String weekMondayKey;
  final String subTheme;
  final ValueChanged<String> onSubThemeChanged;
  final List<String> materials;

  /// Tap on the panel — opens the week-details sheet. Not wired to
  /// the inline TextField (so typing into the sub-theme inline still
  /// works without bouncing into a modal).
  final VoidCallback onTap;

  /// Fires when the sub-theme TextField loses focus — the natural
  /// "I'm done typing" signal. The parent wires this to flush the
  /// debounced sync push so a tab close / app background right
  /// after typing doesn't lose the latest state.
  final VoidCallback? onSubThemeCommit;

  @override
  State<_WeekSidePanel> createState() => _WeekSidePanelState();
}

class _WeekSidePanelState extends State<_WeekSidePanel> {
  late final TextEditingController _subThemeCtrl =
      TextEditingController(text: widget.subTheme);
  // Focus tracking — see didUpdateWidget. Without this, fast typing
  // on the sub-theme field gets stomped by stream re-emissions.
  final FocusNode _subThemeFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _subThemeFocus.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (!_subThemeFocus.hasFocus) {
      widget.onSubThemeCommit?.call();
    }
  }

  @override
  void didUpdateWidget(covariant _WeekSidePanel old) {
    super.didUpdateWidget(old);
    // Bug fix: only sync the controller when the field is NOT
    // focused. Per-keystroke writes feed back through the Drift
    // stream → Riverpod rebuild → didUpdateWidget here. If we
    // overwrite the controller while the user is mid-typing, an
    // earlier (stale) emission can stomp later characters — that's
    // the "I typed Reading and got R back" bug. When the user has
    // focus we trust the controller as the authoritative source;
    // when they don't, an external write (different week reusing
    // this state slot, another teacher's edit landing via realtime)
    // is the legit source of truth.
    if (!_subThemeFocus.hasFocus &&
        widget.subTheme != _subThemeCtrl.text) {
      _subThemeCtrl.text = widget.subTheme;
    }
  }

  @override
  void dispose() {
    _subThemeFocus
      ..removeListener(_handleFocusChange)
      ..dispose();
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
            // Sub-theme — distinct labeled input (v60). Was styled
            // like a card title (bold + large) which read as a
            // heading rather than an editable field; now matches the
            // "Supplies" label idiom below: tiny uppercase label +
            // body-weight text input. Visually obvious that you can
            // type into it and that it's not the title of the
            // section.
            Text(
              'Sub-theme',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 2),
            TextField(
              controller: _subThemeCtrl,
              focusNode: _subThemeFocus,
              onChanged: widget.onSubThemeChanged,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'e.g. Trees, Colors, Helpers',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
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
            // v60.1 — supplies dropped from the side rail. The
            // rail used to aggregate the week's supplies as a
            // shopping list, but now each cell renders its own
            // supplies inline (under the variant title/desc),
            // which is closer to where the user thinks about
            // them. Two places to keep in sync was clutter; cells
            // win.
          ],
        ),
        ),
      ),
    );
  }
}

// _SuppliesTwoColumns removed (v60.1) — supplies render inline in
// each cell now. The week side rail's role shrinks to just the
// sub-theme; the per-cell footer is closer to where the user
// thinks about supplies.

// =====================================================================
// Day cell
// =====================================================================

class _DayCell extends StatefulWidget {
  const _DayCell({
    required this.date,
    required this.groupId,
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
    required this.onAi,
    required this.onDeleteActive,
    required this.onEditActive,
    required this.onCommitEdit,
    required this.onSpanDrop,
    super.key,
  });

  final DateTime date;

  /// Group this cell belongs to. v60.6 — needed for the span drag
  /// data so cross-group drops can be rejected (a span lives in one
  /// group; dragging from group A onto group B's cell is meaningless).
  final String groupId;

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
  final VoidCallback onAi;
  final VoidCallback onDeleteActive;
  // Re-enter inline edit on the active variant — paired with the ✏︎
  // affordance next to ×. The cell already has content; we just want
  // the TextField back so the user can tweak the title or description
  // without opening the full activity sheet.
  final VoidCallback onEditActive;
  // Description-Enter commits the edit. Title-Enter still moves focus
  // to the description (handled inside the cell). When the user hits
  // Enter on the description field, the cell closes the editor and
  // shows the formatted preview.
  final VoidCallback onCommitEdit;

  /// v60.6 — drag-edge span gesture handler. Fires when the user
  /// long-presses a head cell's right-edge handle and drops on a
  /// target cell. The screen routes to extend (drop after head) or
  /// trim (drop earlier inside the existing span).
  final void Function(_SpanDragData source, DateTime targetDate) onSpanDrop;

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

  /// v60.2 — when the user taps directly on the rendered title or
  /// description text, we enter inline edit mode and pre-focus the
  /// matching field (rather than always landing on title). This
  /// field captures which one was tapped between the tap firing
  /// and the parent rebuild that flips `widget.isEditing` true,
  /// when the postFrame focus request runs. Cleared after focus
  /// is granted.
  _CellFocusTarget? _initialFocus;

  /// Tap-on-title or tap-on-description handler. Stamps the focus
  /// target locally so the postFrame focus request in
  /// didUpdateWidget picks the right node, then routes to the
  /// screen's onEditActive (which kicks `_enterInlineEdit`).
  void _enterEditFocused(_CellFocusTarget target) {
    _initialFocus = target;
    widget.onEditActive();
  }

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
    // Commit-on-blur: when both fields lose focus while we're in
    // edit mode, the user has tapped outside the cell. Fire
    // onCommitEdit so the screen runs _exitInlineEdit, which drops
    // an empty variant + clears _focusedCellKey — exactly the
    // "revert to empty visual" behavior the user wanted when they
    // bail without typing.
    //
    // We listen on BOTH nodes (and defer one frame) because the
    // ↵-on-title path moves focus from title to description; in
    // that brief moment both nodes can register as unfocused before
    // the description grabs focus. The post-frame check sees the
    // settled state and ignores the transient gap.
    _titleFocus.addListener(_handleFocusChange);
    _descFocus.addListener(_handleFocusChange);
    if (widget.isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _titleFocus.requestFocus();
      });
    }
  }

  void _handleFocusChange() {
    if (!widget.isEditing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.isEditing) return;
      if (!_titleFocus.hasFocus && !_descFocus.hasFocus) {
        widget.onCommitEdit();
      }
    });
  }

  _MonthlyActivity? get _activeVariant {
    if (widget.variants.isEmpty) return null;
    return widget.variants[
        widget.activeIndex.clamp(0, widget.variants.length - 1)];
  }

  // _viewingAi getter dropped in v59 — view mode is global now,
  // not per-cell. The swap-icon affordance lives in the calendar
  // header and flips every cell at once.

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
        // Honor the tap-on-text initial focus stamp (v60.2). Falls
        // back to title when the entry path didn't specify (empty
        // cell tap, edit-pencil affordance, etc.).
        final target = _initialFocus ?? _CellFocusTarget.title;
        _initialFocus = null;
        switch (target) {
          case _CellFocusTarget.title:
            _titleFocus.requestFocus();
          case _CellFocusTarget.description:
            _descFocus.requestFocus();
        }
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
    _titleFocus.removeListener(_handleFocusChange);
    _descFocus.removeListener(_handleFocusChange);
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
    // "hasContent" — a cell shows the variant pager / preview when
    // any variant carries text. Continuation rows count as content
    // too: even with no per-day text, the "↪ continued" pill needs
    // the same focus + affordance treatment so the user can delete
    // (× shrinks the span) or add per-day content (pencil).
    final hasContent = widget.variants.any(
      (v) => !v.isEmpty || v.isSpanContinuation,
    );
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
                  else if (!isOutOfMonth && _isContinuationOnly)
                    _buildContinuationPill(theme)
                  else if (!isOutOfMonth && hasContent)
                    _buildVariantPager(theme),
                  // v60 — per-cell supplies. Sits BELOW the variant
                  // pager with a divider, unioned across all variants
                  // in the cell so toggling original/AI doesn't change
                  // it. Hidden when the cell has no materials, so
                  // empty-of-supplies cells aren't padded with dead
                  // chrome.
                  if (!isOutOfMonth && !widget.isEditing)
                    _buildCellSupplies(theme),
                ],
              ),
              // ✏︎ + × at top-right; ✨ + span ↔ at bottom-right.
              // v59 — the per-cell swap icon is gone. Variant choice
              // is global now: a single toggle in the calendar header
              // flips every cell between original and AI at once.
              if (showAffordances && hasContent && !widget.isEditing) ...[
                Positioned(
                  top: 0,
                  right: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CellAffordanceButton(
                        icon: Icons.edit_outlined,
                        tone: _AffordanceTone.muted,
                        onTap: widget.onEditActive,
                        tooltip: 'Edit this variant',
                      ),
                      const SizedBox(width: 4),
                      _CellAffordanceButton(
                        icon: Icons.close,
                        tone: _AffordanceTone.muted,
                        onTap: widget.onDeleteActive,
                        tooltip: 'Delete this variant',
                      ),
                    ],
                  ),
                ),
                // Bottom-right: AI ✨. The old span "↔" tap-button
                // is gone (v60.6) — span extension is now a drag of
                // the cell's right-edge handle (rendered separately
                // below) onto a target day.
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
            ],
          ),
        ),
      ),
      ),
    );

    // v60.6 — wrap the cell in a DragTarget so it can receive a
    // span-drag drop from any other cell's right-edge handle, AND
    // overlay a LongPressDraggable handle on the right edge so the
    // user can grab THIS cell's tail and drag it elsewhere. The
    // handle is hidden on continuation rows (only the head extends);
    // on read-only / out-of-month / editing cells; and on cells
    // with no content (nothing to span).
    final activeVariant = _activeVariant;
    // Hover/focus-gated: the drag handle only renders when the
    // cell is currently focused (hover on web, tap-to-focus on
    // mobile). Without this gate, every cell with content
    // permanently shows a vertical bar on its right edge — visual
    // clutter the user complained about ("lines everywhere").
    final canBeSpanSource = !isOutOfMonth &&
        widget.canEdit &&
        widget.isFocused &&
        !widget.isEditing &&
        hasContent &&
        activeVariant != null &&
        !activeVariant.isSpanContinuation;
    final dragSource = canBeSpanSource
        ? _SpanDragData(
            headId: activeVariant.id,
            spanId: activeVariant.spanId,
            headDate: widget.date,
            groupId: _groupIdForCell,
          )
        : null;

    final wrappedBody = DragTarget<_SpanDragData>(
      onWillAcceptWithDetails: (details) =>
          // Reject drops onto self + cross-group drops.
          details.data.headDate != widget.date &&
          details.data.groupId == _groupIdForCell,
      onAcceptWithDetails: (details) =>
          widget.onSpanDrop(details.data, widget.date),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        // StackFit.passthrough so the parent Row's IntrinsicHeight
        // + crossAxisAlignment.stretch propagates through this
        // Stack to the body. Without it, loose fit lets the body
        // stay at its natural size and cells of different content
        // heights end up unequal even though the row reserves
        // tallest-cell height.
        return Stack(
          fit: StackFit.passthrough,
          children: [
            body,
            // Drop-target highlight when a drag is hovering over us.
            if (hovering)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            // Right-edge drag handle. Hover-only (gated above) so a
            // resting cell stays visually clean — no permanent
            // line on the right edge of every focused-or-not cell.
            if (dragSource != null)
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                child: _SpanDragHandle(data: dragSource),
              ),
          ],
        );
      },
    );

    // MouseRegion provides the hover-to-focus path on web. On touch
    // devices it's a no-op (no hover events fire); the parent's tap
    // dispatcher handles focus instead.
    return MouseRegion(
      onEnter: isOutOfMonth ? null : (_) => widget.onFocusEnter(),
      onExit: isOutOfMonth ? null : (_) => widget.onFocusExit(),
      child: wrappedBody,
    );
  }

  String get _groupIdForCell => widget.groupId;

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
          // v60.2 — title wraps to multiple lines instead of
          // single-line clipping. maxLines: null lets it grow with
          // the typed text; the Focus.onKeyEvent below intercepts
          // Enter so it still moves focus to description (web
          // hardware keyboard) instead of inserting a newline.
          // Mobile relies on onSubmitted via textInputAction.next.
          // Shift+Enter falls through if a power user really wants
          // a literal newline in a title (rare).
          Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.enter &&
                  !HardwareKeyboard.instance.isShiftPressed) {
                _descFocus.requestFocus();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: _titleCtrl,
              focusNode: _titleFocus,
              onChanged: widget.onWriteTitle,
              style: titleStyle,
              maxLines: null,
              keyboardType: TextInputType.text,
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
          ),
          const SizedBox(height: 2),
          Expanded(
            // Focus.onKeyEvent intercepts Enter for the web hardware-
            // keyboard path: in a maxLines=null TextField, Enter
            // would otherwise insert a newline regardless of
            // textInputAction. Mobile uses onSubmitted (the keyboard
            // shows a "done" button because action: done). Both
            // paths route to the same commit callback. Shift+Enter
            // falls through to default behavior, so power-users on
            // web can still insert a newline if they need one.
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.enter &&
                    !HardwareKeyboard.instance.isShiftPressed) {
                  widget.onCommitEdit();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _descCtrl,
                focusNode: _descFocus,
                onChanged: widget.onWriteDescription,
                onSubmitted: (_) => widget.onCommitEdit(),
                style: descStyle,
                maxLines: null,
                textInputAction: TextInputAction.done,
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
        for (final v in widget.variants)
          _CellPreview(
            activity: v,
            // v60.2 — tap on the rendered title or description text
            // enters inline edit with the right field focused.
            // Read-only viewers (canEdit=false) and continuation
            // rows (no inline edit on those) leave both null so
            // taps fall through to the outer cell InkWell.
            onTapTitle: widget.canEdit && !v.isSpanContinuation
                ? () => _enterEditFocused(_CellFocusTarget.title)
                : null,
            onTapDescription: widget.canEdit && !v.isSpanContinuation
                ? () => _enterEditFocused(_CellFocusTarget.description)
                : null,
          ),
      ],
    );
  }

  /// True when the only variant in this cell is a continuation row
  /// with no per-day content of its own — render a "continued" pill
  /// instead of an empty variant pager. As soon as the user types
  /// per-day content into a continuation cell, `hasContent` flips
  /// true and the regular pager takes over.
  bool get _isContinuationOnly {
    if (widget.variants.isEmpty) return false;
    return widget.variants.every(
      (v) => v.isSpanContinuation && v.isEmpty,
    );
  }

  /// v60 — per-cell supplies footer. Unions materials across every
  /// variant in the cell (deduped, case-insensitive) so toggling
  /// between original and AI doesn't change what's shown. Renders
  /// nothing when the cell has no materials at all — empty rooms
  /// stay empty, no leftover divider chrome.
  ///
  /// Visual is intentionally compact: a thin divider, a small
  /// "Supplies" label (matching the side rail's idiom), then a
  /// comma-joined wrap of items in muted body-small text. Long
  /// lists wrap naturally and the cell grows to fit (same
  /// IntrinsicHeight rule as title/description).
  Widget _buildCellSupplies(ThemeData theme) {
    final items = _aggregatedMaterials();
    if (items.isEmpty) return const SizedBox.shrink();
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Supplies',
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            items.join(', '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Cell-level material aggregation: union across every variant,
  /// split on commas, dedup case-insensitively, sorted alphabetically
  /// for stable rendering. Same rules the side rail uses, scoped to
  /// this single cell.
  List<String> _aggregatedMaterials() {
    final seen = <String, String>{};
    for (final v in widget.variants) {
      for (final raw in v.materials.split(',')) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) continue;
        seen.putIfAbsent(trimmed.toLowerCase(), () => trimmed);
      }
    }
    final out = seen.values.toList()..sort();
    return out;
  }

  /// Continuation day rendering. v60.4 carries the head's title
  /// here so a continuation cell isn't an anonymous "↪ continued"
  /// blob — the user reads "Tree Stories · continued" and knows
  /// at a glance which arc this day is part of. Tap on the cell
  /// (background or the title text) enters inline edit on this
  /// continuation row so the user can layer per-day notes on top
  /// (like sub-themes — always tap-to-edit-inline).
  Widget _buildContinuationPill(ThemeData theme) {
    final cs = theme.colorScheme;
    final spanId = widget.variants.first.spanId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 14),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.canEdit
            ? () => _enterEditFocused(_CellFocusTarget.title)
            : null,
        child: Consumer(
          builder: (context, ref, _) {
            final spanRows = spanId == null
                ? const <MonthlyActivity>[]
                : (ref.watch(monthlySpanProvider(spanId)).asData?.value ??
                    const <MonthlyActivity>[]);
            final head = spanRows.isEmpty ? null : spanRows.first;
            final headTitle = (head?.title ?? '').trim();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (headTitle.isNotEmpty)
                  Text(
                    headTitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                if (headTitle.isNotEmpty) const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.subdirectory_arrow_right,
                          size: 14,
                          color: cs.onSecondaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'continued',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSecondaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CellPreview extends StatelessWidget {
  const _CellPreview({
    required this.activity,
    this.onTapTitle,
    this.onTapDescription,
  });

  final _MonthlyActivity activity;

  /// Tap handlers for the title + description text. v60.2 — tapping
  /// the title or description text directly enters inline edit
  /// mode with the corresponding field focused, so the user
  /// doesn't have to hit the pencil affordance separately. When
  /// null (read-only viewer, span continuation), taps fall through
  /// to the parent cell's outer InkWell.
  final VoidCallback? onTapTitle;
  final VoidCallback? onTapDescription;

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
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTapTitle,
              child: Text(
                activity.title,
                // No maxLines / ellipsis — the user explicitly wanted
                // all text shown. The cell will grow to fit.
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (activity.description.isNotEmpty) ...[
            const SizedBox(height: 2),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTapDescription,
              child: Text(
                activity.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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

/// v60.6 — drag handle on the right edge of a focused (hovered)
/// head cell. The user grabs the handle and drags to a target
/// day to extend (or trim) the span. The handle is gated on
/// `_DayCell.isFocused` upstream, so on web it's hover-only —
/// no permanent visual chrome cluttering the cell.
///
/// Implementation notes:
/// - `Draggable` (not LongPressDraggable) for snappier desktop
///   feel. Mobile users tap-and-drag the small target on the right
///   edge; the calendar's vertical scroll only has a chance to
///   claim the gesture if the touch lands outside the handle's
///   24dp hit zone.
/// - Feedback widget is fixed-size (a small "Extend" pill) so the
///   Overlay's unbounded constraints don't cause a layout error.
/// - `Material(type: transparency)` wraps so theme propagation
///   works in the Overlay where the feedback renders.
class _SpanDragHandle extends StatelessWidget {
  const _SpanDragHandle({required this.data});

  final _SpanDragData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Hit area is wider than the visible bar so the user has more
    // room to grab — 24dp wide on the right edge of the cell.
    // Visible bar is 4dp wide, vertically centered.
    Widget handleVisual({required bool active}) {
      return SizedBox(
        width: 24,
        height: double.infinity,
        child: Center(
          child: Container(
            width: 4,
            decoration: BoxDecoration(
              color: active
                  ? cs.primary
                  : cs.primary.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );
    }

    // Feedback shown while the drag is in flight. Fixed-size so the
    // Overlay (unbounded) doesn't error out.
    final feedback = Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: cs.primary,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.east, size: 14, color: cs.onPrimary),
            const SizedBox(width: 4),
            Text(
              'Extend span',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Draggable<_SpanDragData>(
        data: data,
        // dragAnchorStrategy.pointerDragAnchorStrategy: feedback
        // tracks the pointer, not the source widget origin — so
        // the pill follows the cursor, which reads correctly on
        // both web and mobile.
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: feedback,
        // Slightly fade the handle while dragging so the user
        // sees the source.
        childWhenDragging:
            Opacity(opacity: 0.3, child: handleVisual(active: true)),
        child: handleVisual(active: false),
      ),
    );
  }
}

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

// _VariantDots removed (v58) — the swap icon at top-right replaces
// the carousel-dot UX. With at most two variants per cell (original
// + AI), a binary toggle reads cleaner than a row of dots.


// =====================================================================
// Persisted add-ons wrapper — bridges the AI module to the repo
// =====================================================================

/// Thin wrapper around `AiActivityAddonsSection` that wires it to
/// the cloud-backed add-on column on the activity row. Watches the
/// row's variants stream so add-ons generated on one device land
/// on every other open client within the second; passes the
/// decoded map to the AI module's section as `previouslyGenerated`,
/// and routes its `onGenerated` / `onRemoved` callbacks into
/// `monthlyPlanRepository.setAddon` / `removeAddon`.
class _PersistedAddonsSection extends ConsumerWidget {
  const _PersistedAddonsSection({
    required this.activity,
    required this.planContext,
    this.onActiveChanged,
  });

  final _MonthlyActivity activity;
  final AiActivityContext? planContext;

  /// Forwarded from `AiActivityAddonsSection.onActiveChanged`. Lets
  /// the parent sheet collapse adjacent sections (objectives, steps,
  /// materials) when an add-on is being viewed or generated, so the
  /// content has full vertical space.
  final ValueChanged<bool>? onActiveChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the variants stream for the cell this activity lives in
    // so the section rebuilds on realtime updates. We don't have
    // (groupId, date) on the UI variant directly — but we can
    // bypass the stream and just re-decode whatever's in the row's
    // current persisted blob via a one-shot read. For real-time
    // sync, the stream-watching path is taken at the cell level.
    //
    // For now (keeps the touch surface small): decode whatever's
    // currently persisted on this row, accept that the addon list
    // doesn't auto-refresh inside an open sheet when another
    // teacher generates one. Closing + re-opening pulls fresh.
    final repo = ref.read(monthlyPlanRepositoryProvider);
    final raw = ref
        .watch(monthlyVariantProvider(activity.id))
        .asData
        ?.value;
    final persisted = MonthlyPlanRepository.decodeAddons(raw?.addons);
    return AiActivityAddonsSection(
      activity: activity.toAiActivity(),
      planContext: planContext,
      previouslyGenerated: persisted,
      onGenerated: (specId, sections) {
        unawaited(repo.setAddon(
          activityId: activity.id,
          specId: specId,
          sections: [
            for (final s in sections)
              {'heading': s.heading, 'body': s.body},
          ],
        ));
      },
      onRemoved: (specId) {
        unawaited(repo.removeAddon(
          activityId: activity.id,
          specId: specId,
        ));
      },
      onActiveChanged: onActiveChanged,
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
class _ActivityFormattedSheet extends StatefulWidget {
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
  State<_ActivityFormattedSheet> createState() =>
      _ActivityFormattedSheetState();
}

class _ActivityFormattedSheetState extends State<_ActivityFormattedSheet> {
  /// True while the embedded add-on section is loading or showing a
  /// generated result. Drives whether objectives / steps / materials
  /// / link / delete-button collapse — when an add-on is in view,
  /// the user wants air around the result, not a wall of activity
  /// metadata stacked above it.
  bool _addonsActive = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mq = MediaQuery.of(context);
    final dateLabel = DateFormat('EEE MMM d').format(widget.date);
    final activity = widget.activity;
    final steps = _splitSteps(activity.steps);
    final materials = activity.materials
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    // Hide objectives/steps/materials/link while an add-on is in
    // view. The activity title + description stay (they're context
    // the add-on is responding to); everything below collapses so
    // the add-on body has the screen.
    final showMetadata = !_addonsActive;

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
                    onPressed: widget.onEdit,
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
              if (showMetadata && activity.objectives.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                const _SectionHeader(label: 'Objectives'),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  activity.objectives,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
              ],
              if (showMetadata && steps.isNotEmpty) ...[
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
              if (showMetadata && materials.isNotEmpty) ...[
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
              if (showMetadata && activity.link.isNotEmpty) ...[
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
              SizedBox(
                height: showMetadata ? AppSpacing.xxl : AppSpacing.lg,
              ),
              // AI add-ons — embedded inline so the user can see
              // the activity above for reference while picking. The
              // section self-manages picker → loading → result
              // state internally; when an add-on is open, we collapse
              // the activity metadata above so the result has the
              // viewport.
              Divider(
                height: 1,
                color: cs.outlineVariant,
              ),
              const SizedBox(height: AppSpacing.lg),
              _PersistedAddonsSection(
                activity: activity,
                planContext: widget.planContext,
                onActiveChanged: (active) {
                  if (mounted) {
                    setState(() => _addonsActive = active);
                  }
                },
              ),
              // Delete button collapses while an add-on is open —
              // it's a destructive action that has no business
              // sitting under a generated discussion ladder.
              if (showMetadata) ...[
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
                  onPressed: widget.onDelete,
                ),
              ],
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

class _MonthlyActivityEditor extends ConsumerStatefulWidget {
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
  ConsumerState<_MonthlyActivityEditor> createState() =>
      _MonthlyActivityEditorState();
}

class _MonthlyActivityEditorState
    extends ConsumerState<_MonthlyActivityEditor> {
  /// True while the embedded add-on section is loading or showing
  /// a generated result. Hides the metadata disclosure (objectives,
  /// steps, materials, link) and the delete button so the add-on
  /// has air. Title + description fields stay visible — they're
  /// the prompt context the add-on is responding to.
  bool _addonsActive = false;

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

  // v56 push helpers — each one routes the controller's text to
  // monthlyPlanRepository.updateVariant for the activity's row id.
  // The repo's updateVariant marks only the touched field as dirty,
  // so the cloud push is a partial UPDATE (other fields untouched).
  void _push({
    String? title,
    String? description,
    String? objectives,
    String? steps,
    String? materials,
    String? link,
  }) {
    unawaited(
      ref.read(monthlyPlanRepositoryProvider).updateVariant(
            id: widget.activity.id,
            title: title,
            description: description,
            objectives: objectives,
            steps: steps,
            materials: materials,
            link: link,
          ),
    );
    widget.onChanged();
  }

  void _pushTitle() => _push(title: _title.text);
  void _pushDescription() => _push(description: _description.text);
  void _pushObjectives() => _push(objectives: _objectives.text);
  void _pushSteps() => _push(steps: _steps.text);
  void _pushMaterials() => _push(materials: _materials.text);
  void _pushLink() => _push(link: _link.text);

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
              if (!_addonsActive) ...[
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
              ],
              // Same inline AI add-ons section as the formatted
              // preview — exposes them at edit-time too so authors
              // can iterate without leaving the editor. When an
              // add-on is open the disclosure + delete button above
              // collapse so the result has the viewport.
              _PersistedAddonsSection(
                activity: widget.activity,
                planContext: widget.planContext,
                onActiveChanged: (active) {
                  if (mounted) {
                    setState(() => _addonsActive = active);
                  }
                },
              ),
              if (!_addonsActive) ...[
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
    this.onCommit,
    super.key,
  });

  final DateTime month;
  final String value;
  final ValueChanged<String> onChanged;

  /// Fires on focus loss — natural "I'm done typing" signal so
  /// the parent can flush debounced sync pushes before a tab close
  /// or app background can swallow the latest state.
  final VoidCallback? onCommit;

  @override
  State<_MonthlyThemeBar> createState() => _MonthlyThemeBarState();
}

class _MonthlyThemeBarState extends State<_MonthlyThemeBar> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.value);
  // Focus tracking — see didUpdateWidget. Same bug class as
  // _WeekSidePanelState's sub-theme field: per-keystroke writes
  // feed back through the stream and a stale emission can stomp
  // newer characters when the user is typing fast.
  final FocusNode _focusNode = FocusNode();
  bool _suggesting = false;
  List<String> _suggestions = const [];
  String? _suggestError;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      widget.onCommit?.call();
    }
  }

  @override
  void didUpdateWidget(covariant _MonthlyThemeBar old) {
    super.didUpdateWidget(old);
    // Only adopt the external value when the user isn't actively
    // typing. Otherwise a stream emission for "R" can overwrite
    // the controller after the user has already typed "Re" — the
    // "Reading → R on reload" bug.
    if (!_focusNode.hasFocus && widget.value != _ctrl.text) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
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
            focusNode: _focusNode,
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
