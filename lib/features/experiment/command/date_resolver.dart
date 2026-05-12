// Deterministic date-phrase resolver.
//
// The LLM stops getting "Wednesday → ISO date" right consistently
// no matter how we prompt it. So we don't ask. This file scans
// teacher inputs for date phrases ("wednesday", "next monday",
// "tomorrow", "in 3 days", "may 15") and resolves them to ISO
// dates in Dart, against a reference "today". The dispatcher
// injects the resolved facts into the user message so the model
// just copies them.
//
// Reference: `_now` is always passed in by the caller so this
// stays unit-testable without `DateTime.now()` poisoning the
// suite.

import 'package:intl/intl.dart';

/// One resolved date phrase from the user's input.
class ResolvedDate {
  const ResolvedDate({
    required this.phrase,
    required this.iso,
    required this.weekday,
  });

  /// The literal phrase the user typed/said ("wednesday",
  /// "tomorrow", "next monday").
  final String phrase;

  /// ISO-8601 yyyy-MM-dd in local time.
  final String iso;

  /// Lowercase weekday name for the resolved date — used by
  /// validators to confirm the LLM picked the right weekday.
  final String weekday;
}

class DateResolver {
  const DateResolver();

  /// Resolve every date phrase found in [input] against [now].
  /// Returns a list in order of first appearance. Returns an
  /// empty list when nothing parseable is found.
  ///
  /// Handles:
  ///   • "today", "tonight"
  ///   • "tomorrow", "tmrw"
  ///   • "yesterday"
  ///   • "<weekday>"
  ///   • "this <weekday>"
  ///   • "next <weekday>"
  ///   • "last <weekday>" (yesterday-ward)
  ///   • "in N days", "N days from now"
  ///   • bare months — "may 15", "may 15th", "jan 3"
  ///   • ISO yyyy-MM-dd (passed through verbatim)
  ///
  /// "<weekday>" with no modifier → NEXT occurrence. If today
  /// is the named weekday, returns today.
  /// "this <weekday>" → THIS calendar week's occurrence. If
  /// that day is in the past this week, falls back to the
  /// upcoming weekday.
  /// "next <weekday>" → NEXT calendar week's occurrence,
  /// strictly after this week.
  List<ResolvedDate> resolve(String input, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final lower = input.toLowerCase();
    final results = <ResolvedDate>[];
    final seen = <String>{};
    void add(String phrase, DateTime date) {
      if (seen.add(phrase)) {
        results.add(
          ResolvedDate(
            phrase: phrase,
            iso: _iso(date),
            weekday: _weekdayName(date),
          ),
        );
      }
    }

    // "today" / "tonight"
    if (RegExp(r'\btoday\b|\btonight\b').hasMatch(lower)) {
      add('today', today);
    }
    // "tomorrow" / "tmrw"
    if (RegExp(r'\btomorrow\b|\btmrw\b').hasMatch(lower)) {
      add('tomorrow', today.add(const Duration(days: 1)));
    }
    // "yesterday"
    if (RegExp(r'\byesterday\b').hasMatch(lower)) {
      add('yesterday', today.subtract(const Duration(days: 1)));
    }

    // "in N days" / "N days from now"
    for (final m in RegExp(
      r'\b(?:in\s+)?(\d{1,3})\s+days?(?:\s+from\s+now)?\b',
    ).allMatches(lower)) {
      final n = int.tryParse(m.group(1)!);
      if (n != null && n >= 0 && n <= 365) {
        add('${m.group(0)!.trim()}', today.add(Duration(days: n)));
      }
    }

    // Weekday phrases — modifier-aware.
    const weekdays = {
      'monday': DateTime.monday,
      'tuesday': DateTime.tuesday,
      'wednesday': DateTime.wednesday,
      'thursday': DateTime.thursday,
      'friday': DateTime.friday,
      'saturday': DateTime.saturday,
      'sunday': DateTime.sunday,
    };
    for (final entry in weekdays.entries) {
      final wd = entry.key;
      // "next <weekday>" — strictly next calendar week.
      if (RegExp('\\bnext\\s+$wd\\b').hasMatch(lower)) {
        add('next $wd', _nextWeekday(today, entry.value, strictlyNextWeek: true));
        continue;
      }
      // "this <weekday>" — this calendar week.
      if (RegExp('\\bthis\\s+$wd\\b').hasMatch(lower)) {
        add('this $wd', _thisWeekday(today, entry.value));
        continue;
      }
      // "last <weekday>" — most recent past occurrence.
      if (RegExp('\\blast\\s+$wd\\b').hasMatch(lower)) {
        add('last $wd', _lastWeekday(today, entry.value));
        continue;
      }
      // Bare weekday — next occurrence including today.
      if (RegExp('\\b$wd\\b').hasMatch(lower)) {
        add(wd, _nextWeekday(today, entry.value, strictlyNextWeek: false));
      }
    }

    // Bare months — "may 15", "may 15th", "jan 3"
    const months = {
      'january': 1, 'jan': 1,
      'february': 2, 'feb': 2,
      'march': 3, 'mar': 3,
      'april': 4, 'apr': 4,
      'may': 5,
      'june': 6, 'jun': 6,
      'july': 7, 'jul': 7,
      'august': 8, 'aug': 8,
      'september': 9, 'sep': 9, 'sept': 9,
      'october': 10, 'oct': 10,
      'november': 11, 'nov': 11,
      'december': 12, 'dec': 12,
    };
    for (final m in RegExp(
      r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec|january|february|march|april|june|july|august|september|october|november|december)\s+(\d{1,2})(?:st|nd|rd|th)?\b',
      caseSensitive: false,
    ).allMatches(lower)) {
      final monthName = m.group(1)!.toLowerCase();
      final dayNum = int.tryParse(m.group(2)!);
      final month = months[monthName];
      if (month == null || dayNum == null) continue;
      if (dayNum < 1 || dayNum > 31) continue;
      // Year heuristic: if the date is in the past by >30 days,
      // assume next year. Otherwise current year.
      var year = today.year;
      var candidate = DateTime(year, month, dayNum);
      if (candidate.isBefore(today.subtract(const Duration(days: 30)))) {
        candidate = DateTime(year + 1, month, dayNum);
      }
      add(m.group(0)!.trim(), candidate);
    }

