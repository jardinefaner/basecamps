import 'package:basecamp/database/database.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TripCard extends StatelessWidget {
  const TripCard({
    required this.trip,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
    super.key,
  });

  final Trip trip;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isPast = trip.date.isBefore(DateTime(now.year, now.month, now.day));
    final dateLabel = DateFormat.MMMEd().format(trip.date);

    return AppCard(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isPast
                  ? theme.colorScheme.surfaceContainerHigh
                  : theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat.MMM().format(trip.date).toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isPast
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                Text(
                  DateFormat.d().format(trip.date),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: isPast
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trip.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  trip.location ?? dateLabel,
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
