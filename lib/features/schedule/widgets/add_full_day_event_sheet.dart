import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/activity_library/widgets/library_picker_sheet.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// A dedicated sheet for creating one-off, full-day events (field trips,
/// special days, closures). Writes a ScheduleEntry with isFullDay=true.
class AddFullDayEventSheet extends ConsumerStatefulWidget {
  const AddFullDayEventSheet({super.key, this.initialDate});

  final DateTime? initialDate;

  @override
  ConsumerState<AddFullDayEventSheet> createState() =>
      _AddFullDayEventSheetState();
}

class _AddFullDayEventSheetState extends ConsumerState<AddFullDayEventSheet> {
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();
  late DateTime _date = widget.initialDate ?? DateTime.now();
  final Set<String> _selectedPodIds = <String>{};
  String? _specialistId;
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _isValid => _titleController.text.trim().isNotEmpty;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _date = picked);
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
      if (picked.notes != null) {
        _notesController.text = picked.notes!;
      }
      if (picked.specialistId != null) {
        _specialistId = picked.specialistId;
      }
    });
  }

  Future<void> _submit() async {
    if (!_isValid) return;
    setState(() => _submitting = true);
    final title = _titleController.text.trim();
    final location = _locationController.text.trim().isEmpty
        ? null
        : _locationController.text.trim();
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();

    await ref.read(scheduleRepositoryProvider).addOneOffEntry(
          date: _date,
          startTime: '00:00',
          endTime: '23:59',
          isFullDay: true,
          title: title,
          podIds: _selectedPodIds.toList(),
          specialistId: _specialistId,
          location: location,
          notes: notes,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final podsAsync = ref.watch(podsProvider);
    final dateLabel = DateFormat.yMMMMEEEEd().format(_date);

    return StickyActionSheet(
      title: 'Full-day event',
      subtitle: const Text(
        'Field trip, closure, or special day for a specific date.',
      ),
      actionBar: AppButton.primary(
        onPressed: _isValid ? _submit : null,
        label: 'Add event',
        isLoading: _submitting,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _openLibrary,
            icon: const Icon(Icons.bookmark_outline, size: 18),
            label: const Text('From library...'),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _titleController,
            label: 'What is it?',
            hint: 'e.g. Aquarium trip · Staff training · 4th of July',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Date', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(dateLabel),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Pods', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          podsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (err, _) => Text('Error: $err'),
            data: (pods) => _PodSelector(
              pods: pods,
              selectedPodIds: _selectedPodIds,
              onAllToggle: () => setState(_selectedPodIds.clear),
              onPodToggle: (id) => setState(() {
                if (!_selectedPodIds.add(id)) {
                  _selectedPodIds.remove(id);
                }
              }),
            ),
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
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _notesController,
            label: 'Notes (optional)',
            maxLines: 3,
          ),
        ],
      ),
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
