import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/attendance/attendance_repository.dart';
import 'package:basecamp/features/attendance/widgets/attendance_sheet.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:basecamp/features/today/widgets/schedule_item_card.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The "right now" hero that dominates the Today screen. Shows the
/// current activity title, a thin progress bar of time elapsed, a
/// countdown to the end, specialist + location, group-scoped children as
/// avatars, and a primary Capture button that jumps into Observe
/// (which auto-tags to whatever's current).
///
/// Rebuilds every minute via the parent's `nowTickProvider` watch, so
/// the progress bar and countdown stay live without any internal timer.
class HeroNowCard extends ConsumerWidget {
  const HeroNowCard({
    required this.item,
    required this.now,
    required this.observationCount,
    required this.onTap,
    required this.onCapture,
    this.attendance,
    this.onOpenAttendance,
    super.key,
  });

  final ScheduleItem item;
  final DateTime now;
  final int observationCount;
  final VoidCallback onTap;
  final VoidCallback onCapture;

  /// Optional attendance roll-up. When present the hero shows a
  /// "check-in" strip above Capture, tapping opens the inline sheet.
  final AttendanceSummary? attendance;
  final VoidCallback? onOpenAttendance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final nowMinutes = now.hour * 60 + now.minute;
    final start = item.startMinutes;
    final endParts = item.endTime.split(':');
    final end = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
    final total = (end - start).clamp(1, 24 * 60);
    final elapsed = (nowMinutes - start).clamp(0, total);
    final remaining = (end - nowMinutes).clamp(0, total);
    final progress = elapsed / total;

    final specialistId = item.specialistId;
    final specialist = specialistId == null
        ? null
        : ref.watch(specialistProvider(specialistId)).asData?.value;
    final allKids = ref.watch(childrenProvider).asData?.value ?? const <Child>[];
    // Respect the new three-state audience: "all groups" (everyone),
    // specific groups (filter by those), or no groups (teacher explicitly
    // chose no children — show an empty list). Always returns a new
    // growable list so the subsequent `.sort()` is safe.
    final List<Child> groupChildren;
    if (item.isAllGroups) {
      groupChildren = List<Child>.from(allKids);
    } else if (item.isNoGroups) {
      groupChildren = <Child>[];
    } else {
      groupChildren = allKids
          .where((k) => k.groupId != null && item.groupIds.contains(k.groupId))
          .toList();
    }
    groupChildren.sort((a, b) => a.firstName.compareTo(b.firstName));
    // Inline attendance only makes sense when there's a bounded group
    // to check in (not "everyone" and not "no one"). For all-groups we
    // fall back to the avatar row since the universe is too broad.
    final showInlineAttendance =
        !item.isAllGroups && !item.isNoGroups && groupChildren.isNotEmpty;
    final dayOnly = DateTime(now.year, now.month, now.day);
    final attendanceMap = showInlineAttendance
        ? (ref.watch(attendanceForDayProvider(dayOnly)).asData?.value ??
            const <String, AttendanceRecord>{})
        : const <String, AttendanceRecord>{};

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.4),
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'HAPPENING NOW',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                Text(
                  item.isFullDay
                      ? 'All day'
                      : '${_formatTime(item.startTime)} – '
                          '${_formatTime(item.endTime)}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              item.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (!item.isFullDay) ...[
              const SizedBox(height: AppSpacing.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor:
                      theme.colorScheme.primary.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(
                    theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Text(
                    '${_fmtDuration(elapsed)} in',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    remaining <= 0
                        ? 'wrapping up'
                        : 'ends in ${_fmtDuration(remaining)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: remaining <= 5
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            if (specialist != null || item.location != null) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                children: [
                  if (specialist != null)
                    _HeroChip(
                      icon: Icons.person_outline,
                      label: specialist.name,
                    ),
                  if (item.location != null && item.location!.isNotEmpty)
                    _HeroChip(
                      icon: Icons.place_outlined,
                      label: item.location!,
                    ),
                ],
              ),
            ],
            if (showInlineAttendance) ...[
              const SizedBox(height: AppSpacing.md),
              // Inline check-in — replaces the old decorative roster.
              // The attendance sheet lives right here on the hero so the
              // teacher can mark kids present/absent without opening a
              // modal.
              AttendanceTilesView(
                roster: groupChildren,
                attendance: attendanceMap,
                date: now,
              ),
            ] else if (groupChildren.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _ChildrenRow(children: groupChildren),
            ],
            if (!showInlineAttendance && attendance != null) ...[
              const SizedBox(height: AppSpacing.md),
              _HeroAttendanceStrip(
                summary: attendance!,
                onTap: onOpenAttendance,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                if (observationCount > 0) ...[
                  Icon(
                    Icons.edit_note_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '$observationCount logged',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const Spacer(),
                FilledButton.icon(
                  onPressed: onCapture,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Capture'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Short human duration for the elapsed / remaining labels. Uses
  /// hours when over an hour so "170m in" doesn't force the teacher to
  /// divide in their head. "45m" / "1h" / "1h 25m" / "3h".
  String _fmtDuration(int mins) {
    if (mins <= 0) return '0m';
    if (mins < 60) return '${mins}m';
    final h = mins ~/ 60;
    final m = mins % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
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

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _HeroAttendanceStrip extends StatelessWidget {
  const _HeroAttendanceStrip({required this.summary, this.onTap});

  final AttendanceSummary summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settled = summary.allSettled;
    final tint = settled
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;
    final subtitle = '${summary.present}/${summary.total} checked in'
        '${summary.absent > 0 ? " · ${summary.absent} absent" : ""}'
        '${summary.pending > 0 ? " · ${summary.pending} pending" : ""}';
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            Icon(
              settled
                  ? Icons.check_circle_outline
                  : Icons.how_to_reg_outlined,
              size: 18,
              color: tint,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                subtitle,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: tint,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChildrenRow extends StatelessWidget {
  const _ChildrenRow({required this.children});

  final List<Child> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const maxVisible = 6;
    final visible = children.take(maxVisible).toList();
    final overflow = children.length - visible.length;

    return Row(
      children: [
        for (final k in visible) ...[
          _ChildInitial(child: k),
          const SizedBox(width: 6),
        ],
        if (overflow > 0)
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              shape: BoxShape.circle,
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Text(
              '+$overflow',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            children.length == 1 ? '1 child' : '${children.length} children',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _ChildInitial extends StatelessWidget {
  const _ChildInitial({required this.child});

  final Child child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = child.firstName.isEmpty
        ? '?'
        : child.firstName.characters.first.toUpperCase();
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
