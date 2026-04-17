import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/attendance/attendance_repository.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom sheet that lets the teacher set each child's attendance for
/// the day in one pass. Used from Today — tap the check-in strip on a
/// card and this opens with the relevant group roster pre-filtered.
///
/// State is live from [todayAttendanceProvider]; tapping a tile cycles
/// through Pending → Present → Absent → Pending. An overflow menu on
/// each tile offers Late and Left early for finer control.
class AttendanceSheet extends ConsumerWidget {
  const AttendanceSheet({
    required this.groupIds,
    required this.date,
    this.activityTitle,
    super.key,
  });

  /// Groups whose children should appear in the sheet. Empty means
  /// "everyone" — we defer to the children provider in that case.
  final List<String> groupIds;
  final DateTime date;

  /// Optional header label, usually the activity name.
  final String? activityTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final kidsAsync = ref.watch(childrenProvider);
    final attendanceAsync = ref.watch(todayAttendanceProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.md,
        bottom: AppSpacing.xl + insets,
      ),
      child: kidsAsync.when(
        loading: () => const SizedBox(
          height: 180,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (err, _) => SizedBox(
          height: 180,
          child: Center(child: Text('Error: $err')),
        ),
        data: (allKids) {
          final roster = (groupIds.isEmpty
              ? List<Child>.from(allKids)
              : allKids
                  .where(
                    (k) =>
                        k.groupId != null && groupIds.contains(k.groupId),
                  )
                  .toList())
            ..sort((a, b) => a.firstName.compareTo(b.firstName));

          final attendance = attendanceAsync.asData?.value ??
              const <String, AttendanceRecord>{};
          final present = roster
              .where(
                (k) =>
                    attendance[k.id]?.status == AttendanceStatus.present,
              )
              .length;
          final absent = roster
              .where(
                (k) =>
                    attendance[k.id]?.status == AttendanceStatus.absent,
              )
              .length;
          final pending = roster.length - present - absent;

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Check-in', style: theme.textTheme.titleLarge),
                if (activityTitle != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    activityTitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                _SummaryRow(
                  present: present,
                  absent: absent,
                  pending: pending,
                  total: roster.length,
                ),
                const SizedBox(height: AppSpacing.md),
                if (roster.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.lg,
                    ),
                    child: Text(
                      'No children in these groups yet.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else ...[
                  if (pending > 0)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () => _markAllPresent(ref, roster),
                        icon: const Icon(Icons.check, size: 16),
                        label: Text(
                          pending == roster.length
                              ? 'Mark everyone present'
                              : 'Mark remaining present',
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final child in roster)
                    _ChildTile(
                      child: child,
                      record: attendance[child.id],
                      onCycle: () => _cycleStatus(
                        ref,
                        child.id,
                        attendance[child.id]?.status,
                      ),
                      onSelectStatus: (s) =>
                          _setStatus(ref, child.id, s),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _cycleStatus(
    WidgetRef ref,
    String childId,
    AttendanceStatus? current,
  ) async {
    final repo = ref.read(attendanceRepositoryProvider);
    switch (current) {
      case null:
        await repo.setStatus(
          childId: childId,
          date: date,
          status: AttendanceStatus.present,
        );
      case AttendanceStatus.present:
        await repo.setStatus(
          childId: childId,
          date: date,
          status: AttendanceStatus.absent,
        );
      case AttendanceStatus.absent:
      case AttendanceStatus.late:
      case AttendanceStatus.leftEarly:
        await repo.clearStatus(childId: childId, date: date);
    }
  }

  Future<void> _setStatus(
    WidgetRef ref,
    String childId,
    AttendanceStatus? status,
  ) async {
    final repo = ref.read(attendanceRepositoryProvider);
    if (status == null) {
      await repo.clearStatus(childId: childId, date: date);
      return;
    }
    final clock = (status == AttendanceStatus.late ||
            status == AttendanceStatus.leftEarly)
        ? _nowHhmm()
        : null;
    await repo.setStatus(
      childId: childId,
      date: date,
      status: status,
      clockTime: clock,
    );
  }

  Future<void> _markAllPresent(WidgetRef ref, List<Child> roster) async {
    await ref.read(attendanceRepositoryProvider).markAllPresent(
          childIds: roster.map((k) => k.id),
          date: date,
        );
  }

  String _nowHhmm() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:'
        '${n.minute.toString().padLeft(2, '0')}';
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.present,
    required this.absent,
    required this.pending,
    required this.total,
  });

  final int present;
  final int absent;
  final int pending;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryCell(
              label: 'Present',
              count: present,
              color: theme.colorScheme.primary,
            ),
          ),
          _VDivider(),
          Expanded(
            child: _SummaryCell(
              label: 'Absent',
              count: absent,
              color: theme.colorScheme.error,
            ),
          ),
          _VDivider(),
          Expanded(
            child: _SummaryCell(
              label: 'Pending',
              count: pending,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count',
          style: theme.textTheme.titleLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _VDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _ChildTile extends StatelessWidget {
  const _ChildTile({
    required this.child,
    required this.record,
    required this.onCycle,
    required this.onSelectStatus,
  });

  final Child child;
  final AttendanceRecord? record;
  final VoidCallback onCycle;
  final ValueChanged<AttendanceStatus?> onSelectStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = record?.status;
    final (bg, border, tintLabel) = switch (status) {
      AttendanceStatus.present => (
          theme.colorScheme.primary.withValues(alpha: 0.08),
          theme.colorScheme.primary.withValues(alpha: 0.35),
          'Present',
        ),
      AttendanceStatus.absent => (
          theme.colorScheme.error.withValues(alpha: 0.08),
          theme.colorScheme.error.withValues(alpha: 0.35),
          'Absent',
        ),
      AttendanceStatus.late => (
          theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
          theme.colorScheme.tertiary.withValues(alpha: 0.4),
          'Late',
        ),
      AttendanceStatus.leftEarly => (
          theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
          theme.colorScheme.tertiary.withValues(alpha: 0.4),
          'Left early',
        ),
      null => (
          theme.colorScheme.surfaceContainerLow,
          theme.colorScheme.outlineVariant,
          'Pending',
        ),
    };

    final initial = child.firstName.isEmpty
        ? '?'
        : child.firstName.characters.first.toUpperCase();
    final fullName =
        [child.firstName, child.lastName].whereType<String>().join(' ');

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onCycle,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor:
                      theme.colorScheme.primaryContainer,
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
                      Text(
                        record?.clockTime == null
                            ? tintLabel
                            : '$tintLabel · ${record!.clockTime}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<AttendanceStatus?>(
                  icon: Icon(
                    Icons.more_vert,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  tooltip: 'More statuses',
                  onSelected: onSelectStatus,
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: AttendanceStatus.present,
                      child: Text('Mark present'),
                    ),
                    const PopupMenuItem(
                      value: AttendanceStatus.absent,
                      child: Text('Mark absent'),
                    ),
                    const PopupMenuItem(
                      value: AttendanceStatus.late,
                      child: Text('Mark late…'),
                    ),
                    const PopupMenuItem(
                      value: AttendanceStatus.leftEarly,
                      child: Text('Left early…'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      child: Text('Clear status'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
