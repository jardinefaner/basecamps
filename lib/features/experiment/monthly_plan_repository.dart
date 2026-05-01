import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/program_scope.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:basecamp/features/sync/sync_specs.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Monthly plan persistence (v55, Slice 1) — themes per (program,
/// month) and sub-themes per (program, ISO Monday).
///
/// **Composite ids.** Both tables key off a deterministic id of the
/// form `${programId}|${period}` so any client can upsert without
/// round-tripping through a generated id and without racing two
/// clients on first-set. The unique index on the cloud side mirrors
/// this so a duplicate insert from a stale client is silently
/// idempotent.
///
/// **Soft-delete.** Like every other synced entity, the repository
/// "deletes" by setting `theme` / `subTheme` to NULL and stamping
/// `deletedAt`. Watch-streams filter out deletedAt-not-null rows so
/// callers see "no theme set" rather than a tombstone.
///
/// **Sync.** Both tables are program-scoped Tier-1 entities; the
/// existing sync engine handles realtime + push automatically once
/// `monthlyThemesSpec` / `weeklySubThemesSpec` are registered in
/// `sync_specs.dart`. No bespoke channel logic here.
class MonthlyPlanRepository {
  MonthlyPlanRepository(this._db, this._ref);

  final AppDatabase _db;
  final Ref _ref;

  String? get _programId => _ref.read(activeProgramIdProvider);

  SyncEngine get _sync => _ref.read(syncEngineProvider);

  // ---- ID composition -------------------------------------------

  /// Compose the deterministic id for a (program, month) row.
  /// `month` is "yyyy-MM" — e.g. "2026-05".
  static String monthlyThemeId(String programId, String yearMonth) =>
      '$programId|$yearMonth';

  /// Compose the deterministic id for a (program, ISO Monday) row.
  /// `mondayDate` is "yyyy-MM-dd" — e.g. "2026-05-04".
  static String weeklySubThemeId(String programId, String mondayDate) =>
      '$programId|$mondayDate';

  // ---- Reads ----------------------------------------------------

  /// Watch the theme for a specific calendar month within the active
  /// program. Returns the trimmed theme text or null when no row
  /// exists / it was soft-deleted / the column is empty.
  Stream<String?> watchTheme(String yearMonth) {
    final query = _db.select(_db.monthlyThemes)
      ..where((r) => matchesActiveProgram(r.programId, _programId))
      ..where((r) => r.yearMonth.equals(yearMonth))
      ..where((r) => r.deletedAt.isNull());
    return query.watchSingleOrNull().map(_themeText);
  }

  /// Watch the sub-theme for a specific ISO Monday within the active
  /// program. Same null-handling shape as [watchTheme].
  Stream<String?> watchSubTheme(String mondayDate) {
    final query = _db.select(_db.weeklySubThemes)
      ..where((r) => matchesActiveProgram(r.programId, _programId))
      ..where((r) => r.mondayDate.equals(mondayDate))
      ..where((r) => r.deletedAt.isNull());
    return query.watchSingleOrNull().map(_subThemeText);
  }

  /// One-shot read of every monthly theme for the active program.
  /// Used by the bootstrap pull to seed local state — the screen
  /// itself watches per-month.
  Future<List<MonthlyTheme>> getAllThemes() {
    final query = _db.select(_db.monthlyThemes)
      ..where((r) => matchesActiveProgram(r.programId, _programId))
      ..where((r) => r.deletedAt.isNull());
    return query.get();
  }

  /// One-shot read of every weekly sub-theme for the active program.
  Future<List<WeeklySubTheme>> getAllSubThemes() {
    final query = _db.select(_db.weeklySubThemes)
      ..where((r) => matchesActiveProgram(r.programId, _programId))
      ..where((r) => r.deletedAt.isNull());
    return query.get();
  }

  // ---- Writes ---------------------------------------------------

  /// Set or clear the theme for a calendar month. Empty string is
  /// treated as "clear" — the row is upserted with `theme: null`
  /// and `deletedAt: now`. The cloud realtime channel will
  /// propagate the change to other clients in the same program.
  Future<void> setTheme({
    required String yearMonth,
    required String theme,
  }) async {
    final programId = _programId;
    if (programId == null) return;
    final id = monthlyThemeId(programId, yearMonth);
    final now = DateTime.now();
    final trimmed = theme.trim();
    final isClear = trimmed.isEmpty;
    await _db.into(_db.monthlyThemes).insertOnConflictUpdate(
          MonthlyThemesCompanion(
            id: Value(id),
            programId: Value(programId),
            yearMonth: Value(yearMonth),
            theme: isClear ? const Value(null) : Value(trimmed),
            deletedAt: isClear ? Value(now) : const Value(null),
            updatedAt: Value(now),
            // createdAt only sticks on first insert — subsequent
            // upserts retain the original via SQLite's "ON CONFLICT
            // ... DO UPDATE SET" leaving the column alone. Drift
            // handles this correctly when we omit the value, but
            // setting it ensures freshly-created rows have a
            // consistent stamp on day one.
            createdAt: Value(now),
          ),
        );
    unawaited(_sync.pushRow(monthlyThemesSpec, id));
  }

  /// Set or clear the sub-theme for an ISO Monday. Same shape as
  /// [setTheme] — empty input clears.
  Future<void> setSubTheme({
    required String mondayDate,
    required String subTheme,
  }) async {
    final programId = _programId;
    if (programId == null) return;
    final id = weeklySubThemeId(programId, mondayDate);
    final now = DateTime.now();
    final trimmed = subTheme.trim();
    final isClear = trimmed.isEmpty;
    await _db.into(_db.weeklySubThemes).insertOnConflictUpdate(
          WeeklySubThemesCompanion(
            id: Value(id),
            programId: Value(programId),
            mondayDate: Value(mondayDate),
            subTheme: isClear ? const Value(null) : Value(trimmed),
            deletedAt: isClear ? Value(now) : const Value(null),
            updatedAt: Value(now),
            createdAt: Value(now),
          ),
        );
    unawaited(_sync.pushRow(weeklySubThemesSpec, id));
  }

  // ---- Helpers --------------------------------------------------

  String? _themeText(MonthlyTheme? row) {
    if (row == null) return null;
    final t = row.theme?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  String? _subThemeText(WeeklySubTheme? row) {
    if (row == null) return null;
    final t = row.subTheme?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}

/// Riverpod surface — repository singleton + per-key stream
/// providers used by the monthly plan screen.

final monthlyPlanRepositoryProvider = Provider<MonthlyPlanRepository>(
  (ref) => MonthlyPlanRepository(ref.watch(databaseProvider), ref),
);

/// Live theme for a specific (active program, "yyyy-MM") month.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final monthlyThemeProvider =
    StreamProvider.family<String?, String>((ref, yearMonth) {
  // Re-watch on program switch so the stream targets the new active
  // program's row rather than the old one. Without this, switching
  // programs would leave each cell still listening on the previous
  // program's id.
  ref.watch(activeProgramIdProvider);
  return ref.watch(monthlyPlanRepositoryProvider).watchTheme(yearMonth);
});

/// Live sub-theme for a specific (active program, ISO Monday) week.
// ignore: specify_nonobvious_property_types
final weeklySubThemeProvider =
    StreamProvider.family<String?, String>((ref, mondayDate) {
  ref.watch(activeProgramIdProvider);
  return ref.watch(monthlyPlanRepositoryProvider).watchSubTheme(mondayDate);
});
