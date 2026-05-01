import 'dart:async';

import 'package:basecamp/features/ai/ai_activity_composer.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/adaptive_sheet.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Lab surface — **Monthly plan.** Mon–Fri grid for a single month;
/// each cell holds at most one activity (no time-of-day, no duration —
/// that's what the week plan is for).
///
/// **Why it lives in /lab and not the planning surface (yet):** this
/// is a different mental model from the week plan. Week plan = "what's
/// happening hour-by-hour"; monthly plan = "one big idea per day,
/// stretching across weeks." We're trying out the simpler model first.
/// If it sticks, it graduates and gets backed by the same template
/// store + library link the week plan uses. Until then, drafts live
/// in memory only.
///
/// **Cell shapes:**
///   * Empty cell: date number top-left, `+ / ✨` chooser centered in
///     the body. + drops a blank activity and opens the inline editor;
///     ✨ opens the shared AI activity composer.
///   * Filled cell: date number top-left, activity title (bold) + a
///     two-line description preview. Tap anywhere on the cell to open
///     the advanced editor in an adaptive sheet.
///
/// **Adjacent-month days** (the days that round out the first/last
/// week of the visible month) render muted and non-interactive — same
/// idiom as Google Calendar's monthly view.
class MonthlyPlanScreen extends StatefulWidget {
  const MonthlyPlanScreen({super.key});

  @override
  State<MonthlyPlanScreen> createState() => _MonthlyPlanScreenState();
}

class _MonthlyPlanScreenState extends State<MonthlyPlanScreen> {
  /// First-of-month for the visible month. Initialised to the current
  /// month at midnight local. Prev/next chevrons in the AppBar shift
  /// this by ±1 month.
  late DateTime _viewMonth = _firstOfMonth(DateTime.now());

  /// In-memory activities keyed by `dayKey(date)` — see [_dayKey] for
  /// why we string-key instead of DateTime-key. Sandbox only; when
  /// this graduates, swap for a Drift-backed repo.
  final Map<String, _MonthlyActivity> _activities = {};

  static DateTime _firstOfMonth(DateTime d) =>
      DateTime(d.year, d.month);

  /// String key for [_activities] map. DateTime equality on Dart
  /// includes time-of-day, so a 2026-04-30 00:00 and a 2026-04-30
  /// 12:00 hash differently. We index by yyyy-mm-dd to dodge that.
  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';

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

  /// `+` icon — manual create. Drops a blank activity at [date] and
  /// immediately opens the editor so the user can type the title
  /// without a second tap.
  Future<void> _onCreateBlank(DateTime date) async {
    final activity = _MonthlyActivity();
    setState(() => _activities[_dayKey(date)] = activity);
    await _openEditor(date, activity);
    // If the user cleared every field, treat it as a cancel: drop the
    // empty placeholder so the cell goes back to showing the chooser.
    if (activity.isEmpty) {
      setState(() => _activities.remove(_dayKey(date)));
    }
  }

  /// `✨` icon — AI create. Opens the shared composer; on a generated
  /// result, lands the activity in the cell. The composer's full
  /// AiActivity field set is kept (objectives, steps, materials, etc.)
  /// so when the editor sheet later surfaces a More-details
  /// disclosure those fields are already there.
  Future<void> _onCreateAi(DateTime date) async {
    final result = await showAiActivityComposer(context);
    if (!mounted || result == null) return;
    setState(() {
      _activities[_dayKey(date)] = _MonthlyActivity(
        title: result.title,
        description: result.description,
        objectives: result.objectives,
        steps: result.steps,
        materials: result.materials,
        link: result.link,
      );
    });
  }

