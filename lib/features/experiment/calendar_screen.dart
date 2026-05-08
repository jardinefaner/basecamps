// Calendar experiment — sandbox surface for the unified
// "calendar tile" model the brainstorm pinned down:
//
//   * The SURFACE implies *when* (the date you tapped).
//   * The FILTER implies *what kind of thing* (Trip / Event /
//     Day plan). One create gesture, three behaviors.
//   * You only TYPE the title. Everything else (destination,
//     time window, attendees, theme) lives behind a tap-to-
//     expand sheet — and only the fields that are relevant to
//     the current type get surfaced.
//
// In-memory only by design — this is the Lab proof for the
// pattern. If it earns its keep, graduate to a Drift-backed
// model + sync the same way `monthly_plan_screen.dart` does.
//
// What this build covers:
//   * Filter bar at the top: TYPE segmented control + GROUP chip
//   * Month grid (Mon–Sun, six rows max)
//   * Click empty cell in a typed mode → inflate inline title cell
//   * Tap existing tile → adaptive sheet with the right fields
//   * "All" filter is read-only — disambiguates the click intent
//     instead of forcing a picker (the brainstorm's preferred
//     resolution to the type-ambiguity question)
//
// What this build skips, deliberately:
//   * Multi-day spans (drag-edge to extend) — TODO once the
//     primitive is proven.
//   * Persistence — sandbox in-memory; reset on hot-restart.
//   * AI scaffolding behind tiles (the day-plan-becomes-schedule
//     bit) — comes after the surface itself feels right.

import 'package:basecamp/database/database.dart' show Group;
import 'package:basecamp/features/ai/openai_client.dart';
import 'package:basecamp/features/children/children_repository.dart'
    show groupsProvider;
import 'package:basecamp/features/experiment/calendar_llm_service.dart';
import 'package:basecamp/features/experiment/calendar_tile_store.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/adaptive_sheet.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// Tile model lives in `calendar_tile_store.dart` (public + Riverpod-
// backed) so the Command Center can write tiles too. The screen
// here just consumes the store.

DateTime _dayKey(DateTime d) => DateTime.utc(d.year, d.month, d.day);

String _newId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${UniqueKey().hashCode}';

