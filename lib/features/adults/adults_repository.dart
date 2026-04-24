import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Structural role an adult plays on the schedule (v28). Distinct from
/// [Adult.role], which is the free-form job-title blurb
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

class AdultsRepository {
  AdultsRepository(this._db);

  final AppDatabase _db;

  Stream<List<Adult>> watchAll() {
    final query = _db.select(_db.adults)
      ..orderBy([(s) => OrderingTerm.asc(s.name)]);
    return query.watch();
  }

  Future<Adult?> getAdult(String id) {
    return (_db.select(_db.adults)..where((s) => s.id.equals(id)))
        .getSingleOrNull();
  }

  /// Stream a single adult so tiles/detail rebuild on edit.
  Stream<Adult?> watchAdult(String id) {
    return (_db.select(_db.adults)..where((s) => s.id.equals(id)))
        .watchSingleOrNull();
  }

  Future<String> addAdult({
    required String name,
    String? role,
    String? notes,
    String? avatarPath,
    AdultRole adultRole = AdultRole.specialist,
    String? anchoredGroupId,
  }) async {
    final id = newId();
    await _db.into(_db.adults).insert(
          AdultsCompanion.insert(
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

  Future<void> updateAdult({
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
    await (_db.update(_db.adults)..where((s) => s.id.equals(id))).write(
      AdultsCompanion(
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

  Future<void> deleteAdult(String id) async {
    await (_db.delete(_db.adults)..where((s) => s.id.equals(id))).go();
  }

  Future<void> deleteAdults(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (_db.delete(_db.adults)..where((s) => s.id.isIn(list))).go();
  }

  /// Re-insert a previously-deleted adult row. Used by the undo
  /// snackbar on delete. Cascaded joins (availability rows, day-
  /// timeline blocks, observation authorship by name) aren't
  /// restored — same 5-second-window tradeoff as other restores.
  Future<void> restoreAdult(Adult row) async {
    await _db.into(_db.adults).insertOnConflictUpdate(row);
  }

  /// Batch restore for bulk-undo on the Adults screen.
  Future<void> restoreAdults(Iterable<Adult> rows) async {
    await _db.transaction(() async {
      for (final row in rows) {
        await _db.into(_db.adults).insertOnConflictUpdate(row);
      }
    });
  }

  // -------- Availability --------

  Stream<List<AdultAvailabilityData>> watchAvailabilityFor(
    String adultId,
  ) {
    return (_db.select(_db.adultAvailability)
          ..where((a) => a.adultId.equals(adultId))
          ..orderBy([
            (a) => OrderingTerm.asc(a.dayOfWeek),
            (a) => OrderingTerm.asc(a.startTime),
          ]))
        .watch();
  }

  /// All availability rows across every adult. Feeds the whole-
  /// program timeline view — one watched stream instead of N
  /// per-adult subscriptions, which matters once the program has
  /// 10+ adults running across 5 weekdays.
  Stream<List<AdultAvailabilityData>> watchAllAvailability() {
    return (_db.select(_db.adultAvailability)
          ..orderBy([
            (a) => OrderingTerm.asc(a.adultId),
            (a) => OrderingTerm.asc(a.dayOfWeek),
            (a) => OrderingTerm.asc(a.startTime),
          ]))
        .watch();
  }

  Future<List<AdultAvailabilityData>> availabilityFor(
    String adultId,
  ) {
    return (_db.select(_db.adultAvailability)
          ..where((a) => a.adultId.equals(adultId))
          ..orderBy([
            (a) => OrderingTerm.asc(a.dayOfWeek),
            (a) => OrderingTerm.asc(a.startTime),
          ]))
        .get();
  }

  Future<String> addAvailability({
    required String adultId,
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
    await _db.into(_db.adultAvailability).insert(
          AdultAvailabilityCompanion.insert(
            id: id,
            adultId: adultId,
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
    await (_db.delete(_db.adultAvailability)
          ..where((a) => a.id.equals(id)))
        .go();
  }

  /// Replace the whole availability set for a adult in one atomic
  /// write — used by the wizard/edit sheet where the teacher is
  /// editing multiple blocks at once.
  Future<void> replaceAvailability({
    required String adultId,
    required List<AvailabilityInput> blocks,
  }) async {
    await _db.transaction(() async {
      await (_db.delete(_db.adultAvailability)
            ..where((a) => a.adultId.equals(adultId)))
          .go();
      for (final b in blocks) {
        await _db.into(_db.adultAvailability).insert(
              AdultAvailabilityCompanion.insert(
                id: newId(),
                adultId: adultId,
                dayOfWeek: b.dayOfWeek,
                startTime: b.startTime,
                endTime: b.endTime,
                startDate: Value(b.startDate),
                endDate: Value(b.endDate),
                breakStart: Value(b.breakStart),
                breakEnd: Value(b.breakEnd),
                break2Start: Value(b.break2Start),
                break2End: Value(b.break2End),
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
    this.break2Start,
    this.break2End,
    this.lunchStart,
    this.lunchEnd,
  });

  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final DateTime? startDate;
  final DateTime? endDate;
  // HH:MM short breaks + lunch inside this shift. All nullable —
  // many shifts are short enough to have neither. break2 is a second
  // break window for programs that run morning AND afternoon breaks
  // (schema v35).
  final String? breakStart;
  final String? breakEnd;
  final String? break2Start;
  final String? break2End;
  final String? lunchStart;
  final String? lunchEnd;
}

final adultsRepositoryProvider = Provider<AdultsRepository>((ref) {
  return AdultsRepository(ref.watch(databaseProvider));
});

final adultsProvider = StreamProvider<List<Adult>>((ref) {
  return ref.watch(adultsRepositoryProvider).watchAll();
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final adultProvider =
    StreamProvider.family<Adult?, String>((ref, id) {
  return ref.watch(adultsRepositoryProvider).watchAdult(id);
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final adultAvailabilityProvider = StreamProvider.family<
    List<AdultAvailabilityData>, String>((ref, adultId) {
  return ref
      .watch(adultsRepositoryProvider)
      .watchAvailabilityFor(adultId);
});

/// Every availability row across the whole program. Used by the
/// program-wide timeline screen — one subscription beats N per-adult
/// family reads.
final allAvailabilityProvider =
    StreamProvider<List<AdultAvailabilityData>>((ref) {
  return ref.watch(adultsRepositoryProvider).watchAllAvailability();
});
