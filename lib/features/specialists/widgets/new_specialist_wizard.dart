import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:basecamp/ui/step_wizard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Create-only wizard for a new specialist. Editing an existing row
/// still opens the dense edit sheet; this flow walks first-timers
/// through name → role → notes one page at a time.
class NewSpecialistWizardScreen extends ConsumerStatefulWidget {
  const NewSpecialistWizardScreen({super.key});

  @override
  ConsumerState<NewSpecialistWizardScreen> createState() =>
      _NewSpecialistWizardScreenState();
}

class _NewSpecialistWizardScreenState
    extends ConsumerState<NewSpecialistWizardScreen> {
  final _name = TextEditingController();
  final _role = TextEditingController();
  final _notes = TextEditingController();
  String? _avatarPath;

  bool get _dirty =>
      _name.text.trim().isNotEmpty ||
      _role.text.trim().isNotEmpty ||
      _notes.text.trim().isNotEmpty ||
      _avatarPath != null;

  bool get _page1Valid => _name.text.trim().isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final role = _role.text.trim();
    final notes = _notes.text.trim();
    await ref.read(specialistsRepositoryProvider).addSpecialist(
          name: _name.text.trim(),
          role: role.isEmpty ? null : role,
          notes: notes.isEmpty ? null : notes,
          avatarPath: _avatarPath,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return StepWizardScaffold(
      title: 'New specialist',
      dirty: _dirty,
      finalActionLabel: 'Add specialist',
      onFinalAction: _submit,
      steps: [
        WizardStep(
          headline: "Who's the specialist?",
          subtitle: 'Name and photo — you can change the photo later too.',
          canProceed: _page1Valid,
          content: _buildNamePage(),
        ),
        WizardStep(
          headline: 'What do they do?',
          subtitle: 'Art teacher, swim instructor, nurse — whatever fits.',
          canSkip: true,
          content: AppTextField(
            controller: _role,
            label: 'Role (optional)',
            hint: 'e.g. Art teacher',
          ),
        ),
        WizardStep(
          headline: 'Anything worth noting?',
          subtitle: 'Internal notes for staff. Skip if nothing comes to mind.',
          canSkip: true,
          content: AppTextField(
            controller: _notes,
            label: 'Notes (optional)',
            hint: 'Certifications, availability quirks, etc.',
            maxLines: 4,
          ),
        ),
      ],
    );
  }

  Widget _buildNamePage() {
    final initial = _name.text.trim().isNotEmpty
        ? _name.text.trim().characters.first.toUpperCase()
        : '?';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: AvatarPicker(
            currentPath: _avatarPath,
            fallbackInitial: initial,
            onChanged: (p) => setState(() => _avatarPath = p),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppTextField(
          controller: _name,
          label: 'Name',
          hint: 'e.g. Sarah',
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }
}
