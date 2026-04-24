import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adult_timeline_repository.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/adults/widgets/adult_timeline_editor_sheet.dart';
import 'package:basecamp/features/adults/widgets/availability_editor.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:basecamp/ui/undo_delete.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EditAdultSheet extends ConsumerStatefulWidget {
  const EditAdultSheet({super.key, this.adult});

  final Adult? adult;

  @override
  ConsumerState<EditAdultSheet> createState() =>
      _EditAdultSheetState();
}

class _EditAdultSheetState extends ConsumerState<EditAdultSheet> {
  late final _nameController =
      TextEditingController(text: widget.adult?.name ?? '');
  late final _roleController =
      TextEditingController(text: widget.adult?.role ?? '');
  late final _notesController =
      TextEditingController(text: widget.adult?.notes ?? '');

  late String? _avatarPath = widget.adult?.avatarPath;

  /// Structural role (v28) — what kind of adult this person is on
  /// the schedule. Defaults to adult (rover) for new rows and
  /// reads through for existing ones via AdultRole.fromDb.
  late AdultRole _adultRole = widget.adult == null
      ? AdultRole.specialist
      : AdultRole.fromDb(widget.adult!.adultRole);

  /// Which group this adult anchors (leads only). Ignored when
  /// [_adultRole] isn't [AdultRole.lead]; the UI clears it on role
  /// change to avoid stale state surviving a save.
  late String? _anchoredGroupId = widget.adult?.anchoredGroupId;

  final Map<int, AvailabilityBlock> _availability = {};
  bool _availabilityLoaded = false;

  /// Snapshot of the availability set as loaded from the DB — used
  /// only to detect "was it changed?" so Save is disabled on a
  /// pristine edit.
  List<({int day, int startMinutes, int endMinutes})> _availabilityBaseline =
      const [];

  bool _submitting = false;

  bool get _isEdit => widget.adult != null;
  bool get _isValid => _nameController.text.trim().isNotEmpty;

  bool get _hasChanges {
    final adult = widget.adult;
    if (adult == null) return true;
    if (_nameController.text.trim() != adult.name) return true;
    final currentRole =
        _roleController.text.trim().isEmpty ? null : _roleController.text.trim();
    if (currentRole != adult.role) return true;
    final currentNotes =
        _notesController.text.trim().isEmpty ? null : _notesController.text.trim();
    if (currentNotes != adult.notes) return true;
    if (_avatarPath != adult.avatarPath) return true;
    if (_adultRole.dbValue != adult.adultRole) return true;
    if (_anchoredGroupId != adult.anchoredGroupId) return true;
    if (!_availabilityLoaded) return false;
    final current = _currentAvailabilitySig();
    if (current.length != _availabilityBaseline.length) return true;
    for (var i = 0; i < current.length; i++) {
      if (current[i] != _availabilityBaseline[i]) return true;
    }
    return false;
  }

