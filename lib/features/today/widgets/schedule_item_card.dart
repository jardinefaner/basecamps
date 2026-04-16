import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ScheduleItemCard extends ConsumerWidget {
  const ScheduleItemCard({
    required this.item,
    required this.isNow,
    required this.isPast,
    super.key,
  });

  final ScheduleItem item;
  final bool isNow;
  final bool isPast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final textColor = isPast
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface;

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: item.isFullDay
                ? Text(
                    'All\nday',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: isNow ? theme.colorScheme.primary : textColor,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatTime(item.startTime),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: isNow ? theme.colorScheme.primary : textColor,
                          fontWeight: isNow ? FontWeight.w700 : null,
                        ),
                      ),
                      Text(
                        _formatTime(item.endTime),
                        style: theme.textTheme.labelMedium,
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: AppSpacing.md),
          Container(
            width: 3,
            height: 48,
            decoration: BoxDecoration(
              color: isNow
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: textColor,
                        ),
                      ),
                    ),
                    if (isNow)
                      _StatusBadge(
                        label: 'NOW',
                        color: theme.colorScheme.primary,
                        textColor: theme.colorScheme.onPrimary,
                      )
                    else if (item.isOneOff)
                      _StatusBadge(
                        label: 'TODAY ONLY',
                        color: theme.colorScheme.tertiaryContainer,
                        textColor: theme.colorScheme.onTertiaryContainer,
                      ),
                  ],
                ),
                if (_subtitle(ref) != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _subtitle(ref)!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _subtitle(WidgetRef ref) {
    final parts = <String>[];
    if (item.podIds.isEmpty) {
      // "All pods" — don't surface this in the card, it's the default.
    } else {
      final names = <String>[];
      for (final podId in item.podIds) {
        final pod = ref.watch(podProvider(podId)).asData?.value;
        if (pod != null) names.add(pod.name);
      }
      if (names.isNotEmpty) parts.add(names.join(' + '));
    }
    if (item.specialistName != null && item.specialistName!.isNotEmpty) {
      parts.add(item.specialistName!);
    }
    if (item.location != null && item.location!.isNotEmpty) {
      parts.add(item.location!);
    }
    return parts.isEmpty ? null : parts.join(' · ');
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
