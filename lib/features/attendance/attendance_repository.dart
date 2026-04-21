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
  });

  final String childId;
  final AttendanceStatus status;
  final String? clockTime;
  final String? notes;
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
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return ref.watch(attendanceRepositoryProvider).watchForDay(today);
});
