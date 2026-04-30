import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adult_timeline_repository.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/adults/widgets/adult_timeline_editor_sheet.dart';
import 'package:basecamp/features/adults/widgets/availability_editor.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/children/widgets/new_group_wizard.dart';
import 'package:basecamp/features/parents/parents_repository.dart';
import 'package:basecamp/features/roles/roles_repository.dart';
import 'package:basecamp/features/roles/widgets/edit_role_sheet.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:basecamp/ui/save_action.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:basecamp/ui/undo_delete.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

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
  late final _phoneController =
      TextEditingController(text: widget.adult?.phone ?? '');
  late final _emailController =
      TextEditingController(text: widget.adult?.email ?? '');
  late final _notesController =
      TextEditingController(text: widget.adult?.notes ?? '');

  /// Freshly-picked avatar — non-null when the teacher has just
  /// snapped or chosen a new photo. Cleared on save. Takes
  /// precedence over the existing row's `avatar_path` /
  /// `avatar_storage_path` for both preview rendering and the
  /// repo write.
  XFile? _pendingAvatar;

  /// Set when the teacher tapped "Remove photo" on a row that
  /// previously had one. Drives `clearAvatarPath: true` on save.
  bool _avatarCleared = false;

  /// v40: link to the Parents row when this staff member is also a
  /// parent of a child in the program. Null when not linked. The
  /// picker below the role section reads/writes this directly.
  late String? _parentId = widget.adult?.parentId;

  /// v39: FK to a Roles row. When non-null the role picker
  /// supersedes the free-text [_roleController] — we save
  /// `roleId = _roleId, role = null`. When the teacher edits the
  /// text field, we clear this back to null so the legacy path
  /// wins. Either one, never both.
  late String? _roleId = widget.adult?.roleId;

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
    if (_roleId != adult.roleId) return true;
    final currentPhone =
        _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim();
    if (currentPhone != adult.phone) return true;
    final currentEmail =
        _emailController.text.trim().isEmpty ? null : _emailController.text.trim();
    if (currentEmail != adult.email) return true;
    final currentNotes =
        _notesController.text.trim().isEmpty ? null : _notesController.text.trim();
    if (currentNotes != adult.notes) return true;
    // Either flag is the teacher having actually touched the
    // avatar this session — pristine opens see neither.
    if (_pendingAvatar != null) return true;
    if (_avatarCleared) return true;
    if (_adultRole.dbValue != adult.adultRole) return true;
    if (_anchoredGroupId != adult.anchoredGroupId) return true;
    if (_parentId != adult.parentId) return true;
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
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isValid) return;
    setState(() => _submitting = true);
    final repo = ref.read(adultsRepositoryProvider);
    final name = _nameController.text.trim();
    // Picker wins: when a roleId is set, save only the FK and clear
    // the legacy string so we don't double-store. When no roleId,
    // fall back to the free-text path.
    final typed =
        _roleController.text.trim().isEmpty ? null : _roleController.text.trim();
    final role = _roleId != null ? null : typed;
    final roleId = _roleId;
    final phone = _phoneController.text.trim().isEmpty
        ? null
        : _phoneController.text.trim();
    final email = _emailController.text.trim().isEmpty
        ? null
        : _emailController.text.trim();
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
        roleId: Value(roleId),
        notes: notes,
        avatarFile: _pendingAvatar,
        clearAvatarPath: _avatarCleared,
        adultRole: Value(_adultRole.dbValue),
        anchoredGroupId: Value(effectiveAnchor),
        phone: Value(phone),
        email: Value(email),
        parentId: Value(_parentId),
      );
      id = existing.id;
    } else {
      id = await repo.addAdult(
        name: name,
        role: role,
        roleId: roleId,
        notes: notes,
        avatarFile: _pendingAvatar,
        adultRole: _adultRole,
        anchoredGroupId: effectiveAnchor,
        phone: phone,
        email: email,
        parentId: _parentId,
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
        onPressed: _isValid && (!_isEdit || _hasChanges)
            ? () => runWithErrorReport(context, _submit)
            : null,
        label: _isEdit ? 'Save' : 'Add adult',
        isLoading: _submitting,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: AvatarPicker(
              // When the teacher has cleared the photo this session
              // we suppress both currentLocalPath and currentStoragePath
              // so the preview falls through to the fallback initial,
              // matching what the row will look like after save.
              currentLocalPath: _avatarCleared
                  ? null
                  : widget.adult?.avatarPath,
              currentStoragePath: _avatarCleared
                  ? null
                  : widget.adult?.avatarStoragePath,
              pendingFile: _pendingAvatar,
              fallbackInitial: _nameController.text.trim().isNotEmpty
                  ? _nameController.text.trim().characters.first.toUpperCase()
                  : '?',
              onChanged: (file) => setState(() {
                if (file == null) {
                  _pendingAvatar = null;
                  _avatarCleared = true;
                } else {
                  _pendingAvatar = file;
                  _avatarCleared = false;
                }
              }),
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
          _RoleFieldPicker(
            selectedRoleId: _roleId,
            onPick: (id) => setState(() {
              _roleId = id;
              // Picker wins: clear the free-text so the two inputs
              // don't fight. Teacher can still type over it below.
              if (id != null) _roleController.clear();
            }),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: _roleController,
            label: 'Or type a one-off title (optional)',
            hint: 'e.g. Floater · Visiting artist',
            onChanged: (v) => setState(() {
              // Typing clears the picker selection so we don't save
              // both an FK and a string — the legacy path wins.
              if (v.trim().isNotEmpty && _roleId != null) _roleId = null;
            }),
          ),
          const SizedBox(height: AppSpacing.lg),
          // v40: direct contact on the adult row itself. Placed right
          // under the name/role cluster so first-timers fill them out
          // in one pass. Validation matches how parents handle it —
          // lenient, no strict format check.
          AppTextField(
            controller: _phoneController,
            label: 'Phone (optional)',
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _emailController,
            label: 'Email (optional)',
            keyboardType: TextInputType.emailAddress,
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
          _ParentLinkSection(
            parentId: _parentId,
            onChanged: (id) => setState(() => _parentId = id),
          ),
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

/// Chip picker for the `Adults.roleId` FK (v39). Horizontal wrap of
/// ChoiceChips — one per Role row — plus an "+ New role" ActionChip
/// that spawns [EditRoleSheet] via rootNavigator and selects the
/// result when it pops with an id. Tapping the currently-selected
/// chip clears the selection (lets the teacher fall back to the
/// free-text field below).
class _RoleFieldPicker extends ConsumerWidget {
  const _RoleFieldPicker({
    required this.selectedRoleId,
    required this.onPick,
  });

  final String? selectedRoleId;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rolesAsync = ref.watch(rolesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Role', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Pick from the shared list, or tap "+ New role" to add one. '
          'Leave unpicked to type a one-off title below.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        rolesAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (err, _) => Text('Error: $err'),
          data: (roles) {
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final r in roles)
                  ChoiceChip(
                    label: Text(r.name),
                    selected: selectedRoleId == r.id,
                    onSelected: (_) => onPick(
                      selectedRoleId == r.id ? null : r.id,
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('New role'),
                  onPressed: () => _openNewRoleSheet(context),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _openNewRoleSheet(BuildContext context) async {
    final id = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (_) => const EditRoleSheet(),
    );
    if (id != null) onPick(id);
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
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'No groups yet. Add one below to anchor this lead.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => _openNewGroupWizard(context),
                      icon: const Icon(
                        Icons.group_add_outlined,
                        size: 18,
                      ),
                      label: const Text('New group'),
                    ),
                  ),
                ],
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
                // Action chip sits alongside the group chips so the
                // teacher can bootstrap a new group without leaving
                // this sheet. The wizard mounts above via
                // rootNavigator; groupsProvider auto-refreshes on
                // return, so the new chip shows up immediately.
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('New group'),
                  onPressed: () => _openNewGroupWizard(context),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// Spawns the New-Group wizard above this sheet. Uses
  /// rootNavigator so the new wizard sits above the sheet backdrop;
  /// on return the sheet stays up and the group chip row
  /// auto-refreshes via groupsProvider.
  Future<void> _openNewGroupWizard(BuildContext context) async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        // Nested spawn from an adult-edit sheet: disable the group
        // wizard's "+ New adult" cross-create so a nested adult
        // wizard can't recurse back into creating more groups.
        builder: (_) => const NewGroupWizardScreen(
          allowCreateAdultInline: false,
        ),
      ),
    );
  }
}

/// v40: "Link to parent record" section on the adult edit sheet.
/// When `parentId == null` shows an outlined button that opens a
/// picker sheet listing every Parent alphabetically with search.
/// When `parentId` is set shows a chip with the parent's display name
/// + a small X to un-link. The FK lives on `adults.parent_id`, so
/// the parallel section on EditParentSheet just does the reverse
/// lookup — no second column needed.
class _ParentLinkSection extends ConsumerWidget {
  const _ParentLinkSection({
    required this.parentId,
    required this.onChanged,
  });

  final String? parentId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Link to parent record', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Set when this staff member is also a parent of a child in '
          'the program. The parent row keeps pickup authorization and '
          'contact info; this row keeps their shift and role.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (parentId == null)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _pick(context, ref),
              icon: const Icon(Icons.person_add_outlined, size: 18),
              label: const Text('Link parent record'),
            ),
          )
        else
          _LinkedParentChip(
            parentId: parentId!,
            onClear: () => onChanged(null),
          ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const _ParentPickerSheet(),
    );
    if (picked != null) onChanged(picked);
  }
}

