/// Shared HH:mm helpers. The audit found 50+ callsites split
/// across `_formatTime` (compact "9:30a") and `_fmt12h` (verbose
/// "9:30 AM") with the same parser-by-string-split logic
/// re-implemented in every screen. This file is the one source
/// of truth.
///
/// `HH:mm` (zero-padded 24-hour) is the wire format the schedule
/// + adult-availability + child-arrival columns all use. The
/// app's display rendering varies by surface (compact strips
/// vs verbose forms), so we expose both.
library;

import 'package:flutter/material.dart' show TimeOfDay;

/// Static-only namespace. Use the named methods instead of free
/// functions so callsites read as `Hhmm.formatLong(...)` and the
/// intent is unambiguous.
class Hhmm {
  Hhmm._();

  /// Parse `"HH:mm"` to total minutes since midnight. Throws
  /// [FormatException] on malformed input. Use [tryToMinutes]
  /// when you can tolerate bad input.
  static int toMinutes(String hhmm) {
    final m = tryToMinutes(hhmm);
    if (m == null) {
      throw FormatException('Not a valid HH:mm value', hhmm);
    }
    return m;
  }

  /// Parse `"HH:mm"` to total minutes since midnight, returning
  /// null on malformed input. Lenient about leading-zero padding
  /// (`"9:30"` parses fine).
  static int? tryToMinutes(String? hhmm) {
    if (hhmm == null) return null;
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }

  /// `570` → `"09:30"`. Always zero-padded so the result is a
  /// valid storage string. Negative or overflow values get
  /// modulo'd into a 24-hour day.
  static String fromMinutes(int totalMinutes) {
    final wrapped = ((totalMinutes % (24 * 60)) + 24 * 60) % (24 * 60);
    final h = wrapped ~/ 60;
    final m = wrapped % 60;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}';
  }

  /// [TimeOfDay] → `"HH:mm"` wire format. Use this whenever a
  /// picker result needs to land in Drift / cloud.
  static String fromTimeOfDay(TimeOfDay t) =>
      fromMinutes(t.hour * 60 + t.minute);

  /// `"HH:mm"` → [TimeOfDay]. Returns null on malformed input
  /// (the picker can't render null, so the caller decides what
  /// fallback makes sense).
  static TimeOfDay? toTimeOfDay(String? hhmm) {
    final m = tryToMinutes(hhmm);
    if (m == null) return null;
    return TimeOfDay(hour: m ~/ 60, minute: m % 60);
  }

  /// `"09:30"` → `"9:30 AM"` (verbose). Used in forms, edit
  /// sheets, reminders — anywhere there's room for the full
  /// AM/PM label. Returns the input unchanged on malformed
  /// input so the UI doesn't crash on stray data.
  static String formatLong(String hhmm) {
    final m = tryToMinutes(hhmm);
    if (m == null) return hhmm;
    return _format(m, compact: false);
  }

  /// `"09:30"` → `"9:30a"` (compact). Used in dense schedule
  /// strips and the today timeline where horizontal space is
  /// scarce. Same fallback semantics as [formatLong].
  static String formatCompact(String hhmm) {
    final m = tryToMinutes(hhmm);
    if (m == null) return hhmm;
    return _format(m, compact: true);
  }

  /// [TimeOfDay] flavor of [formatLong] — `9:30 AM`.
  static String formatLongTimeOfDay(TimeOfDay t) =>
      _format(t.hour * 60 + t.minute, compact: false);

  /// [TimeOfDay] flavor of [formatCompact] — `9:30a`.
  static String formatCompactTimeOfDay(TimeOfDay t) =>
      _format(t.hour * 60 + t.minute, compact: true);

  /// [DateTime] flavor of [formatLong] — uses the time-of-day
  /// component, ignores the date.
  static String formatLongDateTime(DateTime d) =>
      _format(d.hour * 60 + d.minute, compact: false);

  /// [DateTime] flavor of [formatCompact].
  static String formatCompactDateTime(DateTime d) =>
      _format(d.hour * 60 + d.minute, compact: true);

  static String _format(int minutes, {required bool compact}) {
    final h24 = minutes ~/ 60;
    final m = minutes % 60;
    final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    if (compact) {
      final period = h24 < 12 ? 'a' : 'p';
      // "9p" if exactly on the hour; "9:30p" otherwise.
      return m == 0
          ? '$h12$period'
          : '$h12:${m.toString().padLeft(2, '0')}$period';
    } else {
      final period = h24 < 12 ? 'AM' : 'PM';
      return '$h12:${m.toString().padLeft(2, '0')} $period';
    }
  }
}

extension TimeOfDayMinutesSinceMidnight on TimeOfDay {
  /// `9:30` → `570`. Replaces the open-coded
  /// `t.hour * 60 + t.minute` expression that was scattered
  /// across the today screen, lateness pass, ratio check, and
  /// activity wizard.
  int get minutesSinceMidnight => hour * 60 + minute;
}
