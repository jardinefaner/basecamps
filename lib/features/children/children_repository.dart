import 'dart:async';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/sync/media_service.dart';
import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:basecamp/features/sync/sync_specs.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChildrenRepository {
  ChildrenRepository(this._db, this._ref);

  final AppDatabase _db;
  final Ref _ref;

  /// See ObservationsRepository._programId for why we read this on
  /// every insert rather than caching at construction time.
  String? get _programId => _ref.read(activeProgramIdProvider);

  SyncEngine get _sync => _ref.read(syncEngineProvider);
  MediaService get _media => _ref.read(mediaServiceProvider);

  Stream<List<Group>> watchGroups() {
    final query = _db.select(_db.groups)
      ..orderBy([(p) => OrderingTerm.asc(p.createdAt)]);
    return query.watch();
  }

  Stream<List<Child>> watchChildren() {
    final query = _db.select(_db.children)
      ..orderBy([(k) => OrderingTerm.asc(k.firstName)]);
    return query.watch();
  }

  Stream<List<Child>> watchChildrenInGroup(String groupId) {
    final query = _db.select(_db.children)
      ..where((k) => k.groupId.equals(groupId))
      ..orderBy([(k) => OrderingTerm.asc(k.firstName)]);
    return query.watch();
  }

  Future<Child?> getChild(String id) {
    return (_db.select(_db.children)..where((k) => k.id.equals(id)))
        .getSingleOrNull();
  }

  /// Stream a single child. Backs a StreamProvider so the detail screen
  /// reflects edits (rename, avatar change, group change) live.
  Stream<Child?> watchChild(String id) {
    return (_db.select(_db.children)..where((k) => k.id.equals(id)))
        .watchSingleOrNull();
  }

  Future<Group?> getGroup(String id) {
    return (_db.select(_db.groups)..where((p) => p.id.equals(id)))
        .getSingleOrNull();
  }

  /// Stream a single group so screens (section headers, detail sheets,
  /// etc.) rebuild on rename or color change.
  Stream<Group?> watchGroup(String id) {
    return (_db.select(_db.groups)..where((p) => p.id.equals(id)))
        .watchSingleOrNull();
  }

  Future<String> addGroup({required String name, String? colorHex}) async {
    final id = newId();
    await _db.into(_db.groups).insert(
          GroupsCompanion.insert(
            id: id,
            name: name,
            colorHex: Value(colorHex),
            programId: Value(_programId),
          ),
        );
    unawaited(_sync.pushRow(groupsSpec, id));
    return id;
  }

  /// Partial group edit. Passing `null` means "leave alone"; use
  /// [clearColor] to drop the color back to null. Matches the
  /// clear-vs-absent convention the children/observations repos use.
  Future<void> updateGroup({
    required String id,
    String? name,
    String? colorHex,
    bool clearColor = false,
  }) async {
    await (_db.update(_db.groups)..where((p) => p.id.equals(id))).write(
      GroupsCompanion(
        name: name == null ? const Value.absent() : Value(name),
        colorHex: clearColor
            ? const Value<String?>(null)
            : (colorHex == null ? const Value.absent() : Value(colorHex)),
        updatedAt: Value(DateTime.now()),
      ),
    );
    unawaited(_sync.pushRow(groupsSpec, id));
  }

  Future<String> addChild({
    required String firstName,
    String? lastName,
    String? groupId,
    String? notes,
    String? avatarPath,
    String? parentName,
    String? expectedArrival,
    String? expectedPickup,
  }) async {
    final id = newId();
    await _db.into(_db.children).insert(
          ChildrenCompanion.insert(
            id: id,
            firstName: firstName,
            lastName: Value(lastName),
            groupId: Value(groupId),
            notes: Value(notes),
            avatarPath: Value(avatarPath),
            parentName: Value(parentName),
            expectedArrival: Value(expectedArrival),
            expectedPickup: Value(expectedPickup),
            programId: Value(_programId),
          ),
        );
    unawaited(_sync.pushRow(childrenSpec, id));
    if (avatarPath != null) {
      // Fire-and-forget media upload — stamps avatar_storage_path
      // when the file lands in the bucket; the next push picks
      // up the updated row.
      unawaited(_media.uploadChildAvatar(id));
    }
    return id;
  }

  Future<void> updateChildGroup({
    required String childId,
    required String? groupId,
  }) async {
    await (_db.update(_db.children)..where((k) => k.id.equals(childId))).write(
      ChildrenCompanion(
        groupId: Value(groupId),
        updatedAt: Value(DateTime.now()),
      ),
    );
    unawaited(_sync.pushRow(childrenSpec, childId));
  }

  /// Partial child edit. Anything left `null` (or not passed) is
  /// untouched. Use `clearAvatarPath: true` to remove the photo —
  /// passing `avatarPath: null` alone is "don't change it", matching
  /// the same convention the observations repo uses.
  Future<void> updateChild({
    required String id,
    String? firstName,
    String? lastName,
    bool clearLastName = false,
    String? groupId,
    bool clearGroupId = false,
    String? notes,
    bool clearNotes = false,
    String? avatarPath,
    bool clearAvatarPath = false,
    String? parentName,
    bool clearParentName = false,
    String? expectedArrival,
    bool clearExpectedArrival = false,
    String? expectedPickup,
    bool clearExpectedPickup = false,
  }) async {
    final companion = ChildrenCompanion(
      firstName:
          firstName == null ? const Value.absent() : Value(firstName),
      lastName: clearLastName
          ? const Value<String?>(null)
          : (lastName == null ? const Value.absent() : Value(lastName)),
      groupId: clearGroupId
          ? const Value<String?>(null)
          : (groupId == null ? const Value.absent() : Value(groupId)),
      notes: clearNotes
          ? const Value<String?>(null)
          : (notes == null ? const Value.absent() : Value(notes)),
      avatarPath: clearAvatarPath
          ? const Value<String?>(null)
          : (avatarPath == null
              ? const Value.absent()
              : Value(avatarPath)),
      parentName: clearParentName
          ? const Value<String?>(null)
          : (parentName == null
              ? const Value.absent()
              : Value(parentName)),
      expectedArrival: clearExpectedArrival
          ? const Value<String?>(null)
          : (expectedArrival == null
              ? const Value.absent()
              : Value(expectedArrival)),
      expectedPickup: clearExpectedPickup
          ? const Value<String?>(null)
          : (expectedPickup == null
              ? const Value.absent()
              : Value(expectedPickup)),
      updatedAt: Value(DateTime.now()),
    );
    await (_db.update(_db.children)..where((k) => k.id.equals(id))).write(companion);
    unawaited(_sync.pushRow(childrenSpec, id));
    // If the avatar was set/changed in this update, kick a
    // (re-)upload. Idempotent — MediaService skips when the row
    // already has a non-null storage_path matching the file.
    if (avatarPath != null && !clearAvatarPath) {
      unawaited(_media.uploadChildAvatar(id));
    }
  }

  Future<void> deleteGroup(String id) async {
    final row = await (_db.select(_db.groups)..where((p) => p.id.equals(id)))
        .getSingleOrNull();
    final programId = row?.programId;
    await (_db.delete(_db.groups)..where((p) => p.id.equals(id))).go();
    if (programId != null) {
      unawaited(
        _sync.pushDelete(spec: groupsSpec, id: id, programId: programId),
      );
    }
  }

  Future<void> deleteChild(String id) async {
    final row = await (_db.select(_db.children)..where((k) => k.id.equals(id)))
        .getSingleOrNull();
    final programId = row?.programId;
    await (_db.delete(_db.children)..where((k) => k.id.equals(id))).go();
    if (programId != null) {
      unawaited(
        _sync.pushDelete(spec: childrenSpec, id: id, programId: programId),
      );
    }
  }

  /// Re-insert a previously-deleted group row. Used by the undo
  /// snackbar on delete. Cascaded joins (children's groupId pointers
  /// set null, rooms' default_for_group_id set null, etc.) are NOT
  /// automatically re-linked — the group comes back empty. That's
  /// an accepted tradeoff for the 5-second undo window; a mistaken
  /// delete typically hasn't lost meaningful pairings.
  Future<void> restoreGroup(Group row) async {
    await _db.into(_db.groups).insertOnConflictUpdate(row);
    unawaited(_sync.pushRow(groupsSpec, row.id));
  }

  /// Re-insert a previously-deleted child row. See [restoreGroup]
  /// for the cascade caveat.
  Future<void> restoreChild(Child row) async {
    await _db.into(_db.children).insertOnConflictUpdate(row);
    unawaited(_sync.pushRow(childrenSpec, row.id));
  }
}

final childrenRepositoryProvider = Provider<ChildrenRepository>((ref) {
  return ChildrenRepository(ref.watch(databaseProvider), ref);
});

final groupsProvider = StreamProvider<List<Group>>((ref) {
  return ref.watch(childrenRepositoryProvider).watchGroups();
});

final childrenProvider = StreamProvider<List<Child>>((ref) {
  return ref.watch(childrenRepositoryProvider).watchChildren();
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final childProvider = StreamProvider.family<Child?, String>((ref, id) {
  return ref.watch(childrenRepositoryProvider).watchChild(id);
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final groupProvider = StreamProvider.family<Group?, String>((ref, id) {
  return ref.watch(childrenRepositoryProvider).watchGroup(id);
});
