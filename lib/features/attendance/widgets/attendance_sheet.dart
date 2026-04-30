import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/attendance/attendance_repository.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom sheet that lets the teacher set each child's attendance for
/// the day in one pass. Used from Today — tap the check-in strip on a
/// card and this opens with the relevant group roster pre-filtered.
///
/// State is live from [attendanceForDayProvider]; tapping a tile cycles
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
    // Read attendance for the specific [date] passed in — not today.
    // Normalize to date-only so callers with a time component share
    // one provider instance, not one per millisecond.
    final dayOnly = DateTime(date.year, date.month, date.day);
    final attendanceAsync = ref.watch(attendanceForDayProvider(dayOnly));

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
          final roster = rosterFor(allKids, groupIds);
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
                AttendanceSummaryRow(
                  present: present,
                  absent: absent,
                  pending: pending,
                  total: roster.length,
                ),
                const SizedBox(height: AppSpacing.md),
                AttendanceTilesView(
                  roster: roster,
                  attendance: attendance,
                  date: date,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Resolves which children belong to [groupIds] for attendance purposes.
/// Empty `groupIds` means the caller wants everyone (e.g. whole-program
/// check-in). Sorted by first name so the tiles appear consistently.
List<Child> rosterFor(List<Child> allKids, List<String> groupIds) {
  return (groupIds.isEmpty
      ? List<Child>.from(allKids)
      : allKids
          .where(
            (k) => k.groupId != null && groupIds.contains(k.groupId),
          )
          .toList())
    ..sort((a, b) => a.firstName.compareTo(b.firstName));
}

/// A reusable check-in tile list for a pre-resolved roster. No padding,
/// no header — just the "Mark everyone / remaining present" button
/// (when there's still pending) and a tappable tile per child. The
/// parent provides whatever scaffolding it needs (a modal sheet, a
/// hero card, a future history view…).
class AttendanceTilesView extends ConsumerWidget {
  const AttendanceTilesView({
    required this.roster,
    required this.attendance,
    required this.date,
    this.showMarkAllButton = true,
    this.emptyText = 'No children in these groups yet.',
    super.key,
  });

  final List<Child> roster;
  final Map<String, AttendanceRecord> attendance;
  final DateTime date;

  /// When false, the "Mark everyone/remaining present" helper is hidden.
  /// Useful inline on cramped surfaces that already have their own
  /// primary CTA (e.g. the Capture button on HeroNowCard).
  final bool showMarkAllButton;

  final String emptyText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (roster.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Text(
          emptyText,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final pending = roster
        .where((k) {
          final s = attendance[k.id]?.status;
          return s != AttendanceStatus.present &&
              s != AttendanceStatus.absent;
        })
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showMarkAllButton && pending > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _markAllPresent(ref),
              icon: const Icon(Icons.check, size: 16),
              label: Text(
                pending == roster.length
                    ? 'Mark everyone present'
                    : 'Mark remaining present',
              ),
            ),
          ),
        if (showMarkAllButton && pending > 0)
          const SizedBox(height: AppSpacing.sm),
        for (final child in roster)
          _ChildTile(
            child: child,
            record: attendance[child.id],
            onCycle: () =>
                _cycleStatus(ref, child.id, attendance[child.id]?.status),
            onSelectStatus: (s) => _setStatus(ref, child.id, s),
            onRecordPickup: () => _recordPickup(context, ref, child),
            onClearPickup: () => _clearPickup(ref, child.id),
          ),
      ],
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

  Future<void> _markAllPresent(WidgetRef ref) async {
    await ref.read(attendanceRepositoryProvider).markAllPresent(
          childIds: roster.map((k) => k.id),
          date: date,
        );
  }

  /// Opens a small pickup dialog — time (defaults to now) + optional
  /// "picked up by" text — and writes both fields to the attendance
  /// row on save. If the child doesn't have an attendance row yet,
  /// nothing happens at the repo layer (pickup-without-check-in is
  /// always a data-entry mistake; surfaces that care can prompt the
  /// teacher to mark present first).
  Future<void> _recordPickup(
    BuildContext context,
    WidgetRef ref,
    Child child,
  ) async {
    final record = attendance[child.id];
    final result = await showDialog<_PickupInput>(
      context: context,
      builder: (_) => _PickupDialog(
        childName: child.firstName,
        initialTime: record?.pickupTime,
        initialPickedUpBy: record?.pickedUpBy,
      ),
    );
    if (result == null) return;
    final repo = ref.read(attendanceRepositoryProvider);
    // Ensure a row exists — typical when Today's lateness strip opens
    // this sheet for an unchecked-in kid and the teacher wants to
    // combine "arrived late + picked up early" into one pass. Upsert
    // to 'present' before stamping pickup; if the row already exists,
    // this just touches updated_at.
    if (record == null) {
      await repo.setStatus(
        childId: child.id,
        date: date,
        status: AttendanceStatus.present,
      );
    }
    await repo.markPickup(
      childId: child.id,
      date: date,
      pickupTime: result.time,
      pickedUpBy: result.pickedUpBy,
    );
  }

  Future<void> _clearPickup(WidgetRef ref, String childId) async {
    await ref.read(attendanceRepositoryProvider).clearPickup(
          childId: childId,
          date: date,
        );
  }

  String _nowHhmm() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:'
        '${n.minute.toString().padLeft(2, '0')}';
  }
}

/// Result of the pickup dialog — the time (required) and an optional
/// "picked up by" attribution. Dialog returns null when the teacher
/// taps cancel, which the caller treats as "no change."
class _PickupInput {
  const _PickupInput({required this.time, this.pickedUpBy});
  final String time;
  final String? pickedUpBy;
}

