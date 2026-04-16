import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TripsRepository {
  TripsRepository(this._db);

  final AppDatabase _db;

  Stream<List<Trip>> watchAll() {
    final query = _db.select(_db.trips)
      ..orderBy([(t) => OrderingTerm.asc(t.date)]);
    return query.watch();
  }

  Future<Trip?> getTrip(String id) {
    return (_db.select(_db.trips)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<String> addTrip({
    required String name,
    required DateTime date,
    DateTime? endDate,
    String? location,
    String? notes,
  }) async {
    final id = newId();
    await _db.into(_db.trips).insert(
          TripsCompanion.insert(
            id: id,
            name: name,
            date: date,
            endDate: Value(endDate),
            location: Value(location),
            notes: Value(notes),
          ),
        );
    return id;
  }

  Future<void> deleteTrip(String id) async {
    await (_db.delete(_db.trips)..where((t) => t.id.equals(id))).go();
  }
}

final tripsRepositoryProvider = Provider<TripsRepository>((ref) {
  return TripsRepository(ref.watch(databaseProvider));
});

final tripsProvider = StreamProvider<List<Trip>>((ref) {
  return ref.watch(tripsRepositoryProvider).watchAll();
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final tripProvider = FutureProvider.family<Trip?, String>((ref, id) {
  return ref.watch(tripsRepositoryProvider).getTrip(id);
});
