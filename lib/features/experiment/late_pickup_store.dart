// Late-pickup entry store — Drift-backed (v64) + cloud-synced.
//
// Promoted from in-memory `List<LateEntry>` to a real Drift
// table so rows survive restart and propagate to other devices.
// Cloud parity: migration 0038.

import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/program_scope.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:basecamp/features/sync/sync_specs.dart';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LateEntry {
  LateEntry({
    required this.id,
    required this.date,
    required this.pickupTime,
    required this.childId,
    required this.childName,
    required this.parentName,
    required this.reminderCardGiven,
    required this.staffName,
    required this.notes,
  });

  final String id;
  DateTime date;
  TimeOfDay pickupTime;
  String? childId;
  String childName;
  String parentName;
  bool reminderCardGiven;
  String staffName;
  String notes;
}

int _todToMinutes(TimeOfDay t) => t.hour * 60 + t.minute;
TimeOfDay _minutesToTod(int m) => TimeOfDay(hour: m ~/ 60, minute: m % 60);

LateEntry _rowToEntry(LatePickupRow r) {
  return LateEntry(
    id: r.id,
    date: r.date,
    pickupTime: _minutesToTod(r.pickupMinutes),
    childId: r.childId,
    childName: r.childName,
    parentName: r.parentName,
    reminderCardGiven: r.reminderCardGiven,
    staffName: r.staffName,
    notes: r.notes,
  );
}

class LatePickupsRepository {
  LatePickupsRepository(this._db, this._ref);

  final AppDatabase _db;
  final Ref _ref;

  String? get _programId => _ref.read(activeProgramIdProvider);

  /// All non-deleted entries in the active program, newest first.
  Stream<List<LateEntry>> watchAll() {
    return (_db.select(_db.latePickupsTable)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                matchesActiveProgram(t.programId, _programId),
          )
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.date,
                  mode: OrderingMode.desc,
                ),
            (t) => OrderingTerm(
                  expression: t.pickupMinutes,
                  mode: OrderingMode.desc,
                ),
          ]))
        .watch()
        .map((rows) => rows.map(_rowToEntry).toList());
  }

  Future<void> add(LateEntry e) async {
    await _db.into(_db.latePickupsTable).insert(
          LatePickupsTableCompanion(
            id: Value(e.id),
            date: Value(e.date),
            pickupMinutes: Value(_todToMinutes(e.pickupTime)),
            childId: Value(e.childId),
            childName: Value(e.childName),
            parentName: Value(e.parentName),
            reminderCardGiven: Value(e.reminderCardGiven),
            staffName: Value(e.staffName),
            notes: Value(e.notes),
            programId: Value(_programId),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
    _push(e.id);
  }

  /// Update mutable fields on an existing row. Used by the
  /// reminder-card toggle + notes editor.
  Future<void> update(LateEntry e) async {
    await (_db.update(_db.latePickupsTable)
          ..where((t) => t.id.equals(e.id)))
        .write(
      LatePickupsTableCompanion(
        date: Value(e.date),
        pickupMinutes: Value(_todToMinutes(e.pickupTime)),
        childId: Value(e.childId),
        childName: Value(e.childName),
        parentName: Value(e.parentName),
        reminderCardGiven: Value(e.reminderCardGiven),
        staffName: Value(e.staffName),
        notes: Value(e.notes),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    _push(e.id);
  }

  Future<void> remove(String id) async {
    await (_db.update(_db.latePickupsTable)
          ..where((t) => t.id.equals(id)))
        .write(
      LatePickupsTableCompanion(
        deletedAt: Value(DateTime.now().toUtc()),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    _push(id);
  }

  void _push(String id) {
    unawaited(
      _ref.read(syncEngineProvider).pushRow(latePickupsSpec, id),
    );
  }
}

final latePickupsRepoProvider = Provider<LatePickupsRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return LatePickupsRepository(db, ref);
});

/// Live entries list, newest first. Empty list while the first
/// emission is in flight.
final lateEntriesProvider = StreamProvider<List<LateEntry>>((ref) {
  return ref.watch(latePickupsRepoProvider).watchAll();
});
