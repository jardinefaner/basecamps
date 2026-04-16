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
  }) async {
    final id = newId();
    await _db.into(_db.kids).insert(
          KidsCompanion.insert(
            id: id,
            firstName: firstName,
            lastName: Value(lastName),
            podId: Value(podId),
            notes: Value(notes),
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
final kidProvider = FutureProvider.family<Kid?, String>((ref, id) {
  return ref.watch(kidsRepositoryProvider).getKid(id);
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final podProvider = FutureProvider.family<Pod?, String>((ref, id) {
  return ref.watch(kidsRepositoryProvider).getPod(id);
});
