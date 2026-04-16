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
  DateTime? _date;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
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
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.md,
        bottom: AppSpacing.xl + insets,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New trip', style: theme.textTheme.titleLarge),
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
          AppTextField(
            controller: _locationController,
            label: 'Location (optional)',
            hint: 'e.g. Monterey Bay Aquarium',
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton.primary(
            onPressed: _isValid ? _submit : null,
            label: 'Create trip',
            isLoading: _submitting,
          ),
        ],
      ),
    );
  }
}