// ═════════════════════════════════════════════════════════════════
// Screen
// ═════════════════════════════════════════════════════════════════

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  /// `null` means the "All" filter — read-only browse mode.
  /// Anything non-null arms click-to-create for that type.
  CalendarTileType? _activeType = CalendarTileType.dayPlan;

  /// Group filter — null until groups load. "All groups" is a
  /// browse-mode equivalent of [_activeType] = null; for the
  /// proof we keep it required so click-create has an unambiguous
  /// owner for the new tile.
  String? _activeGroupId;

  /// Anchor month (always set to the first of the month).
  late DateTime _anchorMonth;

  /// Tile store reads from the Riverpod-backed
  /// `calendarTilesProvider`. The notifier owns the map; this
  /// getter is a read-through. Build methods that need to
  /// rebuild on changes call `ref.watch(...)` directly.
  Map<String, CalendarTile> get _tiles =>
      ref.read(calendarTilesProvider);

  /// Write pipe — every place that used to do `_tiles[t.id] = t`
  /// now goes through the notifier so all screens (including
  /// the Command Center) see the change.
  CalendarTilesNotifier get _tilesNotifier =>
      ref.read(calendarTilesProvider.notifier);

  /// Inline-create tracking. When non-null, the matching cell
  /// renders a TextField in place of the "+ trip" affordance.
  String? _inlineCellKey;
  final TextEditingController _inlineCtrl = TextEditingController();
  final FocusNode _inlineFocus = FocusNode();

  /// Drop-bar state — the LLM-driven create flow.
  /// `_dropDraft` is the pending preview shown after a successful
  /// model call; `_dropLoading` is the in-flight spinner; the
  /// error string surfaces parse failures + network blips as a
  /// short red note under the bar.
  CalendarTileDraft? _dropDraft;
  bool _dropLoading = false;
  String? _dropError;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _anchorMonth = DateTime(now.year, now.month);

    // If the user just landed here after creating tiles via
    // Command Center, the store may already hold rows the
    // current filters can't see. Auto-snap to the most recently
    // added one on the next frame so navigation from /command
    // doesn't dump the user onto an empty grid.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tiles = ref.read(calendarTilesProvider);
      if (tiles.isEmpty) return;
      // Pick the newest tile by insertion order (Dart hash maps
      // preserve insertion order).
      final newest = tiles.values.last;
      if (_isVisibleUnderCurrentFilters(newest)) return;
      setState(() {
        _activeGroupId = newest.groupId ?? _activeGroupId;
        _activeType = newest.type;
        _anchorMonth = DateTime(newest.date.year, newest.date.month);
      });
    });
  }

  @override
  void dispose() {
    _inlineCtrl.dispose();
    _inlineFocus.dispose();
    super.dispose();
  }

  // ——— Month nav ———————————————————————————————————————————————

  void _shiftMonth(int delta) {
    setState(() {
      _anchorMonth = DateTime(_anchorMonth.year, _anchorMonth.month + delta);
      _exitInlineEdit();
    });
  }

  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      _anchorMonth = DateTime(now.year, now.month);
      _exitInlineEdit();
    });
  }

  // ——— Inline create ——————————————————————————————————————————

  String _cellKey(DateTime day) => _dayKey(day).toIso8601String();

  void _enterInlineEdit(DateTime day) {
    if (_activeType == null || _activeGroupId == null) return;
    setState(() {
      _inlineCellKey = _cellKey(day);
      _inlineCtrl.text = '';
    });
    // Defer focus until the new TextField is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inlineFocus.requestFocus();
    });
  }

  void _commitInlineEdit(DateTime day) {
    final type = _activeType;
    final groupId = _activeGroupId;
    final raw = _inlineCtrl.text.trim();
    if (type == null || groupId == null || raw.isEmpty) {
      _exitInlineEdit();
      return;
    }
    final tile = CalendarTile(
      id: _newId(),
      type: type,
      date: _dayKey(day),
      groupId: groupId,
      title: raw,
    );
    setState(() {
      _tilesNotifier.put(tile);
      _exitInlineEdit();
    });
  }

  void _exitInlineEdit() {
    _inlineCellKey = null;
    _inlineCtrl.clear();
    if (_inlineFocus.hasFocus) _inlineFocus.unfocus();
  }

  // ——— Drop bar (LLM create) ——————————————————————————————————

  /// Send raw text to the LLM, surface a draft for the teacher
  /// to confirm or tweak. The active type filter (or DayPlan as
  /// a sane fallback) is the type the model defaults to when the
  /// user is ambiguous; the active group is what the new tile
  /// gets stamped with.
  Future<void> _onDropSubmitted(String input) async {
    final groupId = _activeGroupId;
    if (groupId == null) return;
    final groups =
        ref.read(groupsProvider).asData?.value ?? const <Group>[];
    final match = groups.where((g) => g.id == groupId).toList();
    final groupName = match.isNotEmpty
        ? match.first.name
        : (groups.isNotEmpty ? groups.first.name : 'group');
    setState(() {
      _dropLoading = true;
      _dropError = null;
      _dropDraft = null;
    });
    try {
      final draft = await CalendarLlmService.draftFromText(
        input: input,
        today: DateTime.now(),
        activeType: _activeType ?? CalendarTileType.dayPlan,
        activeGroupName: groupName,
        availableGroups: groups.map((g) => g.name).toList(),
      );
      if (!mounted) return;
      // Belt-and-suspenders: even with the prompt teaching the
      // model to expand "all groups" / "everyone" to the full
      // roster, gpt-4o-mini occasionally returns an empty array.
      // Detect the pattern in the raw input and override the
      // draft so a teacher's "field trip aquarium for everyone"
      // never silently lands on a single group.
      final overridden = _maybeExpandAllGroups(draft, input, groups);
      setState(() {
        _dropDraft = overridden;
        _dropLoading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _dropLoading = false;
        _dropError = "Couldn't parse that — try rephrasing.";
      });
      debugPrint('[calendar drop] $e');
    }
  }

  void _onDropConfirm() {
    final draft = _dropDraft;
    if (draft == null) return;
    // Resolve the group(s): the model can nominate one OR several,
    // so a single sentence "field trip aquarium for sunflowers and
    // acorns tuesday" mints TWO tiles (same date / title / fields,
    // different groupId). When the model named no groups, fall
    // through to the active filter so the tile lands somewhere.
    final resolvedIds = _resolveGroupIds(draft.groupNames);
    if (resolvedIds.isEmpty) return;
    final created = <CalendarTile>[];
    for (final groupId in resolvedIds) {
      final tile = CalendarTile(
        id: _newId(),
        type: draft.type,
        date: _dayKey(draft.date),
        groupId: groupId,
        title: draft.title,
      )
        ..destination = draft.destination ?? ''
        ..startTime = draft.startTime
        ..endTime = draft.endTime
        ..theme = draft.theme ?? ''
        ..description = draft.description ?? ''
        ..notes = draft.notes ?? '';
      created.add(tile);
    }
    setState(() {
      for (final t in created) {
        _tilesNotifier.put(t);
      }
      _dropDraft = null;
      _dropError = null;
      // Switch the filter to the FIRST resolved group + its month
      // so at least one of the new tiles lands visibly. Also snap
      // the TYPE filter to the new tile's type — without this,
      // the bar happily creates a Day plan while the user has the
      // Trips filter active, and the tile is invisible. Reported
      // bug: "I added something, it didn't show up." The fan-out
      // semantics for type are simpler than for groups: there's
      // only ever one type per draft, so we snap to it.
      _activeGroupId = resolvedIds.first;
      _activeType = created.first.type;
      _anchorMonth =
          DateTime(created.first.date.year, created.first.date.month);
    });
  }

  /// Detect "all groups" / "everyone" / "all classes" patterns in
  /// the raw user input and, if found, override the draft's
  /// `groupNames` with the full roster. Belt-and-suspenders for
  /// the prompt — the model is supposed to do this expansion
  /// itself, but gpt-4o-mini occasionally returns an empty array
  /// even when the prompt is explicit. The check runs whether or
  /// not the model already populated `groupNames` so the user's
  /// "everyone" wins over a model that picked just one group.
  CalendarTileDraft _maybeExpandAllGroups(
    CalendarTileDraft draft,
    String input,
    List<Group> groups,
  ) {
    if (groups.isEmpty) return draft;
    final lowered = input.toLowerCase();
    // Word-boundary matches so we don't trip on "all classes" inside
    // a longer phrase like "smaller classes are coming."
    final patterns = <RegExp>[
      RegExp(r'\ball\s+groups?\b'),
      RegExp(r'\ball\s+classes\b'),
      RegExp(r'\ball\s+kids\b'),
      RegExp(r'\ball\s+the\s+kids\b'),
      RegExp(r'\beveryone\b'),
      RegExp(r'\beverybody\b'),
      RegExp(r'\bfor\s+all\b'),
      RegExp(r'\bwith\s+all\b'),
      RegExp(r'\bwhole\s+(school|program|class)\b'),
    ];
    final matched = patterns.any((re) => re.hasMatch(lowered));
    if (!matched) return draft;
    // Replace with the full roster, in roster order.
    return CalendarTileDraft(
      type: draft.type,
      date: draft.date,
      title: draft.title,
      destination: draft.destination,
      startTime: draft.startTime,
      endTime: draft.endTime,
      theme: draft.theme,
      description: draft.description,
      notes: draft.notes,
      groupNames: groups.map((g) => g.name).toList(),
      confidence: draft.confidence,
    );
  }

  /// Map a list of model-emitted group names back to real group
  /// ids. Lenient match — case-insensitive, trim, dedupe ids so a
  /// model regression that named the same group twice doesn't
  /// create two identical tiles. Falls through to a single-element
  /// list with the active filter (or first available group) when
  /// nothing in [names] resolved.
  List<String> _resolveGroupIds(List<String> names) {
    final groups =
        ref.read(groupsProvider).asData?.value ?? const <Group>[];
    final out = <String>[];
    final seen = <String>{};
    for (final name in names) {
      final needle = name.trim().toLowerCase();
      if (needle.isEmpty) continue;
      final match = groups.where(
        (g) => g.name.trim().toLowerCase() == needle,
      );
      if (match.isEmpty) continue;
      final id = match.first.id;
      if (seen.add(id)) out.add(id);
    }
    if (out.isNotEmpty) return out;
    final fallback =
        _activeGroupId ?? (groups.isNotEmpty ? groups.first.id : null);
    return fallback == null ? const <String>[] : <String>[fallback];
  }

  Future<void> _onDropTweak() async {
    final draft = _dropDraft;
    if (draft == null) return;
    // Convert the draft into one (or more) real tiles, drop the
    // preview, then open the expand sheet for the tile in the
    // group `_onDropConfirm` snapped the filter to. With a
    // fan-out we don't open every new tile — the teacher tweaks
    // the visible one; if it ends up shared (most fan-out cases),
    // the tweak applies cleanly because the tiles share their
    // title + date + fields and only differ by groupId.
    _onDropConfirm();
    final visibleGroupId = _activeGroupId;
    final created = _tiles.values
        .where(
          (t) =>
              t.title == draft.title &&
              t.date == _dayKey(draft.date) &&
              t.groupId == visibleGroupId,
        )
        .lastOrNull;
    if (created != null) {
      await _openTile(created);
    }
  }

  void _onDropDismiss() {
    setState(() {
      _dropDraft = null;
      _dropError = null;
    });
  }

  // ——— Expand sheet ———————————————————————————————————————————

  Future<void> _openTile(CalendarTile tile) async {
    await showAdaptiveSheet<void>(
      context: context,
      builder: (_) => _TileEditorSheet(
        tile: tile,
        onChanged: () => setState(() {}),
        onDelete: () => setState(() => _tilesNotifier.remove(tile.id)),
      ),
    );
  }

  // ——— Build ————————————————————————————————————————————————————

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupsProvider);
    // Subscribe to the tile store so writes from elsewhere
    // (Command Center, eventually persisted variants) trigger a
    // rebuild.
    ref.watch(calendarTilesProvider);

    // Auto-snap filters to a newly-added tile that's NOT visible
    // under the current filters. Without this, a tile created
    // from the Command Center lands on a different group / type /
    // month than the calendar is showing and silently disappears
    // — the user reported "I added it, calendar's empty." We
    // listen to the provider and, when the map's keyset GROWS
    // (a new tile id appeared), check whether it's visible. If
    // not, snap group/type/month to its values so it shows up.
    ref.listen<Map<String, CalendarTile>>(
      calendarTilesProvider,
      (previous, next) {
        if (previous == null) return;
        if (next.length <= previous.length) return;
        final newIds = next.keys.toSet().difference(previous.keys.toSet());
        if (newIds.isEmpty) return;
        // Take the most recently added tile (last in iteration
        // order — `Map`-of-spread literal preserves insertion
        // order for Dart's hash maps). Snap to it.
        final tile = next[newIds.last];
        if (tile == null) return;
        final visibleNow =
            _isVisibleUnderCurrentFilters(tile);
        if (visibleNow) return;
        setState(() {
          _activeGroupId = tile.groupId ?? _activeGroupId;
          _activeType = tile.type;
          _anchorMonth = DateTime(tile.date.year, tile.date.month);
        });
      },
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat.yMMMM().format(_anchorMonth)),
        actions: [
          IconButton(
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _shiftMonth(-1),
          ),
          IconButton(
            tooltip: 'Today',
            icon: const Icon(Icons.today_outlined),
            onPressed: _goToToday,
          ),
          IconButton(
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _shiftMonth(1),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("Couldn't load groups: $e")),
        data: (groups) {
          // Lazy-init the active group on first build (most-recent
          // group cohort isn't known until the stream fires).
          if (_activeGroupId == null && groups.isNotEmpty) {
            _activeGroupId = groups.first.id;
          }
          return Column(
            children: [
              _FilterBar(
                groups: groups,
                activeGroupId: _activeGroupId,
                activeType: _activeType,
                onGroupChanged: (id) => setState(() => _activeGroupId = id),
                onTypeChanged: (t) => setState(() {
                  _activeType = t;
                  _exitInlineEdit();
                }),
              ),
              const Divider(height: 1),
              Expanded(
                child: _MonthGrid(
                  anchorMonth: _anchorMonth,
                  tiles: _visibleTiles(),
                  inlineCellKey: _inlineCellKey,
                  inlineCtrl: _inlineCtrl,
                  inlineFocus: _inlineFocus,
                  activeType: _activeType,
                  hasGroup: _activeGroupId != null,
                  onTapEmpty: _enterInlineEdit,
                  onSubmitInline: _commitInlineEdit,
                  onCancelInline: () => setState(_exitInlineEdit),
                  onTapTile: _openTile,
                ),
              ),
              // Drop bar lives at the bottom — chat-style. Thumb-
              // reach on a phone, and the preview chip floats just
              // above the input as the natural "draft just appeared"
              // affordance. Wrapped in a SafeArea so the system gesture
              // bar doesn't overlap, plus viewInsets padding so the
              // bar lifts above the keyboard when focused.
              _DropBar(
                enabled: OpenAiClient.isAvailable && _activeGroupId != null,
                loading: _dropLoading,
                draft: _dropDraft,
                error: _dropError,
                onSubmit: _onDropSubmitted,
                onConfirm: _onDropConfirm,
                onTweak: _onDropTweak,
                onDismiss: _onDropDismiss,
              ),
            ],
          );
        },
      ),
    );
  }

  /// Tiles visible under the current filter. "All" type shows
  /// everything for the active group; a specific type narrows
  /// to that type only.
  /// True iff [tile] would render under the current filter
  /// state. Used by the auto-snap logic when a new tile arrives
  /// from outside the screen — if it'd be hidden, we snap to it
  /// so the user actually sees what they just created.
  bool _isVisibleUnderCurrentFilters(CalendarTile tile) {
    if (tile.groupId != _activeGroupId) return false;
    if (_activeType != null && tile.type != _activeType) return false;
    final monthStart = _anchorMonth;
    final monthEnd = DateTime(_anchorMonth.year, _anchorMonth.month + 1);
    if (tile.date.isBefore(monthStart) || !tile.date.isBefore(monthEnd)) {
      return false;
    }
    return true;
  }

  Map<String, List<CalendarTile>> _visibleTiles() {
    final out = <String, List<CalendarTile>>{};
    for (final t in _tiles.values) {
      if (t.groupId != _activeGroupId) continue;
      if (_activeType != null && t.type != _activeType) continue;
      // Only show tiles that fall inside the visible month range.
      final monthStart = _anchorMonth;
      final monthEnd = DateTime(_anchorMonth.year, _anchorMonth.month + 1);
      if (t.date.isBefore(monthStart) || !t.date.isBefore(monthEnd)) {
        continue;
      }
      out.putIfAbsent(_cellKey(t.date), () => []).add(t);
    }
    return out;
  }
}

