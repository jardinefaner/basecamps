import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/trips/trips_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/step_wizard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Create-only wizard for a new trip. Walks the teacher through the
/// four buckets (name → date & times → pods → notes) one at a time
/// instead of the old dense sheet.
class NewTripWizardScreen extends ConsumerStatefulWidget {
  const NewTripWizardScreen({super.key});

  @override
  ConsumerState<NewTripWizardScreen> createState() =>
      _NewTripWizardScreenState();
}

class _NewTripWizardScreenState extends ConsumerState<NewTripWizardScreen> {
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();

  DateTime? _date;
  TimeOfDay? _departure;
  TimeOfDay? _return;
  final Set<String> _podIds = <String>{};
  bool _allPods = true;

  bool get _dirty =>
      _name.text.trim().isNotEmpty ||
      _location.text.trim().isNotEmpty ||
      _notes.text.trim().isNotEmpty ||
      _date != null ||
      _departure != null ||
      _return != null ||
      _podIds.isNotEmpty ||
      !_allPods;

  bool get _page1Valid => _name.text.trim().isNotEmpty;
  bool get _page2Valid => _date != null;

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _pickDeparture() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _departure ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null && mounted) setState(() => _departure = picked);
  }

  Future<void> _pickReturn() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _return ?? const TimeOfDay(hour: 15, minute: 0),
    );
    if (picked != null && mounted) setState(() => _return = picked);
  }

  Future<void> _submit() async {
    final location = _location.text.trim();
    final notes = _notes.text.trim();
    await ref.read(tripsRepositoryProvider).addTrip(
          name: _name.text.trim(),
          date: _date!,
          location: location.isEmpty ? null : location,
          notes: notes.isEmpty ? null : notes,
          departureTime: _departure == null ? null : _fmt(_departure!),
          returnTime: _return == null ? null : _fmt(_return!),
          podIds: _allPods ? const [] : _podIds.toList(),
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return StepWizardScaffold(
      title: 'New trip',
      dirty: _dirty,
      finalActionLabel: 'Create trip',
      onFinalAction: _submit,
      steps: [
        WizardStep(
          headline: "Where's the trip?",
          subtitle: 'Name and destination.',
          canProceed: _page1Valid,
          content: _buildNamePage(),
        ),
        WizardStep(
          headline: 'When does it happen?',
          subtitle: 'Pick a date. Add times if it runs on a schedule.',
          canProceed: _page2Valid,
          content: _buildWhenPage(),
        ),
        WizardStep(
          headline: "Who's going?",
          subtitle: 'Leave as "All groups" if everyone at the program is in.',
          canSkip: true,
          content: _buildPodsPage(),
        ),
        WizardStep(
          headline: 'Anything staff should know?',
          subtitle: 'Supplies to bring, meeting points, etc.',
          canSkip: true,
          content: AppTextField(
            controller: _notes,
            label: 'Notes (optional)',
            hint: 'Bring a backpack, water bottle, sunscreen…',
            maxLines: 4,
          ),
        ),
      ],
    );
  }

  // ---- pages ----

  Widget _buildNamePage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: _name,
          label: 'Trip name',
          hint: 'e.g. Aquarium',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          controller: _location,
          label: 'Location (optional)',
          hint: 'e.g. Monterey Bay Aquarium',
        ),
      ],
    );
  }

  Widget _buildWhenPage() {
    final theme = Theme.of(context);
    final dateLabel = _date == null
        ? 'Pick a date'
        : DateFormat.yMMMMEEEEd().format(_date!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        const SizedBox(height: AppSpacing.xl),
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
        const SizedBox(height: AppSpacing.sm),
        Text(
          _departure == null && _return == null
              ? 'No times → shows as an all-day event on the calendar.'
              : 'Shows as a timed event on the calendar.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
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
          title: const Text('All groups'),
          subtitle: const Text('Every group at the program is included'),
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
                  'No groups yet — add some in the Children tab.',
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
