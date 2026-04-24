import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
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
  LibraryUsagesRepository(this._db);

  final AppDatabase _db;

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
    return id;
  }

  /// Most-recent [limit] usage rows across the whole library, newest
  /// first. Powers the "recently used" rail on the library screen.
  Stream<List<ActivityLibraryUsage>> watchRecentUsages(int limit) {
    final query = _db.select(_db.activityLibraryUsages)
      ..orderBy([(u) => OrderingTerm.desc(u.createdAt)])
      ..limit(limit);
    return query.watch();
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
  return LibraryUsagesRepository(ref.watch(databaseProvider));
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final recentLibraryUsagesProvider =
    StreamProvider.family<List<ActivityLibraryUsage>, int>((ref, limit) {
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
