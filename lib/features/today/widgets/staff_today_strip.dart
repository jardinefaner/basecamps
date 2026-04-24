import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Compact "who's working today" strip on Today — sits between the
/// day-summary and the all-day carousel. Collapsible; shows a count
/// when collapsed, the per-adult list when expanded.
///
/// Uses the AdultAvailability shift + break/lunch for today's
/// weekday. Adults with no availability row for today are skipped
/// entirely (they don't have a shift, so they're not "on"). An adult
/// currently inside a break/lunch window gets a tinted status.
class StaffTodayStrip extends ConsumerStatefulWidget {
  const StaffTodayStrip({required this.now, super.key});

  final DateTime now;

  @override
  ConsumerState<StaffTodayStrip> createState() => _StaffTodayStripState();
}

class _StaffTodayStripState extends ConsumerState<StaffTodayStrip> {
  // Default collapsed — teachers already have a lot on Today. The
  // count is visible in either state so they can peek.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final adultsAsync = ref.watch(adultsProvider);

    return adultsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (err, _) => const SizedBox.shrink(),
      data: (adults) {
        // Resolve today's weekday in ISO (1..7). Program is Mon-Fri,
        // but we still show the weekend shift if anything's set.
        final isoDay = widget.now.weekday;
        final onShift = <_OnShiftAdult>[];
        for (final a in adults) {
          final avAsync = ref.watch(adultAvailabilityProvider(a.id));
          final rows = avAsync.asData?.value;
          if (rows == null) continue;
          final row = _availabilityForDay(rows, isoDay);
          if (row == null) continue;
          onShift.add(_OnShiftAdult(adult: a, availability: row));
        }
        if (onShift.isEmpty) return const SizedBox.shrink();

        // Bucket by role so leads / adults / ambient group visually.
        onShift.sort((a, b) {
          final ra = AdultRole.fromDb(a.adult.adultRole).index;
          final rb = AdultRole.fromDb(b.adult.adultRole).index;
          if (ra != rb) return ra.compareTo(rb);
          return a.adult.name.compareTo(b.adult.name);
        });

        return _StripShell(
          count: onShift.length,
          expanded: _expanded,
          onToggle: () => setState(() => _expanded = !_expanded),
          rows: onShift,
          now: widget.now,
        );
      },
    );
  }
}

class _OnShiftAdult {
  const _OnShiftAdult({required this.adult, required this.availability});
  final Adult adult;
  final AdultAvailabilityData availability;
}

AdultAvailabilityData? _availabilityForDay(
  List<AdultAvailabilityData> rows,
  int isoDay,
) {
  for (final r in rows) {
    if (r.dayOfWeek != isoDay) continue;
    return r;
  }
  return null;
}

class _StripShell extends StatelessWidget {
  const _StripShell({
    required this.count,
    required this.expanded,
    required this.onToggle,
    required this.rows,
    required this.now,
  });

  final int count;
  final bool expanded;
  final VoidCallback onToggle;
  final List<_OnShiftAdult> rows;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onToggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.groups_2_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Staff today · $count on shift',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          if (expanded) ...[
            const SizedBox(height: AppSpacing.md),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _StaffRow(entry: r, now: now),
              ),
          ],
        ],
      ),
    );
  }
}

class _StaffRow extends ConsumerWidget {
  const _StaffRow({required this.entry, required this.now});

  final _OnShiftAdult entry;
  final DateTime now;

