import 'dart:async';

import 'package:basecamp/core/id.dart';
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

  // ---- Activities (v56, Slice 2) -------------------------------

  /// Watch every variant for cell (group, date) within the active
  /// program, sorted by position. Soft-deleted rows filtered out.
  /// Empty variants ARE included — they represent in-progress
  /// drafts the user is still typing into; the UI's `hasContent`
  /// check filters them visually without dropping the row.
  Stream<List<MonthlyActivity>> watchVariants({
    required String groupId,
    required String date,
  }) {
    final query = _db.select(_db.monthlyActivities)
      ..where((r) => matchesActiveProgram(r.programId, _programId))
      ..where((r) => r.groupId.equals(groupId))
      ..where((r) => r.date.equals(date))
      ..where((r) => r.deletedAt.isNull())
      ..orderBy([
        (r) => OrderingTerm.asc(r.position),
        (r) => OrderingTerm.asc(r.createdAt),
      ]);
    return query.watch();
  }

  /// Insert a fresh variant at the next position for (group, date).
  /// Returns the row's id so the caller can keep referring to it
  /// across subsequent edits / deletes / etc.
  ///
  /// `position` defaults to "next slot" — the highest existing
  /// position + 1. Pass an explicit value to slot a variant at a
  /// specific spot (rare; the variant carousel is append-only in
  /// practice).
  Future<String> addVariant({
    required String groupId,
    required String date,
    int? position,
    String title = '',
    String description = '',
    String objectives = '',
    String steps = '',
    String materials = '',
    String link = '',
  }) async {
    final programId = _programId;
    if (programId == null) {
      throw StateError('No active program; cannot add a variant.');
    }
    final id = newId();
    final pos = position ?? await _nextPosition(groupId: groupId, date: date);
    final now = DateTime.now();
    await _db.into(_db.monthlyActivities).insert(
          MonthlyActivitiesCompanion.insert(
            id: id,
            programId: Value(programId),
            groupId: groupId,
            date: date,
            position: Value(pos),
            title: title.isEmpty ? const Value(null) : Value(title),
            description:
                description.isEmpty ? const Value(null) : Value(description),
            objectives:
                objectives.isEmpty ? const Value(null) : Value(objectives),
            steps: steps.isEmpty ? const Value(null) : Value(steps),
            materials:
                materials.isEmpty ? const Value(null) : Value(materials),
            link: link.isEmpty ? const Value(null) : Value(link),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    unawaited(_sync.pushRow(monthlyActivitiesSpec, id));
    return id;
  }

  /// Update a variant's content. Pass only the fields that change;
  /// nulls leave the existing column untouched. Marks the touched
  /// fields as dirty so the sync engine can push a partial UPDATE
  /// rather than a full row write.
  ///
  /// The repository accepts empty strings as "clear this field" and
  /// translates to `null` on the wire — same convention as the rest
  /// of the codebase. Passing `null` for a parameter means "don't
  /// touch."
  Future<void> updateVariant({
    required String id,
    String? title,
    String? description,
    String? objectives,
    String? steps,
    String? materials,
    String? link,
  }) async {
    final dirty = <String>[];
    final companion = MonthlyActivitiesCompanion(
      id: Value(id),
      title: _maybeText(title, dirty: dirty, fieldName: 'title'),
      description:
          _maybeText(description, dirty: dirty, fieldName: 'description'),
      objectives:
          _maybeText(objectives, dirty: dirty, fieldName: 'objectives'),
      steps: _maybeText(steps, dirty: dirty, fieldName: 'steps'),
      materials: _maybeText(materials, dirty: dirty, fieldName: 'materials'),
      link: _maybeText(link, dirty: dirty, fieldName: 'link'),
      updatedAt: Value(DateTime.now()),
    );
    if (dirty.isEmpty) return;
    await (_db.update(_db.monthlyActivities)..where((r) => r.id.equals(id)))
        .write(companion);
    await _db.markDirty('monthly_activities', id, dirty);
    unawaited(_sync.pushRow(monthlyActivitiesSpec, id));
  }

  /// Soft-delete a variant. The row stays in the table with its
  /// content + a deletedAt stamp; watch streams filter it out, and
  /// the cloud realtime channel propagates the tombstone so other
  /// clients drop it from their views too.
  Future<void> deleteVariant(String id) async {
    final now = DateTime.now();
    await (_db.update(_db.monthlyActivities)..where((r) => r.id.equals(id)))
        .write(
      MonthlyActivitiesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await _db.markDirty('monthly_activities', id, ['deleted_at']);
    unawaited(_sync.pushRow(monthlyActivitiesSpec, id));
  }

  // ---- Multi-day spans (v57, Slice 3) -------------------------

  /// Extend the span at [headId] by one day. Creates a continuation
  /// row on the next calendar day in the same group; if the head
  /// doesn't yet have a span_id, mints one and stamps the head with
  /// span_position 0 so the lineage is queryable.
  ///
  /// The continuation row inherits position from the head (so the
  /// span's variant carousel structure stays consistent — a head
  /// at variant 1 of [0,1,2] doesn't suddenly become a 0-position
  /// variant on day 2). Content fields are left null on the
  /// continuation; the UI renders a "continued" pill (with the
  /// head's title) until per-day content is filled in.
  Future<void> extendSpanByOneDay(String headId) async {
    final programId = _programId;
    if (programId == null) return;
    final head = await (_db.select(_db.monthlyActivities)
          ..where((r) => r.id.equals(headId))
          ..limit(1))
        .getSingleOrNull();
    if (head == null) return;

    // Mint a span_id on first extend so the head has identity.
    final spanId = head.spanId ?? newId();
    if (head.spanId == null) {
      final now = DateTime.now();
      await (_db.update(_db.monthlyActivities)
            ..where((r) => r.id.equals(headId)))
          .write(
        MonthlyActivitiesCompanion(
          spanId: Value(spanId),
          spanPosition: const Value(0),
          updatedAt: Value(now),
        ),
      );
      await _db.markDirty(
          'monthly_activities', headId, ['span_id', 'span_position']);
      unawaited(_sync.pushRow(monthlyActivitiesSpec, headId));
    }

    // Find the highest span_position currently in the span. Next
    // continuation lands at +1; its date is one day after the
    // current tail.
    final tail = await (_db.select(_db.monthlyActivities)
          ..where((r) => r.spanId.equals(spanId))
          ..where((r) => r.deletedAt.isNull())
          ..orderBy([
            (r) => OrderingTerm.desc(r.spanPosition),
          ])
          ..limit(1))
        .getSingleOrNull();
    final tailRow = tail ?? head;
    final tailDate = _parseDayKey(tailRow.date);
    final nextDate = _formatDayKey(tailDate.add(const Duration(days: 1)));
    final nextPos = tailRow.spanPosition + 1;

    final id = newId();
    final now = DateTime.now();
    await _db.into(_db.monthlyActivities).insert(
          MonthlyActivitiesCompanion.insert(
            id: id,
            programId: Value(programId),
            groupId: head.groupId,
            date: nextDate,
            position: Value(head.position),
            spanId: Value(spanId),
            spanPosition: Value(nextPos),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    unawaited(_sync.pushRow(monthlyActivitiesSpec, id));
  }

  /// Trim the span at [spanId] by one day — soft-deletes the
  /// highest-position continuation row. If the span ends up with
  /// only the head, the head's span_id is left intact (cheap, no
  /// data loss; a future extend re-uses the same id).
  Future<void> trimSpanByOneDay(String spanId) async {
    final tail = await (_db.select(_db.monthlyActivities)
          ..where((r) => r.spanId.equals(spanId))
          ..where((r) => r.spanPosition.isBiggerThanValue(0))
          ..where((r) => r.deletedAt.isNull())
          ..orderBy([
            (r) => OrderingTerm.desc(r.spanPosition),
          ])
          ..limit(1))
        .getSingleOrNull();
    if (tail == null) return;
    await deleteVariant(tail.id);
  }

  /// Watch every continuation + the head for a given span_id, in
  /// span-position order. Used by the formatted sheet to render
  /// "Day 1 of 3" etc.
  Stream<List<MonthlyActivity>> watchSpan(String spanId) {
    final query = _db.select(_db.monthlyActivities)
      ..where((r) => matchesActiveProgram(r.programId, _programId))
      ..where((r) => r.spanId.equals(spanId))
      ..where((r) => r.deletedAt.isNull())
      ..orderBy([
        (r) => OrderingTerm.asc(r.spanPosition),
      ]);
    return query.watch();
  }

  // ---- Day-key helpers ----------------------------------------

  static DateTime _parseDayKey(String s) {
    final parts = s.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  static String _formatDayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<int> _nextPosition({
    required String groupId,
    required String date,
  }) async {
    final rows = await (_db.select(_db.monthlyActivities)
          ..where((r) => matchesActiveProgram(r.programId, _programId))
          ..where((r) => r.groupId.equals(groupId))
          ..where((r) => r.date.equals(date))
          ..where((r) => r.deletedAt.isNull())
          ..orderBy([
            (r) => OrderingTerm.desc(r.position),
          ])
          ..limit(1))
        .get();
    if (rows.isEmpty) return 0;
    return (rows.first.position) + 1;
  }

  /// Helper for [updateVariant] — translates a "maybe touch this
  /// field" parameter into a Drift Value, recording the field name
  /// in [dirty] when it does touch the column. Empty string maps to
  /// SQL NULL (matches "" → null convention everywhere else).
  Value<String?> _maybeText(
    String? input, {
    required List<String> dirty,
    required String fieldName,
  }) {
    if (input == null) return const Value.absent();
    dirty.add(fieldName);
    return input.isEmpty ? const Value(null) : Value(input);
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

/// Family key for [monthlyActivitiesProvider]: (groupId, date) where
/// `date` is "yyyy-MM-dd". Records carry value-equality so two
/// `(groupId, date)` records with the same fields hit the same
/// provider instance.
typedef MonthlyCellKey = ({String groupId, String date});

/// Live variants for cell (groupId, date) within the active program.
/// Sorted by position; soft-deleted rows filtered out. Empty drafts
/// are included — the caller's `hasContent` check decides what to
/// render.
// ignore: specify_nonobvious_property_types
final monthlyActivitiesProvider =
    StreamProvider.family<List<MonthlyActivity>, MonthlyCellKey>(
        (ref, key) {
  ref.watch(activeProgramIdProvider);
  return ref.watch(monthlyPlanRepositoryProvider).watchVariants(
        groupId: key.groupId,
        date: key.date,
      );
});

/// v57 — live rows belonging to a multi-day span. Sorted by
/// span_position so element 0 is always the head. Used by the AI
/// continuity prompt builder and (later) the formatted sheet's
/// "Day N of M" header.
// ignore: specify_nonobvious_property_types
final monthlySpanProvider =
    StreamProvider.family<List<MonthlyActivity>, String>((ref, spanId) {
  ref.watch(activeProgramIdProvider);
  return ref.watch(monthlyPlanRepositoryProvider).watchSpan(spanId);
});
