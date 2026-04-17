import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/schedule/week_days.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

/// Local editable working-hours sketch — what shows up on screen
/// while the teacher is clicking around the wizard/sheet. Converted
/// to [AvailabilityInput] at save time.
class AvailabilityBlock {
  AvailabilityBlock({
    required this.dayOfWeek,
    required this.start,
    required this.end,
  });

  int dayOfWeek;
  TimeOfDay start;
  TimeOfDay end;

  AvailabilityBlock copyWith({
    int? dayOfWeek,
    TimeOfDay? start,
    TimeOfDay? end,
  }) {
    return AvailabilityBlock(
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }

  AvailabilityInput toInput() => AvailabilityInput(
        dayOfWeek: dayOfWeek,
        startTime: _fmt(start),
        endTime: _fmt(end),
      );
}

String _fmt(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay _parse(String hhmm) {
  final parts = hhmm.split(':');
  return TimeOfDay(
    hour: int.parse(parts[0]),
    minute: int.parse(parts[1]),
  );
}

/// Builds [AvailabilityBlock]s from saved rows (or defaults to
/// weekday 9–5 when seeding a new specialist).
List<AvailabilityBlock> availabilityFromRows(
  List<SpecialistAvailabilityData> rows,
) =>
    [
      for (final r in rows)
        AvailabilityBlock(
          dayOfWeek: r.dayOfWeek,
          start: _parse(r.startTime),
          end: _parse(r.endTime),
        ),
    ];

List<AvailabilityBlock> defaultAvailability() => [
      for (final d in scheduleDayValues)
        AvailabilityBlock(
          dayOfWeek: d,
          start: const TimeOfDay(hour: 9, minute: 0),
          end: const TimeOfDay(hour: 17, minute: 0),
        ),
    ];

/// Per-weekday editable rows. Null row = day off. Callers pass the
/// current list and get change callbacks back; this widget is purely
/// a UI — state ownership stays with the parent wizard/sheet.
class AvailabilityEditor extends StatelessWidget {
  const AvailabilityEditor({
    required this.blocksByDay,
    required this.onToggleDay,
    required this.onPickStart,
    required this.onPickEnd,
    super.key,
  });

  /// Map keyed by ISO day-of-week (1..5). Days without a block are
  /// treated as "off".
  final Map<int, AvailabilityBlock> blocksByDay;

  final void Function(int dayOfWeek, {required bool enabled}) onToggleDay;
  final void Function(int dayOfWeek) onPickStart;
  final void Function(int dayOfWeek) onPickEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final d in scheduleDayValues)
          _Row(
            dayOfWeek: d,
            block: blocksByDay[d],
            onToggle: (v) => onToggleDay(d, enabled: v),
            onPickStart: () => onPickStart(d),
            onPickEnd: () => onPickEnd(d),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.dayOfWeek,
    required this.block,
    required this.onToggle,
    required this.onPickStart,
    required this.onPickEnd,
  });

  final int dayOfWeek;
  final AvailabilityBlock? block;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = block != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              scheduleDayShortLabels[dayOfWeek - 1],
              style: theme.textTheme.titleSmall,
            ),
          ),
          Expanded(
            child: enabled
                ? Row(
                    children: [
                      Expanded(
                        child: _TimeChip(
                          label: block!.start.format(context),
                          onTap: onPickStart,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                        ),
                        child: Text(
                          '→',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        child: _TimeChip(
                          label: block!.end.format(context),
                          onTap: onPickEnd,
                        ),
                      ),
                    ],
                  )
                : Text(
                    'Off',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
          Switch(
            value: enabled,
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(label, style: theme.textTheme.bodyMedium),
      ),
    );
  }
}
