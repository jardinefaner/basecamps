import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/vehicles/vehicles_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/save_action.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:basecamp/ui/undo_delete.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Add / edit a vehicle. Name is the only required field — make/model
/// and plate are optional for programs that only run one vehicle and
/// just call it "The Bus." Notes are free-form for VIN, parking,
/// insurance contact — whatever the program wants tied to the row.
class EditVehicleSheet extends ConsumerStatefulWidget {
  const EditVehicleSheet({super.key, this.vehicle});

  /// Null → create. Non-null → edit.
  final Vehicle? vehicle;

  @override
  ConsumerState<EditVehicleSheet> createState() => _EditVehicleSheetState();
}

class _EditVehicleSheetState extends ConsumerState<EditVehicleSheet> {
  late final _nameController =
      TextEditingController(text: widget.vehicle?.name ?? '');
  late final _makeModelController =
      TextEditingController(text: widget.vehicle?.makeModel ?? '');
  late final _plateController =
      TextEditingController(text: widget.vehicle?.licensePlate ?? '');
  late final _notesController =
      TextEditingController(text: widget.vehicle?.notes ?? '');
  bool _submitting = false;

  bool get _isEdit => widget.vehicle != null;
  bool get _isValid => _nameController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _nameController.dispose();
    _makeModelController.dispose();
    _plateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isValid || _submitting) return;
    setState(() => _submitting = true);
    final repo = ref.read(vehiclesRepositoryProvider);
    final name = _nameController.text.trim();
    final makeModel = _makeModelController.text.trim();
    final plate = _plateController.text.trim();
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();
    if (_isEdit) {
      await repo.updateVehicle(
        id: widget.vehicle!.id,
        name: name,
        makeModel: makeModel,
        licensePlate: plate,
        notes: Value(notes),
      );
    } else {
      await repo.addVehicle(
        name: name,
        makeModel: makeModel,
        licensePlate: plate,
        notes: notes,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (!_isEdit) return;
    final vehicle = widget.vehicle!;
    final navigator = Navigator.of(context);
    final confirmed = await confirmDeleteWithUndo(
      context: context,
      title: 'Delete "${vehicle.name}"?',
      message: 'Past vehicle-check forms keep their recorded id; the '
          'link just resolves to "(deleted vehicle)" afterwards. '
          "You'll get a 5-second window to undo.",
      onDelete: () =>
          ref.read(vehiclesRepositoryProvider).deleteVehicle(vehicle.id),
      undoLabel: '"${vehicle.name}" removed',
      onUndo: () =>
          ref.read(vehiclesRepositoryProvider).restoreVehicle(vehicle),
    );
    if (!confirmed || !mounted) return;
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StickyActionSheet(
      title: _isEdit ? 'Edit vehicle' : 'New vehicle',
      titleTrailing: _isEdit
          ? IconButton(
              onPressed: _delete,
              tooltip: 'Delete vehicle',
              icon: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error,
              ),
            )
          : null,
      actionBar: AppButton.primary(
        onPressed: _isValid && !_submitting
            ? () => runWithErrorReport(context, _submit)
            : null,
        label: _isEdit ? 'Save' : 'Add vehicle',
        isLoading: _submitting,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _nameController,
            label: 'Vehicle name',
            hint: 'e.g. Big Bus · Blue Van · The Car',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _makeModelController,
            label: 'Make & model (optional)',
            hint: 'e.g. Ford Transit 350',
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _plateController,
            label: 'License plate (optional)',
            hint: 'e.g. 03234E4',
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _notesController,
            label: 'Notes (optional)',
            hint: 'VIN, parking, insurance contact — whatever staff '
                'should know',
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}