/// Chip rendered when the adult has a parent link set. Name lives in
/// the Parents table — stream it so the chip updates when someone
/// edits the parent's name elsewhere. X clears the link.
class _LinkedParentChip extends ConsumerWidget {
  const _LinkedParentChip({
    required this.parentId,
    required this.onClear,
  });

  final String parentId;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final parentAsync = ref.watch(parentProvider(parentId));
    final parent = parentAsync.asData?.value;
    final label = parent == null
        ? '…'
        : _displayName(parent);
    return Align(
      alignment: Alignment.centerLeft,
      child: InputChip(
        avatar: const Icon(Icons.person_outline, size: 16),
        label: Text(label),
        onDeleted: onClear,
        deleteIcon: const Icon(Icons.close, size: 16),
        deleteButtonTooltipMessage: 'Unlink parent',
        backgroundColor: theme.colorScheme.secondaryContainer,
      ),
    );
  }

  String _displayName(Parent p) {
    final last = p.lastName;
    return last == null || last.isEmpty
        ? p.firstName
        : '${p.firstName} $last';
  }
}

/// Modal sheet that lists every Parent alphabetically with a search
/// field at the top. Taps pop with the parent's id; search filters
/// by name substring (case-insensitive). Kept small and private —
/// shared picker infrastructure isn't worth the abstraction yet.
class _ParentPickerSheet extends ConsumerStatefulWidget {
  const _ParentPickerSheet();

