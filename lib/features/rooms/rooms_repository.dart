import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Physical rooms / zones in the building where activities happen
/// (v28). First-class entities so the conflict layer can catch "two
/// rovers in the Art Room at once" cleanly — previously location was a
/// free-form string, which made reliable collision detection
/// impossible.
///
/// Off-site addresses (field trips) are NOT rooms. Those stay as
/// free-form text on the trip / entry row and open in Google Maps on
/// tap.
class RoomsRepository {
  RoomsRepository(this._db);

  final AppDatabase _db;

  Stream<List<Room>> watchAll() {
    final query = _db.select(_db.rooms)
      ..orderBy([(r) => OrderingTerm.asc(r.name)]);
    return query.watch();
  }

  Future<List<Room>> getAll() {
    final query = _db.select(_db.rooms)
      ..orderBy([(r) => OrderingTerm.asc(r.name)]);
    return query.get();
  }

  Future<Room?> getRoom(String id) {
    return (_db.select(_db.rooms)..where((r) => r.id.equals(id)))
        .getSingleOrNull();
  }

  Stream<Room?> watchRoom(String id) {
    return (_db.select(_db.rooms)..where((r) => r.id.equals(id)))
        .watchSingleOrNull();
  }

  /// The "home room" for a group, if one's been set. Feeds the
  /// activity form's room-picker default so creating a Seedlings
  /// activity doesn't require re-picking "Main Room" every time.
  Future<Room?> defaultRoomFor(String groupId) {
    return (_db.select(_db.rooms)
          ..where((r) => r.defaultForGroupId.equals(groupId))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<String> addRoom({
    required String name,
    int? capacity,
    String? notes,
    String? defaultForGroupId,
  }) async {
    final id = newId();
    await _db.into(_db.rooms).insert(
          RoomsCompanion.insert(
            id: id,
            name: name,
            capacity: Value(capacity),
            notes: Value(notes),
            defaultForGroupId: Value(defaultForGroupId),
          ),
        );
    return id;
  }

  Future<void> updateRoom({
    required String id,
    String? name,
    Value<int?> capacity = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<String?> defaultForGroupId = const Value.absent(),
  }) async {
    await (_db.update(_db.rooms)..where((r) => r.id.equals(id))).write(
      RoomsCompanion(
        name: name == null ? const Value.absent() : Value(name),
        capacity: capacity,
        notes: notes,
        defaultForGroupId: defaultForGroupId,
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteRoom(String id) async {
    await (_db.delete(_db.rooms)..where((r) => r.id.equals(id))).go();
  }
}

final roomsRepositoryProvider = Provider<RoomsRepository>((ref) {
  return RoomsRepository(ref.watch(databaseProvider));
});

final roomsProvider = StreamProvider<List<Room>>((ref) {
  return ref.watch(roomsRepositoryProvider).watchAll();
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final roomProvider =
    StreamProvider.family<Room?, String>((ref, id) {
  return ref.watch(roomsRepositoryProvider).watchRoom(id);
});
