import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:basecamp/ui/step_wizard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

/// Create-only wizard for enrolling a new child. Follows the same
/// page-by-page pattern as the activity and adult wizards so
/// first-timers aren't stuck staring at every field at once. Editing
/// an existing child still uses the dense edit sheet.
class NewChildWizardScreen extends ConsumerStatefulWidget {
  const NewChildWizardScreen({
    required this.groups,
    this.initialGroupId,
    super.key,
  });

  final List<Group> groups;
  final String? initialGroupId;

  @override
  ConsumerState<NewChildWizardScreen> createState() =>
      _NewChildWizardScreenState();
}

class _NewChildWizardScreenState extends ConsumerState<NewChildWizardScreen> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _parentName = TextEditingController();
  final _notes = TextEditingController();

  XFile? _avatarFile;
  late String? _groupId = widget.initialGroupId;

  bool get _dirty =>
      _firstName.text.trim().isNotEmpty ||
      _lastName.text.trim().isNotEmpty ||
      _parentName.text.trim().isNotEmpty ||
      _notes.text.trim().isNotEmpty ||
      _avatarFile != null ||
      _groupId != widget.initialGroupId;

  bool get _page1Valid => _firstName.text.trim().isNotEmpty;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _parentName.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final last = _lastName.text.trim();
    final parent = _parentName.text.trim();
    final notes = _notes.text.trim();
    await ref.read(childrenRepositoryProvider).addChild(
          firstName: _firstName.text.trim(),
          lastName: last.isEmpty ? null : last,
          groupId: _groupId,
          notes: notes.isEmpty ? null : notes,
          avatarFile: _avatarFile,
          parentName: parent.isEmpty ? null : parent,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return StepWizardScaffold(
      title: 'New child',
      dirty: _dirty,
      finalActionLabel: 'Add child',
      onFinalAction: _submit,
      steps: [
        WizardStep(
          headline: "What's their name?",
          subtitle: 'First name is enough; last name and photo are optional.',
          canProceed: _page1Valid,
          content: _buildNamePage(),
        ),
        WizardStep(
          headline: 'Which group?',
          subtitle:
              'Groups are how the app organizes children for schedules and trips.',
          canSkip: true,
          content: _buildGroupPage(),
        ),
        WizardStep(
          headline: 'Parent or guardian',
          subtitle:
              'Used to pre-fill parent concern notes and future parent contact.',
          canSkip: true,
          content: AppTextField(
            controller: _parentName,
            label: 'Parent or guardian (optional)',
            hint: 'Their name',
          ),
        ),
        WizardStep(
          headline: 'Anything staff should know?',
          subtitle:
              'Allergies, quirks, accommodations, etc. Skip if nothing yet.',
          canSkip: true,
          content: AppTextField(
            controller: _notes,
            label: 'Notes (optional)',
            maxLines: 4,
          ),
        ),
      ],
    );
  }

  Widget _buildNamePage() {
    final initial = _firstName.text.trim().isNotEmpty
        ? _firstName.text.trim().characters.first.toUpperCase()
        : '?';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: AvatarPicker(
            // Wizard is create-only — no existing row to render.
            currentLocalPath: null,
            currentStoragePath: null,
            pendingFile: _avatarFile,
            fallbackInitial: initial,
            onChanged: (file) => setState(() => _avatarFile = file),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppTextField(
          controller: _firstName,
          label: 'First name',
          hint: 'e.g. Jordan',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          controller: _lastName,
          label: 'Last name (optional)',
        ),
      ],
    );
  }

  Widget _buildGroupPage() {
    final theme = Theme.of(context);
    if (widget.groups.isEmpty) {
      return Text(
        'No groups yet. You can add one from the Children tab after this '
        'child is created.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            ChoiceChip(
              label: const Text('Unassigned'),
              selected: _groupId == null,
              onSelected: (_) => setState(() => _groupId = null),
            ),
            for (final group in widget.groups)
              ChoiceChip(
                label: Text(group.name),
                selected: _groupId == group.id,
                onSelected: (_) => setState(() => _groupId = group.id),
              ),
          ],
        ),
      ],
    );
  }
}
