import 'dart:async';

import 'package:basecamp/database/database.dart' show Group;
import 'package:basecamp/features/ai/ai_activity_composer.dart';
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

  /// Activities keyed by `"$groupId|$dayKey"`. Group-scoped so each
  /// group can author its own month independently in the same UI.
  final Map<String, _MonthlyActivity> _activities = {};

  /// Sub-theme strings keyed by `weekMondayDayKey`. NOT group-scoped —
  /// the sub-theme is a thematic label for the week as a whole and
  /// shared across groups (a "Colors" week means colors for everyone).
  /// If usage shows that's wrong, easy to scope per-group later.
  final Map<String, String> _subThemes = {};

  static DateTime _firstOfMonth(DateTime d) =>
      DateTime(d.year, d.month);

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';

  String _activityKey(DateTime d, String groupId) =>
      '$groupId|${_dayKey(d)}';

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

  Future<void> _onCreateBlank(DateTime date) async {
    final groupId = _activeGroupId;
    if (groupId == null) return;
    final activity = _MonthlyActivity();
    final key = _activityKey(date, groupId);
    setState(() => _activities[key] = activity);
    // New blank → editor immediately so the user can type the title
    // without an extra tap. (Different from filled-cell tap, which
    // routes to the formatted view first.)
    await _openEditor(date, groupId, activity);
    if (activity.isEmpty && mounted) {
      // Treat "closed without typing" as a cancel.
      setState(() => _activities.remove(key));
    }
  }

  Future<void> _onCreateAi(DateTime date) async {
    final groupId = _activeGroupId;
    if (groupId == null) return;
    final result = await showAiActivityComposer(context);
    if (!mounted || result == null) return;
    setState(() {
      _activities[_activityKey(date, groupId)] = _MonthlyActivity(
        title: result.title,
        description: result.description,
        objectives: result.objectives,
        steps: result.steps,
        materials: result.materials,
        link: result.link,
      );
    });
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
      final activity = _activities[_activityKey(date, groupId)];
      if (activity == null) continue;
      for (final raw in activity.materials.split(',')) {
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

    return Scaffold(
      appBar: AppBar(
        // Stable title — month navigation lives in the toolbar below.
        title: const Text('Monthly Plan'),
        actions: [
          IconButton(
            tooltip: 'This month',
            icon: const Icon(Icons.today_outlined),
            onPressed: _resetToThisMonth,
          ),
        ],
      ),
      body: Column(
        children: [
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
              // Default-select the first group once they load.
              if (_activeGroupId == null ||
                  !groups.any((g) => g.id == _activeGroupId)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() => _activeGroupId = groups.first.id);
                });
              }
              return _GroupFilterBar(
                groups: groups,
                activeId: _activeGroupId,
                onSelect: (id) => setState(() => _activeGroupId = id),
              );
            },
          ),
          _MonthToolbar(
            label: monthLabel,
            onPrev: () => _shiftMonth(-1),
            onNext: () => _shiftMonth(1),
            onReset: _resetToThisMonth,
          ),
          _GridHeader(),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: _activeGroupId == null
                  ? const SizedBox.shrink()
                  : Column(
                      children: [
                        for (final week in weeks)
                          Expanded(
                            child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                              children: [
                                // Side rail: sub-theme + aggregated
                                // materials for this week. flex 3 so
                                // the column has enough breathing
                                // room for materials lists; day cells
                                // use flex 4 each.
                                Expanded(
                                  flex: 3,
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
                                    ),
                                  ),
                                ),
                                for (final date in week)
                                  Expanded(
                                    flex: 4,
                                    child: Padding(
                                      padding: const EdgeInsets.all(2),
                                      child: _DayCell(
                                        date: date,
                                        isCurrentMonth: date.month ==
                                            _viewMonth.month,
                                        activity: _activities[
                                            _activityKey(
                                          date,
                                          _activeGroupId!,
                                        )],
                                        onCreateBlank: () => unawaited(
                                          _onCreateBlank(date),
                                        ),
                                        onCreateAi: () =>
                                            unawaited(_onCreateAi(date)),
                                        onTap: () {
                                          final a = _activities[
                                              _activityKey(
                                            date,
                                            _activeGroupId!,
                                          )];
                                          if (a != null && !a.isEmpty) {
                                            unawaited(_onTapFilled(date, a));
                                          }
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
}

// =====================================================================
// Top bars
// =====================================================================

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
                  label: Text(g.name),
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

class _MonthToolbar extends StatelessWidget {
  const _MonthToolbar({
    required this.label,
    required this.onPrev,
    required this.onNext,
    required this.onReset,
  });

  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              icon: const Icon(Icons.chevron_left),
              onPressed: onPrev,
            ),
            Expanded(
              child: Center(
                child: TextButton(
                  onPressed: onReset,
                  child: Text(
                    label,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              icon: const Icon(Icons.chevron_right),
              onPressed: onNext,
            ),
          ],
        ),
      ),
    );
  }
}

class _GridHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          // Side-rail header — empty title, just visual placeholder
          // so the column widths align with the body grid below.
          Expanded(
            flex: 3,
            child: Center(
              child: Text('Theme · Supplies', style: labelStyle),
            ),
          ),
          for (final label in labels)
            Expanded(
              flex: 4,
              child: Center(child: Text(label, style: labelStyle)),
            ),
        ],
      ),
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
  });

  final String weekMondayKey;
  final String subTheme;
  final ValueChanged<String> onSubThemeChanged;
  final List<String> materials;

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
            // Aggregated supplies — bulleted list scrolled inside the
            // remaining cell height. Empty state stays muted.
            Expanded(
              child: widget.materials.isEmpty
                  ? Text(
                      '—',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final m in widget.materials)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 1),
                              child: Text(
                                '• $m',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// Day cell
// =====================================================================

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.isCurrentMonth,
    required this.activity,
    required this.onCreateBlank,
    required this.onCreateAi,
    required this.onTap,
  });

  final DateTime date;
  final bool isCurrentMonth;
  final _MonthlyActivity? activity;
  final VoidCallback onCreateBlank;
  final VoidCallback onCreateAi;
  final VoidCallback onTap;

  bool get _isToday {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final hasActivity = activity != null && !activity!.isEmpty;
    final isOutOfMonth = !isCurrentMonth;

    final dateColor = isOutOfMonth
        ? cs.onSurfaceVariant.withValues(alpha: 0.4)
        : (_isToday ? cs.primary : cs.onSurfaceVariant);

    final cellShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(
        color: _isToday
            ? cs.primary.withValues(alpha: 0.5)
            : cs.outlineVariant.withValues(alpha: 0.6),
        width: _isToday ? 1 : 0.5,
      ),
    );

    return Material(
      color: isOutOfMonth
          ? cs.surfaceContainerLowest.withValues(alpha: 0.4)
          : cs.surface,
      shape: cellShape,
      child: InkWell(
        onTap: isOutOfMonth || !hasActivity ? null : onTap,
        customBorder: cellShape,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 2, top: 2),
                child: Row(
                  children: [
                    Text(
                      '${date.day}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: dateColor,
                        fontWeight: _isToday
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Expanded(
                child: isOutOfMonth
                    ? const SizedBox.shrink()
                    : (hasActivity
                        ? _CellPreview(activity: activity!)
                        : _CellChooser(
                            onCreateBlank: onCreateBlank,
                            onCreateAi: onCreateAi,
                          )),
              ),
            ],
          ),
        ),
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (activity.title.isNotEmpty)
            Text(
              activity.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          if (activity.description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Expanded(
              child: Text(
                activity.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
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

class _CellChooser extends StatelessWidget {
  const _CellChooser({
    required this.onCreateBlank,
    required this.onCreateAi,
  });

  final VoidCallback onCreateBlank;
  final VoidCallback onCreateAi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ChooserIcon(
            icon: Icons.add,
            background: cs.surface,
            foreground: cs.onSurface,
            borderColor: cs.outlineVariant,
            onTap: onCreateBlank,
          ),
          const SizedBox(width: 4),
          _ChooserIcon(
            icon: Icons.auto_awesome_outlined,
            background: cs.primaryContainer,
            foreground: cs.onPrimaryContainer,
            borderColor: cs.primary.withValues(alpha: 0.4),
            onTap: onCreateAi,
          ),
        ],
      ),
    );
  }
}

class _ChooserIcon extends StatelessWidget {
  const _ChooserIcon({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.borderColor,
    required this.onTap,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final Color borderColor;
  final VoidCallback onTap;

  static const double _size = 26;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_size / 2),
        side: BorderSide(color: borderColor, width: 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(_size / 2),
        onTap: onTap,
        child: SizedBox(
          width: _size,
          height: _size,
          child: Icon(icon, size: 14, color: foreground),
        ),
      ),
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
    required this.onEdit,
    required this.onDelete,
  });

  final DateTime date;
  final _MonthlyActivity activity;
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
    required this.onChanged,
    required this.onDelete,
  });

  final DateTime date;
  final _MonthlyActivity activity;
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
