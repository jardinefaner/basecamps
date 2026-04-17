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

  // -------- Availability --------

  Stream<List<SpecialistAvailabilityData>> watchAvailabilityFor(
    String specialistId,
  ) {
    return (_db.select(_db.specialistAvailability)
          ..where((a) => a.specialistId.equals(specialistId))
          ..orderBy([
            (a) => OrderingTerm.asc(a.dayOfWeek),
            (a) => OrderingTerm.asc(a.startTime),
          ]))
        .watch();
  }

  Future<List<SpecialistAvailabilityData>> availabilityFor(
    String specialistId,
  ) {
    return (_db.select(_db.specialistAvailability)
          ..where((a) => a.specialistId.equals(specialistId))
          ..orderBy([
            (a) => OrderingTerm.asc(a.dayOfWeek),
            (a) => OrderingTerm.asc(a.startTime),
          ]))
        .get();
  }

  Future<String> addAvailability({
    required String specialistId,
    required int dayOfWeek,
    required String startTime,
    required String endTime,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final id = newId();
    await _db.into(_db.specialistAvailability).insert(
          SpecialistAvailabilityCompanion.insert(
            id: id,
            specialistId: specialistId,
            dayOfWeek: dayOfWeek,
            startTime: startTime,
            endTime: endTime,
            startDate: Value(startDate),
            endDate: Value(endDate),
          ),
        );
    return id;
  }

  Future<void> deleteAvailability(String id) async {
    await (_db.delete(_db.specialistAvailability)
          ..where((a) => a.id.equals(id)))
        .go();
  }

  /// Replace the whole availability set for a specialist in one atomic
  /// write — used by the wizard/edit sheet where the teacher is
  /// editing multiple blocks at once.
  Future<void> replaceAvailability({
    required String specialistId,
    required List<AvailabilityInput> blocks,
  }) async {
    await _db.transaction(() async {
      await (_db.delete(_db.specialistAvailability)
            ..where((a) => a.specialistId.equals(specialistId)))
          .go();
      for (final b in blocks) {
        await _db.into(_db.specialistAvailability).insert(
              SpecialistAvailabilityCompanion.insert(
                id: newId(),
                specialistId: specialistId,
                dayOfWeek: b.dayOfWeek,
                startTime: b.startTime,
                endTime: b.endTime,
                startDate: Value(b.startDate),
                endDate: Value(b.endDate),
              ),
            );
      }
    });
  }
}

/// Transport struct for a single availability block, used by the UI
/// while the teacher edits N rows locally.
class AvailabilityInput {
  const AvailabilityInput({
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.startDate,
    this.endDate,
  });

  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final DateTime? startDate;
  final DateTime? endDate;
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

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final specialistAvailabilityProvider = StreamProvider.family<
    List<SpecialistAvailabilityData>, String>((ref, specialistId) {
  return ref
      .watch(specialistsRepositoryProvider)
      .watchAvailabilityFor(specialistId);
});
