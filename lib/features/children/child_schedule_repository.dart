import 'dart:async';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/core/now_tick.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:basecamp/features/sync/sync_specs.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Effective expected times for one child on one day, after daily
/// override rules are applied. Null fields mean "no expectation" —
/// the lateness detector skips them cleanly.
///
/// Built by [ChildScheduleRepository.effectiveExpectationsFor] so both
/// the Today flags pass and the per-child detail screens share one
/// source of truth for "is this child late?"
class ChildExpectations {
  const ChildExpectations({
    required this.childId,
    required this.arrival,
    required this.pickup,
    this.overrideNote,
  });

  final String childId;
  final String? arrival;
  final String? pickup;

  /// Present when an override was applied (arrival or pickup came
  /// from a child_schedule_overrides row), so the UI can surface
  /// "mom texted, running late" context instead of a bare flag.
  final String? overrideNote;
}

class ChildScheduleRepository {
  ChildScheduleRepository(this._db, this._ref);

  final Ref _ref;

  /// `child_schedule_overrides` is a cascade of `children` —
  /// pushing the parent rebuilds the cascade and the override
  /// row rides along. Without this nudge every "mom texted,
  /// running late" entry stayed local-only.
  void _pushParentChild(String childId) {
    unawaited(
      _ref.read(syncEngineProvider).pushRow(childrenSpec, childId),
    );
  }

  final AppDatabase _db;

  /// Midnight-normalized copy of [d] in the user's local time. Used
  /// both when writing (storing the override) and reading (matching
  /// today's row) so a teacher logging an override at 8:47 AM and
  /// the Today view at 10:15 AM both hit the same "date" key.
  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  /// All overrides in effect for [day]. Streams so Today rebuilds live
  /// when the teacher logs an override from any surface.
  Stream<List<ChildScheduleOverride>> watchOverridesFor(DateTime day) {
    final key = _dayKey(day);
    final query = _db.select(_db.childScheduleOverrides)
      ..where((r) => r.date.equals(key));
    return query.watch();
  }

  /// Merges standing times from the children row with any same-day
  /// override row. Non-streaming snapshot — callers drive updates by
  /// watching the children provider + [watchOverridesFor] separately
  /// and recomputing.
  ChildExpectations effectiveExpectationsFor({
    required Child child,
    required ChildScheduleOverride? override,
  }) {
    return ChildExpectations(
      childId: child.id,
      arrival: override?.expectedArrivalOverride ?? child.expectedArrival,
      pickup: override?.expectedPickupOverride ?? child.expectedPickup,
      overrideNote: override?.note,
    );
  }

  /// Upsert for today's override row. Identity is (childId, date) —
  /// if a row already exists for that pair it's updated; otherwise a
  /// new one is inserted. Keeps the table one-per-day-per-child
  /// without needing a SQL UNIQUE constraint (which would have forced
  /// a more involved migration).
  Future<void> setOverride({
    required String childId,
    required DateTime date,
    String? expectedArrivalOverride,
    String? expectedPickupOverride,
    String? note,
  }) async {
    final key = _dayKey(date);
    final existing = await (_db.select(_db.childScheduleOverrides)
          ..where((r) => r.childId.equals(childId) & r.date.equals(key))
          ..limit(1))
        .getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.childScheduleOverrides).insert(
            ChildScheduleOverridesCompanion.insert(
              id: newId(),
              childId: childId,
              date: key,
              expectedArrivalOverride: Value(expectedArrivalOverride),
              expectedPickupOverride: Value(expectedPickupOverride),
              note: Value(note),
            ),
          );
      _pushParentChild(childId);
      return;
    }
    await (_db.update(_db.childScheduleOverrides)
          ..where((r) => r.id.equals(existing.id)))
        .write(
      ChildScheduleOverridesCompanion(
        expectedArrivalOverride: Value(expectedArrivalOverride),
        expectedPickupOverride: Value(expectedPickupOverride),
        note: Value(note),
        updatedAt: Value(DateTime.now()),
      ),
    );
    _pushParentChild(childId);
  }

  /// Drop today's override for a child — "they're back on the normal
  /// schedule after all." Safe to call even when no override exists.
  Future<void> clearOverride({
    required String childId,
    required DateTime date,
  }) async {
    final key = _dayKey(date);
    await (_db.delete(_db.childScheduleOverrides)
          ..where((r) => r.childId.equals(childId) & r.date.equals(key)))
        .go();
    _pushParentChild(childId);
  }
}

final childScheduleRepositoryProvider = Provider<ChildScheduleRepository>(
  (ref) => ChildScheduleRepository(ref.watch(databaseProvider), ref),
);

/// Today's overrides, keyed by child id for fast lookup during the
/// flags pass. Zero rows is the common case — most days, no kid has
/// an exception logged.
///
/// Watches `nowTickProvider` so midnight rollover advances "today",
/// and `activeProgramIdProvider` so a program switch invalidates
/// the stream — without the latter, the flags strip kept computing
/// against the previous program's overrides until something else
/// invalidated.
final todayOverridesProvider =
    StreamProvider<Map<String, ChildScheduleOverride>>((ref) {
  ref.watch(activeProgramIdProvider);
  final repo = ref.watch(childScheduleRepositoryProvider);
  final now = ref.watch(nowTickProvider).value ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return repo.watchOverridesFor(today).map((rows) => {
        for (final r in rows) r.childId: r,
      });
});
