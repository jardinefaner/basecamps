import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/attendance/attendance_repository.dart';
import 'package:basecamp/features/attendance/widgets/attendance_sheet.dart';
import 'package:basecamp/features/children/child_schedule_repository.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/today/lateness.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Top-of-Today strip surfacing lateness + overdue-pickup flags.
/// Self-hides when no kids are flagged — the goal is a quiet screen
/// when things are going fine, loud only when the teacher needs to
/// act. Two sections: late arrivals (morning) and overdue pickups
/// (afternoon / evening); either half self-hides if empty, which is
/// the norm for most of the day.
///
/// Taps a flag row → opens today's attendance sheet pre-focused on
/// the kid's group, so the teacher can mark them present/absent /
/// record pickup in the flow they already know. No dedicated
/// "resolve this flag" action; clearing the flag is a side effect of
/// taking the right attendance action.
class LatenessFlagsStrip extends ConsumerWidget {
  const LatenessFlagsStrip({required this.now, super.key});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final kids = ref.watch(childrenProvider).asData?.value ??
        const <Child>[];
    final attendance = ref.watch(todayAttendanceProvider).asData?.value ??
        const <String, AttendanceRecord>{};
    final overrides = ref.watch(todayOverridesProvider).asData?.value ??
        const <String, ChildScheduleOverride>{};

    final lateFlags = computeLatenessFlags(
      now: now,
      children: kids,
      attendance: attendance,
      overrides: overrides,
    );
    final overdueFlags = computeOverduePickupFlags(
      now: now,
      children: kids,
      attendance: attendance,
      overrides: overrides,
    );
    if (lateFlags.isEmpty && overdueFlags.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        // Tertiary-container not error-container: flagged doesn't
        // mean crisis, it means "this needs a look." Error-red would
        // overshoot and train teachers to dismiss the strip.
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lateFlags.isNotEmpty) ...[
            _SectionHeader(
              icon: Icons.access_time_outlined,
              label: lateFlags.length == 1
                  ? '1 KID LATE'
                  : '${lateFlags.length} KIDS LATE',
            ),
            const SizedBox(height: AppSpacing.sm),
            for (var i = 0; i < lateFlags.length; i++) ...[
              if (i > 0) _sectionDivider(theme),
              _FlagRow(
                title: _displayName(lateFlags[i].child),
                detail: '${_lateLabel(lateFlags[i].minutesLate)} · '
                    'expected ${_fmt12h(lateFlags[i].expectedArrival)}',
                note: lateFlags[i].note,
                onTap: () =>
                    _openAttendanceForChild(context, lateFlags[i].child),
              ),
            ],
          ],
          if (lateFlags.isNotEmpty && overdueFlags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: _sectionDivider(theme),
            ),
          if (overdueFlags.isNotEmpty) ...[
            _SectionHeader(
              icon: Icons.exit_to_app_outlined,
              label: overdueFlags.length == 1
                  ? '1 PICKUP OVERDUE'
                  : '${overdueFlags.length} PICKUPS OVERDUE',
            ),
            const SizedBox(height: AppSpacing.sm),
            for (var i = 0; i < overdueFlags.length; i++) ...[
              if (i > 0) _sectionDivider(theme),
              _FlagRow(
                title: _displayName(overdueFlags[i].child),
                detail: '${_overdueLabel(overdueFlags[i].minutesOverdue)}'
                    ' · expected ${_fmt12h(overdueFlags[i].expectedPickup)}',
                note: overdueFlags[i].note,
                onTap: () => _openAttendanceForChild(
                  context,
                  overdueFlags[i].child,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Attendance-sheet entry point used by all flag rows. Scopes to the
  /// child's pod when they have one, falling back to whole-program on
  /// Unassigned kids so the sheet never opens empty.
  Future<void> _openAttendanceForChild(BuildContext context, Child child) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) {
        final groupId = child.groupId;
        return AttendanceSheet(
          groupIds: groupId == null ? const [] : [groupId],
          date: now,
          activityTitle: 'Check in · ${child.firstName}',
        );
      },
    );
  }

  Widget _sectionDivider(ThemeData theme) => Divider(
        height: 1,
        thickness: 0.5,
        color: theme.colorScheme.onTertiaryContainer.withValues(alpha: 0.2),
      );

  String _displayName(Child c) {
    final last = c.lastName;
    if (last == null || last.trim().isEmpty) return c.firstName;
    return '${c.firstName} ${last.trim().characters.first}.';
  }

  String _lateLabel(int minsLate) {
    if (minsLate == 0) return 'just late';
    if (minsLate < 60) return '$minsLate min late';
    return '${minsLate ~/ 60}h ${minsLate % 60} min late';
  }

  String _overdueLabel(int mins) {
    if (mins == 0) return 'just overdue';
    if (mins < 60) return '$mins min overdue';
    return '${mins ~/ 60}h ${mins % 60} min overdue';
  }
}

/// Small inline section label (e.g. "2 KIDS LATE"). Icon + caps label
/// in the strip's on-tertiary foreground color, used at the top of
/// each half of the strip.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: theme.colorScheme.onTertiaryContainer,
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onTertiaryContainer,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _FlagRow extends StatelessWidget {
  const _FlagRow({
    required this.title,
    required this.detail,
    required this.onTap,
    this.note,
  });

  final String title;
  final String detail;
  final String? note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme.onTertiaryContainer;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: c,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: c.withValues(alpha: 0.85),
                    ),
                  ),
                  if (note != null && note!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        note!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: c.withValues(alpha: 0.75),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: c.withValues(alpha: 0.65),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

String _fmt12h(String hhmm) {
  final parts = hhmm.split(':');
  final h = int.parse(parts[0]);
  final m = int.parse(parts[1]);
  final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
  final period = h >= 12 ? 'PM' : 'AM';
  return '$hour12:${m.toString().padLeft(2, '0')} $period';
}
