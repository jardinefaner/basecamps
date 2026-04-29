import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/lesson_sequences/lesson_sequences_repository.dart';
import 'package:basecamp/features/themes/themes_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Where in the curriculum are we today?" — resolves a calendar date
/// down to a single (theme, sequence, weekIndex, weekArc) tuple so the
/// daily surfaces (Today, Schedule editor) can render curriculum
/// context without knowing the schema.
///
/// Why this lives outside both the themes + lesson_sequences modules:
/// it's the *integration* — pulls a date through the active-themes
/// query, picks one theme when several overlap, walks its sequences,
/// figures out which week the date falls in, and pulls that
/// sequence's WeekArc. Either side could host it but lifting it here
/// keeps the per-table repos focused on their own table and lets
/// callers depend on one provider instead of three.
class CurriculumDay {
  const CurriculumDay({
    required this.theme,
    required this.sequence,
    required this.weekIndex,
    required this.totalWeeks,
    required this.arc,
  });

  /// The active theme covering the resolved date. Picked
  /// deterministically when multiple themes overlap (earliest start
  /// wins — `watchActive` already returns ordered ascending so we
  /// take the first).
  final ProgramTheme theme;

  /// The sequence ("week") within the theme that covers the resolved
  /// date, computed from `(date − theme.startDate).inDays ~/ 7`. Null
  /// when the theme exists but its date range starts in the future,
  /// or the computed week index is past the last sequence.
  final LessonSequence? sequence;

  /// Zero-based week index of the resolved date within the theme. So
  /// week 0 is the first 7 days, week 1 the next 7, etc. Provided
  /// even when [sequence] is null so the UI can still render "Week
  /// 11" with a hint that no curriculum was authored for it.
  final int weekIndex;

  /// Total sequences attached to the theme — the denominator when
  /// rendering "Week 2 of 10".
  final int totalWeeks;

  /// Joined daily-cards / milestones for [sequence], or null when
  /// the sequence is null. Loaded eagerly here so the Today strip
  /// can render in one watch instead of chaining three.
  final WeekArc? arc;
}

/// Stream the (theme, sequence, week, arc) for a date. Returns null
/// when no theme covers that date — Today renders without a curriculum
/// strip in that case (program with no curriculum authored, or a date
/// before/after the active arc).
///
/// Family takes a normalized midnight date; the Today strip already
/// normalizes its `viewedDate` so passing it in here doesn't churn
/// the cache key on every clock tick.
// Riverpod family return type is intentionally inferred; declaring
// it explicitly wouldn't add safety here and would clash with the
// project's existing inference style for similar providers.
// ignore: specify_nonobvious_property_types
final curriculumForDateProvider =
    StreamProvider.family<CurriculumDay?, DateTime>((ref, date) async* {
  final themesRepo = ref.watch(themesRepositoryProvider);
  final sequencesRepo = ref.watch(lessonSequencesRepositoryProvider);
  // Combine three streams without rxdart — listen to active themes,
  // re-pick a theme + sequences each emit. Sequences and arc are
  // pulled per emission instead of via nested StreamGroup so we
  // don't need a third dependency.
  await for (final themes in themesRepo.watchActive(date)) {
    if (themes.isEmpty) {
      yield null;
      continue;
    }
    // First-by-startDate when multiple overlap. The repo already
    // sorts ascending — we just take the head.
    final theme = themes.first;
    final sequences =
        await sequencesRepo.watchSequencesForTheme(theme.id).first;
    final ordered = _orderByWeekNumber(sequences);
    final dayDelta = _daysBetween(theme.startDate, date);
    final weekIndex = dayDelta < 0 ? 0 : dayDelta ~/ 7;
    final sequence =
        weekIndex < ordered.length ? ordered[weekIndex] : null;
    final arc = sequence == null
        ? null
        : await sequencesRepo.watchWeekArc(sequence.id).first;
    yield CurriculumDay(
      theme: theme,
      sequence: sequence,
      weekIndex: weekIndex,
      totalWeeks: ordered.length,
      arc: arc,
    );
  }
});

/// Sort sequences by their leading "Week N:" number when present;
/// fall back to alphabetic name for sequences that don't follow the
/// convention.
///
/// `watchSequencesForTheme` orders alphabetically — fine for "Week 1"
/// through "Week 9" but wrong at week 10 ("Week 10" sorts before
/// "Week 2"). Imported curricula go up to 10+ weeks so we have to
/// re-sort here. Sequences whose names don't start with "Week N:"
/// get sorted alphabetically after the numbered ones.
List<LessonSequence> _orderByWeekNumber(List<LessonSequence> rows) {
  return [...rows]
    ..sort((a, b) {
      final na = _weekNumber(a.name);
      final nb = _weekNumber(b.name);
      if (na != null && nb != null) return na.compareTo(nb);
      if (na != null) return -1; // numbered before un-numbered
      if (nb != null) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
}

/// Parse the leading "Week N" out of a sequence name. Tolerant of
/// case + colon vs. dash separator + leading whitespace. Returns
/// null when the name doesn't start with a `Week <number>` token,
/// which the sort above demotes to alphabetic.
int? _weekNumber(String name) {
  final match = RegExp(r'^\s*week\s+(\d+)', caseSensitive: false)
      .firstMatch(name);
  if (match == null) return null;
  return int.tryParse(match.group(1) ?? '');
}

/// Days between two midnight-normalized dates, returning a negative
/// value when [later] precedes [earlier]. Avoids `Duration.inDays`'s
/// daylight-savings rounding edge case by working off `DateTime.utc`.
int _daysBetween(DateTime earlier, DateTime later) {
  final a = DateTime.utc(earlier.year, earlier.month, earlier.day);
  final b = DateTime.utc(later.year, later.month, later.day);
  return b.difference(a).inDays;
}
