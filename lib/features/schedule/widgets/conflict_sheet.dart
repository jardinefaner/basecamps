import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/rooms/rooms_repository.dart';
import 'package:basecamp/features/schedule/adult_shift_conflicts.dart';
import 'package:basecamp/features/schedule/conflicts.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/trip_conflicts.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom sheet explaining why a given item is flagged as a conflict —
/// which activities it clashes with, and whether the clash is group-based,
/// adult-based, or both.
class ConflictSheet extends ConsumerWidget {
  const ConflictSheet({
    required this.item,
    required this.conflicts,
    this.shiftConflicts = const [],
    this.tripConflicts = const [],
    super.key,
  });

  final ScheduleItem item;
  final List<ConflictInfo> conflicts;

  /// Shift-window clashes (break / lunch / off-shift / no-availability)
  /// for the assigned adult — rendered in a dedicated section below
  /// the activity clashes.
  final List<ShiftConflict> shiftConflicts;

  /// Trip clashes — rendered in their own section.
  final List<TripConflict> tripConflicts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final insets = MediaQuery.of(context).viewInsets.bottom;

    // Short leading sentence tailored to whichever sections are
    // populated — "overlaps with these activities" reads as a lie
    // when the only flag is "outside Sarah's shift".
    final hasActivities = conflicts.isNotEmpty;
    final hasShift = shiftConflicts.isNotEmpty;
    final hasTrip = tripConflicts.isNotEmpty;
    final intro = _buildIntro(
      hasActivities: hasActivities,
      hasShift: hasShift,
      hasTrip: hasTrip,
      activityCount: conflicts.length,
    );

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
              intro,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (hasActivities) ...[
              for (final info in conflicts)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _ConflictCard(info: info),
                ),
            ],
            if (hasShift) ...[
              if (hasActivities) const SizedBox(height: AppSpacing.sm),
              const _SectionHeader(label: 'Shift clashes'),
              const SizedBox(height: AppSpacing.xs),
              for (final s in shiftConflicts)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _ShiftConflictCard(conflict: s),
                ),
            ],
            if (hasTrip) ...[
              if (hasActivities || hasShift)
                const SizedBox(height: AppSpacing.sm),
              const _SectionHeader(label: 'Trip clashes'),
              const SizedBox(height: AppSpacing.xs),
              for (final t in tripConflicts)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _TripConflictCard(conflict: t),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _buildIntro({
    required bool hasActivities,
    required bool hasShift,
    required bool hasTrip,
    required int activityCount,
  }) {
    if (hasActivities) {
      return '"${item.title}" overlaps with ${activityCount == 1 ? "this activity" : "these activities"}:';
    }
    if (hasShift && hasTrip) {
      return '"${item.title}" runs into a shift window and a trip today.';
    }
    if (hasShift) {
      return '"${item.title}" runs into the assigned adult\'s shift.';
    }
    if (hasTrip) {
      return '"${item.title}" overlaps with a trip today.';
    }
    return '"${item.title}" has a conflict.';
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
    if (info.groupClash) {
      final sharedNames = <String>[];
      for (final id in info.sharedGroupIds) {
        final group = ref.watch(groupProvider(id)).asData?.value;
        if (group != null) sharedNames.add(group.name);
      }
      final label = sharedNames.isNotEmpty
          ? 'Group double-booked: ${sharedNames.join(", ")}'
          : other.groupIds.isEmpty || info.sharedGroupIds.isEmpty
              ? 'Group double-booked (all groups)'
              : 'Group double-booked';
      reasonChips.add(_ReasonChip(
        icon: Icons.groups_outlined,
        label: label,
      ));
    }
    if (info.adultClash) {
      // Default when the adult row was deleted / can't be resolved —
      // don't leak the "adult" label to teachers.
      var label = 'Adult double-booked';
      final sid = other.adultId;
      if (sid != null) {
        final adult = ref.watch(adultProvider(sid)).asData?.value;
        if (adult != null) {
          label = '${adult.name} double-booked';
        }
      }
      reasonChips.add(_ReasonChip(
        icon: Icons.badge_outlined,
        label: label,
      ));
    }
    if (info.roomClash) {
      var label = 'Same room double-booked';
      final rid = other.roomId;
      if (rid != null) {
        final room = ref.watch(roomProvider(rid)).asData?.value;
        if (room != null) {
          label = '${room.name} double-booked';
        }
      }
      reasonChips.add(_ReasonChip(
        icon: Icons.meeting_room_outlined,
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _ShiftConflictCard extends StatelessWidget {
  const _ShiftConflictCard({required this.conflict});

  final ShiftConflict conflict;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Kind-specific icon — coffee for a break, restaurant for lunch,
    // schedule_off for "outside the shift", event_busy when the adult
    // isn't here today at all.
    final icon = switch (conflict.kind) {
      ShiftConflictKind.breakWindow => Icons.coffee_outlined,
      ShiftConflictKind.break2Window => Icons.coffee_outlined,
      ShiftConflictKind.lunchWindow => Icons.restaurant_outlined,
      ShiftConflictKind.offShift => Icons.schedule_outlined,
      ShiftConflictKind.noAvailabilityToday => Icons.event_busy_outlined,
    };
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              conflict.reason,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _TripConflictCard extends StatelessWidget {
  const _TripConflictCard({required this.conflict});

  final TripConflict conflict;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.map_outlined,
            size: 18,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              conflict.reason,
              style: theme.textTheme.bodyMedium,
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
