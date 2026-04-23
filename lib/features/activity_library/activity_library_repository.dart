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

  /// Updates ONLY the fields explicitly provided. Uses Drift's
  /// `Value.absent()` for anything not passed so a caller that only
  /// touches preset fields (title/duration/location/…) doesn't
  /// accidentally null out the rich-card columns (audience, summary,
  /// hook, etc.) just by virtue of not mentioning them.
  ///
  /// Regression fixed here: the edit sheet was calling updateItem with
  /// positional `null`s for rich fields, which got written to the DB
  /// and wiped every AI-generated card on its first edit.
  Future<void> updateItem({
    required String id,
    String? title,
    // Each field uses a `Value<T>` wrapper so callers can distinguish
    // "leave this alone" (absent) from "set it to null" (Value(null)).
    Value<int?> defaultDurationMin = const Value.absent(),
    Value<String?> specialistId = const Value.absent(),
    Value<String?> location = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<int?> audienceMinAge = const Value.absent(),
    Value<int?> audienceMaxAge = const Value.absent(),
    Value<String?> hook = const Value.absent(),
    Value<String?> summary = const Value.absent(),
    Value<String?> keyPoints = const Value.absent(),
    Value<String?> learningGoals = const Value.absent(),
    Value<int?> engagementTimeMin = const Value.absent(),
    Value<String?> sourceUrl = const Value.absent(),
    Value<String?> sourceAttribution = const Value.absent(),
  }) async {
    await (_db.update(_db.activityLibrary)..where((a) => a.id.equals(id)))
        .write(
      ActivityLibraryCompanion(
        title: title == null ? const Value.absent() : Value(title),
        defaultDurationMin: defaultDurationMin,
        specialistId: specialistId,
        location: location,
        notes: notes,
        audienceMinAge: audienceMinAge,
        audienceMaxAge: audienceMaxAge,
        hook: hook,
        summary: summary,
        keyPoints: keyPoints,
        learningGoals: learningGoals,
        engagementTimeMin: engagementTimeMin,
        sourceUrl: sourceUrl,
        sourceAttribution: sourceAttribution,
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

  /// Restore helpers for the undo snackbar — re-insert with the
  /// original id. Cascaded schedule-entry / template source links
  /// (source_library_item_id) are already null from the delete
  /// cascade and don't come back.
  Future<void> restoreItem(ActivityLibraryData row) async {
    await _db.into(_db.activityLibrary).insertOnConflictUpdate(row);
  }

  Future<void> restoreItems(Iterable<ActivityLibraryData> rows) async {
    await _db.transaction(() async {
      for (final row in rows) {
        await _db.into(_db.activityLibrary).insertOnConflictUpdate(row);
      }
    });
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
