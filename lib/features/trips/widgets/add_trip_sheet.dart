import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/trips/trips_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class AddTripSheet extends ConsumerStatefulWidget {
  const AddTripSheet({super.key});

  @override
  ConsumerState<AddTripSheet> createState() => _AddTripSheetState();
}

class _AddTripSheetState extends ConsumerState<AddTripSheet> {
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime? _date;
  TimeOfDay? _departure;
  TimeOfDay? _return;
  final Set<String> _selectedPodIds = <String>{};
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _pickDeparture() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _departure ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) setState(() => _departure = picked);
  }

  Future<void> _pickReturn() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _return ?? const TimeOfDay(hour: 15, minute: 0),
    );
    if (picked != null) setState(() => _return = picked);
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  bool get _isValid =>
      _nameController.text.trim().isNotEmpty && _date != null;

  Future<void> _submit() async {
    if (!_isValid) return;
    setState(() => _submitting = true);
    await ref.read(tripsRepositoryProvider).addTrip(
          name: _nameController.text.trim(),
          date: _date!,
          location: _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          departureTime: _departure == null ? null : _fmt(_departure!),
          returnTime: _return == null ? null : _fmt(_return!),
          podIds: _selectedPodIds.toList(),
        );
    if (!mounted) return;
    Navigator.of(context).pop();
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
            Text('New trip', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'The trip will be added to the calendar for the selected pods.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xl),
            AppTextField(
              controller: _nameController,
              label: 'Trip name',
              hint: 'e.g. Aquarium',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Date', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(
                _date == null
                    ? 'Pick a date'
                    : DateFormat.yMMMMEEEEd().format(_date!),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: _TimeField(
                    label: 'Departure (optional)',
                    time: _departure,
                    onPick: _pickDeparture,
                    onClear: _departure == null
                        ? null
                        : () => setState(() => _departure = null),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _TimeField(
                    label: 'Return (optional)',
                    time: _return,
                    onPick: _pickReturn,
                    onClear: _return == null
                        ? null
                        : () => setState(() => _return = null),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _departure == null && _return == null
                  ? 'No times → shows as an all-day event on the calendar.'
                  : 'Shows as a timed event on the calendar.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              controller: _locationController,
              label: 'Location (optional)',
              hint: 'e.g. Monterey Bay Aquarium',
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Pods going', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            podsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text('Error: $err'),
              data: (pods) => _PodSelector(
                pods: pods,
                selectedPodIds: _selectedPodIds,
                onAllToggle: () => setState(_selectedPodIds.clear),
                onPodToggle: (id) => setState(() {
                  if (!_selectedPodIds.add(id)) _selectedPodIds.remove(id);
                }),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              controller: _notesController,
              label: 'Notes (optional)',
              hint: 'Bring a backpack, water bottle, sunscreen…',
              maxLines: 3,
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton.primary(
              onPressed: _isValid ? _submit : null,
              label: 'Create trip',
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
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final TimeOfDay? time;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                icon: const Icon(Icons.schedule_outlined, size: 16),
                label: Text(
                  time == null ? 'Set time' : time!.format(context),
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

class _PodSelector extends StatelessWidget {
  const _PodSelector({
    required this.pods,
    required this.selectedPodIds,
    required this.onAllToggle,
    required this.onPodToggle,
  });

  final List<Pod> pods;
  final Set<String> selectedPodIds;
  final VoidCallback onAllToggle;
  final ValueChanged<String> onPodToggle;

  @override
  Widget build(BuildContext context) {
    if (pods.isEmpty) {
      return Text(
        'No pods yet — add some in the Kids tab.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final allSelected = selectedPodIds.isEmpty;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        FilterChip(
          label: const Text('All pods'),
          selected: allSelected,
          onSelected: (_) => onAllToggle(),
        ),
        for (final pod in pods)
          FilterChip(
            label: Text(pod.name),
            selected: selectedPodIds.contains(pod.id),
            onSelected: (_) => onPodToggle(pod.id),
          ),
      ],
    );
  }
}
