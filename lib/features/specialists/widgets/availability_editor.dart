import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/schedule/week_days.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

/// Local editable working-hours sketch — what shows up on screen
/// while the teacher is clicking around the wizard/sheet. Converted
/// to [AvailabilityInput] at save time.
///
/// v28: carries optional break + lunch windows per day so the Today
/// view can render "on lunch until 1:00" for each adult.
class AvailabilityBlock {
  AvailabilityBlock({
    required this.dayOfWeek,
    required this.start,
    required this.end,
    this.breakStart,
    this.breakEnd,
    this.lunchStart,
    this.lunchEnd,
  });

  int dayOfWeek;
  TimeOfDay start;
  TimeOfDay end;
  TimeOfDay? breakStart;
  TimeOfDay? breakEnd;
  TimeOfDay? lunchStart;
  TimeOfDay? lunchEnd;

  AvailabilityBlock copyWith({
    int? dayOfWeek,
    TimeOfDay? start,
    TimeOfDay? end,
    // Nullable fields use a sentinel-wrapper pattern; the default
    // means "don't touch", passing Value.absent-style is clumsy in
    // Dart so we accept typed params here and let the parent pass the
    // new value through explicitly.
    TimeOfDay? breakStart,
    TimeOfDay? breakEnd,
    TimeOfDay? lunchStart,
    TimeOfDay? lunchEnd,
    bool clearBreak = false,
    bool clearLunch = false,
  }) {
    return AvailabilityBlock(
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      start: start ?? this.start,
      end: end ?? this.end,
      breakStart: clearBreak ? null : (breakStart ?? this.breakStart),
      breakEnd: clearBreak ? null : (breakEnd ?? this.breakEnd),
      lunchStart: clearLunch ? null : (lunchStart ?? this.lunchStart),
      lunchEnd: clearLunch ? null : (lunchEnd ?? this.lunchEnd),
    );
  }

  AvailabilityInput toInput() => AvailabilityInput(
        dayOfWeek: dayOfWeek,
        startTime: _fmt(start),
        endTime: _fmt(end),
        breakStart: breakStart == null ? null : _fmt(breakStart!),
        breakEnd: breakEnd == null ? null : _fmt(breakEnd!),
        lunchStart: lunchStart == null ? null : _fmt(lunchStart!),
        lunchEnd: lunchEnd == null ? null : _fmt(lunchEnd!),
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

TimeOfDay? _parseNullable(String? hhmm) {
  if (hhmm == null || hhmm.isEmpty) return null;
  return _parse(hhmm);
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
          breakStart: _parseNullable(r.breakStart),
          breakEnd: _parseNullable(r.breakEnd),
          lunchStart: _parseNullable(r.lunchStart),
          lunchEnd: _parseNullable(r.lunchEnd),
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

/// Signature for picking a time that's optional to set. Null result =
/// "keep as-is"; returning a TimeOfDay replaces the value.
typedef TimePick = Future<TimeOfDay?> Function();

/// Per-weekday editable rows. Null row = day off. Callers pass the
/// current list and get change callbacks back; this widget is purely
/// a UI — state ownership stays with the parent wizard/sheet.
class AvailabilityEditor extends StatelessWidget {
  const AvailabilityEditor({
    required this.blocksByDay,
    required this.onToggleDay,
    required this.onPickStart,
    required this.onPickEnd,
    this.onPickBreak,
    this.onPickLunch,
    this.onClearBreak,
    this.onClearLunch,
    super.key,
  });

  /// Map keyed by ISO day-of-week (1..5). Days without a block are
  /// treated as "off".
  final Map<int, AvailabilityBlock> blocksByDay;

  final void Function(int dayOfWeek, {required bool enabled}) onToggleDay;
  final void Function(int dayOfWeek) onPickStart;
  final void Function(int dayOfWeek) onPickEnd;

  /// Optional — set both to enable the break-window UI. Callers pass
  /// start + end picker callbacks via [onPickBreak]; we never prompt
  /// for one half without the other.
  final Future<void> Function(int dayOfWeek)? onPickBreak;
  final Future<void> Function(int dayOfWeek)? onPickLunch;
  final void Function(int dayOfWeek)? onClearBreak;
  final void Function(int dayOfWeek)? onClearLunch;

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
            onPickBreak:
                onPickBreak == null ? null : () => onPickBreak!(d),
            onPickLunch:
                onPickLunch == null ? null : () => onPickLunch!(d),
            onClearBreak:
                onClearBreak == null ? null : () => onClearBreak!(d),
            onClearLunch:
                onClearLunch == null ? null : () => onClearLunch!(d),
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
    this.onPickBreak,
    this.onPickLunch,
    this.onClearBreak,
    this.onClearLunch,
  });

  final int dayOfWeek;
  final AvailabilityBlock? block;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback? onPickBreak;
  final VoidCallback? onPickLunch;
  final VoidCallback? onClearBreak;
  final VoidCallback? onClearLunch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = block != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
          // Break + lunch sub-row (shown only when shift is on and
          // the callbacks were passed in). Keeps them out of sight for
          // the wizard's "new specialist" flow where they'd be noise.
          if (enabled && (onPickBreak != null || onPickLunch != null))
            Padding(
              padding: const EdgeInsets.only(
                left: 48,
                top: AppSpacing.xs,
              ),
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  if (onPickBreak != null)
                    _BreakChip(
                      icon: Icons.coffee_outlined,
                      start: block!.breakStart,
                      end: block!.breakEnd,
                      emptyLabel: 'Add break',
                      onTap: onPickBreak!,
                      onClear: onClearBreak,
                    ),
                  if (onPickLunch != null)
                    _BreakChip(
                      icon: Icons.restaurant_outlined,
                      start: block!.lunchStart,
                      end: block!.lunchEnd,
                      emptyLabel: 'Add lunch',
                      onTap: onPickLunch!,
                      onClear: onClearLunch,
                    ),
                ],
              ),
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

/// Compact chip showing either the set break/lunch window or a
/// prompt to add one. Tappable on both sides. Cleared via a small X
/// when a window is set.
class _BreakChip extends StatelessWidget {
  const _BreakChip({
    required this.icon,
    required this.start,
    required this.end,
    required this.emptyLabel,
    required this.onTap,
    this.onClear,
  });

  final IconData icon;
  final TimeOfDay? start;
  final TimeOfDay? end;
  final String emptyLabel;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasWindow = start != null && end != null;
    final label = hasWindow
        ? '${start!.format(context)} – ${end!.format(context)}'
        : emptyLabel;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: hasWindow
              ? theme.colorScheme.surfaceContainerLow
              : theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(label, style: theme.textTheme.labelMedium),
            if (hasWindow && onClear != null) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: onClear,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close,
                    size: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
