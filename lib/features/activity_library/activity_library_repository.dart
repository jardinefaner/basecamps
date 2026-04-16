import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ActivityLibraryRepository {
  ActivityLibraryRepository(this._db);

  final AppDatabase _db;

  Stream<List<ActivityLibraryData>> watchAll() {
    final query = _db.select(_db.activityLibrary)
      ..orderBy([(a) => OrderingTerm.asc(a.title)]);
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
  }) async {
    await (_db.update(_db.activityLibrary)..where((a) => a.id.equals(id)))
        .write(
      ActivityLibraryCompanion(
        title: Value(title),
        defaultDurationMin: Value(defaultDurationMin),
        specialistId: Value(specialistId),
        location: Value(location),
        notes: Value(notes),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteItem(String id) async {
    await (_db.delete(_db.activityLibrary)..where((a) => a.id.equals(id)))
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
