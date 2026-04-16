import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Landing screen for the "Forms & surveys" section. Lists the form
/// types the staff can fill out — currently just parent concern notes;
/// other form types will drop in as siblings.
class FormsHubScreen extends StatelessWidget {
  const FormsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Forms & surveys')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          _FormTypeTile(
            icon: Icons.chat_outlined,
            label: 'Parent concern notes',
            subtitle: 'Log concerns raised by parents or guardians',
            onTap: () => context.push('/more/forms/parent-concern'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              'MORE COMING SOON',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const _DisabledTile(
            icon: Icons.person_off_outlined,
            label: 'Incident reports',
          ),
          const _DisabledTile(
            icon: Icons.checklist_outlined,
            label: 'Daily attendance',
          ),
          const _DisabledTile(
            icon: Icons.poll_outlined,
            label: 'Family satisfaction survey',
          ),
        ],
      ),
    );
  }
}

class _FormTypeTile extends StatelessWidget {
  const _FormTypeTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(label, style: theme.textTheme.titleMedium),
      subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}

class _DisabledTile extends StatelessWidget {
  const _DisabledTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      enabled: false,
      leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
      title: Text(label, style: theme.textTheme.titleMedium),
    );
  }
}
