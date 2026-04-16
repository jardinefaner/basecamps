import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class KidsRepository {
  KidsRepository(this._db);

  final AppDatabase _db;

  Stream<List<Pod>> watchPods() {
    final query = _db.select(_db.pods)
      ..orderBy([(p) => OrderingTerm.asc(p.createdAt)]);
    return query.watch();
  }

  Stream<List<Kid>> watchKids() {
    final query = _db.select(_db.kids)
      ..orderBy([(k) => OrderingTerm.asc(k.firstName)]);
    return query.watch();
  }

  Stream<List<Kid>> watchKidsInPod(String podId) {
    final query = _db.select(_db.kids)
      ..where((k) => k.podId.equals(podId))
      ..orderBy([(k) => OrderingTerm.asc(k.firstName)]);
    return query.watch();
  }

  Future<Kid?> getKid(String id) {
    return (_db.select(_db.kids)..where((k) => k.id.equals(id)))
        .getSingleOrNull();
  }

  /// Stream a single kid. Backs a StreamProvider so the detail screen
  /// reflects edits (rename, avatar change, pod change) live.
  Stream<Kid?> watchKid(String id) {
    return (_db.select(_db.kids)..where((k) => k.id.equals(id)))
        .watchSingleOrNull();
  }

  Future<Pod?> getPod(String id) {
    return (_db.select(_db.pods)..where((p) => p.id.equals(id)))
        .getSingleOrNull();
  }

  Future<String> addPod({required String name, String? colorHex}) async {
    final id = newId();
    await _db.into(_db.pods).insert(
          PodsCompanion.insert(
            id: id,
            name: name,
            colorHex: Value(colorHex),
          ),
        );
    return id;
  }

  Future<String> addKid({
    required String firstName,
    String? lastName,
    String? podId,
    String? notes,
    String? avatarPath,
    String? parentName,
  }) async {
    final id = newId();
    await _db.into(_db.kids).insert(
          KidsCompanion.insert(
            id: id,
            firstName: firstName,
            lastName: Value(lastName),
            podId: Value(podId),
            notes: Value(notes),
            avatarPath: Value(avatarPath),
            parentName: Value(parentName),
          ),
        );
    return id;
  }

  Future<void> updateKidPod({
    required String kidId,
    required String? podId,
  }) async {
    await (_db.update(_db.kids)..where((k) => k.id.equals(kidId))).write(
      KidsCompanion(
        podId: Value(podId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Partial kid edit. Anything left `null` (or not passed) is
  /// untouched. Use `clearAvatarPath: true` to remove the photo —
  /// passing `avatarPath: null` alone is "don't change it", matching
  /// the same convention the observations repo uses.
  Future<void> updateKid({
    required String id,
    String? firstName,
    String? lastName,
    bool clearLastName = false,
    String? podId,
    bool clearPodId = false,
    String? notes,
    bool clearNotes = false,
    String? avatarPath,
    bool clearAvatarPath = false,
    String? parentName,
    bool clearParentName = false,
  }) async {
    final companion = KidsCompanion(
      firstName:
          firstName == null ? const Value.absent() : Value(firstName),
      lastName: clearLastName
          ? const Value<String?>(null)
          : (lastName == null ? const Value.absent() : Value(lastName)),
      podId: clearPodId
          ? const Value<String?>(null)
          : (podId == null ? const Value.absent() : Value(podId)),
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
    await (_db.update(_db.kids)..where((k) => k.id.equals(id))).write(companion);
  }

  Future<void> deletePod(String id) async {
    await (_db.delete(_db.pods)..where((p) => p.id.equals(id))).go();
  }

  Future<void> deleteKid(String id) async {
    await (_db.delete(_db.kids)..where((k) => k.id.equals(id))).go();
  }
}

final kidsRepositoryProvider = Provider<KidsRepository>((ref) {
  return KidsRepository(ref.watch(databaseProvider));
});

final podsProvider = StreamProvider<List<Pod>>((ref) {
  return ref.watch(kidsRepositoryProvider).watchPods();
});

final kidsProvider = StreamProvider<List<Kid>>((ref) {
  return ref.watch(kidsRepositoryProvider).watchKids();
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final kidProvider = StreamProvider.family<Kid?, String>((ref, id) {
  return ref.watch(kidsRepositoryProvider).watchKid(id);
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final podProvider = FutureProvider.family<Pod?, String>((ref, id) {
  return ref.watch(kidsRepositoryProvider).getPod(id);
});
