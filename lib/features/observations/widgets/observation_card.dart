import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class ObservationCard extends ConsumerWidget {
  const ObservationCard({
    required this.observation,
    this.onTap,
    super.key,
  });

  final Observation observation;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final domain = ObservationDomain.fromName(observation.domain);
    final sentiment = ObservationSentiment.fromName(observation.sentiment);
    final time = DateFormat.MMMd().add_jm().format(observation.createdAt);

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SentimentIcon(sentiment: sentiment),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _TargetLabel(observation: observation),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(domain.label, style: theme.textTheme.labelMedium),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(observation.note, style: theme.textTheme.bodyMedium),
          if (observation.activityLabel != null &&
              observation.activityLabel!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(
                  Icons.schedule_outlined,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'During ${observation.activityLabel!}',
                    style: theme.textTheme.labelSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(time, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _SentimentIcon extends StatelessWidget {
  const _SentimentIcon({required this.sentiment});

  final ObservationSentiment sentiment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = switch (sentiment) {
      ObservationSentiment.positive => (
          Icons.sentiment_satisfied,
          theme.colorScheme.primary,
        ),
      ObservationSentiment.neutral => (
          Icons.sentiment_neutral,
          theme.colorScheme.onSurfaceVariant,
        ),
      ObservationSentiment.concern => (
          Icons.flag,
          theme.colorScheme.error,
        ),
    };
    return Icon(icon, size: 18, color: color);
  }
}

class _TargetLabel extends ConsumerWidget {
  const _TargetLabel({required this.observation});

  final Observation observation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final kidsAsync = ref.watch(observationKidsProvider(observation.id));
    return kidsAsync.when(
      loading: () => Text('…', style: theme.textTheme.titleMedium),
      error: (err, _) =>
          Text('Error', style: theme.textTheme.titleMedium),
      data: (kids) {
        if (kids.isNotEmpty) {
          return Text(
            _formatKidList(kids),
            style: theme.textTheme.titleMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          );
        }
        // Fallbacks for legacy single-kid or pod/activity-scoped observations.
        final legacyKidId = observation.kidId;
        if (legacyKidId != null) {
          final kidAsync = ref.watch(kidProvider(legacyKidId));
          return kidAsync.maybeWhen(
            data: (k) => Text(
              k == null ? 'Unknown kid' : _singleKidLabel(k),
              style: theme.textTheme.titleMedium,
            ),
            orElse: () => Text('…', style: theme.textTheme.titleMedium),
          );
        }
        final podId = observation.podId;
        if (podId != null) {
          final podAsync = ref.watch(podProvider(podId));
          return podAsync.maybeWhen(
            data: (p) => Text(
              p?.name ?? 'Unknown pod',
              style: theme.textTheme.titleMedium,
            ),
            orElse: () => Text('…', style: theme.textTheme.titleMedium),
          );
        }
        return Text(
          observation.activityLabel ?? 'General note',
          style: theme.textTheme.titleMedium,
        );
      },
    );
  }

  String _singleKidLabel(Kid kid) {
    final last = kid.lastName;
    if (last == null || last.isEmpty) return kid.firstName;
    return '${kid.firstName} ${last[0]}.';
  }

  String _formatKidList(List<Kid> kids) {
    if (kids.length == 1) return _singleKidLabel(kids.first);
    if (kids.length == 2) {
      return '${_singleKidLabel(kids[0])} & ${_singleKidLabel(kids[1])}';
    }
    final firstTwo = kids.take(2).map(_singleKidLabel).join(', ');
    return '$firstTwo + ${kids.length - 2} more';
  }
}
