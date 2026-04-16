import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
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
    return StickyActionSheet(
      title: 'New pod',
      actionBar: AppButton.primary(
        onPressed: _submit,
        label: 'Create pod',
        isLoading: _submitting,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _nameController,
            label: 'Pod name',
            hint: 'e.g. Dolphins',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