  /// Opens the editor on an existing activity. Same sheet for both
  /// "fill in a fresh blank" and "edit an existing one" — the
  /// difference is just whether the fields start populated.
  Future<void> _openEditor(
    DateTime date,
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
          setState(() => _activities.remove(_dayKey(date)));
          // Fire-and-forget — caller doesn't need the pop result and
          // the surrounding callback is sync-typed.
          unawaited(Navigator.of(context).maybePop());
        },
      ),
    );
  }

  // -----------------------------------------------------------------
  // Layout
  // -----------------------------------------------------------------

  /// Build the visible weeks. Each row is Mon–Fri (5 dates). Pads with
  /// adjacent-month dates so every row is a complete week — those
  /// dates render muted in the cells.
  List<List<DateTime>> _buildWeeks() {
    final first = DateTime(_viewMonth.year, _viewMonth.month);
    final last = DateTime(_viewMonth.year, _viewMonth.month + 1, 0);

    // Monday of the week containing the 1st (could be in prior month).
    final firstMonday = first.subtract(Duration(days: first.weekday - 1));
    // Friday of the week containing the last day. weekday: 1=Mon..7=Sun.
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

  @override
  Widget build(BuildContext context) {
    final weeks = _buildWeeks();
    final monthLabel = DateFormat.yMMMM().format(_viewMonth);

    return Scaffold(
      appBar: AppBar(
        title: Text(monthLabel),
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
          // Prev/next chevrons + range label. Mirrors the week plan's
          // toolbar pattern so muscle memory transfers.
          _MonthToolbar(
            label: monthLabel,
            onPrev: () => _shiftMonth(-1),
            onNext: () => _shiftMonth(1),
            onReset: _resetToThisMonth,
          ),
          // Day-of-week header. Mon–Fri only — weekends never render.
          _DayOfWeekHeader(),
          const Divider(height: 1),
          // Grid of weeks. Expanded so it fills the remaining space;
          // each row inside is also Expanded so weeks share the
          // height evenly (so a 4-week month uses bigger cells than
          // a 6-week month — feels right for a sandbox where there's
          // never more than ~22 cells visible).
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: Column(
                children: [
                  for (final week in weeks)
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final date in week)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: _DayCell(
                                  date: date,
                                  isCurrentMonth:
                                      date.month == _viewMonth.month,
                                  activity: _activities[_dayKey(date)],
                                  onCreateBlank: () =>
                                      unawaited(_onCreateBlank(date)),
                                  onCreateAi: () =>
                                      unawaited(_onCreateAi(date)),
                                  onTap: () {
                                    final a = _activities[_dayKey(date)];
                                    if (a != null) {
                                      unawaited(_openEditor(date, a));
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

/// In-memory record. Plain class (not freezed) because the editor
/// sheet writes back field-by-field; immutability would force a
/// `copyWith` per keystroke.
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

  // Carried through from the AI composer so the sheet's More-details
  // disclosure has something to render. The cell-preview only shows
  // title + description; these are tucked away.
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
// Toolbar / header
// =====================================================================

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

class _DayOfWeekHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          for (final label in labels)
            Expanded(
              child: Center(
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
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

    // Out-of-month days render as muted, non-interactive context
    // — they exist purely to keep the grid rectangular. Same idiom
    // as Google Calendar.
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

    final cell = Material(
      color: isOutOfMonth
          ? cs.surfaceContainerLowest.withValues(alpha: 0.4)
          : cs.surface,
      shape: cellShape,
      child: InkWell(
        // Out-of-month cells aren't interactive (yet — could later
        // jump to that month). Empty in-month cells use the chooser
        // icons inline; tapping the cell body when empty is a no-op
        // so we don't accidentally create a blank.
        onTap: isOutOfMonth || !hasActivity ? null : onTap,
        customBorder: cellShape,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Date number — top-left, small, semi-bold for the
              // current day so it pops.
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
              // Body — either the activity preview, the +/✨ chooser
              // (in-month empty cells), or nothing (out-of-month).
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

    return cell;
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
            // Two-line clipped description so a long one doesn't
            // blow out the cell. The rest is reachable in the editor.
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
// Editor sheet — adaptive (bottom on mobile, side panel on web)
// =====================================================================

/// Editor for a single day's activity. Same shape as the experiment's
/// advanced editor, scoped to the monthly-plan field set: title +
/// description as the primary fields; objectives / steps / materials
/// / link tucked behind a More-details disclosure (open by default if
/// any are filled — usually true after an AI generation).
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
                      helperText: 'What you need on hand',
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

/// Same disclosure shape as the experiment screen — chevron + label
/// row, AnimatedSize'd children. Hand-rolled rather than ExpansionTile
/// so it doesn't fight the sheet's surrounding layout with default
/// dividers.
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
