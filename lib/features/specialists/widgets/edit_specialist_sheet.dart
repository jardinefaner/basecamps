import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:basecamp/features/specialists/widgets/availability_editor.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EditSpecialistSheet extends ConsumerStatefulWidget {
  const EditSpecialistSheet({super.key, this.specialist});

  final Specialist? specialist;

  @override
  ConsumerState<EditSpecialistSheet> createState() =>
      _EditSpecialistSheetState();
}

class _EditSpecialistSheetState extends ConsumerState<EditSpecialistSheet> {
  late final _nameController =
      TextEditingController(text: widget.specialist?.name ?? '');
  late final _roleController =
      TextEditingController(text: widget.specialist?.role ?? '');
  late final _notesController =
      TextEditingController(text: widget.specialist?.notes ?? '');

  late String? _avatarPath = widget.specialist?.avatarPath;

  final Map<int, AvailabilityBlock> _availability = {};
  bool _availabilityLoaded = false;

  bool _submitting = false;

  bool get _isEdit => widget.specialist != null;
  bool get _isValid => _nameController.text.trim().isNotEmpty;

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
      });
      return;
    }
    final rows = await ref
        .read(specialistsRepositoryProvider)
        .availabilityFor(widget.specialist!.id);
    if (!mounted) return;
    setState(() {
      _availability.clear();
      for (final b in availabilityFromRows(rows)) {
        _availability[b.dayOfWeek] = b;
      }
      _availabilityLoaded = true;
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
    final repo = ref.read(specialistsRepositoryProvider);
    final name = _nameController.text.trim();
    final role =
        _roleController.text.trim().isEmpty ? null : _roleController.text.trim();
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();

    String id;
    if (_isEdit) {
      final existing = widget.specialist!;
      await repo.updateSpecialist(
        id: existing.id,
        name: name,
        role: role,
        notes: notes,
        avatarPath: _avatarPath,
        clearAvatarPath:
            _avatarPath == null && existing.avatarPath != null,
      );
      id = existing.id;
    } else {
      id = await repo.addSpecialist(
        name: name,
        role: role,
        notes: notes,
        avatarPath: _avatarPath,
      );
    }
    if (_availabilityLoaded) {
      await repo.replaceAvailability(
        specialistId: id,
        blocks: _availability.values.map((b) => b.toInput()).toList(),
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (!_isEdit) return;
    await ref
        .read(specialistsRepositoryProvider)
        .deleteSpecialist(widget.specialist!.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StickyActionSheet(
      title: _isEdit ? 'Edit specialist' : 'New specialist',
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
        onPressed: _isValid ? _submit : null,
        label: _isEdit ? 'Save' : 'Add specialist',
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
            label: 'Role (optional)',
            hint: 'e.g. Art teacher',
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
