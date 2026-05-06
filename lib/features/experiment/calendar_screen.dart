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
import 'package:basecamp/features/children/children_repository.dart'
    show groupsProvider;
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/adaptive_sheet.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// ═════════════════════════════════════════════════════════════════
// Tile model
// ═════════════════════════════════════════════════════════════════

/// Three flavors today. Each one surfaces a different field set
/// in the expand sheet, but they share the same storage shape —
/// optional fields, populated on demand. This is the "one
/// primitive with optional fields" model the brainstorm landed
/// on.
enum CalendarTileType {
  trip('Trips', Icons.directions_bus_filled_outlined, 'trip'),
  event('Events', Icons.celebration_outlined, 'event'),
  dayPlan('Day plans', Icons.wb_sunny_outlined, 'day plan');

  const CalendarTileType(this.pluralLabel, this.icon, this.singularLabel);

  final String pluralLabel;
  final IconData icon;
  final String singularLabel;
}

class _CalendarTile {
  _CalendarTile({
    required this.id,
    required this.type,
    required this.date,
    required this.groupId,
    required this.title,
  });

  final String id;
  final CalendarTileType type;
  DateTime date; // day key (UTC midnight)
  final String? groupId; // null = "all groups"
  String title;

  // Optional fields — populated by the expand sheet on demand.
  // Empty/null means "the user hasn't set this." Keeping them as
  // mutable fields (not constructor args) reflects the design:
  // create with just a title, fill in the rest when needed.
  String description = '';
  String destination = ''; // trips
  TimeOfDay? startTime; // trips, events
  TimeOfDay? endTime; // trips, events
  String theme = ''; // day plans
  String notes = ''; // any
}

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

  /// In-memory tile store. Keyed by id. Filtered for display.
  final Map<String, _CalendarTile> _tiles = <String, _CalendarTile>{};

  /// Inline-create tracking. When non-null, the matching cell
  /// renders a TextField in place of the "+ trip" affordance.
  String? _inlineCellKey;
  final TextEditingController _inlineCtrl = TextEditingController();
  final FocusNode _inlineFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _anchorMonth = DateTime(now.year, now.month);
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
    final tile = _CalendarTile(
      id: _newId(),
      type: type,
      date: _dayKey(day),
      groupId: groupId,
      title: raw,
    );
    setState(() {
      _tiles[tile.id] = tile;
      _exitInlineEdit();
    });
  }

  void _exitInlineEdit() {
    _inlineCellKey = null;
    _inlineCtrl.clear();
    if (_inlineFocus.hasFocus) _inlineFocus.unfocus();
  }

  // ——— Expand sheet ———————————————————————————————————————————

  Future<void> _openTile(_CalendarTile tile) async {
    await showAdaptiveSheet<void>(
      context: context,
      builder: (_) => _TileEditorSheet(
        tile: tile,
        onChanged: () => setState(() {}),
        onDelete: () => setState(() => _tiles.remove(tile.id)),
      ),
    );
  }

  // ——— Build ————————————————————————————————————————————————————

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupsProvider);
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
              const _DayHeaderRow(),
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
            ],
          );
        },
      ),
    );
  }

  /// Tiles visible under the current filter. "All" type shows
  /// everything for the active group; a specific type narrows
  /// to that type only.
  Map<String, List<_CalendarTile>> _visibleTiles() {
    final out = <String, List<_CalendarTile>>{};
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
  const _DayHeaderRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Container(
      color: theme.colorScheme.surfaceContainerLowest,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          for (final l in labels)
            Expanded(
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
  final Map<String, List<_CalendarTile>> tiles;
  final String? inlineCellKey;
  final TextEditingController inlineCtrl;
  final FocusNode inlineFocus;
  final CalendarTileType? activeType;
  final bool hasGroup;
  final ValueChanged<DateTime> onTapEmpty;
  final ValueChanged<DateTime> onSubmitInline;
  final VoidCallback onCancelInline;
  final ValueChanged<_CalendarTile> onTapTile;

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = anchorMonth;
    // Mon=1..Sun=7 → grid leading offset.
    final leading = (firstOfMonth.weekday - 1) % 7;
    final daysInMonth =
        DateTime(anchorMonth.year, anchorMonth.month + 1, 0).day;
    final totalCells = leading + daysInMonth;
    final rows = (totalCells / 7).ceil();
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellH = constraints.maxHeight / rows;
        return Column(
          children: [
            for (var r = 0; r < rows; r++)
              SizedBox(
                height: cellH,
                child: Row(
                  children: [
                    for (var c = 0; c < 7; c++)
                      Expanded(
                        child: _Cell(
                          day: _dayForCell(r, c, leading),
                          inMonth: _inMonth(r, c, leading, daysInMonth),
                          tiles: _tilesForCell(r, c, leading, daysInMonth),
                          isInlineEditing: _isInlineEditing(
                            r,
                            c,
                            leading,
                            daysInMonth,
                          ),
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
          ],
        );
      },
    );
  }

  DateTime _dayForCell(int r, int c, int leading) {
    final dayNumber = r * 7 + c - leading + 1;
    return DateTime(anchorMonth.year, anchorMonth.month, dayNumber);
  }

  bool _inMonth(int r, int c, int leading, int daysInMonth) {
    final dayNumber = r * 7 + c - leading + 1;
    return dayNumber >= 1 && dayNumber <= daysInMonth;
  }

  List<_CalendarTile> _tilesForCell(
    int r,
    int c,
    int leading,
    int daysInMonth,
  ) {
    if (!_inMonth(r, c, leading, daysInMonth)) return const [];
    final day = _dayForCell(r, c, leading);
    return tiles[_dayKey(day).toIso8601String()] ?? const [];
  }

  bool _isInlineEditing(int r, int c, int leading, int daysInMonth) {
    if (!_inMonth(r, c, leading, daysInMonth)) return false;
    if (inlineCellKey == null) return false;
    final day = _dayForCell(r, c, leading);
    return inlineCellKey == _dayKey(day).toIso8601String();
  }
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
  final List<_CalendarTile> tiles;
  final bool isInlineEditing;
  final TextEditingController inlineCtrl;
  final FocusNode inlineFocus;
  final CalendarTileType? activeType;
  final bool hasGroup;
  final ValueChanged<DateTime> onTapEmpty;
  final ValueChanged<DateTime> onSubmitInline;
  final VoidCallback onCancelInline;
  final ValueChanged<_CalendarTile> onTapTile;

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

  final _CalendarTile tile;
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tile.type.icon, size: 12, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  tile.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
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

  final _CalendarTile tile;
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

  List<Widget> _typeSpecificFields(ThemeData theme, _CalendarTile t) {
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
          const SizedBox(height: AppSpacing.sm),
          // Forward-look — this is where AI-scaffolded blocks
          // would live. Keeping the placeholder so the design
          // intent is visible while the panel is open.
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'AI-scaffolded schedule blocks land here once the day '
                    'plan has a theme.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
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

  final _CalendarTile tile;
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