  @override
  ConsumerState<_ParentPickerSheet> createState() =>
      _ParentPickerSheetState();
}

class _ParentPickerSheetState extends ConsumerState<_ParentPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parentsAsync = ref.watch(parentsProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                'Link parent record',
                style: theme.textTheme.titleLarge,
              ),
            ),
            AppTextField(
              controller: _searchController,
              label: 'Search parents',
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: parentsAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (err, _) => Text('Error: $err'),
                data: (parents) {
                  final filtered = _filter(parents);
                  if (filtered.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.lg,
                      ),
                      child: Text(
                        parents.isEmpty
                            ? 'No parents yet. Add one from the Parents '
                                'tab first.'
                            : 'No matches.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final p = filtered[i];
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor:
                              theme.colorScheme.secondaryContainer,
                          foregroundColor:
                              theme.colorScheme.onSecondaryContainer,
                          child: Text(
                            p.firstName.isEmpty
                                ? '?'
                                : p.firstName.characters.first
                                    .toUpperCase(),
                          ),
                        ),
                        title: Text(_display(p)),
                        subtitle: p.relationship == null ||
                                p.relationship!.isEmpty
                            ? null
                            : Text(p.relationship!),
                        onTap: () => Navigator.of(context).pop(p.id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Parent> _filter(List<Parent> all) {
    final sorted = [...all]..sort((a, b) {
        final byFirst =
            a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
        if (byFirst != 0) return byFirst;
        return (a.lastName ?? '')
            .toLowerCase()
            .compareTo((b.lastName ?? '').toLowerCase());
      });
    if (_query.isEmpty) return sorted;
    final q = _query.toLowerCase();
    return sorted.where((p) {
      final name = _display(p).toLowerCase();
      return name.contains(q);
    }).toList();
  }

  String _display(Parent p) {
    final last = p.lastName;
    return last == null || last.isEmpty
        ? p.firstName
        : '${p.firstName} $last';
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
