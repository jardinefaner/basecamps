import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ActivityLibraryRepository {
  ActivityLibraryRepository(this._db);

  final AppDatabase _db;

  Stream<List<ActivityLibraryData>> watchAll() {
    // Newest first — the user's spec for the creation flow ends with
    // the freshly-generated card appearing at the top of the bucket,
    // and that's the intuitive order for a bucket anyway.
    final query = _db.select(_db.activityLibrary)
      ..orderBy([(a) => OrderingTerm.desc(a.createdAt)]);
    return query.watch();
  }

  Future<ActivityLibraryData?> getItem(String id) {
    return (_db.select(_db.activityLibrary)..where((a) => a.id.equals(id)))
        .getSingleOrNull();
  }

  Future<String> addItem({
    required String title,
    int? defaultDurationMin,
    String? specialistId,
    String? location,
    String? notes,
    // Rich card fields — all optional so legacy "just a preset" rows
    // (title + duration etc.) still work through the same API.
    int? audienceMinAge,
    int? audienceMaxAge,
    String? hook,
    String? summary,
    String? keyPoints,
    String? learningGoals,
    int? engagementTimeMin,
    String? sourceUrl,
    String? sourceAttribution,
  }) async {
    final id = newId();
    await _db.into(_db.activityLibrary).insert(
          ActivityLibraryCompanion.insert(
            id: id,
            title: title,
            defaultDurationMin: Value(defaultDurationMin),
            specialistId: Value(specialistId),
            location: Value(location),
            notes: Value(notes),
            audienceMinAge: Value(audienceMinAge),
            audienceMaxAge: Value(audienceMaxAge),
            hook: Value(hook),
            summary: Value(summary),
            keyPoints: Value(keyPoints),
            learningGoals: Value(learningGoals),
            engagementTimeMin: Value(engagementTimeMin),
            sourceUrl: Value(sourceUrl),
            sourceAttribution: Value(sourceAttribution),
          ),
        );
    return id;
  }

  Future<void> updateItem({
    required String id,
    required String title,
    int? defaultDurationMin,
    String? specialistId,
    String? location,
    String? notes,
    int? audienceMinAge,
    int? audienceMaxAge,
    String? hook,
    String? summary,
    String? keyPoints,
    String? learningGoals,
    int? engagementTimeMin,
    String? sourceUrl,
    String? sourceAttribution,
  }) async {
    await (_db.update(_db.activityLibrary)..where((a) => a.id.equals(id)))
        .write(
      ActivityLibraryCompanion(
        title: Value(title),
        defaultDurationMin: Value(defaultDurationMin),
        specialistId: Value(specialistId),
        location: Value(location),
        notes: Value(notes),
        audienceMinAge: Value(audienceMinAge),
        audienceMaxAge: Value(audienceMaxAge),
        hook: Value(hook),
        summary: Value(summary),
        keyPoints: Value(keyPoints),
        learningGoals: Value(learningGoals),
        engagementTimeMin: Value(engagementTimeMin),
        sourceUrl: Value(sourceUrl),
        sourceAttribution: Value(sourceAttribution),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteItem(String id) async {
    await (_db.delete(_db.activityLibrary)..where((a) => a.id.equals(id)))
        .go();
  }

  Future<void> deleteItems(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (_db.delete(_db.activityLibrary)..where((a) => a.id.isIn(list)))
        .go();
  }
}

final activityLibraryRepositoryProvider =
    Provider<ActivityLibraryRepository>((ref) {
  return ActivityLibraryRepository(ref.watch(databaseProvider));
});

final activityLibraryProvider =
    StreamProvider<List<ActivityLibraryData>>((ref) {
  return ref.watch(activityLibraryRepositoryProvider).watchAll();
});
