import 'dart:async';

import 'package:basecamp/core/format/date.dart';
import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:basecamp/features/sync/sync_specs.dart';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Typed view of the `kind` column on [AdultRoleBlock] /
/// [AdultRoleBlockOverride]. The DB stores raw text (validated
/// by a CHECK constraint cloud-side) — this enum is the
/// type-safe access layer for callers.
enum RoleBlockKind {
  /// Anchored to a classroom. Most blocks are this for the
  /// pair-of-anchors model.
  anchor('anchor'),

  /// Teaching a subject across rooms. May be in their home
  /// room or visiting another. `subject` is usually set.
  specialist('specialist'),

  /// Off-duty short break.
  break_('break'),

  /// Off-duty meal.
  lunch('lunch'),

  /// Non-classroom work (planning, paperwork).
  admin('admin'),

  /// Covering for an absent teacher.
  sub('sub');

  const RoleBlockKind(this.value);

  /// The string stored in the `kind` column.
  final String value;

  /// Lookup by stored value. Falls back to anchor when an
  /// unknown string lands (e.g. row from a newer client that
  /// added a kind we don't know yet) so the timeline still
  /// renders something rather than crashing.
  static RoleBlockKind fromValue(String raw) {
    for (final k in RoleBlockKind.values) {
      if (k.value == raw) return k;
    }
    return RoleBlockKind.anchor;
  }

  /// True when this kind is on-duty in a classroom (needs a
  /// `groupId`). Drives "this block must have a group selected"
  /// validation in the editor.
  bool get isInRoom =>
      this == RoleBlockKind.anchor ||
      this == RoleBlockKind.specialist ||
      this == RoleBlockKind.sub;

  /// Human label for the timeline UI.
  String get label {
    switch (this) {
      case RoleBlockKind.anchor:
        return 'Anchor';
      case RoleBlockKind.specialist:
        return 'Specialist';
      case RoleBlockKind.break_:
        return 'Break';
      case RoleBlockKind.lunch:
        return 'Lunch';
      case RoleBlockKind.admin:
        return 'Admin';
      case RoleBlockKind.sub:
        return 'Sub';
    }
  }
}

/// CRUD + resolver for the per-adult role-block timeline (v48).
///
/// The pattern + override model:
///   * Every adult has zero-or-more `AdultRoleBlock` rows per
///     weekday (the recurring pattern).
///   * For specific dates, `AdultRoleBlockOverride` rows can
///     either ADD a one-off block (`replaces = false`) or
///     REPLACE the overlapping pattern (`replaces = true`).
///   * `resolveDay(adultId, date)` layers them: pattern blocks
///     for `date.weekday` minus replaced ones plus all overrides.
///
/// Writes push through the existing `adultsSpec` cascade — both
/// tables are cascades of `adults`, so `pushRow(adultsSpec, adultId)`
/// re-uploads them as part of the parent push. Same pattern as
/// `adult_availability` / `adult_day_blocks`.
class RoleBlocksRepository {
  RoleBlocksRepository(this._db, this._ref);

  final AppDatabase _db;
  final Ref _ref;

  String? get _programId => _ref.read(activeProgramIdProvider);
  SyncEngine get _sync => _ref.read(syncEngineProvider);

  // ---- Pattern (weekday) blocks --------------------------------

  /// Stream every pattern block for [adultId], sorted by weekday
  /// then start time so the day-plan tab renders in chronological
  /// order without re-sorting.
  Stream<List<AdultRoleBlock>> watchPatternFor(String adultId) {
    final query = _db.select(_db.adultRoleBlocks)
      ..where((b) => b.adultId.equals(adultId))
      ..orderBy([
        (b) => OrderingTerm.asc(b.weekday),
        (b) => OrderingTerm.asc(b.startMinute),
      ]);
    return query.watch();
  }

