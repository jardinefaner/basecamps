import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TripsRepository {
  TripsRepository(this._db, this._ref);

  final AppDatabase _db;
  final Ref _ref;

  /// See ObservationsRepository._programId for why we read this on
  /// every insert rather than caching at construction time.
  String? get _programId => _ref.read(activeProgramIdProvider);

  Stream<List<Trip>> watchAll() {
    final query = _db.select(_db.trips)
      ..orderBy([(t) => OrderingTerm.asc(t.date)]);
    return query.watch();
  }

  Future<Trip?> getTrip(String id) {
    return (_db.select(_db.trips)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<List<String>> groupsForTrip(String tripId) async {
    final rows = await (_db.select(_db.tripGroups)
          ..where((p) => p.tripId.equals(tripId)))
        .get();
    return rows.map((r) => r.groupId).toList();
  }

  /// Watch every trip-group link as a `{tripId: [groupId, …]}` map.
  /// Used by the calendar synthesizer to scope trip events by group
  /// in the Today agenda. Cheap — trip_groups is tiny (one row per
  /// trip-group pair) and the whole set fits in memory comfortably.
  Stream<Map<String, List<String>>> watchAllGroupsByTrip() {
    return _db.select(_db.tripGroups).watch().map((rows) {
      final out = <String, List<String>>{};
      for (final r in rows) {
        (out[r.tripId] ??= <String>[]).add(r.groupId);
      }
      return out;
    });
  }

  /// Adds a trip and auto-creates a matching ScheduleEntry on the trip's
  /// date so the calendar is in sync. If [departureTime] / [returnTime]
  /// are supplied, the entry is timed; otherwise it's full-day. The trip's
  /// groups are mirrored onto the entry via EntryGroups.
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
              programId: Value(_programId),
            ),
          );
      for (final groupId in groupIds) {
        await _db.into(_db.tripGroups).insert(
              TripGroupsCompanion.insert(tripId: tripId, groupId: groupId),
            );
      }
      // Mirror onto the schedule. Stamp programId so the trip's
      // schedule entry is in the same program as the trip itself —
      // bypasses ScheduleRepository on this path so we have to do
      // it here directly.
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
              programId: Value(_programId),
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
  /// all group link rows.
  Future<void> deleteTrip(String id) async {
    await (_db.delete(_db.trips)..where((t) => t.id.equals(id))).go();
  }

  /// Batch version of [deleteTrip]. Same cascade semantics (linked
  /// schedule entries + group join rows go with the trips).
  Future<void> deleteTrips(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (_db.delete(_db.trips)..where((t) => t.id.isIn(list))).go();
  }

  /// Re-insert a previously-deleted trip row for the undo snackbar.
  /// Cascaded joins (trip_groups, any schedule_entries that
  /// referenced this trip) aren't restored.
  Future<void> restoreTrip(Trip row) async {
    await _db.into(_db.trips).insertOnConflictUpdate(row);
  }

  /// Batch restore for bulk-undo. Writes in one transaction so
  /// partial failures don't leave half a selection re-inserted.
  Future<void> restoreTrips(Iterable<Trip> rows) async {
    await _db.transaction(() async {
      for (final row in rows) {
        await _db.into(_db.trips).insertOnConflictUpdate(row);
      }
    });
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

final tripsRepositoryProvider = Provider<TripsRepository>((ref) {
  return TripsRepository(ref.watch(databaseProvider), ref);
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
final tripGroupsProvider =
    FutureProvider.family<List<String>, String>((ref, id) {
  return ref.watch(tripsRepositoryProvider).groupsForTrip(id);
});
