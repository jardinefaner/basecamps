import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Repository for the lesson-sequence tables (v40).
///
/// Schema-only this round — no UI consumes these methods yet. Round 4
/// builds the week-planner on top. Kept deliberately thin so the later
/// round can grow the API without renaming what's here.
class LessonSequencesRepository {
  LessonSequencesRepository(this._db);

  final AppDatabase _db;

  // -------- Sequences --------

  Stream<List<LessonSequence>> watchAll() {
    final query = _db.select(_db.lessonSequences)
      ..orderBy([(s) => OrderingTerm.asc(s.name)]);
    return query.watch();
  }

  Future<LessonSequence?> getSequence(String id) {
    return (_db.select(_db.lessonSequences)..where((s) => s.id.equals(id)))
        .getSingleOrNull();
  }

  Future<String> addSequence({
    required String name,
    String? description,
  }) async {
    final id = newId();
    await _db.into(_db.lessonSequences).insert(
          LessonSequencesCompanion.insert(
            id: id,
            name: name,
            description: Value(description),
          ),
        );
    return id;
  }

  Future<void> updateSequence({
    required String id,
    String? name,
    Value<String?> description = const Value.absent(),
  }) async {
    await (_db.update(_db.lessonSequences)..where((s) => s.id.equals(id)))
        .write(
      LessonSequencesCompanion(
        name: name == null ? const Value.absent() : Value(name),
        description: description,
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteSequence(String id) async {
    await (_db.delete(_db.lessonSequences)..where((s) => s.id.equals(id)))
        .go();
  }

  // -------- Items --------

  /// Ordered items in a sequence. Sorted by `position` ascending so
  /// the planner can render them as a list without re-sorting.
  Stream<List<LessonSequenceItem>> watchItemsFor(String sequenceId) {
    final query = _db.select(_db.lessonSequenceItems)
      ..where((i) => i.sequenceId.equals(sequenceId))
      ..orderBy([(i) => OrderingTerm.asc(i.position)]);
    return query.watch();
  }

  /// Appends [libraryItemId] to the end of [sequenceId]. Position
  /// comes from the max existing position + 1; for an empty sequence
  /// that's 0.
  Future<String> addItem({
    required String sequenceId,
    required String libraryItemId,
  }) async {
    final existing = await (_db.select(_db.lessonSequenceItems)
          ..where((i) => i.sequenceId.equals(sequenceId))
          ..orderBy([(i) => OrderingTerm.desc(i.position)])
          ..limit(1))
        .getSingleOrNull();
    final nextPosition = (existing?.position ?? -1) + 1;
    final id = newId();
    await _db.into(_db.lessonSequenceItems).insert(
          LessonSequenceItemsCompanion.insert(
            id: id,
            sequenceId: sequenceId,
            libraryItemId: libraryItemId,
            position: nextPosition,
          ),
        );
    return id;
  }

  Future<void> deleteItem(String id) async {
    await (_db.delete(_db.lessonSequenceItems)..where((i) => i.id.equals(id)))
        .go();
  }
}

final lessonSequencesRepositoryProvider =
    Provider<LessonSequencesRepository>((ref) {
  return LessonSequencesRepository(ref.watch(databaseProvider));
});

final lessonSequencesProvider =
    StreamProvider<List<LessonSequence>>((ref) {
  return ref.watch(lessonSequencesRepositoryProvider).watchAll();
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final lessonSequenceItemsProvider =
    StreamProvider.family<List<LessonSequenceItem>, String>(
  (ref, sequenceId) {
    return ref
        .watch(lessonSequencesRepositoryProvider)
        .watchItemsFor(sequenceId);
  },
);