  Future<String> addPatternBlock({
    required String adultId,
    required int weekday,
    required int startMinute,
    required int endMinute,
    required RoleBlockKind kind,
    String? subject,
    String? groupId,
  }) async {
    final id = newId();
    await _db.into(_db.adultRoleBlocks).insert(
          AdultRoleBlocksCompanion.insert(
            id: id,
            adultId: adultId,
            weekday: weekday,
            startMinute: startMinute,
            endMinute: endMinute,
            kind: kind.value,
            subject: Value(subject),
            groupId: Value(groupId),
            programId: Value(_programId),
          ),
        );
    unawaited(_sync.pushRow(adultsSpec, adultId));
    return id;
  }

  Future<void> updatePatternBlock({
    required String id,
    int? weekday,
    int? startMinute,
    int? endMinute,
    RoleBlockKind? kind,
    Value<String?> subject = const Value.absent(),
    Value<String?> groupId = const Value.absent(),
  }) async {
    final row = await (_db.select(_db.adultRoleBlocks)
          ..where((b) => b.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    await (_db.update(_db.adultRoleBlocks)..where((b) => b.id.equals(id)))
        .write(
      AdultRoleBlocksCompanion(
        weekday: weekday == null ? const Value.absent() : Value(weekday),
        startMinute: startMinute == null
            ? const Value.absent()
            : Value(startMinute),
        endMinute:
            endMinute == null ? const Value.absent() : Value(endMinute),
        kind: kind == null ? const Value.absent() : Value(kind.value),
        subject: subject,
        groupId: groupId,
        updatedAt: Value(DateTime.now()),
      ),
    );
    unawaited(_sync.pushRow(adultsSpec, row.adultId));
  }

  Future<void> deletePatternBlock(String id) async {
    final row = await (_db.select(_db.adultRoleBlocks)
          ..where((b) => b.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    await (_db.delete(_db.adultRoleBlocks)..where((b) => b.id.equals(id)))
        .go();
    unawaited(_sync.pushRow(adultsSpec, row.adultId));
  }

  // ---- Overrides (date-specific) -------------------------------

  /// Stream override blocks for one adult on one date. Used when
  /// the day-plan tab pivots to a specific day to show what
  /// substitutions / additions are in play.
  Stream<List<AdultRoleBlockOverride>> watchOverridesFor({
    required String adultId,
    required DateTime date,
  }) {
    final dayStart = date.dayOnly;
    final query = _db.select(_db.adultRoleBlockOverrides)
      ..where((o) =>
          o.adultId.equals(adultId) &
          o.date.equals(dayStart))
      ..orderBy([(o) => OrderingTerm.asc(o.startMinute)]);
    return query.watch();
  }

  Future<String> addOverride({
    required String adultId,
    required DateTime date,
    required int startMinute,
    required int endMinute,
    required RoleBlockKind kind,
    String? subject,
    String? groupId,
    bool replaces = false,
  }) async {
    final id = newId();
    final dayStart = date.dayOnly;
    await _db.into(_db.adultRoleBlockOverrides).insert(
          AdultRoleBlockOverridesCompanion.insert(
            id: id,
            adultId: adultId,
            date: dayStart,
            startMinute: startMinute,
            endMinute: endMinute,
            kind: kind.value,
            subject: Value(subject),
            groupId: Value(groupId),
            replaces: Value(replaces),
            programId: Value(_programId),
          ),
        );
    unawaited(_sync.pushRow(adultsSpec, adultId));
    return id;
  }

  Future<void> deleteOverride(String id) async {
    final row = await (_db.select(_db.adultRoleBlockOverrides)
          ..where((o) => o.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    await (_db.delete(_db.adultRoleBlockOverrides)
          ..where((o) => o.id.equals(id)))
        .go();
    unawaited(_sync.pushRow(adultsSpec, row.adultId));
  }

  // ---- Resolver ------------------------------------------------

  /// "What blocks are in effect for [adultId] on [date]?"
  /// Returns the layered timeline as `ResolvedRoleBlock`s.
  ///
  /// Algorithm:
  ///   1. Pattern blocks for `date.weekday` form the baseline.
  ///   2. Overrides for `date` with `replaces = true` carve out
  ///      any pattern block that overlaps their span.
  ///   3. All overrides (replacing or additive) are appended.
  ///   4. Sort by start time.
  ///
  /// The carve-out is a simple span subtract — if an override
  /// fully contains a pattern block, the pattern goes; if it
  /// partially overlaps, the pattern's surviving fragments stay.
  /// This produces a visually correct timeline without baking
  /// the override choice into the persisted state.
  Future<List<ResolvedRoleBlock>> resolveDay({
    required String adultId,
    required DateTime date,
  }) async {
    final dayStart = date.dayOnly;
    final pattern = await (_db.select(_db.adultRoleBlocks)
          ..where((b) =>
              b.adultId.equals(adultId) & b.weekday.equals(date.weekday)))
        .get();
    final overrides = await (_db.select(_db.adultRoleBlockOverrides)
          ..where((o) =>
              o.adultId.equals(adultId) & o.date.equals(dayStart)))
        .get();

    // Carve out the replaced spans from pattern blocks.
    final replacers = overrides.where((o) => o.replaces).toList();
    final survivors = <ResolvedRoleBlock>[];
    for (final p in pattern) {
      final fragments = _subtractSpans(
        startMinute: p.startMinute,
        endMinute: p.endMinute,
        replacers: replacers,
      );
      for (final f in fragments) {
        survivors.add(ResolvedRoleBlock(
          source: ResolvedRoleBlockSource.pattern,
          startMinute: f.startMinute,
          endMinute: f.endMinute,
          kind: RoleBlockKind.fromValue(p.kind),
          subject: p.subject,
          groupId: p.groupId,
        ));
      }
    }
    for (final o in overrides) {
      survivors.add(ResolvedRoleBlock(
        source: o.replaces
            ? ResolvedRoleBlockSource.overrideReplace
            : ResolvedRoleBlockSource.overrideAdd,
        startMinute: o.startMinute,
        endMinute: o.endMinute,
        kind: RoleBlockKind.fromValue(o.kind),
        subject: o.subject,
        groupId: o.groupId,
      ));
    }
    survivors.sort((a, b) => a.startMinute.compareTo(b.startMinute));
    return survivors;
  }

  /// Returns the surviving sub-intervals of `[start, end)` after
  /// removing every replacer span that overlaps it. A replacer
  /// fully containing the input returns an empty list.
  List<({int startMinute, int endMinute})> _subtractSpans({
    required int startMinute,
    required int endMinute,
    required List<AdultRoleBlockOverride> replacers,
  }) {
    var fragments = <({int startMinute, int endMinute})>[
      (startMinute: startMinute, endMinute: endMinute),
    ];
    for (final r in replacers) {
      final next = <({int startMinute, int endMinute})>[];
      for (final f in fragments) {
        if (r.endMinute <= f.startMinute || r.startMinute >= f.endMinute) {
          // No overlap — pattern fragment survives intact.
          next.add(f);
          continue;
        }
        if (r.startMinute > f.startMinute) {
          next.add((
            startMinute: f.startMinute,
            endMinute: r.startMinute,
          ));
        }
        if (r.endMinute < f.endMinute) {
          next.add((
            startMinute: r.endMinute,
            endMinute: f.endMinute,
          ));
        }
      }
      fragments = next;
    }
    return fragments;
  }
}

/// One block in the resolved timeline for a date. `source`
/// distinguishes pattern vs override so the UI can mark
/// overrides visually (e.g. with a "today only" badge).
class ResolvedRoleBlock {
  const ResolvedRoleBlock({
    required this.source,
    required this.startMinute,
    required this.endMinute,
    required this.kind,
    required this.subject,
    required this.groupId,
  });

  final ResolvedRoleBlockSource source;
  final int startMinute;
  final int endMinute;
  final RoleBlockKind kind;
  final String? subject;
  final String? groupId;
}

enum ResolvedRoleBlockSource { pattern, overrideAdd, overrideReplace }

final roleBlocksRepositoryProvider = Provider<RoleBlocksRepository>((ref) {
  return RoleBlocksRepository(ref.watch(databaseProvider), ref);
});

/// Pattern blocks for one adult.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final adultRoleBlockPatternProvider =
    StreamProvider.family<List<AdultRoleBlock>, String>((ref, adultId) {
  ref.watch(activeProgramIdProvider);
  return ref.watch(roleBlocksRepositoryProvider).watchPatternFor(adultId);
});
