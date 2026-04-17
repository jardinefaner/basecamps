import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/step_wizard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Single-step wizard for creating a pod. Pods are one field today
/// (name), but keep the wizard chrome so the "new thing" experience
/// stays consistent across the app. The progress strip auto-hides for
/// single-step wizards inside [StepWizardScaffold].
class NewPodWizardScreen extends ConsumerStatefulWidget {
  const NewPodWizardScreen({super.key});

  @override
  ConsumerState<NewPodWizardScreen> createState() =>
      _NewPodWizardScreenState();
}

class _NewPodWizardScreenState extends ConsumerState<NewPodWizardScreen> {
  final _name = TextEditingController();

  bool get _dirty => _name.text.trim().isNotEmpty;
  bool get _isValid => _name.text.trim().isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    await ref.read(kidsRepositoryProvider).addPod(name: _name.text.trim());
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return StepWizardScaffold(
      title: 'New pod',
      dirty: _dirty,
      finalActionLabel: 'Create pod',
      onFinalAction: _submit,
      steps: [
        WizardStep(
          headline: 'Name this pod',
          subtitle: 'A short name for the group — Dolphins, Redbirds, etc.',
          canProceed: _isValid,
          content: AppTextField(
            controller: _name,
            label: 'Pod name',
            hint: 'e.g. Dolphins',
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }
}
