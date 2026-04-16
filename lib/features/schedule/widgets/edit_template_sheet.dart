import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _dayShortLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

class EditTemplateSheet extends ConsumerStatefulWidget {
  const EditTemplateSheet({super.key, this.template, this.initialDays});

  final ScheduleTemplate? template;
  final Set<int>? initialDays;

  @override
  ConsumerState<EditTemplateSheet> createState() => _EditTemplateSheetState();
}

class _EditTemplateSheetState extends ConsumerState<EditTemplateSheet> {
  late final _titleController =
      TextEditingController(text: widget.template?.title ?? '');
  late final _specialistController =
      TextEditingController(text: widget.template?.specialistName ?? '');
  late final _locationController =
      TextEditingController(text: widget.template?.location ?? '');

  late final Set<int> _selectedDays = widget.template != null
      ? {widget.template!.dayOfWeek}
      : (widget.initialDays ?? {DateTime.now().weekday});

  late TimeOfDay _start = widget.template != null
      ? _parseTime(widget.template!.startTime)
      : const TimeOfDay(hour: 9, minute: 0);
  late TimeOfDay _end = widget.template != null
      ? _parseTime(widget.template!.endTime)
      : const TimeOfDay(hour: 10, minute: 0);
  late bool _isFullDay = widget.template?.isFullDay ?? false;
  late String? _podId = widget.template?.podId;
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
    if (!_isEdit) {
      // Back-to-back: default start to end of last activity on the primary day.
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutofillStart());
    }
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
    // Only nudge if the user hasn't already changed the default
    if (_start.hour == 9 && _start.minute == 0) {
      setState(() {
        _start = newStart;
        // Keep a 1h duration by default
        final endDt = DateTime(2000, 1, 1, newStart.hour, newStart.minute)
            .add(const Duration(hours: 1));
        _end = TimeOfDay(hour: endDt.hour, minute: endDt.minute);
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _specialistController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _titleController.text.trim().isNotEmpty && _selectedDays.isNotEmpty;

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
    final specialist = _specialistController.text.trim().isEmpty
        ? null
        : _specialistController.text.trim();
    final location = _locationController.text.trim().isEmpty
        ? null
        : _locationController.text.trim();
    // When full day, normalize time values; they're hidden in the UI anyway.
    final startHhmm = _isFullDay ? '00:00' : _formatTime(_start);
    final endHhmm = _isFullDay ? '23:59' : _formatTime(_end);

    if (_isEdit) {
      await repo.updateTemplate(
        id: widget.template!.id,
        dayOfWeek: _selectedDays.first,
        startTime: startHhmm,
        endTime: endHhmm,
        isFullDay: _isFullDay,
        title: title,
        podId: _podId,
        specialistName: specialist,
        location: location,
      );
    } else {
      for (final day in _selectedDays) {
        await repo.addTemplate(
          dayOfWeek: day,
          startTime: startHhmm,
          endTime: endHhmm,
          isFullDay: _isFullDay,
          title: title,
          podId: _podId,
          specialistName: specialist,
          location: location,
        );
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (!_isEdit) return;
    await ref
        .read(scheduleRepositoryProvider)
        .deleteTemplate(widget.template!.id);
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

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);
    final podsAsync = ref.watch(podsProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.md,
        bottom: AppSpacing.xl + insets,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isEdit ? 'Edit activity' : 'New activity',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (_isEdit)
                  IconButton(
                    onPressed: _delete,
                    icon: Icon(
                      Icons.delete_outline,
                      color: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
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
            SwitchListTile(
              title: const Text('Full day'),
              subtitle: const Text('No specific time — like a field trip'),
              value: _isFullDay,
              onChanged: (v) => setState(() => _isFullDay = v),
              contentPadding: EdgeInsets.zero,
            ),
            if (!_isFullDay) ...[
              const SizedBox(height: AppSpacing.sm),
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
                    onTap: () =>
                        _applyDurationPreset(const Duration(hours: 1)),
                  ),
                  _DurationChip(
                    label: '90m',
                    onTap: () =>
                        _applyDurationPreset(const Duration(minutes: 90)),
                  ),
                  _DurationChip(
                    label: '2h',
                    onTap: () =>
                        _applyDurationPreset(const Duration(hours: 2)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Text('Pod', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            podsAsync.maybeWhen(
              data: (pods) => DropdownButtonFormField<String?>(
                initialValue: _podId,
                items: [
                  const DropdownMenuItem<String?>(
                    child: Text('All pods'),
                  ),
                  for (final p in pods)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: (v) => setState(() => _podId = v),
              ),
              orElse: () => const LinearProgressIndicator(),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              controller: _specialistController,
              label: 'Specialist (optional)',
              hint: 'Who runs this?',
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              controller: _locationController,
              label: 'Location (optional)',
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton.primary(
              onPressed: _isValid ? _submit : null,
              label: _isEdit
                  ? 'Save'
                  : _selectedDays.length > 1
                      ? 'Add to ${_selectedDays.length} days'
                      : 'Add activity',
              isLoading: _submitting,
            ),
          ],
        ),
      ),
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
            for (var day = 1; day <= 7; day++) ...[
              _DayChip(
                label: _dayShortLabels[day - 1],
                selected: selected.contains(day),
                onTap: () => onToggle(day),
              ),
              if (day < 7) const SizedBox(width: AppSpacing.xs),
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
