import 'dart:async';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/program_scope.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:basecamp/features/sync/sync_specs.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Log of "this library card was instantiated into the schedule"
/// events (v40). One row per use so the library screen can sort by
/// "recently used" and show the last-used-at on each card.
///
/// This round: schema + repository only. Round 2 wires the template /
/// entry creation flows to auto-log a usage, and the library screen
/// uses [lastUsedAtProvider] to decorate cards.
class LibraryUsagesRepository {
  LibraryUsagesRepository(this._db, this._ref);

  final AppDatabase _db;
  final Ref _ref;

  /// See ObservationsRepository._programId for why we read this on
  /// every read rather than caching at construction time.
  String? get _programId => _ref.read(activeProgramIdProvider);

  /// Record that [libraryItemId] was used on [usedOn]. Exactly one of
  /// [templateId] / [entryId] is typically set (the schedule row the
  /// usage spawned), but both-null is legal for a "used in planning"
  /// note that doesn't yet have a schedule row.
  Future<String> logUsage({
    required String libraryItemId,
    required DateTime usedOn,
    String? templateId,
    String? entryId,
  }) async {
    final id = newId();
    final dayOnly = DateTime(usedOn.year, usedOn.month, usedOn.day);
    await _db.into(_db.activityLibraryUsages).insert(
          ActivityLibraryUsagesCompanion.insert(
            id: id,
            libraryItemId: libraryItemId,
            templateId: Value(templateId),
            entryId: Value(entryId),
            usedOn: dayOnly,
          ),
        );
    // Cascade of activity_library — pushing the parent rebuilds
    // the cascade so the new usage row reaches cloud. Without
    // this, "recently used" diverged per device because each
    // device only ever saw its own usage history.
    unawaited(
      _ref
          .read(syncEngineProvider)
          .pushRow(activityLibrarySpec, libraryItemId),
    );
    return id;
  }

  /// Most-recent [limit] usage rows across the whole library, newest
  /// first. Powers the "recently used" rail on the library screen.
  Stream<List<ActivityLibraryUsage>> watchRecentUsages(int limit) {
    // Scope through the parent activity_library row — usages have no
    // programId of their own (cascade table), so we filter on the
    // joined library row's programId.
    final query = _db.select(_db.activityLibraryUsages).join([
      innerJoin(
        _db.activityLibrary,
        _db.activityLibrary.id
            .equalsExp(_db.activityLibraryUsages.libraryItemId),
      ),
    ])
      ..where(matchesActiveProgram(
        _db.activityLibrary.programId,
        _programId,
      ))
      ..orderBy([
        OrderingTerm.desc(_db.activityLibraryUsages.createdAt),
      ])
      ..limit(limit);
    return query.watch().map(
          (rows) =>
              rows.map((r) => r.readTable(_db.activityLibraryUsages)).toList(),
        );
  }

  /// The latest usage timestamp for [libraryItemId], or null when
  /// the card has never been used. Streamed so the card tile can
  /// live-update when the teacher schedules it for the first time.
  Stream<DateTime?> watchLastUsedAt(String libraryItemId) {
    final query = _db.select(_db.activityLibraryUsages)
      ..where((u) => u.libraryItemId.equals(libraryItemId))
      ..orderBy([(u) => OrderingTerm.desc(u.createdAt)])
      ..limit(1);
    return query.watchSingleOrNull().map((row) => row?.createdAt);
  }
}

final libraryUsagesRepositoryProvider =
    Provider<LibraryUsagesRepository>((ref) {
  return LibraryUsagesRepository(ref.watch(databaseProvider), ref);
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final recentLibraryUsagesProvider =
    StreamProvider.family<List<ActivityLibraryUsage>, int>((ref, limit) {
  ref.watch(activeProgramIdProvider);
  return ref.watch(libraryUsagesRepositoryProvider).watchRecentUsages(limit);
});

/// Per-card stream of the most-recent usage timestamp. Null = never
/// used. Families cache per-id so each library tile subscribes once.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final lastUsedAtProvider =
    StreamProvider.family<DateTime?, String>((ref, libraryItemId) {
  return ref
      .watch(libraryUsagesRepositoryProvider)
      .watchLastUsedAt(libraryItemId);
});