    // ISO yyyy-MM-dd passed through.
    for (final m in RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b').allMatches(input)) {
      try {
        final d = DateTime.parse(m.group(0)!);
        add(m.group(0)!, d);
      } on FormatException {
        // skip
      }
    }

    return results;
  }

  // ——— Helpers —————————————————————————————————————————————

  DateTime _nextWeekday(
    DateTime from,
    int targetWeekday, {
    required bool strictlyNextWeek,
  }) {
    if (strictlyNextWeek) {
      // Jump to the next Monday's row, then forward to the target.
      final daysToNextMonday = (8 - from.weekday) % 7;
      final nextMon = from.add(
        Duration(days: daysToNextMonday == 0 ? 7 : daysToNextMonday),
      );
      final offset = (targetWeekday - nextMon.weekday) % 7;
      return nextMon.add(Duration(days: offset));
    }
    final offset = (targetWeekday - from.weekday) % 7;
    return from.add(Duration(days: offset));
  }

  DateTime _thisWeekday(DateTime from, int targetWeekday) {
    // Monday-anchored week.
    final mondayThisWeek = from.subtract(Duration(days: from.weekday - 1));
    final candidate = mondayThisWeek.add(Duration(days: targetWeekday - 1));
    // If "this <day>" already passed this week, fall back to the
    // upcoming bare weekday (= next week, since today→Sunday is
    // the full window of "this week").
    if (candidate.isBefore(from)) {
      return _nextWeekday(from, targetWeekday, strictlyNextWeek: false);
    }
    return candidate;
  }

  DateTime _lastWeekday(DateTime from, int targetWeekday) {
    final offset = (from.weekday - targetWeekday) % 7;
    return from.subtract(Duration(days: offset == 0 ? 7 : offset));
  }

  String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  String _weekdayName(DateTime d) {
    const names = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    return names[d.weekday - 1];
  }
}

/// Singleton for use from the dispatcher / tools.
const kDateResolver = DateResolver();
