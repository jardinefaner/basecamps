import 'package:basecamp/core/now_tick.dart';
import 'package:basecamp/database/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Attendance states a teacher can set for a child on a given day.
/// The DB stores the `.name` of these values as a text column so new
/// states (e.g. `excused`) can land without a schema change.
enum AttendanceStatus {
  present,
  absent,
  late,
  leftEarly;

  static AttendanceStatus? fromName(String? value) {
    if (value == null) return null;
    for (final s in AttendanceStatus.values) {
      if (s.name == value) return s;
    }
    return null;
  }
}

/// Read-only snapshot of one attendance row for the sheet's local state
/// and the today-screen summaries. Keeping it tiny and immutable makes
/// it safe to pass through builders.
class AttendanceRecord {
  const AttendanceRecord({
    required this.childId,
    required this.status,
    this.clockTime,
    this.notes,
    this.pickupTime,
    this.pickedUpBy,
  });

  final String childId;
  final AttendanceStatus status;
  final String? clockTime;
  final String? notes;

  /// HH:mm the child was collected for the day (v31). Null while the
  /// child is still on-site / hasn't been checked out yet. Flipping
  /// this on doesn't change [status] — the row stays 'present' — so
  /// the roll count keeps meaning "how many showed up today" rather
  /// than "how many are still here right now."
  final String? pickupTime;

  /// Free-text pickup attribution (dad / grandma / Auntie Nia). Null
  /// until pickup is recorded. Matches the `notes` pattern — a
  /// caregivers table can come later without breaking this.
  final String? pickedUpBy;
}

class AttendanceRepository {
  AttendanceRepository(this._db);

  final AppDatabase _db;

  /// Map of child id → record for a specific day. Children without a row are
  /// *not* present in the map — the caller renders them as pending.
  Stream<Map<String, AttendanceRecord>> watchForDay(DateTime date) {
    final day = _dayOnly(date);
    final nextDay = day.add(const Duration(days: 1));
    return (_db.select(_db.attendance)
          ..where(
            (a) =>
                a.date.isBiggerOrEqualValue(day) &
                a.date.isSmallerThanValue(nextDay),
          ))
        .watch()
        .map((rows) {
      final out = <String, AttendanceRecord>{};
      for (final r in rows) {
        final status = AttendanceStatus.fromName(r.status);
        if (status == null) continue;
        out[r.childId] = AttendanceRecord(
          childId: r.childId,
          status: status,
          clockTime: r.clockTime,
          notes: r.notes,
          pickupTime: r.pickupTime,
          pickedUpBy: r.pickedUpBy,
        );
      }
      return out;
    });
  }

  /// Set (or replace) the status for a child on a specific day. Upsert
  /// keeps the composite (child, date) unique — no stale duplicate rows.
  Future<void> setStatus({
    required String childId,
    required DateTime date,
    required AttendanceStatus status,
    String? clockTime,
    String? notes,
  }) async {
    final day = _dayOnly(date);
    final now = DateTime.now();
    await _db.into(_db.attendance).insertOnConflictUpdate(
          AttendanceCompanion.insert(
            childId: childId,
            date: day,
            status: status.name,
            clockTime: Value(clockTime),
            notes: Value(notes),
            updatedAt: Value(now),
          ),
        );
  }

  /// Record a pickup on an existing attendance row. The child must
  /// already have a row for the day (typically 'present'); the
  /// repository refuses to insert a fresh row here because a pickup
  /// without a matching check-in is always a data-entry mistake.
  ///
  /// [pickupTime] is required and stamped as HH:mm; [pickedUpBy] is
  /// optional — teacher can record "they got picked up" without
  /// remembering the name. Row stays in its existing status.
  Future<void> markPickup({
    required String childId,
    required DateTime date,
    required String pickupTime,
    String? pickedUpBy,
  }) async {
    final day = _dayOnly(date);
    final now = DateTime.now();
    await (_db.update(_db.attendance)
          ..where((a) => a.childId.equals(childId) & a.date.equals(day)))
        .write(
      AttendanceCompanion(
        pickupTime: Value(pickupTime),
        pickedUpBy: Value(pickedUpBy),
        updatedAt: Value(now),
      ),
    );
  }

  /// Undoes a pickup — "wait, she's still here, I marked that by
  /// mistake." Nulls both pickup columns while keeping the rest of
  /// the attendance row (status, notes, check-in time) intact.
  Future<void> clearPickup({
    required String childId,
    required DateTime date,
  }) async {
    final day = _dayOnly(date);
    final now = DateTime.now();
    await (_db.update(_db.attendance)
          ..where((a) => a.childId.equals(childId) & a.date.equals(day)))
        .write(
      AttendanceCompanion(
        pickupTime: const Value<String?>(null),
        pickedUpBy: const Value<String?>(null),
        updatedAt: Value(now),
      ),
    );
  }

  /// Drops the row entirely — used when the teacher wants to revert
  /// back to "not yet checked in" / pending, not stamp a new status.
  Future<void> clearStatus({
    required String childId,
    required DateTime date,
  }) async {
    final day = _dayOnly(date);
    await (_db.delete(_db.attendance)
          ..where((a) => a.childId.equals(childId) & a.date.equals(day)))
        .go();
  }

  /// Batch helper — "Mark everyone present" on a roster. One
  /// transaction so the Today card either sees all-green or the
  /// original state, never a half-step.
  Future<void> markAllPresent({
    required Iterable<String> childIds,
    required DateTime date,
    String? clockTime,
  }) async {
    final day = _dayOnly(date);
    final now = DateTime.now();
    await _db.transaction(() async {
      for (final childId in childIds) {
        await _db.into(_db.attendance).insertOnConflictUpdate(
              AttendanceCompanion.insert(
                childId: childId,
                date: day,
                status: AttendanceStatus.present.name,
                clockTime: Value(clockTime),
                updatedAt: Value(now),
              ),
            );
      }
    });
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

final attendanceRepositoryProvider =
    Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(ref.watch(databaseProvider));
});

/// Live map of attendance for the given calendar day. The family is
/// parameterized so date-aware callers (the attendance sheet for a
/// tapped past-day card, any future attendance history surface) read
/// the right slice, instead of everyone being stuck on "today" via a
/// single global [todayAttendanceProvider]. Pass a `DateTime` stripped
/// of its time-of-day component so identical dates share one
/// subscription.
// ignore: specify_nonobvious_property_types
final attendanceForDayProvider = StreamProvider.family<
    Map<String, AttendanceRecord>, DateTime>((ref, date) {
  return ref.watch(attendanceRepositoryProvider).watchForDay(date);
});

/// Shortcut for the Today dashboard — resolves to today's slice. Kept
/// as a dedicated provider (rather than piping through the family) so
/// existing consumers don't have to know about [attendanceForDayProvider]
/// or care about date normalization.
final todayAttendanceProvider =
    StreamProvider<Map<String, AttendanceRecord>>((ref) {
  // Watch the wall clock so a session left running over midnight
  // advances to the new day automatically — without the tick the
  // provider would keep emitting yesterday's attendance map until
  // the next route remount.
  final now = ref.watch(nowTickProvider).value ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return ref.watch(attendanceRepositoryProvider).watchForDay(today);
});
