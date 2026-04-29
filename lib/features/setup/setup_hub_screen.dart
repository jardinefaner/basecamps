import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// `/more/setup` — single-page index for the program-config screens
/// teachers configure once and rarely revisit: Rooms, Vehicles, Roles,
/// Forms, Trips. Each row is a thin wrapper around a `context.push`
/// to the existing route — no data merging, no model changes.
///
/// Before: 5 separate launcher rows. After: 1 ("Setup"), and the
/// individual screens stay reachable through this hub or via the
/// launcher's global search (which already surfaces individual
/// rooms / vehicles / trips by name).
class SetupHubScreen extends StatelessWidget {
  const SetupHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = <_SetupEntry>[
      const _SetupEntry(
        icon: Icons.meeting_room_outlined,
        label: 'Rooms',
        subtitle: 'Where activities happen.',
        path: '/more/rooms',
      ),
      const _SetupEntry(
        icon: Icons.directions_bus_outlined,
        label: 'Vehicles',
        subtitle: 'Buses & vans for trips.',
        path: '/more/vehicles',
      ),
      const _SetupEntry(
        icon: Icons.work_outline,
        label: 'Roles',
        subtitle: 'Anchor / specialist / break / lunch.',
        path: '/more/roles',
      ),
      const _SetupEntry(
        icon: Icons.assignment_outlined,
        label: 'Forms',
        subtitle: 'Permission slips, parent concerns, custom forms.',
        path: '/more/forms',
      ),
      const _SetupEntry(
        icon: Icons.map_outlined,
        label: 'Trips',
        subtitle: 'Field-trip planning & rosters.',
        path: '/trips',
      ),
    ];
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Setup'),
        backgroundColor: theme.scaffoldBackgroundColor,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            0,
            AppSpacing.sm,
            0,
            AppSpacing.xxxl,
          ),
          children: [
            for (final e in entries)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xs,
                ),
                leading: Icon(
                  e.icon,
                  color: theme.colorScheme.primary,
                ),
                title: Text(e.label),
                subtitle: Text(
                  e.subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                onTap: () => context.push(e.path),
              ),
          ],
        ),
      ),
    );
  }
}

class _SetupEntry {
  const _SetupEntry({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.path,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final String path;
}