  List<({int day, int startMinutes, int endMinutes})> _currentAvailabilitySig() {
    final entries = _availability.values
        .map(
          (b) => (
            day: b.dayOfWeek,
            startMinutes: b.start.hour * 60 + b.start.minute,
            endMinutes: b.end.hour * 60 + b.end.minute,
          ),
        )
        .toList()
      ..sort((a, b) => a.day.compareTo(b.day));
    return entries;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadAvailability());
    });
  }

  Future<void> _loadAvailability() async {
    if (!_isEdit) {
      setState(() {
        for (final b in defaultAvailability()) {
          _availability[b.dayOfWeek] = b;
        }
        _availabilityLoaded = true;
        _availabilityBaseline = _currentAvailabilitySig();
      });
      return;
    }
    final rows = await ref
        .read(adultsRepositoryProvider)
        .availabilityFor(widget.adult!.id);
    if (!mounted) return;
    setState(() {
      _availability.clear();
      for (final b in availabilityFromRows(rows)) {
        _availability[b.dayOfWeek] = b;
      }
      _availabilityLoaded = true;
      _availabilityBaseline = _currentAvailabilitySig();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _roleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isValid) return;
    setState(() => _submitting = true);
    final repo = ref.read(adultsRepositoryProvider);
    final name = _nameController.text.trim();
    final role =
        _roleController.text.trim().isEmpty ? null : _roleController.text.trim();
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();

    // Anchor only applies to leads; clear it for adults/ambient
    // so role toggles don't leave stale group pointers.
    final effectiveAnchor =
        _adultRole == AdultRole.lead ? _anchoredGroupId : null;

    String id;
    if (_isEdit) {
      final existing = widget.adult!;
      await repo.updateAdult(
        id: existing.id,
        name: name,
        role: role,
        notes: notes,
        avatarPath: _avatarPath,
        clearAvatarPath:
            _avatarPath == null && existing.avatarPath != null,
        adultRole: Value(_adultRole.dbValue),
        anchoredGroupId: Value(effectiveAnchor),
      );
      id = existing.id;
    } else {
      id = await repo.addAdult(
        name: name,
        role: role,
        notes: notes,
        avatarPath: _avatarPath,
        adultRole: _adultRole,
        anchoredGroupId: effectiveAnchor,
      );
    }
    if (_availabilityLoaded) {
      await repo.replaceAvailability(
        adultId: id,
        blocks: _availability.values.map((b) => b.toInput()).toList(),
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (!_isEdit) return;
    final existing = widget.adult!;
    final navigator = Navigator.of(context);
    final confirmed = await confirmDeleteWithUndo(
      context: context,
      title: 'Remove ${existing.name}?',
      message: "You'll get a 5-second window to undo.",
      onDelete: () => ref
          .read(adultsRepositoryProvider)
          .deleteAdult(existing.id),
      undoLabel: '${existing.name} removed',
      onUndo: () => ref
          .read(adultsRepositoryProvider)
          .restoreAdult(existing),
    );
    if (!confirmed || !mounted) return;
    // Pop the sheet AND the detail screen beneath it so the teacher
    // lands back on the Adults list. If they hit Undo, the sheet is
    // already closed but the row reappears in the list — that's
    // fine.
    navigator
      ..pop() // sheet
      ..pop(); // detail
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StickyActionSheet(
      title: _isEdit ? 'Edit adult' : 'New adult',
      titleTrailing: _isEdit
          ? IconButton(
              onPressed: _delete,
              icon: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error,
              ),
            )
          : null,
      actionBar: AppButton.primary(
        onPressed: _isValid && (!_isEdit || _hasChanges) ? _submit : null,
        label: _isEdit ? 'Save' : 'Add adult',
        isLoading: _submitting,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: AvatarPicker(
              currentPath: _avatarPath,
              fallbackInitial: _nameController.text.trim().isNotEmpty
                  ? _nameController.text.trim().characters.first.toUpperCase()
                  : '?',
              onChanged: (path) => setState(() => _avatarPath = path),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _nameController,
            label: 'Name',
            hint: 'e.g. Sarah',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _roleController,
            label: 'Job title (optional)',
            hint: 'e.g. Art teacher · Director · Head cook',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.xl),
          _RolePicker(
            selected: _adultRole,
            onChanged: (r) => setState(() {
              _adultRole = r;
              if (r != AdultRole.lead) _anchoredGroupId = null;
            }),
          ),
          if (_adultRole == AdultRole.lead) ...[
            const SizedBox(height: AppSpacing.lg),
            _AnchorGroupPicker(
              selectedGroupId: _anchoredGroupId,
              onChanged: (id) => setState(() => _anchoredGroupId = id),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          Text('Availability', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          if (!_availabilityLoaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: LinearProgressIndicator(),
            )
          else
            AvailabilityEditor(
              blocksByDay: _availability,
              onToggleDay: (day, {required enabled}) {
                setState(() {
                  if (enabled) {
                    _availability[day] = AvailabilityBlock(
                      dayOfWeek: day,
                      start: const TimeOfDay(hour: 9, minute: 0),
                      end: const TimeOfDay(hour: 17, minute: 0),
                    );
                  } else {
                    _availability.remove(day);
                  }
                });
              },
              onPickStart: (day) async {
                final existing = _availability[day];
                if (existing == null) return;
                final picked = await showTimePicker(
                  context: context,
                  initialTime: existing.start,
                );
                if (picked == null || !mounted) return;
                setState(() {
                  _availability[day] = existing.copyWith(start: picked);
                });
              },
              onPickEnd: (day) async {
                final existing = _availability[day];
                if (existing == null) return;
                final picked = await showTimePicker(
                  context: context,
                  initialTime: existing.end,
                );
                if (picked == null || !mounted) return;
                setState(() {
                  _availability[day] = existing.copyWith(end: picked);
                });
              },
              onPickBreak: (day) => _pickWindow(
                day,
                existingStart: _availability[day]?.breakStart,
                existingEnd: _availability[day]?.breakEnd,
                fallbackStart: const TimeOfDay(hour: 10, minute: 30),
                fallbackEnd: const TimeOfDay(hour: 10, minute: 45),
                onPicked: (start, end) {
                  final existing = _availability[day];
                  if (existing == null) return;
                  _availability[day] = existing.copyWith(
                    breakStart: start,
                    breakEnd: end,
                  );
                },
              ),
              onPickBreak2: (day) => _pickWindow(
                day,
                existingStart: _availability[day]?.break2Start,
                existingEnd: _availability[day]?.break2End,
                fallbackStart: const TimeOfDay(hour: 14, minute: 30),
                fallbackEnd: const TimeOfDay(hour: 14, minute: 45),
                onPicked: (start, end) {
                  final existing = _availability[day];
                  if (existing == null) return;
                  _availability[day] = existing.copyWith(
                    break2Start: start,
                    break2End: end,
                  );
                },
              ),
              onPickLunch: (day) => _pickWindow(
                day,
                existingStart: _availability[day]?.lunchStart,
                existingEnd: _availability[day]?.lunchEnd,
                fallbackStart: const TimeOfDay(hour: 12, minute: 0),
                fallbackEnd: const TimeOfDay(hour: 13, minute: 0),
                onPicked: (start, end) {
                  final existing = _availability[day];
                  if (existing == null) return;
                  _availability[day] = existing.copyWith(
                    lunchStart: start,
                    lunchEnd: end,
                  );
                },
              ),
              onClearBreak: (day) => setState(() {
                final existing = _availability[day];
                if (existing == null) return;
                _availability[day] = existing.copyWith(clearBreak: true);
              }),
              onClearBreak2: (day) => setState(() {
                final existing = _availability[day];
                if (existing == null) return;
                _availability[day] = existing.copyWith(clearBreak2: true);
              }),
              onClearLunch: (day) => setState(() {
                final existing = _availability[day];
                if (existing == null) return;
                _availability[day] = existing.copyWith(clearLunch: true);
              }),
            ),
          const SizedBox(height: AppSpacing.lg),
          // Day-timeline (v30) launches a dedicated editor sheet.
          // Stays optional: most adults' days don't need block-level
          // detail, so we keep a single button here instead of
          // cluttering this sheet with per-day tables.
          _DayTimelineLaunchRow(adult: widget.adult),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _notesController,
            label: 'Notes (optional)',
            maxLines: 3,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  /// Prompt for a start/end time pair. Used for both break and lunch
  /// so the picker flow is consistent: tap once, pick the start time,
  /// then the end time. Cancelling either step aborts the whole pick.
  Future<void> _pickWindow(
    int dayOfWeek, {
    required TimeOfDay? existingStart,
    required TimeOfDay? existingEnd,
    required TimeOfDay fallbackStart,
    required TimeOfDay fallbackEnd,
    required void Function(TimeOfDay start, TimeOfDay end) onPicked,
  }) async {
    final startSeed = existingStart ?? fallbackStart;
    final start = await showTimePicker(
      context: context,
      initialTime: startSeed,
      helpText: 'Starts at',
    );
    if (start == null || !mounted) return;
    final endSeed = existingEnd ??
        _addMinutes(
          start,
          existingEnd == null && existingStart == null
              ? _windowDefaultMinutes(startSeed, fallbackEnd)
              : 15,
        );
    final end = await showTimePicker(
      context: context,
      initialTime: endSeed,
      helpText: 'Ends at',
    );
    if (end == null || !mounted) return;
    setState(() => onPicked(start, end));
  }

  int _windowDefaultMinutes(TimeOfDay start, TimeOfDay fallbackEnd) {
    final startMin = start.hour * 60 + start.minute;
    final endMin = fallbackEnd.hour * 60 + fallbackEnd.minute;
    final diff = endMin - startMin;
    return diff > 0 ? diff : 30;
  }

  TimeOfDay _addMinutes(TimeOfDay t, int minutes) {
    final total = t.hour * 60 + t.minute + minutes;
    final wrapped = ((total % (24 * 60)) + 24 * 60) % (24 * 60);
    return TimeOfDay(hour: wrapped ~/ 60, minute: wrapped % 60);
  }
}

/// Three-chip picker for the structural adult role. Plain FilterChips
/// because these roles aren't mutually exclusive in *capability* (a
/// lead can also cover activities) — just in *default placement* on
/// the schedule. Keep it simple.
class _RolePicker extends StatelessWidget {
  const _RolePicker({required this.selected, required this.onChanged});

  final AdultRole selected;
  final ValueChanged<AdultRole> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Role on the schedule', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'How this person shows up on Today. Leads anchor a group all '
          'day. Adults rotate between activities. Ambient staff '
          "(director, nurse, kitchen) have a shift but aren't on the "
          'activity grid.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final r in AdultRole.values)
              ChoiceChip(
                label: Text(_labelFor(r)),
                selected: selected == r,
                onSelected: (_) => onChanged(r),
              ),
          ],
        ),
      ],
    );
  }

  String _labelFor(AdultRole r) {
    switch (r) {
      case AdultRole.lead:
        return 'Lead';
      case AdultRole.specialist:
        return 'Specialist';
      case AdultRole.ambient:
        return 'Ambient staff';
    }
  }
}

/// Group chip picker shown only when the adult is a lead. Used to
/// anchor them to one group. Lazily loads the group list; shows a
/// helper message when the DB has none.
class _AnchorGroupPicker extends ConsumerWidget {
  const _AnchorGroupPicker({
    required this.selectedGroupId,
    required this.onChanged,
  });

  final String? selectedGroupId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final groupsAsync = ref.watch(groupsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Anchor group', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'The group this lead stays with all day. Their schedule on '
          "Today follows this group's activity schedule.",
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        groupsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (err, _) => Text('Error: $err'),
          data: (groups) {
            if (groups.isEmpty) {
              return Text(
                'No groups yet — add some in the Children tab first.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              );
            }
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final g in groups)
                  ChoiceChip(
                    label: Text(g.name),
                    selected: selectedGroupId == g.id,
                    onSelected: (_) => onChanged(g.id),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Compact launcher row for the day-timeline editor. Lives on the
/// adult edit sheet; tapping opens the timeline editor sheet which
/// replaces the static role for the rest of the day-cycle. Shows a
/// block-count hint when there's a timeline so teachers can see at a
/// glance whether it's been set up.
class _DayTimelineLaunchRow extends ConsumerWidget {
  const _DayTimelineLaunchRow({required this.adult});

  final Adult? adult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final id = adult?.id;
    // Pull live so the block count refreshes when the teacher saves
    // the editor sheet and pops back to this sheet.
    final blocksAsync = id == null
        ? const AsyncValue<List<AdultDayBlock>>.data([])
        : ref.watch(
            StreamProvider.autoDispose<List<AdultDayBlock>>(
              (ref) =>
                  ref.watch(adultTimelineRepositoryProvider).watchBlocksFor(id),
            ),
          );
    final count = blocksAsync.asData?.value.length ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Day timeline (advanced)', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Subdivides the shift into role blocks — "lead Butterflies '
          '8:30-11, adult rotator 11-12, back to Butterflies '
          '12-3." Leave empty and Today uses the structural role above.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          // Can't edit a timeline for an unsaved row (no id yet). The
          // button is inert until the teacher saves the adult at least
          // once; the copy explains why.
          onPressed: id == null
              ? null
              : () async {
                  final blocks = blocksAsync.asData?.value ?? const [];
                  await showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    useSafeArea: true,
                    builder: (_) => AdultTimelineEditorSheet(
                      adultId: id,
                      adultName: adult?.name ?? 'Adult',
                      initialBlocks: [
                        for (final b in blocks) AdultTimelineBlock.fromRow(b),
                      ],
                    ),
                  );
                },
          icon: const Icon(Icons.schedule, size: 18),
          label: Text(
            id == null
                ? 'Save first, then edit timeline'
                : count == 0
                    ? 'Edit day timeline'
                    : 'Edit day timeline · $count block${count == 1 ? "" : "s"}',
          ),
        ),
      ],
    );
  }
}
