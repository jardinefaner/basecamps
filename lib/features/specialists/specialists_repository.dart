import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Structural role an adult plays on the schedule (v28). Distinct from
/// [Specialist.role], which is the free-form job-title blurb
/// ("Art teacher", "Director").
///
///   - [AdultRole.lead]       — anchored to one group all day; the
///                               "steady" adult in that group's room
///   - [AdultRole.specialist] — rover that rotates across activities
///                               (existing behavior; default for
///                               legacy rows)
///   - [AdultRole.ambient]    — present in the building but not on the
///                               activity grid (director, nurse,
///                               kitchen, front desk)
enum AdultRole {
  lead('lead'),
  specialist('specialist'),
  ambient('ambient');

  const AdultRole(this.dbValue);
  final String dbValue;

  static AdultRole fromDb(String raw) {
    for (final r in AdultRole.values) {
      if (r.dbValue == raw) return r;
    }
    // Any bad / pre-v28 value falls back to the legacy behavior.
    return AdultRole.specialist;
  }
}

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
    AdultRole adultRole = AdultRole.specialist,
    String? anchoredGroupId,
  }) async {
    final id = newId();
    await _db.into(_db.specialists).insert(
          SpecialistsCompanion.insert(
            id: id,
            name: name,
            role: Value(role),
            notes: Value(notes),
            avatarPath: Value(avatarPath),
            adultRole: Value(adultRole.dbValue),
            anchoredGroupId: Value(anchoredGroupId),
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
    // Both default to Value.absent() so callers that only touch the
    // legacy fields (name / role / notes / avatar) don't accidentally
    // clobber adultRole / anchoredGroupId back to their defaults.
    Value<String> adultRole = const Value.absent(),
    Value<String?> anchoredGroupId = const Value.absent(),
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
        adultRole: adultRole,
        anchoredGroupId: anchoredGroupId,
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteSpecialist(String id) async {
    await (_db.delete(_db.specialists)..where((s) => s.id.equals(id))).go();
  }

  Future<void> deleteSpecialists(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (_db.delete(_db.specialists)..where((s) => s.id.isIn(list))).go();
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
    String? breakStart,
    String? breakEnd,
    String? lunchStart,
    String? lunchEnd,
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
            breakStart: Value(breakStart),
            breakEnd: Value(breakEnd),
            lunchStart: Value(lunchStart),
            lunchEnd: Value(lunchEnd),
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
                breakStart: Value(b.breakStart),
                breakEnd: Value(b.breakEnd),
                lunchStart: Value(b.lunchStart),
                lunchEnd: Value(b.lunchEnd),
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
    this.breakStart,
    this.breakEnd,
    this.lunchStart,
    this.lunchEnd,
  });

  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final DateTime? startDate;
  final DateTime? endDate;
  // HH:MM short break + lunch inside this shift. All nullable — many
  // shifts are short enough to have neither.
  final String? breakStart;
  final String? breakEnd;
  final String? lunchStart;
  final String? lunchEnd;
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
