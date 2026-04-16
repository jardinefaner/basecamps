import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EditTemplateSheet extends ConsumerStatefulWidget {
  const EditTemplateSheet({super.key, this.template, this.initialDayOfWeek});

  final ScheduleTemplate? template;
  final int? initialDayOfWeek;

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
  late int _dayOfWeek = widget.template?.dayOfWeek ??
      widget.initialDayOfWeek ??
      DateTime.now().weekday;
  late TimeOfDay _start = widget.template != null
      ? _parseTime(widget.template!.startTime)
      : const TimeOfDay(hour: 9, minute: 0);
  late TimeOfDay _end = widget.template != null
      ? _parseTime(widget.template!.endTime)
      : const TimeOfDay(hour: 10, minute: 0);
  late String? _podId = widget.template?.podId;
  bool _submitting = false;

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
  void dispose() {
    _titleController.dispose();
    _specialistController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  bool get _isValid => _titleController.text.trim().isNotEmpty;

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
    final specialist = _specialistController.text.trim();
    final location = _locationController.text.trim();

    if (widget.template == null) {
      await repo.addTemplate(
        dayOfWeek: _dayOfWeek,
        startTime: _formatTime(_start),
        endTime: _formatTime(_end),
        title: title,
        podId: _podId,
        specialistName: specialist.isEmpty ? null : specialist,
        location: location.isEmpty ? null : location,
      );
    } else {
      await repo.updateTemplate(
        id: widget.template!.id,
        dayOfWeek: _dayOfWeek,
        startTime: _formatTime(_start),
        endTime: _formatTime(_end),
        title: title,
        podId: _podId,
        specialistName: specialist.isEmpty ? null : specialist,
        location: location.isEmpty ? null : location,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (widget.template == null) return;
    await ref.read(scheduleRepositoryProvider).deleteTemplate(
          widget.template!.id,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);
    final isEdit = widget.template != null;
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
                    isEdit ? 'Edit activity' : 'New activity',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (isEdit)
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
              hint: 'e.g. Art · Swim · Snack',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Day', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<int>(
              initialValue: _dayOfWeek,
              items: const [
                DropdownMenuItem(value: 1, child: Text('Monday')),
                DropdownMenuItem(value: 2, child: Text('Tuesday')),
                DropdownMenuItem(value: 3, child: Text('Wednesday')),
                DropdownMenuItem(value: 4, child: Text('Thursday')),
                DropdownMenuItem(value: 5, child: Text('Friday')),
                DropdownMenuItem(value: 6, child: Text('Saturday')),
                DropdownMenuItem(value: 7, child: Text('Sunday')),
              ],
              onChanged: (v) => setState(() => _dayOfWeek = v ?? _dayOfWeek),
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
              label: isEdit ? 'Save' : 'Add activity',
              isLoading: _submitting,
            ),
          ],
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
