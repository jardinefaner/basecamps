import 'dart:async';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:basecamp/features/sync/sync_specs.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Parents / guardians (v38). Promoted from the free-text
/// `Children.parentName` column so siblings share a single row and
/// contact info lives in one place. See tables.dart for why
/// `parentName` still exists in the children table.
///
/// The join table `ParentChildren` is many-to-many: sibling rows
/// point at the same parent, a child with two parents has two rows.
/// Primary-pickup-contact is a boolean on the join; the repository
/// enforces "at most one primary per child" since SQLite can't
/// express it cheaply.
class ParentsRepository {
  ParentsRepository(this._db, this._ref);

  final AppDatabase _db;
  final Ref _ref;

  /// See ObservationsRepository._programId for why we read this on
  /// every insert rather than caching at construction time.
  String? get _programId => _ref.read(activeProgramIdProvider);

  SyncEngine get _sync => _ref.read(syncEngineProvider);

  // ---- Reads ----

  Stream<List<Parent>> watchAll() {
    final query = _db.select(_db.parents)
      ..orderBy([
        (p) => OrderingTerm.asc(p.firstName),
        (p) => OrderingTerm.asc(p.lastName),
      ]);
    return query.watch();
  }

  Future<List<Parent>> getAll() {
    final query = _db.select(_db.parents)
      ..orderBy([
        (p) => OrderingTerm.asc(p.firstName),
        (p) => OrderingTerm.asc(p.lastName),
      ]);
    return query.get();
  }

  Future<Parent?> getParent(String id) {
    return (_db.select(_db.parents)..where((p) => p.id.equals(id)))
        .getSingleOrNull();
  }

  Stream<Parent?> watchParent(String id) {
    return (_db.select(_db.parents)..where((p) => p.id.equals(id)))
        .watchSingleOrNull();
  }

