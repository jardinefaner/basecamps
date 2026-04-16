import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SpecialistsRepository {
  SpecialistsRepository(this._db);

  final AppDatabase _db;

  Stream<List<Specialist>> watchAll() {
    final query = _db.select(_db.specialists)
      ..orderBy([(s) => OrderingTerm.asc(s.name)]);
    return query.watch();
  }

  Future<Specialist?> getSpecialist(String id) {
    return (_db.select(_db.specialists)..where((s) => s.id.equals(id)))
        .getSingleOrNull();
  }

  /// Stream a single specialist so tiles/detail rebuild on edit.
  Stream<Specialist?> watchSpecialist(String id) {
    return (_db.select(_db.specialists)..where((s) => s.id.equals(id)))
        .watchSingleOrNull();
  }

  Future<String> addSpecialist({
    required String name,
    String? role,
    String? notes,
    String? avatarPath,
  }) async {
    final id = newId();
    await _db.into(_db.specialists).insert(
          SpecialistsCompanion.insert(
            id: id,
            name: name,
            role: Value(role),
            notes: Value(notes),
            avatarPath: Value(avatarPath),
          ),
        );
    return id;
  }

  Future<void> updateSpecialist({
    required String id,
    required String name,
    String? role,
    String? notes,
    String? avatarPath,
    bool clearAvatarPath = false,
  }) async {
    await (_db.update(_db.specialists)..where((s) => s.id.equals(id))).write(
      SpecialistsCompanion(
        name: Value(name),
        role: Value(role),
        notes: Value(notes),
        avatarPath: clearAvatarPath
            ? const Value<String?>(null)
            : (avatarPath == null
                ? const Value.absent()
                : Value(avatarPath)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteSpecialist(String id) async {
    await (_db.delete(_db.specialists)..where((s) => s.id.equals(id))).go();
  }
}

final specialistsRepositoryProvider = Provider<SpecialistsRepository>((ref) {
  return SpecialistsRepository(ref.watch(databaseProvider));
});

final specialistsProvider = StreamProvider<List<Specialist>>((ref) {
  return ref.watch(specialistsRepositoryProvider).watchAll();
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final specialistProvider =
    StreamProvider.family<Specialist?, String>((ref, id) {
  return ref.watch(specialistsRepositoryProvider).watchSpecialist(id);
});
