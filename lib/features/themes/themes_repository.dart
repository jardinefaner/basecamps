import 'dart:async';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/program_scope.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:basecamp/features/sync/sync_specs.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Program-level themes (v40) — "Bug week", "Kindness week". Each
/// row spans a date range and (optionally) carries a color for the
/// Today / planning surfaces. The data class is named `ProgramTheme`
/// so it doesn't collide with Flutter's `Theme` widget.
///
/// Schema-only this round — no UI consumes these methods yet. Round 4
/// builds the planner; Round 5 wires PDF export. Kept thin so the
/// later rounds grow the API without renaming what's here.
class ThemesRepository {
  ThemesRepository(this._db, this._ref);

  final AppDatabase _db;
  final Ref _ref;

  /// See ObservationsRepository._programId for why we read this on
  /// every insert rather than caching at construction time.
  String? get _programId => _ref.read(activeProgramIdProvider);

  SyncEngine get _sync => _ref.read(syncEngineProvider);

  Stream<List<ProgramTheme>> watchAll() {
    final query = _db.select(_db.themes)
      ..where((t) => matchesActiveProgram(t.programId, _programId))
      ..orderBy([(t) => OrderingTerm.desc(t.startDate)]);
    return query.watch();
  }

  /// Single-row fetch — used by the curriculum view to render the
  /// app-bar title from the theme's name + tint the week chips
  /// from `colorHex`.
  Future<ProgramTheme?> getTheme(String id) {
    return (_db.select(_db.themes)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Reactive variant of [getTheme] — the curriculum view subscribes
  /// so renames or color tweaks made elsewhere flow through live.
  Stream<ProgramTheme?> watchTheme(String id) {
    return (_db.select(_db.themes)..where((t) => t.id.equals(id)))
        .watchSingleOrNull();
  }

  /// Themes whose date range covers [date] inclusive. In practice
  /// it's at most one at a time, but the query returns a list so the
  /// UI layer decides what "active" means when two overlap.
  Stream<List<ProgramTheme>> watchActive(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final query = _db.select(_db.themes)
      ..where((t) =>
          t.startDate.isSmallerOrEqualValue(day) &
          t.endDate.isBiggerOrEqualValue(day) &
          matchesActiveProgram(t.programId, _programId))
      ..orderBy([(t) => OrderingTerm.asc(t.startDate)]);
    return query.watch();
  }

  Future<String> addTheme({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    String? colorHex,
    String? notes,
  }) async {
    final id = newId();
    await _db.into(_db.themes).insert(
          ThemesCompanion.insert(
            id: id,
            name: name,
            startDate: _dayOnly(startDate),
            endDate: _dayOnly(endDate),
            colorHex: Value(colorHex),
            notes: Value(notes),
            programId: Value(_programId),
          ),
        );
    unawaited(_sync.pushRow(themesSpec, id));
    return id;
  }

  Future<void> updateTheme({
    required String id,
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    Value<String?> colorHex = const Value.absent(),
    Value<String?> notes = const Value.absent(),
  }) async {
    await (_db.update(_db.themes)..where((t) => t.id.equals(id))).write(
      ThemesCompanion(
        name: name == null ? const Value.absent() : Value(name),
        startDate: startDate == null
            ? const Value.absent()
            : Value(_dayOnly(startDate)),
        endDate: endDate == null
            ? const Value.absent()
            : Value(_dayOnly(endDate)),
        colorHex: colorHex,
        notes: notes,
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _db.markDirty('themes', id, [
      if (name != null) 'name',
      if (startDate != null) 'start_date',
      if (endDate != null) 'end_date',
      if (colorHex.present) 'color_hex',
      if (notes.present) 'notes',
    ]);
    unawaited(_sync.pushRow(themesSpec, id));
  }

  Future<void> deleteTheme(String id) async {
    final row = await (_db.select(_db.themes)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    final programId = row?.programId;
    await (_db.delete(_db.themes)..where((t) => t.id.equals(id))).go();
    if (programId != null) {
      unawaited(
        _sync.pushDelete(spec: themesSpec, id: id, programId: programId),
      );
    }
  }

  /// Re-insert a deleted theme row. Paired with [deleteTheme] by the
  /// undo snackbar — same 5-second window pattern as every other
  /// destructive flow.
  Future<void> restoreTheme(ProgramTheme row) async {
    await _db.into(_db.themes).insertOnConflictUpdate(row);
    unawaited(_sync.pushRow(themesSpec, row.id));
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

final themesRepositoryProvider = Provider<ThemesRepository>((ref) {
  return ThemesRepository(ref.watch(databaseProvider), ref);
});

final themesProvider = StreamProvider<List<ProgramTheme>>((ref) {
  ref.watch(activeProgramIdProvider);
  return ref.watch(themesRepositoryProvider).watchAll();
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final activeThemesProvider =
    StreamProvider.family<List<ProgramTheme>, DateTime>((ref, date) {
  ref.watch(activeProgramIdProvider);
  return ref.watch(themesRepositoryProvider).watchActive(date);
});

/// One theme by id — used by the curriculum view's app bar.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final themeByIdProvider =
    StreamProvider.family<ProgramTheme?, String>((ref, id) {
  return ref.watch(themesRepositoryProvider).watchTheme(id);
});