  /// Which break window (if any) the current wall-clock falls into —
  /// so we can render "on lunch until 1:00" prominently.
  _ActiveStatus _status() {
    final a = entry.availability;
    final nowMin = now.hour * 60 + now.minute;
    final lunch = _windowMinutes(a.lunchStart, a.lunchEnd);
    if (lunch != null && nowMin >= lunch.$1 && nowMin < lunch.$2) {
      return _ActiveStatus.onLunch(end: a.lunchEnd!);
    }
    final brk = _windowMinutes(a.breakStart, a.breakEnd);
    if (brk != null && nowMin >= brk.$1 && nowMin < brk.$2) {
      return _ActiveStatus.onBreak(end: a.breakEnd!);
    }
    final brk2 = _windowMinutes(a.break2Start, a.break2End);
    if (brk2 != null && nowMin >= brk2.$1 && nowMin < brk2.$2) {
      return _ActiveStatus.onBreak(end: a.break2End!);
    }
    final shift = _windowMinutes(a.startTime, a.endTime);
    if (shift != null && nowMin >= shift.$1 && nowMin < shift.$2) {
      return const _ActiveStatus.working();
    }
    return const _ActiveStatus.offShift();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final adult = entry.adult;
    final role = AdultRole.fromDb(adult.adultRole);
    final status = _status();
    final initial = adult.name.isEmpty
        ? '?'
        : adult.name.characters.first.toUpperCase();

    // For leads, pull their anchor group's name so the row reads
    // "Ms. Park (Seedlings)" at a glance.
    String? anchorName;
    if (role == AdultRole.lead && adult.anchoredGroupId != null) {
      final g =
          ref.watch(groupProvider(adult.anchoredGroupId!)).asData?.value;
      anchorName = g?.name;
    }

    return Row(
      children: [
        // Avatar + name read as a single unit, so the whole pair is
        // the tap target for "open this adult's detail". The ripple is
        // scoped to that pair so it doesn't flood the row or fight the
        // outer AppCard's expand/collapse tap.
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.push('/more/adults/${adult.id}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SmallAvatar(
                    path: adult.avatarPath,
                    fallbackInitial: initial,
                    radius: 16,
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    foregroundColor: theme.colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          anchorName == null
                              ? adult.name
                              : '${adult.name}  ·  $anchorName',
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _shiftLine(entry.availability),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _StatusBadge(status: status),
      ],
    );
  }

  String _shiftLine(AdultAvailabilityData a) {
    final parts = <String>[_timeRange(a.startTime, a.endTime)];
    if (a.lunchStart != null && a.lunchEnd != null) {
      parts.add('lunch ${_timeRange(a.lunchStart!, a.lunchEnd!)}');
    }
    if (a.breakStart != null && a.breakEnd != null) {
      parts.add('break ${_timeRange(a.breakStart!, a.breakEnd!)}');
    }
    if (a.break2Start != null && a.break2End != null) {
      parts.add('break ${_timeRange(a.break2Start!, a.break2End!)}');
    }
    return parts.join(' · ');
  }
}

(int, int)? _windowMinutes(String? start, String? end) {
  if (start == null || end == null) return null;
  final startMin = _minutesOf(start);
  final endMin = _minutesOf(end);
  if (startMin == null || endMin == null) return null;
  return (startMin, endMin);
}

int? _minutesOf(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

String _timeRange(String startHhmm, String endHhmm) {
  return '${_short(startHhmm)}–${_short(endHhmm)}';
}

String _short(String hhmm) {
  final parts = hhmm.split(':');
  final h = int.parse(parts[0]);
  final m = parts[1];
  final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
  final period = h < 12 ? 'a' : 'p';
  return m == '00' ? '$hour12$period' : '$hour12:$m$period';
}

/// Where the adult is right now — drives the tinted status badge at
/// the right of each row.
sealed class _ActiveStatus {
  const _ActiveStatus();
  const factory _ActiveStatus.working() = _Working;
  const factory _ActiveStatus.onBreak({required String end}) = _OnBreak;
  const factory _ActiveStatus.onLunch({required String end}) = _OnLunch;
  const factory _ActiveStatus.offShift() = _OffShift;
}

class _Working extends _ActiveStatus {
  const _Working();
}

class _OnBreak extends _ActiveStatus {
  const _OnBreak({required this.end});
  final String end;
}

class _OnLunch extends _ActiveStatus {
  const _OnLunch({required this.end});
  final String end;
}

class _OffShift extends _ActiveStatus {
  const _OffShift();
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final _ActiveStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, bg, fg) = switch (status) {
      _Working() => (
          'On',
          theme.colorScheme.primaryContainer,
          theme.colorScheme.onPrimaryContainer,
        ),
      _OnLunch(end: final e) => (
          'Lunch · back ${_short(e)}',
          theme.colorScheme.tertiaryContainer,
          theme.colorScheme.onTertiaryContainer,
        ),
      _OnBreak(end: final e) => (
          'Break · back ${_short(e)}',
          theme.colorScheme.tertiaryContainer,
          theme.colorScheme.onTertiaryContainer,
        ),
      _OffShift() => (
          'Off',
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurfaceVariant,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
