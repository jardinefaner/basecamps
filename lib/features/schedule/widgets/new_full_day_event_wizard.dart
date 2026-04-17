import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:basecamp/features/forms/widgets/specialist_chip_picker.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/step_wizard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Wizard for a one-off full-day event (field trip, staff day,
/// closure). Creates a ScheduleEntry with `isFullDay: true` bound to
/// a single date.
class NewFullDayEventWizardScreen extends ConsumerStatefulWidget {
  const NewFullDayEventWizardScreen({this.initialDate, super.key});

  final DateTime? initialDate;

  @override
  ConsumerState<NewFullDayEventWizardScreen> createState() =>
      _NewFullDayEventWizardScreenState();
}

class _NewFullDayEventWizardScreenState
    extends ConsumerState<NewFullDayEventWizardScreen> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();

  late DateTime _date = widget.initialDate ?? DateTime.now();
  final Set<String> _podIds = <String>{};
  bool _allPods = true;
  String? _specialistId;

  /// When non-null, fields were pre-filled from a library pick. We
  /// surface a tiny banner on page 1 and let the teacher unlink.
  ActivityLibraryData? _fromLibrary;

  bool get _dirty =>
      _title.text.trim().isNotEmpty ||
      _location.text.trim().isNotEmpty ||
      _notes.text.trim().isNotEmpty ||
      _podIds.isNotEmpty ||
      _specialistId != null ||
      _fromLibrary != null;

  bool get _page1Valid => _title.text.trim().isNotEmpty;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    final location = _location.text.trim();
    final notes = _notes.text.trim();
    await ref.read(scheduleRepositoryProvider).addOneOffEntry(
          date: _date,
          startTime: '00:00',
          endTime: '23:59',
          isFullDay: true,
          title: _title.text.trim(),
          podIds: _allPods ? const [] : _podIds.toList(),
          specialistId: _specialistId,
          location: location.isEmpty ? null : location,
          notes: notes.isEmpty ? null : notes,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return StepWizardScaffold(
      title: 'Full-day event',
      dirty: _dirty,
      finalActionLabel: 'Add event',
      onFinalAction: _submit,
      steps: [
        WizardStep(
          headline: 'What is it, and when?',
          subtitle: 'Name the event and pick its date.',
          canProceed: _page1Valid,
          content: _buildTitlePage(),
        ),
        WizardStep(
          headline: "Who's going?",
          subtitle: 'Leave as "All pods" if the whole program is included.',
          canSkip: true,
          content: _buildPodsPage(),
        ),
        WizardStep(
          headline: 'Details',
          subtitle: 'Specialist, location, notes — whatever helps staff.',
          canSkip: true,
          content: _buildDetailsPage(),
        ),
      ],
    );
  }

  // ---- pages ----

  Widget _buildTitlePage() {
    final theme = Theme.of(context);
    final dateLabel = DateFormat.yMMMMEEEEd().format(_date);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LibraryChipRow(
          onPick: (item) => setState(() {
            _fromLibrary = item;
            _title.text = item.title;
            if (item.location != null) _location.text = item.location!;
            if (item.notes != null) _notes.text = item.notes!;
            if (item.specialistId != null) _specialistId = item.specialistId;
          }),
        ),
        if (_fromLibrary != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.bookmark_outlined,
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Linked to library: ${_fromLibrary!.title}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Unlink',
                    icon: Icon(
                      Icons.close,
                      size: 16,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    onPressed: () => setState(() => _fromLibrary = null),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.xl),
        AppTextField(
          controller: _title,
          label: 'Event name',
          hint: 'e.g. Aquarium trip · 4th of July · Staff training',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Date', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.event_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(dateLabel, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPodsPage() {
    final theme = Theme.of(context);
    final podsAsync = ref.watch(podsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          title: const Text('All pods'),
          subtitle: const Text(
            'Every pod at the program is included',
          ),
          value: _allPods,
          onChanged: (v) => setState(() {
            _allPods = v;
            if (v) _podIds.clear();
          }),
          contentPadding: EdgeInsets.zero,
        ),
        if (!_allPods)
          podsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (err, _) => Text('Error: $err'),
            data: (pods) {
              if (pods.isEmpty) {
                return Text(
                  'No pods yet — add some in the Kids tab.',
                  style: theme.textTheme.bodySmall,
                );
              }
              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Wrap(
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
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildDetailsPage() {
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
          label: 'Location (optional)',
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          controller: _notes,
          label: 'Notes (optional)',
          maxLines: 3,
        ),
      ],
    );
  }
}

// ------------------------------------------------------------

class _LibraryChipRow extends ConsumerWidget {
  const _LibraryChipRow({required this.onPick});

  final ValueChanged<ActivityLibraryData> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final itemsAsync = ref.watch(activityLibraryProvider);
    return itemsAsync.maybeWhen(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
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
      orElse: () => const SizedBox.shrink(),
    );
  }
}