  /// "Who are Noah's parents?" — powered by the index on
  /// parent_children.child_id. Returns the parent rows joined to
  /// their (isPrimary) flag so the caller can render "Mom · primary"
  /// without a second lookup.
  Stream<List<ParentLink>> watchForChild(String childId) {
    final pc = _db.parentChildren;
    final p = _db.parents;
    final query = _db.select(pc).join([
      innerJoin(p, p.id.equalsExp(pc.parentId)),
    ])
      ..where(pc.childId.equals(childId))
      ..orderBy([
        // Primary contact floats to the top, then alphabetical.
        OrderingTerm(expression: pc.isPrimary, mode: OrderingMode.desc),
        OrderingTerm.asc(p.firstName),
        OrderingTerm.asc(p.lastName),
      ]);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          ParentLink(
            parent: row.readTable(p),
            isPrimary: row.readTable(pc).isPrimary,
          ),
      ],
    );
  }

  /// "Which children does this parent pick up?" — used on the parent
  /// detail screen. Cheap to watch even when a parent has many kids
  /// across siblings.
  Stream<List<Child>> watchChildrenForParent(String parentId) {
    final pc = _db.parentChildren;
    final c = _db.children;
    final query = _db.select(pc).join([
      innerJoin(c, c.id.equalsExp(pc.childId)),
    ])
      ..where(pc.parentId.equals(parentId))
      ..orderBy([OrderingTerm.asc(c.firstName)]);
    return query.watch().map(
      (rows) => [for (final row in rows) row.readTable(c)],
    );
  }

  // ---- Writes ----

  Future<String> addParent({
    required String firstName,
    String? lastName,
    String? relationship,
    String? phone,
    String? email,
    String? notes,
  }) async {
    final id = newId();
    await _db.into(_db.parents).insert(
          ParentsCompanion.insert(
            id: id,
            firstName: firstName,
            lastName: Value(lastName),
            relationship: Value(relationship),
            phone: Value(phone),
            email: Value(email),
            notes: Value(notes),
            programId: Value(_programId),
          ),
        );
    unawaited(_sync.pushRow(parentsSpec, id));
    return id;
  }

  Future<void> updateParent({
    required String id,
    String? firstName,
    Value<String?> lastName = const Value.absent(),
    Value<String?> relationship = const Value.absent(),
    Value<String?> phone = const Value.absent(),
    Value<String?> email = const Value.absent(),
    Value<String?> notes = const Value.absent(),
  }) async {
    await (_db.update(_db.parents)..where((p) => p.id.equals(id))).write(
      ParentsCompanion(
        firstName:
            firstName == null ? const Value.absent() : Value(firstName),
        lastName: lastName,
        relationship: relationship,
        phone: phone,
        email: email,
        notes: notes,
        updatedAt: Value(DateTime.now()),
      ),
    );
    unawaited(_sync.pushRow(parentsSpec, id));
  }

  Future<void> deleteParent(String id) async {
    // Cascade on parent_children removes the links; sibling rows for
    // other children of the same parent also go. Acceptable —
    // deleting a parent really does mean "forget them everywhere."
    final row = await (_db.select(_db.parents)..where((p) => p.id.equals(id)))
        .getSingleOrNull();
    final programId = row?.programId;
    await (_db.delete(_db.parents)..where((p) => p.id.equals(id))).go();
    if (programId != null) {
      unawaited(
        _sync.pushDelete(spec: parentsSpec, id: id, programId: programId),
      );
    }
  }

  /// Re-insert a previously-deleted parent row + its child links for
  /// the undo snackbar. Links restored from the snapshot the caller
  /// saved before delete.
  Future<void> restoreParent(Parent row, List<ParentChildrenData> links) async {
    await _db.transaction(() async {
      await _db.into(_db.parents).insertOnConflictUpdate(row);
      for (final l in links) {
        await _db.into(_db.parentChildren).insertOnConflictUpdate(l);
      }
    });
  }

  /// Snapshot the join rows for a parent before deleting, so undo
  /// can restore them.
  Future<List<ParentChildrenData>> snapshotLinks(String parentId) {
    return (_db.select(_db.parentChildren)
          ..where((l) => l.parentId.equals(parentId)))
        .get();
  }

  // ---- Joins ----

  Future<void> linkParentToChild({
    required String parentId,
    required String childId,
    bool isPrimary = false,
  }) async {
    await _db.transaction(() async {
      if (isPrimary) {
        // Clear any existing primary on the child — at-most-one.
        await (_db.update(_db.parentChildren)
              ..where((l) => l.childId.equals(childId)))
            .write(const ParentChildrenCompanion(isPrimary: Value(false)));
      }
      await _db.into(_db.parentChildren).insertOnConflictUpdate(
            ParentChildrenCompanion.insert(
              parentId: parentId,
              childId: childId,
              isPrimary: Value(isPrimary),
            ),
          );
    });
    // Cascade write — push the parent so the new parent_children
    // join row rides along with its parent through sync.
    unawaited(_sync.pushRow(parentsSpec, parentId));
  }

  Future<void> unlinkParentFromChild({
    required String parentId,
    required String childId,
  }) async {
    await (_db.delete(_db.parentChildren)
          ..where((l) =>
              l.parentId.equals(parentId) & l.childId.equals(childId)))
        .go();
    unawaited(_sync.pushRow(parentsSpec, parentId));
  }

  Future<void> setPrimary({
    required String parentId,
    required String childId,
  }) async {
    // Snapshot every parent that had a row for this child up-front —
    // setPrimary clears the old primary across all parents, so each
    // affected parent's cascade rows need a fresh push too.
    final affected = await (_db.select(_db.parentChildren)
          ..where((l) => l.childId.equals(childId)))
        .get();
    await _db.transaction(() async {
      await (_db.update(_db.parentChildren)
            ..where((l) => l.childId.equals(childId)))
          .write(const ParentChildrenCompanion(isPrimary: Value(false)));
      await (_db.update(_db.parentChildren)
            ..where((l) =>
                l.parentId.equals(parentId) & l.childId.equals(childId)))
          .write(const ParentChildrenCompanion(isPrimary: Value(true)));
    });
    final touched = <String>{parentId, for (final r in affected) r.parentId};
    for (final pid in touched) {
      unawaited(_sync.pushRow(parentsSpec, pid));
    }
  }
}

/// Parent joined to its (isPrimary) flag for a specific child. Used
/// by the child detail screen so the UI can render "Sarah Reed ·
/// primary" without two widgets' worth of lookups.
class ParentLink {
  const ParentLink({required this.parent, required this.isPrimary});
  final Parent parent;
  final bool isPrimary;
}

final parentsRepositoryProvider = Provider<ParentsRepository>((ref) {
  return ParentsRepository(ref.watch(databaseProvider), ref);
});

final parentsProvider = StreamProvider<List<Parent>>((ref) {
  return ref.watch(parentsRepositoryProvider).watchAll();
});

// Riverpod family return types are complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final parentProvider =
    StreamProvider.family<Parent?, String>((ref, id) {
  return ref.watch(parentsRepositoryProvider).watchParent(id);
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final parentsForChildProvider =
    StreamProvider.family<List<ParentLink>, String>((ref, childId) {
  return ref.watch(parentsRepositoryProvider).watchForChild(childId);
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final childrenForParentProvider =
    StreamProvider.family<List<Child>, String>((ref, parentId) {
  return ref.watch(parentsRepositoryProvider).watchChildrenForParent(parentId);
});
