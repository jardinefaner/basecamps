import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Repository for the lesson-sequence tables (v40).
///
/// Schema-only this round — no UI consumes these methods yet. Round 4
/// builds the week-planner on top. Kept deliberately thin so the later
/// round can grow the API without renaming what's here.
class LessonSequencesRepository {
  LessonSequencesRepository(this._db, this._ref);

  final AppDatabase _db;
  final Ref _ref;

  /// See ObservationsRepository._programId for why we read this on
  /// every insert rather than caching at construction time.
  String? get _programId => _ref.read(activeProgramIdProvider);

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
            programId: Value(_programId),
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

  /// Fetch a single item by id — used by the undo path on remove.
  Future<LessonSequenceItem?> getItem(String id) {
    return (_db.select(_db.lessonSequenceItems)..where((i) => i.id.equals(id)))
        .getSingleOrNull();
  }

  /// Re-insert a previously-deleted item. Used by confirmDeleteWithUndo
  /// so removals have a 5-second take-back window.
  Future<void> restoreItem(LessonSequenceItem row) async {
    await _db.into(_db.lessonSequenceItems).insertOnConflictUpdate(row);
  }

  /// Rewrite `position` for every item in [sequenceId] so the order
  /// matches [itemIdsInNewOrder]. Done in one transaction — positions
  /// land 0..N-1 matching the passed list. Unlisted ids are ignored
  /// (caller is responsible for passing every item).
  Future<void> reorderItems(
    String sequenceId,
    List<String> itemIdsInNewOrder,
  ) async {
    await _db.transaction(() async {
      for (var i = 0; i < itemIdsInNewOrder.length; i++) {
        final itemId = itemIdsInNewOrder[i];
        await (_db.update(_db.lessonSequenceItems)
              ..where((row) =>
                  row.id.equals(itemId) &
                  row.sequenceId.equals(sequenceId)))
            .write(LessonSequenceItemsCompanion(position: Value(i)));
      }
    });
  }

  /// Stream every (item, libraryItem) pair for a sequence, ordered by
  /// position. The detail screen needs the joined library row so it
  /// can render real titles / durations without a second per-row
  /// FutureProvider lookup.
  Stream<List<SequenceItemWithLibrary>> watchItemsJoined(String sequenceId) {
    final query = _db.select(_db.lessonSequenceItems).join([
      innerJoin(
        _db.activityLibrary,
        _db.activityLibrary.id.equalsExp(_db.lessonSequenceItems.libraryItemId),
      ),
    ])
      ..where(_db.lessonSequenceItems.sequenceId.equals(sequenceId))
      ..orderBy([OrderingTerm.asc(_db.lessonSequenceItems.position)]);

    return query.watch().map((rows) {
      return [
        for (final row in rows)
          SequenceItemWithLibrary(
            item: row.readTable(_db.lessonSequenceItems),
            library: row.readTable(_db.activityLibrary),
          ),
      ];
    });
  }
}

/// Joined sequence-item + library-row pair used by the detail screen
/// so it can render each row with its real title / duration without
/// a separate lookup per row.
class SequenceItemWithLibrary {
  const SequenceItemWithLibrary({required this.item, required this.library});

  final LessonSequenceItem item;
  final ActivityLibraryData library;
}

final lessonSequencesRepositoryProvider =
    Provider<LessonSequencesRepository>((ref) {
  return LessonSequencesRepository(ref.watch(databaseProvider), ref);
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

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final lessonSequenceItemsJoinedProvider =
    StreamProvider.family<List<SequenceItemWithLibrary>, String>(
  (ref, sequenceId) {
    return ref
        .watch(lessonSequencesRepositoryProvider)
        .watchItemsJoined(sequenceId);
  },
);

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final lessonSequenceProvider =
    FutureProvider.family<LessonSequence?, String>(
  (ref, id) {
    return ref.watch(lessonSequencesRepositoryProvider).getSequence(id);
  },
);
