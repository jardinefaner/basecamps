import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:basecamp/features/forms/widgets/specialist_chip_picker.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/step_wizard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Create-only wizard for a new library item. Edits still use the
/// dense edit sheet. Library items are reusable defaults (title +
/// duration + default specialist + default location) that get pulled
/// in via the "From library" pick on the activity wizard.
class NewLibraryItemWizardScreen extends ConsumerStatefulWidget {
  const NewLibraryItemWizardScreen({super.key});

  @override
  ConsumerState<NewLibraryItemWizardScreen> createState() =>
      _NewLibraryItemWizardScreenState();
}

class _NewLibraryItemWizardScreenState
    extends ConsumerState<NewLibraryItemWizardScreen> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();

  int? _durationMin;
  String? _specialistId;

  bool get _dirty =>
      _title.text.trim().isNotEmpty ||
      _location.text.trim().isNotEmpty ||
      _notes.text.trim().isNotEmpty ||
      _durationMin != null ||
      _specialistId != null;

  bool get _page1Valid => _title.text.trim().isNotEmpty;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final location = _location.text.trim();
    final notes = _notes.text.trim();
    await ref.read(activityLibraryRepositoryProvider).addItem(
          title: _title.text.trim(),
          defaultDurationMin: _durationMin,
          specialistId: _specialistId,
          location: location.isEmpty ? null : location,
          notes: notes.isEmpty ? null : notes,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return StepWizardScaffold(
      title: 'New library item',
      dirty: _dirty,
      finalActionLabel: 'Add to library',
      onFinalAction: _submit,
      steps: [
        WizardStep(
          headline: "What's the activity?",
          subtitle:
              'Title + a default duration. This is the template pulled in '
              'when you tap "From library" on a new schedule item.',
          canProceed: _page1Valid,
          content: _buildTitlePage(),
        ),
        WizardStep(
          headline: 'Default specialist & location',
          subtitle:
              'Auto-filled when you pull this item into a schedule — still '
              'overridable then. Skip if it varies.',
          canSkip: true,
          content: _buildSpecialistPage(),
        ),
        WizardStep(
          headline: 'Notes',
          subtitle: 'Optional prep-list or supplies — shown when picking '
              'from the library.',
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

  Widget _buildTitlePage() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: _title,
          label: 'Title',
          hint: 'e.g. Morning circle · Snack · Pickup',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Default duration', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final entry in const [
              ('—', null),
              ('15m', 15),
              ('30m', 30),
              ('45m', 45),
              ('1h', 60),
              ('90m', 90),
              ('2h', 120),
            ])
              ChoiceChip(
                label: Text(entry.$1),
                selected: _durationMin == entry.$2,
                onSelected: (_) => setState(() => _durationMin = entry.$2),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSpecialistPage() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Default specialist', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        SpecialistChipPicker(
          selectedId: _specialistId,
          onChanged: (id) => setState(() => _specialistId = id),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppTextField(
          controller: _location,
          label: 'Default location (optional)',
          hint: 'Room, gym, field…',
        ),
      ],
    );
  }
}
