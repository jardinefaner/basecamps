import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/activity_library/widgets/library_picker_sheet.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/week_days.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/confirm_dialog.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

const _dayShortLabels = ['M', 'T', 'W', 'T', 'F'];

class EditTemplateSheet extends ConsumerStatefulWidget {
  const EditTemplateSheet({
    super.key,
    this.template,
    this.initialDays,
    this.occurrenceDate,
  });

  final ScheduleTemplate? template;
  final Set<int>? initialDays;

  /// The concrete date the teacher tapped to open this sheet. When
  /// set, the delete flow offers "Delete this day only" (adds a
  /// cancellation entry for just that date) alongside the usual
  /// "Delete every occurrence". Null for new-template creation and
  /// any caller that doesn't have a date in context.
  final DateTime? occurrenceDate;

  @override
  ConsumerState<EditTemplateSheet> createState() => _EditTemplateSheetState();
}

class _EditTemplateSheetState extends ConsumerState<EditTemplateSheet> {
  late final _titleController =
      TextEditingController(text: widget.template?.title ?? '');
  late final _locationController =
      TextEditingController(text: widget.template?.location ?? '');
  late String? _specialistId = widget.template?.specialistId;

  late final Set<int> _selectedDays = widget.template != null
      ? {widget.template!.dayOfWeek}
      : (widget.initialDays ??
          {clampToScheduleDay(DateTime.now().weekday)});

  late TimeOfDay _start = widget.template != null
      ? _parseTime(widget.template!.startTime)
      : const TimeOfDay(hour: 9, minute: 0);
  late TimeOfDay _end = widget.template != null
      ? _parseTime(widget.template!.endTime)
      : const TimeOfDay(hour: 10, minute: 0);
  late DateTime? _rangeStart = widget.template?.startDate;
  late DateTime? _rangeEnd = widget.template?.endDate;

  /// Non-empty = specific pods. When empty, [_allPods] disambiguates
  /// between "for everyone" (true) and "no pods picked yet" (false).
  final Set<String> _selectedPodIds = <String>{};
  late bool _allPods = widget.template?.allGroups ?? true;
  bool _podsLoaded = false;

  bool _submitting = false;
  bool _didAutofillStart = false;

  bool get _isEdit => widget.template != null;