/// Horizontal "N Present · N Absent · N Pending" strip used at the top
/// of the sheet. Pulled out as a public widget so other surfaces can
/// reuse the same count layout.
class AttendanceSummaryRow extends StatelessWidget {
  const AttendanceSummaryRow({
    required this.present,
    required this.absent,
    required this.pending,
    required this.total,
    super.key,
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
    required this.onRecordPickup,
    required this.onClearPickup,
  });

  final Child child;
  final AttendanceRecord? record;
  final VoidCallback onCycle;
  final ValueChanged<AttendanceStatus?> onSelectStatus;

  /// Opens the pickup-capture dialog. Shown on the "more" menu when
  /// the child is present (it's the natural time to record pickup);
  /// also selectable for pending rows so a teacher catching up at
  /// end-of-day can retroactively mark arrival + pickup together.
  final VoidCallback onRecordPickup;

  /// Nulls both pickup fields on the row. Visible in the menu only
  /// when a pickup has been recorded, to avoid dead actions.
  final VoidCallback onClearPickup;

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
                SmallAvatar(
                  // Reuses the shared avatar pipeline so the
                  // photo flows in from drift cache (web) or
                  // local file (native), with cross-device
                  // fallback through avatar_storage_path.
                  path: child.avatarPath,
                  storagePath: child.avatarStoragePath,
                  etag: child.avatarEtag,
                  fallbackInitial: initial,
                  radius: 16,
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
                      if (record?.pickupTime != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            record?.pickedUpBy == null ||
                                    record!.pickedUpBy!.trim().isEmpty
                                ? 'Picked up · ${record!.pickupTime!}'
                                : 'Picked up · ${record!.pickupTime!} · '
                                    '${record!.pickedUpBy!}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<_TileAction>(
                  icon: Icon(
                    Icons.more_vert,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  tooltip: 'More',
                  onSelected: (action) {
                    switch (action) {
                      case _TileAction.markPresent:
                        onSelectStatus(AttendanceStatus.present);
                      case _TileAction.markAbsent:
                        onSelectStatus(AttendanceStatus.absent);
                      case _TileAction.markLate:
                        onSelectStatus(AttendanceStatus.late);
                      case _TileAction.markLeftEarly:
                        onSelectStatus(AttendanceStatus.leftEarly);
                      case _TileAction.clearStatus:
                        onSelectStatus(null);
                      case _TileAction.recordPickup:
                        onRecordPickup();
                      case _TileAction.clearPickup:
                        onClearPickup();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: _TileAction.markPresent,
                      child: Text('Mark present'),
                    ),
                    const PopupMenuItem(
                      value: _TileAction.markAbsent,
                      child: Text('Mark absent'),
                    ),
                    const PopupMenuItem(
                      value: _TileAction.markLate,
                      child: Text('Mark late…'),
                    ),
                    const PopupMenuItem(
                      value: _TileAction.markLeftEarly,
                      child: Text('Left early…'),
                    ),
                    const PopupMenuDivider(),
                    // Pickup affordances live below the status ones so
                    // the common-path items stay above the fold. Record
                    // always visible; Clear only when there's something
                    // to clear, so a dead action doesn't take a slot.
                    const PopupMenuItem(
                      value: _TileAction.recordPickup,
                      child: Text('Record pickup…'),
                    ),
                    if (record?.pickupTime != null)
                      const PopupMenuItem(
                        value: _TileAction.clearPickup,
                        child: Text('Clear pickup'),
                      ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _TileAction.clearStatus,
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

/// Menu actions on an attendance tile. Kept as an enum (rather than a
/// loose nullable AttendanceStatus like before) so the pickup
/// actions and the status changes share one dispatch path without
/// overloading the status type.
enum _TileAction {
  markPresent,
  markAbsent,
  markLate,
  markLeftEarly,
  clearStatus,
  recordPickup,
  clearPickup,
}

/// Small dialog for capturing a pickup: time (tap to pick, default
/// now) + optional "picked up by" free-text field. Returns a
/// [_PickupInput] on save, null on cancel.
class _PickupDialog extends StatefulWidget {
  const _PickupDialog({
    required this.childName,
    this.initialTime,
    this.initialPickedUpBy,
  });

  final String childName;
  final String? initialTime;
  final String? initialPickedUpBy;

  @override
  State<_PickupDialog> createState() => _PickupDialogState();
}

class _PickupDialogState extends State<_PickupDialog> {
  late TimeOfDay _time = _seedTime();
  late final _nameController =
      TextEditingController(text: widget.initialPickedUpBy ?? '');

  TimeOfDay _seedTime() {
    final raw = widget.initialTime;
    if (raw == null) {
      final now = DateTime.now();
      return TimeOfDay(hour: now.hour, minute: now.minute);
    }
    final parts = raw.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Pickup · ${widget.childName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _time,
              );
              if (picked != null) setState(() => _time = picked);
            },
            icon: const Icon(Icons.access_time, size: 18),
            label: Text('At ${_time.format(context)}'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Picked up by (optional)',
              hintText: 'Dad · Grandma · Auntie Nia',
              isDense: true,
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Time defaults to now. Leave the name blank if you want to '
            'record pickup fast and fill in the name later.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final hhmm = '${_time.hour.toString().padLeft(2, '0')}:'
                '${_time.minute.toString().padLeft(2, '0')}';
            final name = _nameController.text.trim();
            Navigator.of(context).pop(
              _PickupInput(
                time: hhmm,
                pickedUpBy: name.isEmpty ? null : name,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
