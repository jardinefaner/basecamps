import 'dart:async';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/core/now_tick.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:basecamp/features/sync/sync_specs.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Role an adult has during one block of their day-timeline. Currently
/// just lead (with a group anchor) or specialist (rotator, no group).
/// Break + lunch live on adult_availability and overlay on top;
/// 'off' is implied by absent blocks.
enum AdultBlockRole {
  lead('lead'),
  specialist('specialist');

  const AdultBlockRole(this.dbValue);
  final String dbValue;

  static AdultBlockRole fromDb(String raw) {
    for (final r in AdultBlockRole.values) {
      if (r.dbValue == raw) return r;
    }
    // Defensive default — an unknown role string falls back to
    // specialist (the rotator role) the same way legacy adultRole
    // values do. Keeps pre-v30 data that somehow leaked into this
    // table from breaking reads.
    return AdultBlockRole.specialist;
  }
}

/// In-memory block used by the editor + derivation logic. Thin
/// wrapper over the Drift row with the role typed and the times
/// kept as HH:mm strings.
class AdultTimelineBlock {
  const AdultTimelineBlock({
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.role,
    this.groupId,
  });

  factory AdultTimelineBlock.fromRow(AdultDayBlock row) =>
      AdultTimelineBlock(
        dayOfWeek: row.dayOfWeek,
        startTime: row.startTime,
        endTime: row.endTime,
        role: AdultBlockRole.fromDb(row.role),
        groupId: row.groupId,
      );

  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final AdultBlockRole role;
  final String? groupId;

  int get startMinutes => _parseHHmm(startTime);
  int get endMinutes => _parseHHmm(endTime);
}

int _parseHHmm(String hhmm) {
  final parts = hhmm.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

class AdultTimelineRepository {
  AdultTimelineRepository(this._db, this._ref);

  final AppDatabase _db;
  final Ref _ref;

  /// All timeline blocks for [adultId], across every day of the
  /// week. Ordered by (day, start time) for stable editor rendering.
  Stream<List<AdultDayBlock>> watchBlocksFor(String adultId) {
    final query = _db.select(_db.adultDayBlocks)
      ..where((b) => b.adultId.equals(adultId))
      ..orderBy([
        (b) => OrderingTerm.asc(b.dayOfWeek),
        (b) => OrderingTerm.asc(b.startTime),
      ]);
    return query.watch();
  }

  /// All timeline blocks across the program for [dayOfWeek]. Feeds
  /// the Today surfaces that need to answer "who's in Butterflies at
  /// 10:15?" without N per-adult subqueries.
  Stream<List<AdultDayBlock>> watchBlocksForDay(int dayOfWeek) {
    final query = _db.select(_db.adultDayBlocks)
      ..where((b) => b.dayOfWeek.equals(dayOfWeek))
      ..orderBy([
        (b) => OrderingTerm.asc(b.adultId),
        (b) => OrderingTerm.asc(b.startTime),
      ]);
    return query.watch();
  }

  /// Atomic "replace this adult's entire timeline" — deletes all
  /// existing blocks for [adultId] and inserts [blocks] in one
  /// transaction. The editor UI builds a full in-memory list and
  /// saves the lot, which is cleaner than diffing row by row.
  Future<void> replaceBlocks({
    required String adultId,
    required List<AdultTimelineBlock> blocks,
  }) async {
    await _db.transaction(() async {
      await (_db.delete(_db.adultDayBlocks)
            ..where((b) => b.adultId.equals(adultId)))
          .go();
      for (final b in blocks) {
        await _db.into(_db.adultDayBlocks).insert(
              AdultDayBlocksCompanion.insert(
                id: newId(),
                adultId: adultId,
                dayOfWeek: b.dayOfWeek,
                startTime: b.startTime,
                endTime: b.endTime,
                role: b.role.dbValue,
                groupId: Value(b.groupId),
              ),
            );
      }
    });
    // adult_day_blocks is a cascade of adults — pushing the
    // parent rebuilds the cascade and the new timeline rides
    // along. Without this every device's day timeline diverged
    // from every other.
    unawaited(
      _ref.read(syncEngineProvider).pushRow(adultsSpec, adultId),
    );
  }
}

final adultTimelineRepositoryProvider =
    Provider<AdultTimelineRepository>((ref) {
  return AdultTimelineRepository(ref.watch(databaseProvider), ref);
});

/// Today's blocks for every adult (all role types), as raw rows.
/// Derivation / filtering happens in `features/today/adult_staffing.dart`
/// so the pure pass can be unit-tested without Drift.
///
/// Watches `nowTickProvider` so the day-of-week recomputes at
/// midnight rollover — without this a session left running over
/// midnight would keep showing yesterday's blocks until the next
/// route remount.
final todayAdultBlocksProvider =
    StreamProvider<List<AdultDayBlock>>((ref) {
  final repo = ref.watch(adultTimelineRepositoryProvider);
  // ISO: 1 = Mon. Dart's DateTime.weekday is already ISO so no remap.
  final now = ref.watch(nowTickProvider).value ?? DateTime.now();
  return repo.watchBlocksForDay(now.weekday);
});
