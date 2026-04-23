import 'package:basecamp/features/forms/polymorphic/form_definition.dart';
import 'package:basecamp/features/forms/polymorphic/registry.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Landing screen for the "Forms & surveys" section. Lists every
/// form type the app knows about — parent concern notes still on
/// its bespoke screen; everything new routes through the
/// polymorphic generic list screen.
class FormsHubScreen extends StatelessWidget {
  const FormsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forms & surveys')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          // Parent concern notes keeps its dedicated surface for now;
          // the polymorphic system can absorb it in a later slice
          // without breaking the export / share pipelines it already
          // has.
          _FormTypeTile(
            icon: Icons.chat_outlined,
            label: 'Parent concern notes',
            subtitle: 'Log concerns raised by parents or guardians',
            onTap: () => context.push('/more/forms/parent-concern'),
          ),
          for (final def in allFormDefinitions)
            _FormTypeTile(
              icon: def.icon,
              label: def.shortTitle,
              subtitle: def.subtitle,
              onTap: () =>
                  context.push('/more/forms/type/${def.typeKey}'),
              secondaryHint: def.parentTypeKey == null
                  ? null
                  : _followUpHintFor(def),
            ),
        ],
      ),
    );
  }

  /// Follow-up forms (like behavior monitoring) get a subtle "(from
  /// X)" suffix on the hub so teachers know the tile is a list
  /// viewer, not a "start anywhere" button.
  String? _followUpHintFor(FormDefinition def) {
    final parent = formDefinitionFor(def.parentTypeKey!);
    if (parent == null) return null;
    return 'Started from a ${parent.shortTitle.toLowerCase()}.';
  }
}

class _FormTypeTile extends StatelessWidget {
  const _FormTypeTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.secondaryHint,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final String? secondaryHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(label, style: theme.textTheme.titleMedium),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle, style: theme.textTheme.bodySmall),
          if (secondaryHint != null)
            Text(
              secondaryHint!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}
