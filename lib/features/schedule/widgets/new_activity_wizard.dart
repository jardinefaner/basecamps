import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:basecamp/features/forms/widgets/specialist_chip_picker.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/week_days.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/step_wizard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full-screen wizard for creating a new weekly-recurring activity
/// (aka "template"). Splits the dense edit sheet into five light pages
/// so first-timers aren't faced with a wall of inputs. Editing an
/// existing activity still uses the dense edit sheet — this wizard is
/// creation-only.
///
/// Pages:
///   1. Activity — library pick OR typed name
///   2. When — day chips + start/end times
///   3. Groups  — who it's for (optional)
///   4. Who + where — specialist + location (optional)
///   5. Range — optional date bounds
class NewActivityWizardScreen extends ConsumerStatefulWidget {
  const NewActivityWizardScreen({
    this.initialDays,
    this.initialSpecialistId,
    super.key,
  });

  final Set<int>? initialDays;

  /// Pre-selects a specialist on page 4. Used when opening the wizard
  /// from the specialist detail screen so "+ Add activity" already
  /// knows who the activity is for.
  final String? initialSpecialistId;

  @override
  ConsumerState<NewActivityWizardScreen> createState() =>
      _NewActivityWizardScreenState();
}

class _NewActivityWizardScreenState
    extends ConsumerState<NewActivityWizardScreen> {
  final _title = TextEditingController();
  final _location = TextEditingController();

  late final Set<int> _selectedDays = widget.initialDays?.toSet() ??
      <int>{clampToScheduleDay(DateTime.now().weekday)};
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 10, minute: 0);

  final Set<String> _podIds = <String>{};
  bool _allPods = true;

  late String? _specialistId = widget.initialSpecialistId;

  DateTime? _startDate;
  DateTime? _endDate;

  /// When non-null, the wizard is populated from a library item.
  ActivityLibraryData? _fromLibrary;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _title.text.trim().isNotEmpty ||
      _location.text.trim().isNotEmpty ||
      _podIds.isNotEmpty ||
      _specialistId != null ||
      _startDate != null ||
      _endDate != null ||
      _fromLibrary != null;

  // ---- page-level helpers ----

  bool get _page1Valid => _title.text.trim().isNotEmpty;

  bool get _page2Valid =>
      _selectedDays.isNotEmpty && _minutesFor(_start) < _minutesFor(_end);

  void _pickFromLibrary(ActivityLibraryData item) {
    setState(() {
      _fromLibrary = item;
      _title.text = item.title;
      if (item.location != null) _location.text = item.location!;
      if (item.specialistId != null) _specialistId = item.specialistId;
      final dur = item.defaultDurationMin;
      if (dur != null) {
        final startDt = DateTime(2000, 1, 1, _start.hour, _start.minute);
        final endDt = startDt.add(Duration(minutes: dur));
        _end = TimeOfDay(hour: endDt.hour, minute: endDt.minute);
      }
    });
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(context: context, initialTime: _start);
    if (picked == null || !mounted) return;
    final startMinutes = picked.hour * 60 + picked.minute;
    final endMinutes = _end.hour * 60 + _end.minute;
    setState(() {
      _start = picked;
      if (endMinutes <= startMinutes) {
        // Keep a positive-duration by default when the user pushes the
        // start past the end — nudge the end to +60 minutes.
        final bumped = DateTime(2000, 1, 1, picked.hour, picked.minute)
            .add(const Duration(hours: 1));
        _end = TimeOfDay(hour: bumped.hour, minute: bumped.minute);
      }
    });
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(context: context, initialTime: _end);
    if (picked != null && mounted) setState(() => _end = picked);
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _submit() async {
    final repo = ref.read(scheduleRepositoryProvider);
    // Only carry specific pod ids when the teacher actually picked some.
    // The new allGroups flag preserves the distinction between "for
    // everyone" (toggle on) and "for nobody yet" (toggle off, no pods).
    final groupIds = _allPods ? const <String>[] : _podIds.toList();
    final location = _location.text.trim().isEmpty
        ? null
        : _location.text.trim();
    // If the teacher didn't touch page 5, default to "this week only"
    // instead of weekly-forever. That matches what most one-off
    // activities actually are, and keeps the schedule from filling up
    // with perpetual rows people forget about.
    final bounds = _effectiveRange();
    // One fresh group id per wizard pass, so "delete every occurrence"
    // on any tapped day can later nuke every weekday row this submit
    // is about to create.
    final groupId = _selectedDays.length > 1 ? newId() : null;
    for (final day in _selectedDays) {
      await repo.addTemplate(
        dayOfWeek: day,
        startTime: _formatTime(_start),
        endTime: _formatTime(_end),
        title: _title.text.trim(),
        groupIds: groupIds,
        allGroups: _allPods,
        specialistId: _specialistId,
        location: location,
        startDate: bounds.start,
        endDate: bounds.end,
        groupId: groupId,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  ({DateTime? start, DateTime? end}) _effectiveRange() {
    if (_startDate != null || _endDate != null) {
      return (start: _startDate, end: _endDate);
    }
    final (monday, friday) = _currentProgramWeek();
    return (start: monday, end: friday);
  }

  (DateTime monday, DateTime friday) _currentProgramWeek() {
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);
    final monday = todayOnly.subtract(Duration(days: todayOnly.weekday - 1));
    final friday = monday.add(const Duration(days: 4));
    return (monday, friday);
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    return StepWizardScaffold(
      title: 'New activity',
      dirty: _dirty,
      finalActionLabel: _selectedDays.length > 1
          ? 'Create on ${_selectedDays.length} days'
          : 'Create activity',
      onFinalAction: _submit,
      steps: [
        WizardStep(
          headline: 'What are you scheduling?',
          subtitle: 'Pick from your library, or type a new one.',
          content: _buildActivityPage(),
          canProceed: _page1Valid,
        ),
        WizardStep(
          headline: 'When does it happen?',
          subtitle: 'Pick days of the week and a time window.',
          content: _buildWhenPage(),
          canProceed: _page2Valid,
        ),
        WizardStep(
          headline: "Who's in it?",
          subtitle: 'Leave as "All groups" if the activity is for everyone.',
          content: _buildPodsPage(),
          canSkip: true,
        ),
        WizardStep(
          headline: "Who's running it, and where?",
          subtitle: 'Assign a specialist and a location if it matters.',
          content: _buildSpecialistPage(),
          canSkip: true,
        ),
        WizardStep(
          headline: 'How long does this run?',
          subtitle:
              'Skip to keep it to this week only. Pick dates to run it '
              'longer — a camp block, a summer session, etc.',
          content: _buildRangePage(),
          canSkip: true,
        ),
      ],
    );
  }

  // ---- page 1: activity ----

  Widget _buildActivityPage() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_fromLibrary != null)
          _LibraryBanner(
            item: _fromLibrary!,
            onClear: () => setState(() {
              _fromLibrary = null;
              // Don't wipe fields — teacher may still want the text.
            }),
          )
        else ...[
          _LibraryGrid(onPick: _pickFromLibrary),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: Divider(color: theme.colorScheme.outlineVariant),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                ),
                child: Text(
                  'OR',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Expanded(
                child: Divider(color: theme.colorScheme.outlineVariant),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        AppTextField(
          controller: _title,
          label: _fromLibrary == null
              ? 'Or type an activity name'
              : 'Activity name',
          hint: 'e.g. Morning circle, Swim, Field trip',
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  // ---- page 2: when ----

  Widget _buildWhenPage() {
    final theme = Theme.of(context);
    final duration = _minutesFor(_end) - _minutesFor(_start);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Days', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (var d = 1; d <= scheduleDayCount; d++)
              FilterChip(
                label: Text(scheduleDayShortLabels[d - 1]),
                selected: _selectedDays.contains(d),
                onSelected: (_) => setState(() {
                  if (!_selectedDays.add(d)) _selectedDays.remove(d);
                }),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(
              child: _TimeTile(
                label: 'Starts',
                time: _start,
                onTap: _pickStart,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _TimeTile(
                label: 'Ends',
                time: _end,
                onTap: _pickEnd,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(
                Icons.schedule_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _selectedDays.isEmpty
                      ? 'Pick at least one day'
                      : _buildWhenPreview(duration),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _buildWhenPreview(int durationMins) {
    final days = _selectedDays.toList()..sort();
    final dayStr = days.length == 1
        ? scheduleDayLabels[days.first - 1]
        : days.map((d) => scheduleDayShortLabels[d - 1]).join(' · ');
    final timeStr = '${_formatClock(_start)} – ${_formatClock(_end)}';
    if (durationMins <= 0) {
      return '$dayStr · $timeStr (end must be after start)';
    }
    final hours = durationMins ~/ 60;
    final mins = durationMins % 60;
    final lenStr = hours == 0
        ? '$mins min'
        : (mins == 0 ? '${hours}h' : '${hours}h ${mins}m');
    return '$dayStr · $timeStr · $lenStr';
  }

  // ---- page 3: pods ----

  Widget _buildPodsPage() {
    final theme = Theme.of(context);
    final podsAsync = ref.watch(groupsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          title: const Text('All groups'),
          subtitle: const Text(
            'Everyone at the program is included',
          ),
          value: _allPods,
          onChanged: (v) => setState(() {
            _allPods = v;
            if (v) _podIds.clear();
          }),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: AppSpacing.md),
        if (!_allPods)
          podsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (err, _) => Text('Error: $err'),
            data: (pods) {
              if (pods.isEmpty) {
                return Text(
                  'No groups yet — add some from the Children tab, or stay on "All groups".',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              }
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final pod in pods)
                    FilterChip(
                      label: Text(pod.name),
                      selected: _podIds.contains(pod.id),
                      onSelected: (_) => setState(() {
                        if (!_podIds.add(pod.id)) _podIds.remove(pod.id);
                      }),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  // ---- page 4: specialist + location ----

  Widget _buildSpecialistPage() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Specialist', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        SpecialistChipPicker(
          selectedId: _specialistId,
          onChanged: (id) => setState(() => _specialistId = id),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppTextField(
          controller: _location,
          label: 'Location',
          hint: 'Room, gym, field, etc.',
        ),
      ],
    );
  }

  // ---- page 5: date range ----

  Widget _buildRangePage() {
    final bounds = _effectiveRange();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _DateTile(
                label: 'Starts',
                value: _startDate,
                onTap: _pickStartDate,
                onClear: _startDate == null
                    ? null
                    : () => setState(() => _startDate = null),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _DateTile(
                label: 'Ends',
                value: _endDate,
                onTap: _pickEndDate,
                onClear: _endDate == null
                    ? null
                    : () => setState(() => _endDate = null),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _RangePreview(
          startDate: bounds.start,
          endDate: bounds.end,
          days: _selectedDays,
          isDefault: _startDate == null && _endDate == null,
        ),
      ],
    );
  }

  // ---- utils ----

  int _minutesFor(TimeOfDay t) => t.hour * 60 + t.minute;

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _formatClock(TimeOfDay t) {
    final hour12 = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    final period = t.hour < 12 ? 'a' : 'p';
    final mins = t.minute.toString().padLeft(2, '0');
    return '$hour12:$mins$period';
  }
}

// ---------- page 1 helpers ----------

class _LibraryGrid extends ConsumerWidget {
  const _LibraryGrid({required this.onPick});

  final ValueChanged<ActivityLibraryData> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final itemsAsync = ref.watch(activityLibraryProvider);

    return itemsAsync.when(
      loading: () => const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Text('Error: $err'),
      data: (items) {
        if (items.isEmpty) {
          return _LibraryEmpty();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'FROM LIBRARY',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0.8,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final item in items)
                  ActionChip(
                    avatar: const Icon(Icons.bookmark_outlined, size: 16),
                    label: Text(item.title),
                    onPressed: () => onPick(item),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _LibraryEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.bookmarks_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Your activity library is empty. Type a name below, or add '
              'reusable activities in More → Activity library.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryBanner extends StatelessWidget {
  const _LibraryBanner({required this.item, required this.onClear});

  final ActivityLibraryData item;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.bookmark_outlined,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'From library',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                Text(
                  item.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Unlink',
            icon: Icon(
              Icons.close,
              size: 18,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}

// ---------- page 2 helpers ----------

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.label,
    required this.time,
    required this.onTap,
  });

  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              time.format(context),
              style: theme.textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- page 5 helpers ----------

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value == null ? 'Pick a date' : _formatDate(value!),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: value == null
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            if (onClear != null)
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClear,
              ),
          ],
        ),
      ),
    );
  }
}

class _RangePreview extends StatelessWidget {
  const _RangePreview({
    required this.startDate,
    required this.endDate,
    required this.days,
    required this.isDefault,
  });

  final DateTime? startDate;
  final DateTime? endDate;
  final Set<int> days;

  /// True when the teacher skipped the range step entirely — the dates
  /// come from the "this week only" fallback rather than their pick.
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = _countOccurrences();
    final bounds = _describeBounds();
    final label = isDefault ? 'This week only · $bounds' : bounds;
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(
            isDefault
                ? Icons.calendar_today_outlined
                : Icons.event_repeat_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              count == null
                  ? label
                  : '$label · ${count == 1 ? "1 occurrence" : "$count occurrences"}',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _describeBounds() {
    if (startDate != null && endDate != null) {
      return '${_formatDate(startDate!)} → ${_formatDate(endDate!)}';
    }
    if (startDate != null) return 'Starts ${_formatDate(startDate!)}';
    if (endDate != null) return 'Ends ${_formatDate(endDate!)}';
    return 'No dates set';
  }

  /// Count the actual dates in the range that match the selected days.
  /// Returns null when either bound is open-ended.
  int? _countOccurrences() {
    if (startDate == null || endDate == null || days.isEmpty) return null;
    final start = DateTime(startDate!.year, startDate!.month, startDate!.day);
    final end = DateTime(endDate!.year, endDate!.month, endDate!.day);
    if (end.isBefore(start)) return 0;
    var count = 0;
    for (var d = start;
        !d.isAfter(end);
        d = d.add(const Duration(days: 1))) {
      if (days.contains(d.weekday)) count++;
    }
    return count;
  }
}

String _formatDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}
