import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(
            title: Text('More'),
            floating: true,
            snap: true,
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _MoreTile(
                  icon: Icons.badge_outlined,
                  label: 'Adults',
                  subtitle:
                      'Leads, adults, director, kitchen — '
                      'everyone on shift',
                  onTap: () => context.push('/more/adults'),
                ),
                _MoreTile(
                  icon: Icons.bookmarks_outlined,
                  label: 'Activity library',
                  subtitle: 'Reusable activities for the schedule',
                  onTap: () => context.push('/more/library'),
                ),
                _MoreTile(
                  icon: Icons.meeting_room_outlined,
                  label: 'Rooms',
                  subtitle:
                      'Tracked rooms + home-room defaults for groups',
                  onTap: () => context.push('/more/rooms'),
                ),
                _MoreTile(
                  icon: Icons.directions_bus_outlined,
                  label: 'Vehicles',
                  subtitle: 'Vans, buses, cars — picked on the '
                      'vehicle-check form',
                  onTap: () => context.push('/more/vehicles'),
                ),
                _MoreTile(
                  icon: Icons.assignment_outlined,
                  label: 'Forms & surveys',
                  subtitle: 'Attendance, incidents, parent concerns',
                  onTap: () => context.push('/more/forms'),
                ),
                _MoreTile(
                  icon: Icons.person_outline,
                  label: 'Profile',
                  subtitle: 'Your account',
                  onTap: () {},
                ),
                _MoreTile(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  subtitle: 'Grace windows, program-wide knobs',
                  onTap: () => context.push('/more/settings'),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    'Basecamp · v0.1',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
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
      leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
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
