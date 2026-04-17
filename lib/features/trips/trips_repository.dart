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

  Future<List<String>> podsForTrip(String tripId) async {
    final rows = await (_db.select(_db.tripGroups)
          ..where((p) => p.tripId.equals(tripId)))
        .get();
    return rows.map((r) => r.groupId).toList();
  }

  /// Adds a trip and auto-creates a matching ScheduleEntry on the trip's
  /// date so the calendar is in sync. If [departureTime] / [returnTime]
  /// are supplied, the entry is timed; otherwise it's full-day. The trip's
  /// pods are mirrored onto the entry via EntryPods.
  Future<String> addTrip({
    required String name,
    required DateTime date,
    DateTime? endDate,
    String? location,
    String? notes,
    String? departureTime,
    String? returnTime,
    List<String> groupIds = const [],
  }) async {
    final tripId = newId();
    final entryId = newId();
    final isFullDay = departureTime == null && returnTime == null;
    final startHhmm = departureTime ?? '00:00';
    final endHhmm = returnTime ?? '23:59';

    await _db.transaction(() async {
      await _db.into(_db.trips).insert(
            TripsCompanion.insert(
              id: tripId,
              name: name,
              date: date,
              endDate: Value(endDate),
              location: Value(location),
              notes: Value(notes),
              departureTime: Value(departureTime),
              returnTime: Value(returnTime),
            ),
          );
      for (final groupId in groupIds) {
        await _db.into(_db.tripGroups).insert(
              TripGroupsCompanion.insert(tripId: tripId, groupId: groupId),
            );
      }
      // Mirror onto the schedule.
      await _db.into(_db.scheduleEntries).insert(
            ScheduleEntriesCompanion.insert(
              id: entryId,
              date: _dayOnly(date),
              startTime: startHhmm,
              endTime: endHhmm,
              isFullDay: Value(isFullDay),
              title: name,
              location: Value(location),
              notes: Value(notes),
              kind: 'addition',
              sourceTripId: Value(tripId),
            ),
          );
      for (final groupId in groupIds) {
        await _db.into(_db.entryGroups).insert(
              EntryGroupsCompanion.insert(entryId: entryId, groupId: groupId),
            );
      }
    });

    return tripId;
  }

  /// Deletes a trip. FK cascade also removes the linked ScheduleEntry and
  /// all pod link rows.
  Future<void> deleteTrip(String id) async {
    await (_db.delete(_db.trips)..where((t) => t.id.equals(id))).go();
  }

  /// Batch version of [deleteTrip]. Same cascade semantics (linked
  /// schedule entries + pod join rows go with the trips).
  Future<void> deleteTrips(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (_db.delete(_db.trips)..where((t) => t.id.isIn(list))).go();
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
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

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final tripPodsProvider =
    FutureProvider.family<List<String>, String>((ref, id) {
  return ref.watch(tripsRepositoryProvider).podsForTrip(id);
});
