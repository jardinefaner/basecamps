import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Bottom sheet showing an activity's details and the kid roster for it.
/// Roster is derived from pod membership: kids whose pod is listed (or
/// all kids if the item targets "all pods").
class ActivityDetailSheet extends ConsumerWidget {
  const ActivityDetailSheet({required this.item, super.key});

  final ScheduleItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final kidsAsync = ref.watch(kidsProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.md,
        bottom: AppSpacing.xl + insets,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(item.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              item.isFullDay
                  ? 'All day'
                  : '${_formatTime(item.startTime)} – ${_formatTime(item.endTime)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _SpecialistRow(specialistId: item.specialistId),
            if (item.location != null && item.location!.isNotEmpty)
              _MetaRow(
                icon: Icons.place_outlined,
                text: item.location!,
              ),
            _PodsRow(podIds: item.podIds),
            if (item.notes != null && item.notes!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text('Notes', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(item.notes!, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: AppSpacing.xl),
            Text('Roster', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            kidsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text('Error: $err'),
              data: (kids) {
                final attending = kids
                    .where(
                      (k) =>
                          item.isAllPods ||
                          (k.podId != null && item.podIds.contains(k.podId)),
                    )
                    .toList();
                if (attending.isEmpty) {
                  return Text(
                    item.isNoPods
                        ? 'No pods selected — this activity has no kids.'
                        : 'No kids assigned to these pods yet.',
                    style: theme.textTheme.bodySmall,
                  );
                }
                return Column(
                  children: [
                    for (final kid in attending)
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _RosterTile(
                          kid: kid,
                          onTap: () {
                            Navigator.of(context).pop();
                            unawaited(context.push('/kids/${kid.id}'));
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.parse(parts[0]);
    final m = parts[1];
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final period = h < 12 ? 'a' : 'p';
    return m == '00' ? '$hour12$period' : '$hour12:$m$period';
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _SpecialistRow extends ConsumerWidget {
  const _SpecialistRow({required this.specialistId});

  final String? specialistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (specialistId == null) return const SizedBox.shrink();
    final specialist = ref.watch(specialistProvider(specialistId!)).asData?.value;
    if (specialist == null) return const SizedBox.shrink();
    final label = specialist.role == null || specialist.role!.isEmpty
        ? specialist.name
        : '${specialist.name} · ${specialist.role}';
    return _MetaRow(icon: Icons.badge_outlined, text: label);
  }
}

class _PodsRow extends ConsumerWidget {
  const _PodsRow({required this.podIds});

  final List<String> podIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (podIds.isEmpty) {
      return const _MetaRow(
        icon: Icons.groups_outlined,
        text: 'All pods',
      );
    }
    final names = <String>[];
    for (final id in podIds) {
      final pod = ref.watch(podProvider(id)).asData?.value;
      if (pod != null) names.add(pod.name);
    }
    if (names.isEmpty) return const SizedBox.shrink();
    return _MetaRow(
      icon: Icons.groups_outlined,
      text: names.join(' + '),
    );
  }
}

class _RosterTile extends ConsumerWidget {
  const _RosterTile({required this.kid, required this.onTap});

  final Kid kid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fullName =
        [kid.firstName, kid.lastName].whereType<String>().join(' ');
    final initial = kid.firstName.isNotEmpty
        ? kid.firstName.characters.first.toUpperCase()
        : '?';
    final podId = kid.podId;
    final pod =
        podId == null ? null : ref.watch(podProvider(podId)).asData?.value;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              initial,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fullName, style: theme.textTheme.titleMedium),
                if (pod != null)
                  Text(pod.name, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