  static TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
  }

  static String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPods());
    } else {
      _podsLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutofillStart());
    }
  }

  /// Set of pod ids the template started with — snapshot captured
  /// right after [_loadPods] so we can tell a pristine edit from one
  /// where the teacher actually toggled something.
  Set<String> _podsBaseline = const <String>{};
  late final bool _allPodsBaseline = widget.template?.allGroups ?? true;

  Future<void> _loadPods() async {
    if (!_isEdit) return;
    final pods = await ref
        .read(scheduleRepositoryProvider)
        .podsForTemplate(widget.template!.id);
    if (!mounted) return;
    setState(() {
      _selectedPodIds.addAll(pods);
      _podsBaseline = Set<String>.from(pods);
      _podsLoaded = true;
    });
  }

  Future<void> _tryAutofillStart() async {
    if (_didAutofillStart) return;
    _didAutofillStart = true;
    final primaryDay = _selectedDays.first;
    final last = await ref
        .read(scheduleRepositoryProvider)
        .latestEndTimeForDay(primaryDay);
    if (last == null || !mounted) return;
    final newStart = _parseTime(last);
    if (_start.hour == 9 && _start.minute == 0) {
      setState(() {
        _start = newStart;
        final endDt = DateTime(2000, 1, 1, newStart.hour, newStart.minute)
            .add(const Duration(hours: 1));
        _end = TimeOfDay(hour: endDt.hour, minute: endDt.minute);
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _titleController.text.trim().isNotEmpty && _selectedDays.isNotEmpty;

  bool get _hasChanges {
    final template = widget.template;
    if (template == null) return true;
    String? trimOrNull(String s) => s.trim().isEmpty ? null : s.trim();
    if (_titleController.text.trim() != template.title) return true;
    if (_selectedDays.length != 1 ||
        _selectedDays.first != template.dayOfWeek) {
      return true;
    }
    if (_formatTime(_start) != template.startTime) return true;
    if (_formatTime(_end) != template.endTime) return true;
    if (_specialistId != template.specialistId) return true;
    if (trimOrNull(_locationController.text) != template.location) return true;
    if (_rangeStart != template.startDate) return true;
    if (_rangeEnd != template.endDate) return true;
    if (!_podsLoaded) return false;
    if (_selectedPodIds.length != _podsBaseline.length) return true;
    if (!_selectedPodIds.containsAll(_podsBaseline)) return true;
    if (_allPods != _allPodsBaseline) return true;
    return false;
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(context: context, initialTime: _start);
    if (picked != null) setState(() => _start = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(context: context, initialTime: _end);
    if (picked != null) setState(() => _end = picked);
  }

  Future<void> _submit() async {
    if (!_isValid) return;
    setState(() => _submitting = true);
    final repo = ref.read(scheduleRepositoryProvider);
    final title = _titleController.text.trim();
    final location = _locationController.text.trim().isEmpty
        ? null
        : _locationController.text.trim();
    final startHhmm = _formatTime(_start);
    final endHhmm = _formatTime(_end);
    final groupIds = _selectedPodIds.toList();

    if (_isEdit) {
      await repo.updateTemplate(
        id: widget.template!.id,
        dayOfWeek: _selectedDays.first,
        startTime: startHhmm,
        endTime: endHhmm,
        title: title,
        groupIds: groupIds,
        allGroups: _allPods,
        specialistId: _specialistId,
        location: location,
        startDate: _rangeStart,
        endDate: _rangeEnd,
      );
    } else {
      for (final day in _selectedDays) {
        await repo.addTemplate(
          dayOfWeek: day,
          startTime: startHhmm,
          endTime: endHhmm,
          title: title,
          groupIds: groupIds,
          allGroups: _allPods,
          specialistId: _specialistId,
          location: location,
          startDate: _rangeStart,
          endDate: _rangeEnd,
        );
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (!_isEdit) return;
    final template = widget.template!;
    final occ = widget.occurrenceDate;
    final repo = ref.read(scheduleRepositoryProvider);

    // Two-path flow when we know the specific date the teacher tapped:
    // "this day only" writes a cancellation entry for that date;
    // "every occurrence" nukes the whole template. No-date callers
    // (e.g. opening from an empty state) fall back to the single
    // all-or-nothing dialog.
    if (occ != null) {
      final groupCount = await repo.countTemplatesInGroupFor(template.id);
      if (!mounted) return;
      final choice = await showModalBottomSheet<_DeleteChoice>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => _DeleteOptionsSheet(
          title: template.title,
          occurrenceDate: occ,
          groupCount: groupCount,
        ),
      );
      if (choice == null) return;
      if (choice == _DeleteChoice.thisDay) {
        await repo.cancelTemplateForDate(
          templateId: template.id,
          date: occ,
        );
      } else {
        await repo.deleteTemplateGroupFor(template.id);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }

    final count = await repo.countTemplatesInGroupFor(template.id);
    if (!mounted) return;
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Delete every occurrence?',
      message: count > 1
          ? 'This removes "${template.title}" from all $count days '
              'it runs (every week within any date range set). '
              'Cannot be undone.'
          : 'This removes "${template.title}" from every day it '
              'runs — every week within its date range (or forever '
              'if no range is set). Cannot be undone.',
      confirmLabel: 'Delete all',
    );
    if (!confirmed) return;
    await repo.deleteTemplateGroupFor(template.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _applyDurationPreset(Duration duration) {
    final startDt = DateTime(2000, 1, 1, _start.hour, _start.minute);
    final endDt = startDt.add(duration);
    setState(() {
      _end = TimeOfDay(hour: endDt.hour, minute: endDt.minute);
    });
  }

  Future<void> _pickRangeStart() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _rangeStart ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) setState(() => _rangeStart = picked);
  }

  Future<void> _pickRangeEnd() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _rangeEnd ?? _rangeStart ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) setState(() => _rangeEnd = picked);
  }

  Future<void> _openLibrary() async {
    final picked = await showModalBottomSheet<ActivityLibraryData>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const LibraryPickerSheet(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _titleController.text = picked.title;
      if (picked.location != null) {
        _locationController.text = picked.location!;
      }
      if (picked.specialistId != null) {
        _specialistId = picked.specialistId;
      }
      final dur = picked.defaultDurationMin;
      if (dur != null) {
        final startDt = DateTime(2000, 1, 1, _start.hour, _start.minute);
        final endDt = startDt.add(Duration(minutes: dur));
        _end = TimeOfDay(hour: endDt.hour, minute: endDt.minute);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final podsAsync = ref.watch(groupsProvider);

    return StickyActionSheet(
      title: _isEdit ? 'Edit activity' : 'New activity',
      titleTrailing: _isEdit
          ? IconButton(
              onPressed: _delete,
              tooltip: 'Delete every occurrence',
              icon: Icon(
                Icons.delete_sweep_outlined,
                color: theme.colorScheme.error,
              ),
            )
          : null,
      actionBar: AppButton.primary(
        onPressed:
            _isValid && (!_isEdit || _hasChanges) ? _submit : null,
        label: _isEdit
            ? 'Save'
            : _selectedDays.length > 1
                ? 'Add to ${_selectedDays.length} days'
                : 'Add activity',
        isLoading: _submitting,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_isEdit) ...[
            OutlinedButton.icon(
              onPressed: _openLibrary,
              icon: const Icon(Icons.bookmark_outline, size: 18),
              label: const Text('From library...'),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          AppTextField(
            controller: _titleController,
            label: 'Activity',
            hint: 'e.g. Art · Swim · Field trip',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          _DayPicker(
            selected: _selectedDays,
            singleSelect: _isEdit,
            onToggle: (day) => setState(() {
              if (_isEdit) {
                _selectedDays
                  ..clear()
                  ..add(day);
              } else if (!_selectedDays.add(day)) {
                if (_selectedDays.length > 1) _selectedDays.remove(day);
              }
            }),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _TimeField(
                  label: 'Start',
                  time: _start,
                  onPressed: _pickStart,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _TimeField(
                  label: 'End',
                  time: _end,
                  onPressed: _pickEnd,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              _DurationChip(
                label: '30m',
                onTap: () =>
                    _applyDurationPreset(const Duration(minutes: 30)),
              ),
              _DurationChip(
                label: '1h',
                onTap: () => _applyDurationPreset(const Duration(hours: 1)),
              ),
              _DurationChip(
                label: '90m',
                onTap: () =>
                    _applyDurationPreset(const Duration(minutes: 90)),
              ),
              _DurationChip(
                label: '2h',
                onTap: () => _applyDurationPreset(const Duration(hours: 2)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Groups', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          podsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (err, _) => Text('Error: $err'),
            data: (pods) {
              if (!_podsLoaded) return const LinearProgressIndicator();
              return _PodSelector(
                pods: pods,
                selectedPodIds: _selectedPodIds,
                allGroups: _allPods,
                onAllToggle: () => setState(() {
                  _allPods = true;
                  _selectedPodIds.clear();
                }),
                onPodToggle: (id) => setState(() {
                  if (!_selectedPodIds.add(id)) {
                    _selectedPodIds.remove(id);
                  }
                  // Any specific pick means "not all pods". Deselecting
                  // the last one leaves the empty-allGroups=false state,
                  // which readers will treat as "no kids".
                  _allPods = false;
                }),
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          _SpecialistPicker(
            selectedId: _specialistId,
            onChanged: (id) => setState(() => _specialistId = id),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _locationController,
            label: 'Location (optional)',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          _DateRangeSection(
            rangeStart: _rangeStart,
            rangeEnd: _rangeEnd,
            onPickStart: _pickRangeStart,
            onPickEnd: _pickRangeEnd,
            onClearStart: () => setState(() => _rangeStart = null),
            onClearEnd: () => setState(() => _rangeEnd = null),
          ),
        ],
      ),
    );
  }
}

class _PodSelector extends StatelessWidget {
  const _PodSelector({
    required this.pods,
    required this.selectedPodIds,
    required this.allGroups,
    required this.onAllToggle,
    required this.onPodToggle,
  });

  final List<Group> pods;
  final Set<String> selectedPodIds;
  final bool allGroups;
  final VoidCallback onAllToggle;
  final ValueChanged<String> onPodToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (pods.isEmpty) {
      return Text(
        'No groups yet — add some in the Children tab.',
        style: theme.textTheme.bodySmall,
      );
    }
    final noneChosen = selectedPodIds.isEmpty && !allGroups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilterChip(
              label: const Text('All groups'),
              selected: allGroups && selectedPodIds.isEmpty,
              onSelected: (_) => onAllToggle(),
            ),
            for (final pod in pods)
              FilterChip(
                label: Text(pod.name),
                selected: selectedPodIds.contains(pod.id),
                onSelected: (_) => onPodToggle(pod.id),
              ),
          ],
        ),
        if (noneChosen) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No groups selected — no children will be included in this activity.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}

class _DayPicker extends StatelessWidget {
  const _DayPicker({
    required this.selected,
    required this.onToggle,
    required this.singleSelect,
  });

  final Set<int> selected;
  final ValueChanged<int> onToggle;
  final bool singleSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          singleSelect ? 'Day' : 'Days',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            for (var day = 1; day <= scheduleDayCount; day++) ...[
              _DayChip(
                label: _dayShortLabels[day - 1],
                selected: selected.contains(day),
                onTap: () => onToggle(day),
              ),
              if (day < scheduleDayCount)
                const SizedBox(width: AppSpacing.xs),
            ],
          ],
        ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainer;
    final fg = selected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
              width: 0.5,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              color: fg,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.time,
    required this.onPressed,
  });

  final String label;
  final TimeOfDay time;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.schedule_outlined),
          label: Text(time.format(context)),
        ),
      ],
    );
  }
}

class _SpecialistPicker extends ConsumerWidget {
  const _SpecialistPicker({
    required this.selectedId,
    required this.onChanged,
  });

  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final specialistsAsync = ref.watch(specialistsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Specialist', style: theme.textTheme.titleSmall),
            ),
            TextButton.icon(
              onPressed: () => context.push('/more/specialists'),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Manage'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        specialistsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (err, _) => Text('Error: $err'),
          data: (specialists) {
            if (specialists.isEmpty) {
              return Text(
                'No specialists yet — add one in More → Specialists.',
                style: theme.textTheme.bodySmall,
              );
            }
            return DropdownButtonFormField<String?>(
              initialValue: selectedId,
              items: [
                const DropdownMenuItem<String?>(child: Text('None')),
                for (final s in specialists)
                  DropdownMenuItem(
                    value: s.id,
                    child: Text(
                      s.role == null || s.role!.isEmpty
                          ? s.name
                          : '${s.name} · ${s.role}',
                    ),
                  ),
              ],
              onChanged: onChanged,
            );
          },
        ),
      ],
    );
  }
}

class _DateRangeSection extends StatelessWidget {
  const _DateRangeSection({
    required this.rangeStart,
    required this.rangeEnd,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onClearStart,
    required this.onClearEnd,
  });

  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onClearStart;
  final VoidCallback onClearEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Date range (optional)',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Limits when this recurring activity is active. Leave blank for no bounds.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _DateField(
                label: 'Starts on',
                date: rangeStart,
                placeholder: 'Any time',
                onPick: onPickStart,
                onClear: rangeStart == null ? null : onClearStart,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _DateField(
                label: 'Ends on',
                date: rangeEnd,
                placeholder: 'Any time',
                onPick: onPickEnd,
                onClear: rangeEnd == null ? null : onClearEnd,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.placeholder,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final DateTime? date;
  final String placeholder;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatted =
        date == null ? placeholder : DateFormat.MMMd().format(date!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(
                  formatted,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (onClear != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Clear',
                onPressed: onClear,
              ),
          ],
        ),
      ],
    );
  }
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}

