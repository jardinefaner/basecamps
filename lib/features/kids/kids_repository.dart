import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChildrenRepository {
  ChildrenRepository(this._db);

  final AppDatabase _db;

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

  Future<Child?> getKid(String id) {
    return (_db.select(_db.children)..where((k) => k.id.equals(id)))
        .getSingleOrNull();
  }

  /// Stream a single kid. Backs a StreamProvider so the detail screen
  /// reflects edits (rename, avatar change, pod change) live.
  Stream<Child?> watchKid(String id) {
    return (_db.select(_db.children)..where((k) => k.id.equals(id)))
        .watchSingleOrNull();
  }

  Future<Group?> getPod(String id) {
    return (_db.select(_db.groups)..where((p) => p.id.equals(id)))
        .getSingleOrNull();
  }

  /// Stream a single pod so screens (section headers, detail sheets,
  /// etc.) rebuild on rename or color change.
  Stream<Group?> watchPod(String id) {
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
          ),
        );
    return id;
  }

  /// Partial pod edit. Passing `null` means "leave alone"; use
  /// [clearColor] to drop the color back to null. Matches the
  /// clear-vs-absent convention the kids/observations repos use.
  Future<void> updatePod({
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
  }

  Future<String> addChild({
    required String firstName,
    String? lastName,
    String? groupId,
    String? notes,
    String? avatarPath,
    String? parentName,
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
          ),
        );
    return id;
  }

  Future<void> updateKidPod({
    required String childId,
    required String? groupId,
  }) async {
    await (_db.update(_db.children)..where((k) => k.id.equals(childId))).write(
      ChildrenCompanion(
        groupId: Value(groupId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Partial kid edit. Anything left `null` (or not passed) is
  /// untouched. Use `clearAvatarPath: true` to remove the photo —
  /// passing `avatarPath: null` alone is "don't change it", matching
  /// the same convention the observations repo uses.
  Future<void> updateChild({
    required String id,
    String? firstName,
    String? lastName,
    bool clearLastName = false,
    String? groupId,
    bool clearPodId = false,
    String? notes,
    bool clearNotes = false,
    String? avatarPath,
    bool clearAvatarPath = false,
    String? parentName,
    bool clearParentName = false,
  }) async {
    final companion = ChildrenCompanion(
      firstName:
          firstName == null ? const Value.absent() : Value(firstName),
      lastName: clearLastName
          ? const Value<String?>(null)
          : (lastName == null ? const Value.absent() : Value(lastName)),
      groupId: clearPodId
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
      updatedAt: Value(DateTime.now()),
    );
    await (_db.update(_db.children)..where((k) => k.id.equals(id))).write(companion);
  }

  Future<void> deleteGroup(String id) async {
    await (_db.delete(_db.groups)..where((p) => p.id.equals(id))).go();
  }

  Future<void> deleteChild(String id) async {
    await (_db.delete(_db.children)..where((k) => k.id.equals(id))).go();
  }
}

final childrenRepositoryProvider = Provider<ChildrenRepository>((ref) {
  return ChildrenRepository(ref.watch(databaseProvider));
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
  return ref.watch(childrenRepositoryProvider).watchKid(id);
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final groupProvider = StreamProvider.family<Group?, String>((ref, id) {
  return ref.watch(childrenRepositoryProvider).watchPod(id);
});
