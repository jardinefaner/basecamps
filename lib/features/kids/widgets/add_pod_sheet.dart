import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AddPodSheet extends ConsumerStatefulWidget {
  const AddPodSheet({super.key});

  @override
  ConsumerState<AddPodSheet> createState() => _AddPodSheetState();
}

class _AddPodSheetState extends ConsumerState<AddPodSheet> {
  final _nameController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _submitting = true);
    await ref.read(kidsRepositoryProvider).addPod(name: name);
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
          Text('New pod', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xl),
          AppTextField(
            controller: _nameController,
            label: 'Pod name',
            hint: 'e.g. Dolphins',
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton.primary(
            onPressed: _submit,
            label: 'Create pod',
            isLoading: _submitting,
          ),
        ],
      ),
    );
  }
}