enum _DeleteChoice { thisDay, allDays }

/// Two-option chooser for deleting a template-sourced activity — one
/// day vs every occurrence. Pops with the chosen value or null on
/// dismiss.
class _DeleteOptionsSheet extends StatelessWidget {
  const _DeleteOptionsSheet({
    required this.title,
    required this.occurrenceDate,
    required this.groupCount,
  });

  final String title;
  final DateTime occurrenceDate;

  /// Total number of template rows that share this activity — shown
  /// in the subtitle so the teacher knows the tap-to-confirm blast
  /// radius before committing.
  final int groupCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel = DateFormat.yMMMMEEEEd().format(occurrenceDate);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                'Delete "$title"',
                style: theme.textTheme.titleMedium,
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_busy_outlined),
              title: const Text('Delete this day only'),
              subtitle: Text(
                'Skip $dateLabel. The activity still runs on every '
                'other day it normally would.',
              ),
              onTap: () =>
                  Navigator.of(context).pop(_DeleteChoice.thisDay),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.delete_sweep_outlined,
                color: theme.colorScheme.error,
              ),
              title: Text(
                groupCount > 1
                    ? 'Delete all $groupCount days'
                    : 'Delete every occurrence',
              ),
              subtitle: Text(
                groupCount > 1
                    ? 'Removes "$title" from every weekday it runs — all '
                        '$groupCount days, every week within any date '
                        'range set.'
                    : 'Remove from every day it runs — every week within '
                        'its date range (or forever if no range is set).',
              ),
              onTap: () =>
                  Navigator.of(context).pop(_DeleteChoice.allDays),
            ),
          ],
        ),
      ),
    );
  }
}
