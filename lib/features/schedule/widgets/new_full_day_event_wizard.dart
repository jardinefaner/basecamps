import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/forms/widgets/specialist_chip_picker.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/widgets/new_activity_wizard.dart'
    show CreatedActivity;
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/step_wizard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Wizard for a one-off event — a single all-day date (field trip,
/// staff day, closure) or a range that spans several days (summer
/// break, spirit week, ongoing note). Writes a single ScheduleEntry
/// with `isFullDay: true`; when an end date is set the entry applies
/// to every day in `[date, endDate]`.
///
/// When [existing] is non-null the wizard opens in edit mode:
/// fields prefill from the entry, the action bar reads "Save changes",
/// and submit calls [ScheduleRepository.updateEntry] on that id instead
/// of creating a new row.
class NewFullDayEventWizardScreen extends ConsumerStatefulWidget {
  const NewFullDayEventWizardScreen({
    this.initialDate,
    this.existing,
    super.key,
  });

  final DateTime? initialDate;

  /// Entry row to edit. When non-null the wizard runs in edit mode.
  final ScheduleEntry? existing;

  @override
  ConsumerState<NewFullDayEventWizardScreen> createState() =>
      _NewFullDayEventWizardScreenState();
}

class _NewFullDayEventWizardScreenState
    extends ConsumerState<NewFullDayEventWizardScreen> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _location =
      TextEditingController(text: widget.existing?.location ?? '');
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');

  late DateTime _date = widget.existing?.date ?? widget.initialDate ?? DateTime.now();
  late DateTime? _endDate = widget.existing?.endDate;
  final Set<String> _groupIds = <String>{};
  late bool _allGroups = widget.existing?.allGroups ?? true;
  late String? _specialistId = widget.existing?.specialistId;

  bool get _isEdit => widget.existing != null;

  /// When non-null, fields were pre-filled from a library pick. We
  /// surface a tiny banner on page 1 and let the teacher unlink.
  ActivityLibraryData? _fromLibrary;

  bool get _dirty =>
      _title.text.trim().isNotEmpty ||
      _location.text.trim().isNotEmpty ||
      _notes.text.trim().isNotEmpty ||
      _groupIds.isNotEmpty ||
      _specialistId != null ||
      _endDate != null ||
      _fromLibrary != null;

  bool get _page1Valid => _title.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final groups = await ref
            .read(scheduleRepositoryProvider)
            .podsForEntry(widget.existing!.id);
        if (!mounted) return;
        setState(() => _groupIds.addAll(groups));
      });
    }
  }

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
    if (picked != null && mounted) {
      // Was the existing end date about to become invalid? Capture
      // that BEFORE the setState clears it, so we can flag the change
      // instead of silently turning a multi-day event into a single day.
      final endDropped =
          _endDate != null && _endDate!.isBefore(picked);
      setState(() {
        _date = picked;
        if (endDropped) {
          _endDate = null;
        }
      });
      if (endDropped) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'End date cleared — it was before the new start.',
              ),
              duration: Duration(seconds: 3),
            ),
          );
      }
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _date,
      firstDate: _date,
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null && mounted) setState(() => _endDate = picked);
  }

  Future<void> _submit() async {
    final location = _location.text.trim();
    final notes = _notes.text.trim();
    final repo = ref.read(scheduleRepositoryProvider);
    final existing = widget.existing;
    if (existing != null) {
      await repo.updateEntry(
        id: existing.id,
        date: _date,
        endDate: _endDate,
        startTime: '00:00',
        endTime: '23:59',
        isFullDay: true,
        allGroups: _allGroups,
        title: _title.text.trim(),
        groupIds: _allGroups ? const [] : _groupIds.toList(),
        specialistId: _specialistId,
        location: location.isEmpty ? null : location,
        notes: notes.isEmpty ? null : notes,
      );
    } else {
      await repo.addOneOffEntry(
        date: _date,
        endDate: _endDate,
        startTime: '00:00',
        endTime: '23:59',
        isFullDay: true,
        allGroups: _allGroups,
        title: _title.text.trim(),
        groupIds: _allGroups ? const [] : _groupIds.toList(),
        specialistId: _specialistId,
        location: location.isEmpty ? null : location,
        notes: notes.isEmpty ? null : notes,
      );
    }
    if (!mounted) return;
    // Return the bounds so the schedule editor can jump its week view
    // to where the event lives + flash a snackbar. Otherwise events
    // dated in the future save silently and look like no-ops.
    Navigator.of(context).pop<CreatedActivity>(
      CreatedActivity(
        title: _title.text.trim(),
        startDate: _date,
        endDate: _endDate,
        dayCount: _daysInRange(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StepWizardScaffold(
      title: _isEdit ? 'Edit event' : 'Event or note',
      dirty: _dirty,
      finalActionLabel: _isEdit
          ? 'Save changes'
          : (_endDate == null
              ? 'Add event'
              : 'Add across ${_daysInRange()} days'),
      onFinalAction: _submit,
      steps: [
        WizardStep(
          headline: 'What is it, and when?',
          subtitle: 'Name it and pick a date. Add an end date to span '
              'several days.',
          canProceed: _page1Valid,
          content: _buildTitlePage(),
        ),
        WizardStep(
          headline: "Who's going?",
          subtitle: 'Leave as "All groups" if the whole program is included.',
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
        Text(
          _endDate == null ? 'Date' : 'Dates',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        _DateTile(
          label: _endDate == null ? 'On' : 'Starts',
          value: _date,
          icon: Icons.event_outlined,
          onTap: _pickDate,
        ),
        const SizedBox(height: AppSpacing.sm),
        _DateTile(
          label: 'Ends (optional)',
          value: _endDate,
          placeholder: 'Same day',
          icon: Icons.event_available_outlined,
          onTap: _pickEndDate,
          onClear: _endDate == null
              ? null
              : () => setState(() => _endDate = null),
        ),
        if (_endDate != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Spans ${_daysInRange()} days.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ],
    );
  }

  int _daysInRange() {
    if (_endDate == null) return 1;
    final start = DateTime(_date.year, _date.month, _date.day);
    final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day);
    return end.difference(start).inDays + 1;
  }

  Widget _buildPodsPage() {
    final theme = Theme.of(context);
    final podsAsync = ref.watch(groupsProvider);
    final noGroupsSelected = !_allGroups && _groupIds.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          title: const Text('All groups'),
          subtitle: const Text(
            'Every group at the program is included',
          ),
          value: _allGroups,
          onChanged: (v) => setState(() {
            _allGroups = v;
            if (v) _groupIds.clear();
          }),
          contentPadding: EdgeInsets.zero,
        ),
        // Clarify what the "no toggle, no picks" state means so the
        // teacher doesn't think they've mis-configured. This is
        // legitimate state for staff-prep / closure-style events that
        // have no children to track.
        if (noGroupsSelected) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'No groups selected — saves as a staff-only event. '
                    "No children are tracked, and it won't conflict "
                    'with other activities on the same day.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (!_allGroups)
          podsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (err, _) => Text('Error: $err'),
            data: (groups) {
              if (groups.isEmpty) {
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
                    for (final group in groups)
                      FilterChip(
                        label: Text(group.name),
                        selected: _groupIds.contains(group.id),
                        onSelected: (_) => setState(() {
                          if (!_groupIds.add(group.id)) _groupIds.remove(group.id);
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

/// Outlined tap tile for picking a date — mirrors the other tiles in
/// the app's form surfaces. `onClear` shows an X when provided.
class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.onTap,
    required this.icon,
    this.placeholder = 'Pick a date',
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final IconData icon;
  final String placeholder;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayLabel = value == null
        ? placeholder
        : DateFormat.yMMMMEEEEd().format(value!);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
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
            Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    displayLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
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
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                iconSize: 18,
                tooltip: 'Clear',
                icon: const Icon(Icons.close),
                onPressed: onClear,
              ),
          ],
        ),
      ),
    );
  }
}
