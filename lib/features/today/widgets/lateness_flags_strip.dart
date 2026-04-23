import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/attendance/attendance_repository.dart';
import 'package:basecamp/features/attendance/widgets/attendance_sheet.dart';
import 'package:basecamp/features/children/child_schedule_repository.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/today/lateness.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Top-of-Today strip surfacing lateness flags. Self-hides when no
/// kids are flagged — the goal is a quiet screen when things are
/// going fine, loud only when the teacher needs to act.
///
/// Taps a flag row → opens today's attendance sheet pre-focused on
/// the kid's group, so the teacher can mark them present/absent in
/// the flow they already know. No dedicated "resolve this flag"
/// action; clearing the flag is a side effect of taking the right
/// attendance action, which keeps the mental model simple.
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

    final flags = computeLatenessFlags(
      now: now,
      children: kids,
      attendance: attendance,
      overrides: overrides,
    );
    if (flags.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        // Tertiary-container not error-container: late doesn't mean
        // crisis, it means "this needs a look." Error-red would overshoot
        // and train teachers to dismiss the strip.
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.access_time_outlined,
                size: 16,
                color: theme.colorScheme.onTertiaryContainer,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                flags.length == 1
                    ? '1 KID LATE'
                    : '${flags.length} KIDS LATE',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < flags.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 0.5,
                color: theme.colorScheme.onTertiaryContainer.withValues(
                  alpha: 0.2,
                ),
              ),
            _FlagRow(
              flag: flags[i],
              onTap: () => _openAttendance(context, flags[i]),
            ),
          ],
        ],
      ),
    );
  }

  /// Open today's attendance sheet scoped to the flagged child's
  /// group. If they're Unassigned, falls back to the whole-program
  /// view rather than popping an empty sheet.
  Future<void> _openAttendance(BuildContext context, LatenessFlag flag) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) {
        final groupId = flag.child.groupId;
        return AttendanceSheet(
          groupIds: groupId == null ? const [] : [groupId],
          date: now,
          activityTitle: 'Check in · ${flag.child.firstName}',
        );
      },
    );
  }
}

class _FlagRow extends StatelessWidget {
  const _FlagRow({required this.flag, required this.onTap});

  final LatenessFlag flag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme.onTertiaryContainer;
    final minsLate = flag.minutesLate;
    final lateLabel = minsLate == 0
        ? 'just late'
        : minsLate < 60
            ? '$minsLate min late'
            : '${minsLate ~/ 60}h ${minsLate % 60} min late';
    final displayName = flag.child.lastName == null ||
            flag.child.lastName!.trim().isEmpty
        ? flag.child.firstName
        : '${flag.child.firstName} ${flag.child.lastName!.trim().characters.first}.';
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
                    displayName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: c,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$lateLabel · expected ${_fmt12h(flag.expectedArrival)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: c.withValues(alpha: 0.85),
                    ),
                  ),
                  if (flag.note != null && flag.note!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        flag.note!,
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

  String _fmt12h(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final period = h >= 12 ? 'PM' : 'AM';
    return '$hour12:${m.toString().padLeft(2, '0')} $period';
  }
}
