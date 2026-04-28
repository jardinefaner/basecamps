import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:basecamp/features/curriculum/templates/curriculum_template.dart';
import 'package:basecamp/features/lesson_sequences/lesson_sequences_repository.dart';
import 'package:basecamp/features/themes/themes_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bulk-import a [CurriculumTemplate] into the active program:
/// creates one theme, N lesson sequences, M sequence items
/// (5 daily + 1 milestone per week), and the same number of
/// activity-library cards (one per ritual / milestone, with
/// adjacent-age rewrites).
///
/// Each underlying repository write goes through its existing
/// `addX` method so the program-id stamp + sync push happen as
/// they would for a hand-typed entry. No bypass — the imported
/// theme is indistinguishable from one the user typed in by hand
/// and is immediately editable from the existing screens.
///
/// Caller passes start/end dates for the theme's date range
/// since templates don't carry calendar dates (they describe
/// "week 1, week 2, …" abstractly). The recommended convention
/// is `startDate` = the theme's launch Monday, `endDate` =
/// `startDate + 7 * weekCount` — but the importer doesn't enforce.
class CurriculumImporter {
  CurriculumImporter(this._ref);

  final Ref _ref;

  /// Returns the new theme id.
  Future<String> import({
    required CurriculumTemplate template,
    required String themeName,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final themes = _ref.read(themesRepositoryProvider);
    final sequences = _ref.read(lessonSequencesRepositoryProvider);
    final library = _ref.read(activityLibraryRepositoryProvider);

    // 1. Theme.
    final themeId = await themes.addTheme(
      name: themeName,
      startDate: startDate,
      endDate: endDate,
      colorHex: template.themeColorHex,
      notes: template.summary,
    );

    // 2. One LessonSequence per week — name prefixed with
    //    "Week N:" so the curriculum view's chip strip and
    //    sequences list both show ordering at a glance.
    for (final week in template.weeks) {
      final seqId = await sequences.addSequence(
        name: 'Week ${week.week}: ${week.title}',
        description: week.description,
        themeId: themeId,
        coreQuestion: week.coreQuestion,
        phase: week.phase,
        colorHex: week.colorHex,
        engineNotes: week.engineNotes,
      );

      // 3. Daily rituals + 4. Milestone — each is its own
      //    activity-library row (so the card is reusable in
      //    other sequences later), then linked into the
      //    sequence via `lesson_sequence_items` with the right
      //    day-of-week + kind.
      for (final daily in week.daily) {
        final libraryId = await library.addItem(
          title: daily.name,
          summary: daily.description,
          ageVariants: _toAgeVariantMap(daily.ageBands),
        );
        await sequences.addItem(
          sequenceId: seqId,
          libraryItemId: libraryId,
          dayOfWeek: daily.dayOfWeek,
        );
      }

      final milestoneLibraryId = await library.addItem(
        title: week.milestone.name,
        summary: week.milestone.description,
        ageVariants: _toAgeVariantMap(week.milestone.ageBands),
      );
      await sequences.addItem(
        sequenceId: seqId,
        libraryItemId: milestoneLibraryId,
        kind: 'milestone',
      );
    }

    return themeId;
  }

  /// Convert the template's `List<AgeBand>` into the runtime
  /// `Map<int, AgeVariant>` shape the activity-library repo
  /// accepts. Returns null when the band list is empty so the
  /// `age_variants` JSON column stays null (cheaper than an
  /// empty map for a card that doesn't have rewrites).
  Map<int, AgeVariant>? _toAgeVariantMap(List<AgeBand> bands) {
    if (bands.isEmpty) return null;
    return {
      for (final b in bands)
        b.age: AgeVariant(summary: b.summary),
    };
  }
}

final curriculumImporterProvider = Provider<CurriculumImporter>((ref) {
  return CurriculumImporter(ref);
});