// ═════════════════════════════════════════════════════════════════
// Filter bar
// ═════════════════════════════════════════════════════════════════

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.groups,
    required this.activeGroupId,
    required this.activeType,
    required this.onGroupChanged,
    required this.onTypeChanged,
  });

  final List<Group> groups;
  final String? activeGroupId;
  final CalendarTileType? activeType;
  final ValueChanged<String> onGroupChanged;
  final ValueChanged<CalendarTileType?> onTypeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Type row — segmented "Trips · Events · Day plans · All".
          // The active segment is what new tiles will become; "All"
          // disables click-to-create (read-only browse).
          SizedBox(
            height: 36,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final t in CalendarTileType.values) ...[
                    _TypeChip(
                      label: t.pluralLabel,
                      icon: t.icon,
                      selected: activeType == t,
                      onTap: () => onTypeChanged(t),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  _TypeChip(
                    label: 'All',
                    icon: Icons.layers_outlined,
                    selected: activeType == null,
                    onTap: () => onTypeChanged(null),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Group row — a tile must belong to a group, so this
          // stays single-select like monthly plan's filter bar.
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text(
                'No groups yet — create one in People → Children & groups.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final g in groups)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: ChoiceChip(
                        label: Text(g.name),
                        selected: activeGroupId == g.id,
                        onSelected: (_) => onGroupChanged(g.id),
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

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurfaceVariant;
    return Material(
      color: selected
          ? theme.colorScheme.primary
          : theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// Month grid
// ═════════════════════════════════════════════════════════════════

class _DayHeaderRow extends StatelessWidget {
  const _DayHeaderRow({required this.cellWidth});

  /// Pinned to the same width as the body cells so the labels
  /// line up under their columns regardless of horizontal scroll
  /// position.
  final double cellWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // School-week calendar — Mon–Fri only. Saturday/Sunday don't
    // belong here because BASECamp doesn't run on weekends; any
    // tile parked on Sat/Sun would just be visual noise.
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
    return Container(
      color: theme.colorScheme.surfaceContainerLowest,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          for (final l in labels)
            SizedBox(
              width: cellWidth,
              child: Center(
                child: Text(
                  l,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.anchorMonth,
    required this.tiles,
    required this.inlineCellKey,
    required this.inlineCtrl,
    required this.inlineFocus,
    required this.activeType,
    required this.hasGroup,
    required this.onTapEmpty,
    required this.onSubmitInline,
    required this.onCancelInline,
    required this.onTapTile,
  });

  final DateTime anchorMonth;
  final Map<String, List<CalendarTile>> tiles;
  final String? inlineCellKey;
  final TextEditingController inlineCtrl;
  final FocusNode inlineFocus;
  final CalendarTileType? activeType;
  final bool hasGroup;
  final ValueChanged<DateTime> onTapEmpty;
  final ValueChanged<DateTime> onSubmitInline;
  final VoidCallback onCancelInline;
  final ValueChanged<CalendarTile> onTapTile;

  // Min cell width — keeps each day readable on a phone. The
  // grid scrolls horizontally when the viewport is narrower than
  // the total. Mirrors the monthly-plan rationale: a phone-fit
  // grid crunches each cell to ~30dp wide, which is unreadable.
  static const double _minCellWidth = 140;

  // Floor on row height so empty weeks don't collapse into a
  // line. Cells with content can grow taller via IntrinsicHeight.
  static const double _minRowHeight = 120;

  static const int _columnsPerWeek = 5;

  @override
  Widget build(BuildContext context) {
    final weeks = _buildWeeks(anchorMonth);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = constraints.maxWidth >=
                _minCellWidth * _columnsPerWeek
            ? constraints.maxWidth / _columnsPerWeek
            : _minCellWidth;
        final totalWidth = cellWidth * _columnsPerWeek;
        return SingleChildScrollView(
          // Vertical outer scroll for many-week months.
          child: SingleChildScrollView(
            // Horizontal inner scroll for narrow viewports.
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalWidth,
              child: Column(
                children: [
                  _DayHeaderRow(cellWidth: cellWidth),
                  const Divider(height: 1),
                  for (final week in weeks)
                    IntrinsicHeight(
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(minHeight: _minRowHeight),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final cell in week)
                              SizedBox(
                                width: cellWidth,
                                child: _Cell(
                                  day: cell.day,
                                  inMonth: cell.inMonth,
                                  tiles:
                                      tiles[_dayKey(cell.day).toIso8601String()] ??
                                          const [],
                                  isInlineEditing: inlineCellKey ==
                                      _dayKey(cell.day).toIso8601String(),
                                  inlineCtrl: inlineCtrl,
                                  inlineFocus: inlineFocus,
                                  activeType: activeType,
                                  hasGroup: hasGroup,
                                  onTapEmpty: onTapEmpty,
                                  onSubmitInline: onSubmitInline,
                                  onCancelInline: onCancelInline,
                                  onTapTile: onTapTile,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Build a list of weeks, each week is a fixed list of 5
  /// [_GridCell]s (Mon–Fri). Out-of-month days at the start /
  /// end render dimmed but still occupy a slot so columns stay
  /// aligned. Sat/Sun are skipped entirely — BASECamp doesn't
  /// schedule on weekends so they'd just be empty noise.
  List<List<_GridCell>> _buildWeeks(DateTime anchor) {
    final firstOfMonth = DateTime(anchor.year, anchor.month);
    final daysInMonth = DateTime(anchor.year, anchor.month + 1, 0).day;
    final lastOfMonth = DateTime(anchor.year, anchor.month, daysInMonth);

    // Snap the start back to Monday of the week containing the 1st.
    final startMonday =
        firstOfMonth.subtract(Duration(days: firstOfMonth.weekday - 1));
    // Snap the end to the Friday of the week containing the last
    // day of the month. If the month ends Mon–Thu we ADD days to
    // reach Friday; if it ends Sat/Sun we SUBTRACT (the formula
    // is the same — `Duration(days: 5 - weekday)` works in both
    // directions).
    final endFriday = lastOfMonth.add(
      Duration(days: DateTime.friday - lastOfMonth.weekday),
    );

    final weeks = <List<_GridCell>>[];
    var weekStart = startMonday;
    while (!weekStart.isAfter(endFriday)) {
      final week = <_GridCell>[];
      for (var c = 0; c < _columnsPerWeek; c++) {
        final day = weekStart.add(Duration(days: c));
        final inMonth = day.month == anchor.month && day.year == anchor.year;
        week.add(_GridCell(day: day, inMonth: inMonth));
      }
      weeks.add(week);
      weekStart = weekStart.add(const Duration(days: 7));
    }
    return weeks;
  }
}

class _GridCell {
  const _GridCell({required this.day, required this.inMonth});
  final DateTime day;
  final bool inMonth;
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.day,
    required this.inMonth,
    required this.tiles,
    required this.isInlineEditing,
    required this.inlineCtrl,
    required this.inlineFocus,
    required this.activeType,
    required this.hasGroup,
    required this.onTapEmpty,
    required this.onSubmitInline,
    required this.onCancelInline,
    required this.onTapTile,
  });

  final DateTime day;
  final bool inMonth;
  final List<CalendarTile> tiles;
  final bool isInlineEditing;
  final TextEditingController inlineCtrl;
  final FocusNode inlineFocus;
  final CalendarTileType? activeType;
  final bool hasGroup;
  final ValueChanged<DateTime> onTapEmpty;
  final ValueChanged<DateTime> onSubmitInline;
  final VoidCallback onCancelInline;
  final ValueChanged<CalendarTile> onTapTile;

  bool get _isToday {
    final now = DateTime.now();
    return now.year == day.year &&
        now.month == day.month &&
        now.day == day.day;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canCreate =
        inMonth && activeType != null && hasGroup && !isInlineEditing;
    return InkWell(
      onTap: canCreate && tiles.isEmpty ? () => onTapEmpty(day) : null,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          color: inMonth
              ? null
              : theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.4),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 6,
          vertical: 4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Day number — circled when today.
            Row(
              children: [
                _DayNumber(day: day, today: _isToday, dimmed: !inMonth),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 2),
            // Tiles — each is a typed mini-card.
            for (final t in tiles)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: _TilePill(tile: t, onTap: () => onTapTile(t)),
              ),
            // Inline create row (when this cell is being edited).
            if (isInlineEditing && activeType != null)
              _InlineCreateRow(
                type: activeType!,
                controller: inlineCtrl,
                focusNode: inlineFocus,
                onSubmit: () => onSubmitInline(day),
                onCancel: onCancelInline,
              )
            // Faint create affordance — visible on cells with no
            // tiles, when a type filter is selected, when the cell
            // is in-month. The whole cell is the tap target via
            // InkWell above; this is just the visual hint.
            else if (canCreate && tiles.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '+ ${activeType!.singularLabel}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.4),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayNumber extends StatelessWidget {
  const _DayNumber({
    required this.day,
    required this.today,
    required this.dimmed,
  });

  final DateTime day;
  final bool today;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = dimmed
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
        : today
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurface;
    final body = Text(
      '${day.day}',
      style: theme.textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: today ? FontWeight.w700 : FontWeight.w500,
      ),
    );
    if (today) {
      return Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          shape: BoxShape.circle,
        ),
        child: body,
      );
    }
    return SizedBox(width: 18, height: 18, child: Center(child: body));
  }
}

class _TilePill extends StatelessWidget {
  const _TilePill({required this.tile, required this.onTap});

  final CalendarTile tile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _accentFor(theme, tile.type);
    return Material(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          // Cross-align to start so a wrapping title doesn't push the
          // icon to the middle — the icon stays anchored to the
          // first line. The row uses IntrinsicHeight cells (see
          // `_MonthGrid`), so taller tiles just grow their row;
          // nothing gets cropped.
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(tile.type.icon, size: 12, color: color),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  tile.title,
                  // No maxLines / no ellipsis — titles wrap as
                  // many lines as they need. The user explicitly
                  // wants nothing cropped.
                  softWrap: true,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
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

Color _accentFor(ThemeData theme, CalendarTileType type) {
  return switch (type) {
    CalendarTileType.trip => theme.colorScheme.tertiary,
    CalendarTileType.event => theme.colorScheme.secondary,
    CalendarTileType.dayPlan => theme.colorScheme.primary,
  };
}

class _InlineCreateRow extends StatelessWidget {
  const _InlineCreateRow({
    required this.type,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onCancel,
  });

  final CalendarTileType type;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _accentFor(theme, type);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color),
        ),
        child: Row(
          children: [
            Icon(type.icon, size: 12, color: color),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '${type.singularLabel} title',
                  hintStyle: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                onSubmitted: (_) => onSubmit(),
                onTapOutside: (_) => onCancel(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// Expand sheet
// ═════════════════════════════════════════════════════════════════

class _TileEditorSheet extends StatefulWidget {
  const _TileEditorSheet({
    required this.tile,
    required this.onChanged,
    required this.onDelete,
  });

  final CalendarTile tile;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  State<_TileEditorSheet> createState() => _TileEditorSheetState();
}

class _TileEditorSheetState extends State<_TileEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _destination;
  late final TextEditingController _theme;
  late final TextEditingController _notes;

  /// AI-itinerary state. Spinner + error live here, not on the
  /// tile, because regenerate is a per-sheet interaction. The
  /// generated blocks themselves persist on the tile.
  bool _itineraryLoading = false;
  String? _itineraryError;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.tile.title);
    _description = TextEditingController(text: widget.tile.description);
    _destination = TextEditingController(text: widget.tile.destination);
    _theme = TextEditingController(text: widget.tile.theme);
    _notes = TextEditingController(text: widget.tile.notes);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _destination.dispose();
    _theme.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    setState(() {
      widget.tile.title = _title.text.trim();
      widget.tile.description = _description.text.trim();
      widget.tile.destination = _destination.text.trim();
      widget.tile.theme = _theme.text.trim();
      widget.tile.notes = _notes.text.trim();
    });
    widget.onChanged();
  }

  /// Hit the LLM for a fresh itinerary. Always replaces the
  /// existing blocks on success — the regenerate flow is "throw
  /// the old set away, render the new set." Editing individual
  /// blocks (out of scope for v0) would want a merge instead.
  Future<void> _generateItinerary() async {
    final t = widget.tile;
    if (!OpenAiClient.isAvailable) {
      setState(() {
        _itineraryError = 'Sign in to use AI scaffolding.';
      });
      return;
    }
    setState(() {
      _itineraryLoading = true;
      _itineraryError = null;
    });
    try {
      final drafts = await CalendarLlmService.draftItinerary(
        ItineraryDraftRequest(
          type: t.type,
          title: t.title,
          destination:
              t.destination.isEmpty ? null : t.destination,
          theme: t.theme.isEmpty ? null : t.theme,
          startTime: t.startTime,
          endTime: t.endTime,
        ),
      );
      if (!mounted) return;
      setState(() {
        t.itinerary
          ..clear()
          ..addAll(drafts.map(
            (d) => ItineraryBlock(
              id: _newId(),
              time: d.time,
              title: d.title,
              description: d.description ?? '',
            ),
          ));
        _itineraryLoading = false;
      });
      widget.onChanged();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _itineraryLoading = false;
        _itineraryError = "Couldn't generate — try again.";
      });
      debugPrint('[calendar itinerary] $e');
    }
  }

  void _removeBlock(String id) {
    setState(() {
      widget.tile.itinerary.removeWhere((b) => b.id == id);
    });
    widget.onChanged();
  }

  void _clearItinerary() {
    setState(() {
      widget.tile.itinerary.clear();
      _itineraryError = null;
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = widget.tile;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header — icon + type label + delete.
            Row(
              children: [
                Icon(t.type.icon, color: _accentFor(theme, t.type)),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  t.type.singularLabel.toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    widget.onDelete();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Title — always shown, always editable.
            TextField(
              controller: _title,
              style: theme.textTheme.titleLarge,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Title',
              ),
              onChanged: (_) => _save(),
            ),
            // Date — read-only for now (no date picker yet).
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                DateFormat.yMMMMEEEEd().format(t.date),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            // Type-specific fields. Empty fields render as a
            // faint "+ add X" affordance and only inflate when
            // the user taps. Right now we just show the labelled
            // input directly — the "tap to add" empty-state polish
            // is the next iteration.
            ..._typeSpecificFields(theme, t),
            const SizedBox(height: AppSpacing.md),
            // Notes — always available.
            _LabelledField(
              label: 'Notes',
              controller: _notes,
              onChanged: _save,
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _typeSpecificFields(ThemeData theme, CalendarTile t) {
    final itinerarySection = _ItinerarySection(
      tile: t,
      loading: _itineraryLoading,
      error: _itineraryError,
      onGenerate: _generateItinerary,
      onClear: _clearItinerary,
      onRemoveBlock: _removeBlock,
    );
    switch (t.type) {
      case CalendarTileType.trip:
        return [
          _LabelledField(
            label: 'Destination',
            controller: _destination,
            onChanged: _save,
          ),
          const SizedBox(height: AppSpacing.sm),
          _TimeWindowRow(tile: t, onChanged: () => setState(_save)),
          const SizedBox(height: AppSpacing.sm),
          _LabelledField(
            label: 'Description',
            controller: _description,
            onChanged: _save,
            maxLines: 2,
          ),
          const SizedBox(height: AppSpacing.md),
          itinerarySection,
        ];
      case CalendarTileType.event:
        return [
          _TimeWindowRow(tile: t, onChanged: () => setState(_save)),
          const SizedBox(height: AppSpacing.sm),
          _LabelledField(
            label: 'Description',
            controller: _description,
            onChanged: _save,
            maxLines: 2,
          ),
        ];
      case CalendarTileType.dayPlan:
        return [
          _LabelledField(
            label: 'Theme',
            controller: _theme,
            onChanged: _save,
          ),
          const SizedBox(height: AppSpacing.sm),
          _LabelledField(
            label: 'Description',
            controller: _description,
            onChanged: _save,
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.md),
          itinerarySection,
        ];
    }
  }
}

class _LabelledField extends StatelessWidget {
  const _LabelledField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }
}

class _TimeWindowRow extends StatelessWidget {
  const _TimeWindowRow({
    required this.tile,
    required this.onChanged,
  });

  final CalendarTile tile;
  final VoidCallback onChanged;

  Future<void> _pick({
    required BuildContext context,
    required bool start,
  }) async {
    final initial = (start ? tile.startTime : tile.endTime) ??
        const TimeOfDay(hour: 9, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null) return;
    if (start) {
      tile.startTime = picked;
    } else {
      tile.endTime = picked;
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String fmt(TimeOfDay? t) =>
        t == null ? 'Add' : t.format(context);
    return Row(
      children: [
        Expanded(
          child: _ChipButton(
            label: 'Start: ${fmt(tile.startTime)}',
            onTap: () => _pick(context: context, start: true),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _ChipButton(
            label: 'End: ${fmt(tile.endTime)}',
            onTap: () => _pick(context: context, start: false),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        if (tile.startTime != null || tile.endTime != null)
          IconButton(
            tooltip: 'Clear times',
            icon: Icon(
              Icons.close,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            onPressed: () {
              tile.startTime = null;
              tile.endTime = null;
              onChanged();
            },
          ),
      ],
    );
  }
}

class _ChipButton extends StatelessWidget {
  const _ChipButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Center(
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// Itinerary section (AI scaffolding)
// ═════════════════════════════════════════════════════════════════

/// The AI-scaffolded body of a tile: timed blocks of titles +
/// short descriptions. Trips get an itinerary arc (leave / arrive
/// / activities / snack / return); day plans get a classroom day
/// shape (circle / art / outside / story). Both render the same
/// way — a sectioned list with a regenerate button at the top.
///
/// Visual states stack:
///   * Empty → single full-width button "✨ Generate itinerary".
///   * Loading → spinner + label.
///   * Error → red note + retry button.
///   * Populated → list of blocks, each tappable to remove.
///                 Header gains "regenerate" + "clear" actions.
class _ItinerarySection extends StatelessWidget {
  const _ItinerarySection({
    required this.tile,
    required this.loading,
    required this.error,
    required this.onGenerate,
    required this.onClear,
    required this.onRemoveBlock,
  });

  final CalendarTile tile;
  final bool loading;
  final String? error;
  final Future<void> Function() onGenerate;
  final VoidCallback onClear;
  final ValueChanged<String> onRemoveBlock;

  String get _sectionLabel => switch (tile.type) {
        CalendarTileType.trip => 'Itinerary',
        CalendarTileType.dayPlan => 'Schedule',
        CalendarTileType.event => 'Schedule',
      };

  String get _generateLabel => switch (tile.type) {
        CalendarTileType.trip => 'Generate itinerary',
        CalendarTileType.dayPlan => 'Generate schedule',
        CalendarTileType.event => 'Generate schedule',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocks = tile.itinerary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header row — section label + (when populated) regen +
        // clear actions on the right.
        Row(
          children: [
            Text(
              _sectionLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (blocks.isNotEmpty && !loading) ...[
              TextButton.icon(
                onPressed: onGenerate,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Regenerate'),
              ),
              IconButton(
                tooltip: 'Clear all blocks',
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: onClear,
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        // Body — depends on state.
        if (loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Asking the model…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else if (blocks.isEmpty) ...[
          // Empty state — single primary button. Uses the auto-
          // awesome icon to telegraph "AI" without needing words.
          // Disabled with a hint when the OpenAI proxy isn't
          // reachable (no Supabase session) so the teacher knows
          // why nothing happens, instead of tapping a ghost
          // button.
          OutlinedButton.icon(
            onPressed: OpenAiClient.isAvailable ? onGenerate : null,
            icon: const Icon(Icons.auto_awesome_outlined, size: 18),
            label: Text(_generateLabel),
          ),
          if (!OpenAiClient.isAvailable)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Sign in to use AI scaffolding.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ]
        else
          Column(
            children: [
              for (final b in blocks)
                _ItineraryRow(
                  block: b,
                  onRemove: () => onRemoveBlock(b.id),
                ),
            ],
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

class _ItineraryRow extends StatelessWidget {
  const _ItineraryRow({
    required this.block,
    required this.onRemove,
  });

  final ItineraryBlock block;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time column — fixed-width so titles align even when
          // the times vary in length (8:00 vs 11:30).
          SizedBox(
            width: 56,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                block.time.format(context),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          // Title + description column.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  block.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                if (block.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      block.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Remove — small, low contrast.
          IconButton(
            tooltip: 'Remove block',
            icon: Icon(
              Icons.close,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// Drop bar (LLM create)
// ═════════════════════════════════════════════════════════════════

/// One-line natural-language input that turns short fragments
/// like "field trip aquarium next tuesday 8 to 3" into a preview
/// tile. Two visual states stack vertically:
///
///   1. The TEXT INPUT row — always visible (when [enabled]).
///      Disabled with a hint when no Supabase session is signed
///      in (the proxy needs a JWT) or no group is selected (a
///      tile must belong to a group).
///   2. The PREVIEW row — appears below the input when the LLM
///      returns a draft. Shows the parsed tile with confirm /
///      tweak / dismiss controls.
class _DropBar extends StatefulWidget {
  const _DropBar({
    required this.enabled,
    required this.loading,
    required this.draft,
    required this.error,
    required this.onSubmit,
    required this.onConfirm,
    required this.onTweak,
    required this.onDismiss,
  });

  final bool enabled;
  final bool loading;
  final CalendarTileDraft? draft;
  final String? error;
  final ValueChanged<String> onSubmit;
  final VoidCallback onConfirm;
  final VoidCallback onTweak;
  final VoidCallback onDismiss;

  @override
  State<_DropBar> createState() => _DropBarState();
}

class _DropBarState extends State<_DropBar> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty || widget.loading) return;
    widget.onSubmit(text);
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = widget.draft;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      // Bottom-anchored chat-style bar — preview chip + error
      // stack ABOVE the input so a draft floats in just above
      // the field where the teacher's eye already is. SafeArea
      // protects the bottom system gesture, and the surrounding
      // body's `resizeToAvoidBottomInset` (Scaffold default) lifts
      // the whole bar above the keyboard when it opens.
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Preview row — visible when the model returned a
              // draft. Floats above the input.
              if (draft != null) ...[
                _DraftPreview(
                  draft: draft,
                  onConfirm: widget.onConfirm,
                  onTweak: widget.onTweak,
                  onDismiss: widget.onDismiss,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              // Error row — short red note when the LLM call failed.
              if (widget.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    widget.error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              // Input row — at the bottom, thumb-reach.
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 18,
                    color: widget.enabled
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      enabled: widget.enabled && !widget.loading,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: widget.enabled
                            ? '"field trip aquarium next tues 8 to 3"'
                            : 'Sign in + pick a group to use AI create',
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  if (widget.loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      tooltip: 'Send',
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: widget.enabled ? _submit : null,
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

class _DraftPreview extends StatelessWidget {
  const _DraftPreview({
    required this.draft,
    required this.onConfirm,
    required this.onTweak,
    required this.onDismiss,
  });

  final CalendarTileDraft draft;
  final VoidCallback onConfirm;
  final VoidCallback onTweak;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentFor(theme, draft.type);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(draft.type.icon, color: accent, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${draft.type.singularLabel.toUpperCase()} · ${draft.title}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  draft.summaryFor(context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Buttons — confirm / tweak / dismiss.
          IconButton(
            tooltip: 'Tweak before adding',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: onTweak,
          ),
          IconButton(
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDismiss,
          ),
          FilledButton.icon(
            onPressed: onConfirm,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
