import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AddKidSheet extends ConsumerStatefulWidget {
  const AddKidSheet({required this.pods, super.key, this.initialPodId});

  final List<Pod> pods;
  final String? initialPodId;

  @override
  ConsumerState<AddKidSheet> createState() => _AddKidSheetState();
}

class _AddKidSheetState extends ConsumerState<AddKidSheet> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  late String? _selectedPodId = widget.initialPodId ??
      (widget.pods.isNotEmpty ? widget.pods.first.id : null);
  bool _submitting = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final firstName = _firstNameController.text.trim();
    if (firstName.isEmpty) return;
    final lastName = _lastNameController.text.trim();
    setState(() => _submitting = true);
    await ref.read(kidsRepositoryProvider).addKid(
          firstName: firstName,
          lastName: lastName.isEmpty ? null : lastName,
          podId: _selectedPodId,
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
          Text('New kid', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xl),
          AppTextField(
            controller: _firstNameController,
            label: 'First name',
            hint: 'e.g. Jordan',
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _lastNameController,
            label: 'Last name (optional)',
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Pod', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _selectedPodId,
            items: [
              for (final pod in widget.pods)
                DropdownMenuItem(value: pod.id, child: Text(pod.name)),
            ],
            onChanged: (value) => setState(() => _selectedPodId = value),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton.primary(
            onPressed: _submit,
            label: 'Add kid',
            isLoading: _submitting,
          ),
        ],
      ),
    );
  }
}
