import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/children/group_colors.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/step_wizard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Single-step wizard for creating a group. Groups are small but not
/// trivial — we take a name and an optional accent color so the group
/// reads at a glance on the Children tab and the launcher.
class NewGroupWizardScreen extends ConsumerStatefulWidget {
  const NewGroupWizardScreen({super.key});

  @override
  ConsumerState<NewGroupWizardScreen> createState() =>
      _NewGroupWizardScreenState();
}

class _NewGroupWizardScreenState extends ConsumerState<NewGroupWizardScreen> {
  final _name = TextEditingController();
  String? _colorHex;

  bool get _dirty => _name.text.trim().isNotEmpty || _colorHex != null;
  bool get _isValid => _name.text.trim().isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    await ref.read(childrenRepositoryProvider).addGroup(
          name: _name.text.trim(),
          colorHex: _colorHex,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StepWizardScaffold(
      title: 'New group',
      dirty: _dirty,
      finalActionLabel: 'Create group',
      onFinalAction: _submit,
      steps: [
        WizardStep(
          headline: 'Name and color',
          subtitle: 'A short name plus a color to tell it apart on the '
              'Children tab and the launcher.',
          canProceed: _isValid,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                controller: _name,
                label: 'Group name',
                hint: 'e.g. Dolphins',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Color', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              _GroupColorPicker(
                selectedHex: _colorHex,
                onChanged: (hex) => setState(() => _colorHex = hex),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Grid of preset group colors plus an "unset" chip. Shared between
/// the create wizard and the edit sheet so the two flows agree on
/// which swatches are offered.
class _GroupColorPicker extends StatelessWidget {
  const _GroupColorPicker({
    required this.selectedHex,
    required this.onChanged,
  });

  final String? selectedHex;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        // "No color" tile — outlined circle with a strike-through.
        _ColorDot(
          color: theme.colorScheme.surfaceContainerHigh,
          selected: selectedHex == null,
          border: theme.colorScheme.outlineVariant,
          icon: Icons.block,
          iconColor: theme.colorScheme.onSurfaceVariant,
          onTap: () => onChanged(null),
        ),
        for (final c in groupColors)
          _ColorDot(
            color: c.color,
            selected: c.hex == selectedHex,
            onTap: () => onChanged(c.hex),
          ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
    this.border,
    this.icon,
    this.iconColor,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final Color? border;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? theme.colorScheme.onSurface
                : (border ?? Colors.transparent),
            width: selected ? 3 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: icon != null
            ? Icon(icon, color: iconColor, size: 20)
            : (selected
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : null),
      ),
    );
  }
}
