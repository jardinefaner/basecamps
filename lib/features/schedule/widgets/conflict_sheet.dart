import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/schedule/conflicts.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom sheet explaining why a given item is flagged as a conflict —
/// which activities it clashes with, and whether the clash is pod-based,
/// specialist-based, or both.
class ConflictSheet extends ConsumerWidget {
  const ConflictSheet({
    required this.item,
    required this.conflicts,
    super.key,
  });

  final ScheduleItem item;
  final List<ConflictInfo> conflicts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final insets = MediaQuery.of(context).viewInsets.bottom;

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
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Schedule conflict',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '"${item.title}" overlaps with ${conflicts.length == 1 ? "this activity" : "these activities"}:',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final info in conflicts)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _ConflictCard(info: info),
              ),
          ],
        ),
      ),
    );
  }
}

class _ConflictCard extends ConsumerWidget {
  const _ConflictCard({required this.info});

  final ConflictInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final other = info.other;

    final reasonChips = <Widget>[];
    if (info.podClash) {
      final sharedNames = <String>[];
      for (final id in info.sharedPodIds) {
        final pod = ref.watch(podProvider(id)).asData?.value;
        if (pod != null) sharedNames.add(pod.name);
      }
      final label = sharedNames.isNotEmpty
          ? 'Group double-booked: ${sharedNames.join(", ")}'
          : other.podIds.isEmpty || info.sharedPodIds.isEmpty
              ? 'Group double-booked (all groups)'
              : 'Group double-booked';
      reasonChips.add(_ReasonChip(
        icon: Icons.groups_outlined,
        label: label,
      ));
    }
    if (info.specialistClash) {
      var label = 'Specialist double-booked';
      final sid = other.specialistId;
      if (sid != null) {
        final specialist = ref.watch(specialistProvider(sid)).asData?.value;
        if (specialist != null) {
          label = '${specialist.name} double-booked';
        }
      }
      reasonChips.add(_ReasonChip(
        icon: Icons.badge_outlined,
        label: label,
      ));
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(other.title, style: theme.textTheme.titleMedium),
              ),
              Text(
                other.isFullDay
                    ? 'All day'
                    : '${_formatTime(other.startTime)} – ${_formatTime(other.endTime)}',
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: reasonChips,
          ),
        ],
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  const _ReasonChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatTime(String hhmm) {
  final parts = hhmm.split(':');
  final h = int.parse(parts[0]);
  final m = parts[1];
  final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
  final period = h < 12 ? 'a' : 'p';
  return m == '00' ? '$hour12$period' : '$hour12:$m$period';
}
