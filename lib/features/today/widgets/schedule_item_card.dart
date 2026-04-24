import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/schedule/conflicts.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/widgets/conflict_sheet.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// List card for an activity on Today. Shows time, title, group/adult/
/// location subtitle, status badges, and (when relevant) three dynamic
/// affordances:
///
/// * **Next-up badge** — the very next upcoming activity displays an
///   "IN N MIN" chip so the teacher can prep.
/// * **Obs prompt** — past activities with zero observations today surface
///   a subtle "Log observations →" strip; tapping jumps to Observe.
/// * **Concern flag** — a red chip when any child in this activity's group
///   has an active concern logged today; tapping opens that concern.
class ScheduleItemCard extends ConsumerWidget {
  const ScheduleItemCard({
    required this.item,
    required this.isNow,
    required this.isPast,
    this.conflicts = const [],
    this.minutesUntilStart,
    this.showLogObservationsPrompt = false,
    this.concernMatch,
    this.attendance,
    this.onTap,
    this.onLogObservations,
    this.onOpenConcern,
    this.onOpenAttendance,
    super.key,
  });

  final ScheduleItem item;
  final bool isNow;
  final bool isPast;
  final List<ConflictInfo> conflicts;

  /// Non-null only for the single "next up" activity. When ≤ 60 the card
  /// shows an "IN N MIN" chip to cue the teacher to wrap up and prep.
  final int? minutesUntilStart;

  /// When true, renders a "Log observations →" strip under the subtitle.
  /// Only the parent knows what counts as "past with zero logs" — it
  /// resolves the flag from today's activity-count map.
  final bool showLogObservationsPrompt;

  /// A concern to surface if any child in this activity's group matches.
  /// The parent does the group-to-concern lookup; this card just renders
  /// whatever it's handed.
  final ConcernMatch? concernMatch;

  /// Today's attendance for the children in this activity's groups.
  /// Null hides the check-in strip (e.g. "all groups" activities that
  /// don't usefully roll up to a per-activity roster).
  final AttendanceSummary? attendance;

  final VoidCallback? onTap;
  final VoidCallback? onLogObservations;
  final VoidCallback? onOpenConcern;
  final VoidCallback? onOpenAttendance;

  bool get _hasConflict => conflicts.isNotEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final textColor = isPast
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 60,
                child: item.isFullDay
                    ? Text(
                        'All\nday',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: isNow
                              ? theme.colorScheme.primary
                              : textColor,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatTime(item.startTime),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: isNow
                                  ? theme.colorScheme.primary
                                  : textColor,
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
                        if (_hasConflict) ...[
                          Tooltip(
                            message: 'Tap to see conflict',
                            child: InkResponse(
                              radius: 18,
                              onTap: () => _openConflictSheet(context),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  size: 18,
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                        ],
                        _TrailingBadge(
                          isNow: isNow,
                          minutesUntilStart: minutesUntilStart,
                          isOneOff: item.isOneOff,
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
          if (concernMatch != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _ConcernStrip(
              match: concernMatch!,
              onTap: onOpenConcern,
            ),
          ],
          if (attendance != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _AttendanceStrip(
              summary: attendance!,
              onTap: onOpenAttendance,
            ),
          ],
          if (showLogObservationsPrompt) ...[
            const SizedBox(height: AppSpacing.sm),
            _LogObservationsStrip(onTap: onLogObservations),
          ],
        ],
      ),
    );
  }

  Future<void> _openConflictSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ConflictSheet(item: item, conflicts: conflicts),
    );
  }

  String? _subtitle(WidgetRef ref) {
    final parts = <String>[];
    if (item.groupIds.isNotEmpty) {
      final names = <String>[];
      for (final groupId in item.groupIds) {
        final group = ref.watch(groupProvider(groupId)).asData?.value;
        if (group != null) names.add(group.name);
      }
      if (names.isNotEmpty) parts.add(names.join(' + '));
    }
    final adultId = item.adultId;
    if (adultId != null) {
      final adult =
          ref.watch(adultProvider(adultId)).asData?.value;
      if (adult != null) parts.add(adult.name);
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

/// Payload the parent hands the card when a group-matching concern exists
/// for today. [preview] is a short string to show on the strip (first
/// line of the concern, typically).
class ConcernMatch {
  const ConcernMatch({required this.id, required this.preview});
  final String id;
  final String preview;
}

/// Per-activity roll-up of today's attendance. The card uses this for a
/// compact "checked in" strip that doubles as the tap target for the
/// inline attendance sheet.
class AttendanceSummary {
  const AttendanceSummary({
    required this.present,
    required this.absent,
    required this.total,
  });

  final int present;
  final int absent;
  final int total;

  int get pending => (total - present - absent).clamp(0, total);
  bool get allSettled => pending == 0 && total > 0;
  bool get allPresent => present == total && total > 0;
}

class _TrailingBadge extends StatelessWidget {
  const _TrailingBadge({
    required this.isNow,
    required this.minutesUntilStart,
    required this.isOneOff,
  });

  final bool isNow;
  final int? minutesUntilStart;
  final bool isOneOff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (isNow) {
      return _Chip(
        label: 'NOW',
        bg: theme.colorScheme.primary,
        fg: theme.colorScheme.onPrimary,
      );
    }
    final mins = minutesUntilStart;
    if (mins != null && mins > 0 && mins <= 60) {
      return _Chip(
        label: mins <= 1 ? 'IN 1 MIN' : 'IN $mins MIN',
        bg: theme.colorScheme.secondaryContainer,
        fg: theme.colorScheme.onSecondaryContainer,
      );
    }
    if (isOneOff) {
      return _Chip(
        label: 'TODAY ONLY',
        bg: theme.colorScheme.tertiaryContainer,
        fg: theme.colorScheme.onTertiaryContainer,
      );
    }
    return const SizedBox.shrink();
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.bg, required this.fg});

  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _LogObservationsStrip extends StatelessWidget {
  const _LogObservationsStrip({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.edit_note_outlined,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'Log observations',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward,
              size: 14,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceStrip extends StatelessWidget {
  const _AttendanceStrip({required this.summary, this.onTap});

  final AttendanceSummary summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Color ramps with how "done" check-in is: neutral pending, warm
    // primary once everyone's settled.
    final settled = summary.allSettled;
    final tint = settled
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final bg = settled
        ? theme.colorScheme.primary.withValues(alpha: 0.08)
        : theme.colorScheme.surfaceContainerLow;
    final subtitle = summary.total == 0
        ? 'No children in this activity'
        : '${summary.present}/${summary.total} present'
            '${summary.absent > 0 ? " · ${summary.absent} absent" : ""}'
            '${summary.pending > 0 ? " · ${summary.pending} pending" : ""}';

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              settled
                  ? Icons.check_circle_outline
                  : Icons.how_to_reg_outlined,
              size: 16,
              color: tint,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                subtitle,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: settled
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward,
              size: 14,
              color: tint,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConcernStrip extends StatelessWidget {
  const _ConcernStrip({required this.match, this.onTap});

  final ConcernMatch match;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.error.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.priority_high_rounded,
              size: 16,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                match.preview,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.arrow_forward,
              size: 14,
              color: theme.colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }
}
