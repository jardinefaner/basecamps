/// Schema for built-in curriculum templates that can be imported
/// in one tap. Mirrors the runtime data model:
///   * [CurriculumTemplate] → one program theme (10 weeks).
///   * [WeekTemplate]       → one LessonSequence inside the theme.
///   * [DailyTemplate]      → a daily ritual on a specific weekday.
///   * [MilestoneTemplate]  → the weekly capstone.
///   * [AgeBand]            → adjacent-age rewrites for one activity.
///
/// Importer turns these into:
///   * `themes` row + `lesson_sequences` rows (one per week)
///   * `lesson_sequence_items` rows (5 daily + 1 milestone per week)
///   * `activity_library` rows (one per ritual, with age variants)
class CurriculumTemplate {
  const CurriculumTemplate({
    required this.id,
    required this.name,
    required this.tagline,
    required this.summary,
    required this.audience,
    required this.weekCount,
    required this.themeColorHex,
    required this.weeks,
  });

  /// Stable id, e.g. `'different-world-2026'`. Used as the
  /// "already imported?" key so the templates screen can surface
  /// a "view" affordance instead of "import" on re-visits.
  final String id;
  final String name;
  final String tagline;
  final String summary;
  final String audience;
  final int weekCount;

  /// Theme-level accent color. Individual weeks override via
  /// `WeekTemplate.colorHex`.
  final String themeColorHex;
  final List<WeekTemplate> weeks;
}

class WeekTemplate {
  const WeekTemplate({
    required this.week,
    required this.phase,
    required this.title,
    required this.coreQuestion,
    required this.colorHex,
    required this.description,
    required this.daily,
    required this.milestone,
    required this.engineNotes,
  });

  /// 1-based week number. Ordering for the curriculum view.
  final int week;

  /// Free-text phase label. Sequences with the same phase render
  /// under one phase header in the curriculum view (e.g.
  /// "ALL ABOUT ME" for weeks 1–2).
  final String phase;
  final String title;
  final String coreQuestion;
  final String colorHex;
  final String description;
  final List<DailyTemplate> daily;
  final MilestoneTemplate milestone;

  /// Pedagogical commentary surfaced behind a toggle. Free-form
  /// text the curriculum author wrote for teachers.
  final String engineNotes;
}

class DailyTemplate {
  const DailyTemplate({
    required this.dayOfWeek,
    required this.name,
    required this.description,
    this.ageBands = const [],
  });

  /// 1=Mon … 5=Fri. The importer stamps this onto the
  /// `lesson_sequence_items.day_of_week` column.
  final int dayOfWeek;

  /// Becomes `activity_library.title`.
  final String name;

  /// Becomes `activity_library.summary`.
  final String description;

  /// Optional adjacent-age rewrites. Stored as the JSON-shaped
  /// `activity_library.age_variants` blob.
  final List<AgeBand> ageBands;
}

class MilestoneTemplate {
  const MilestoneTemplate({
    required this.name,
    required this.description,
    this.ageBands = const [],
  });

  final String name;
  final String description;
  final List<AgeBand> ageBands;
}

class AgeBand {
  const AgeBand({
    required this.age,
    required this.summary,
  });

  /// Single representative age for the band — e.g. an "8-12" band
  /// is encoded as `age: 10` (mid-band) so the runtime renderer
  /// can pick the closest match without having to model ranges
  /// in the storage layer. Authors can store as many ages as
  /// they like; the renderer does nearest-match.
  final int age;
  final String summary;
}
