// Calendar tile store — Drift-backed (v64) + cloud-synced.
//
// Promoted from in-memory `Map<String, CalendarTile>` to a real
// Drift table so creates from the Command Center survive an app
// restart and propagate to other devices via the existing sync
// engine. Cloud parity: migration 0038.
//
// Public API kept compatible with the previous in-memory
// notifier so callers don't have to change much:
//   * `calendarTilesProvider` is now a `StreamProvider`
//     (Map<String, CalendarTile>) instead of a Notifier. Callers
//     that read it bare get the Map directly via `.value` /
//     `.valueOrNull ?? const {}`.
//   * `calendarTilesRepoProvider` exposes the write API:
//     `put(tile)`, `touch(id)`, `remove(id)`. Replaces the old
//     `notifier.put / touch / remove`.

import 'dart:async';
import 'dart:convert';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/program_scope.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ═════════════════════════════════════════════════════════════════
// Public model classes (kept identical to the prior in-memory
// shapes so screen code doesn't change).
// ═════════════════════════════════════════════════════════════════

/// Three flavors today. Each one surfaces a different field set
/// in the expand sheet, but they share the same storage shape —
/// optional fields, populated on demand.
enum CalendarTileType {
  trip('Trips', Icons.directions_bus_filled_outlined, 'trip'),
  event('Events', Icons.celebration_outlined, 'event'),
  dayPlan('Day plans', Icons.wb_sunny_outlined, 'day plan');

  const CalendarTileType(this.pluralLabel, this.icon, this.singularLabel);

  final String pluralLabel;
  final IconData icon;
  final String singularLabel;

  static CalendarTileType fromCode(String code) {
    return CalendarTileType.values.firstWhere(
      (t) => t.name == code,
      orElse: () => CalendarTileType.event,
    );
  }
}

class CalendarTile {
  CalendarTile({
    required this.id,
    required this.type,
    required this.date,
    required this.groupId,
    required this.title,
  });

  final String id;
  final CalendarTileType type;
  DateTime date; // day key (UTC midnight)
  final String? groupId;
  String title;

  String description = '';
  String destination = '';
  TimeOfDay? startTime;
  TimeOfDay? endTime;
  String theme = '';
  String notes = '';

  List<ItineraryBlock> itinerary = <ItineraryBlock>[];
}

class ItineraryBlock {
  ItineraryBlock({
    required this.id,
    required this.time,
    required this.title,
    this.description = '',
  });

  final String id;
  TimeOfDay time;
  String title;
  String description;
}

// ═════════════════════════════════════════════════════════════════
// Mapping between Drift rows and the in-memory models.
// ═════════════════════════════════════════════════════════════════

int? _todToMinutes(TimeOfDay? t) =>
    t == null ? null : t.hour * 60 + t.minute;

TimeOfDay? _minutesToTod(int? m) =>
    m == null ? null : TimeOfDay(hour: m ~/ 60, minute: m % 60);

String _itineraryToJson(List<ItineraryBlock> blocks) {
  return jsonEncode([
    for (final b in blocks)
      {
        'id': b.id,
        'time':
            '${b.time.hour.toString().padLeft(2, '0')}:${b.time.minute.toString().padLeft(2, '0')}',
        'title': b.title,
        'description': b.description,
      },
  ]);
}

List<ItineraryBlock> _itineraryFromJson(String raw) {
  if (raw.trim().isEmpty) return <ItineraryBlock>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <ItineraryBlock>[];
    return decoded.whereType<Map<String, dynamic>>().map((m) {
      final timeStr = (m['time'] as String?)?.trim() ?? '';
      final parts = timeStr.split(':');
      final h = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
      final mn = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      return ItineraryBlock(
        id: (m['id'] as String?) ?? '',
        time: TimeOfDay(hour: h, minute: mn),
        title: (m['title'] as String?) ?? '',
        description: (m['description'] as String?) ?? '',
      );
    }).toList();
  } on FormatException {
    return <ItineraryBlock>[];
  }
}

CalendarTile _rowToTile(CalendarTileRow r) {
  return CalendarTile(
    id: r.id,
    type: CalendarTileType.fromCode(r.type),
    date: r.date,
    groupId: r.groupId,
    title: r.title,
  )
    ..description = r.description
    ..destination = r.destination
    ..startTime = _minutesToTod(r.startMinutes)
    ..endTime = _minutesToTod(r.endMinutes)
    ..theme = r.theme
    ..notes = r.notes
    ..itinerary = _itineraryFromJson(r.itineraryJson);
}

// ═════════════════════════════════════════════════════════════════
// Repository
// ═════════════════════════════════════════════════════════════════

class CalendarTilesRepository {
  CalendarTilesRepository(this._db, this._ref);

  final AppDatabase _db;
  final Ref _ref;

  String? get _programId => _ref.read(activeProgramIdProvider);

  /// Stream of every tile in the active program (and any
  /// program-untagged rows from before the migration), keyed by
  /// id. Soft-deleted rows are filtered out.
  Stream<Map<String, CalendarTile>> watchAll() {
    return (_db.select(_db.calendarTilesTable)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                matchesActiveProgram(t.programId, _programId),
          ))
        .watch()
        .map(
          (rows) => <String, CalendarTile>{
            for (final r in rows) r.id: _rowToTile(r),
          },
        );
  }

  /// Insert or replace a tile. The Drift watch on `watchAll`
  /// re-emits, so consumers update without a manual refresh.
  Future<void> put(CalendarTile tile) async {
    final companion = CalendarTilesTableCompanion(
      id: Value(tile.id),
      type: Value(tile.type.name),
      date: Value(tile.date),
      groupId: Value(tile.groupId),
      title: Value(tile.title),
      description: Value(tile.description),
      destination: Value(tile.destination),
      startMinutes: Value(_todToMinutes(tile.startTime)),
      endMinutes: Value(_todToMinutes(tile.endTime)),
      theme: Value(tile.theme),
      notes: Value(tile.notes),
      itineraryJson: Value(_itineraryToJson(tile.itinerary)),
      programId: Value(_programId),
      updatedAt: Value(DateTime.now().toUtc()),
    );
    await _db.into(_db.calendarTilesTable).insertOnConflictUpdate(companion);
  }

  /// Bump `updated_at` on a tile so re-emit semantics fire when
  /// something downstream wants to "publish" a mutated row.
  /// Field updates ride through `put`; this is just the heartbeat.
  Future<void> touch(String id) async {
    await (_db.update(_db.calendarTilesTable)
          ..where((t) => t.id.equals(id)))
        .write(
      CalendarTilesTableCompanion(
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Soft-delete. Other devices learn about the delete on next
  /// pull (sync engine pushes `deleted_at` through the same path
  /// every other column travels).
  Future<void> remove(String id) async {
    await (_db.update(_db.calendarTilesTable)
          ..where((t) => t.id.equals(id)))
        .write(
      CalendarTilesTableCompanion(
        deletedAt: Value(DateTime.now().toUtc()),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }
}

final calendarTilesRepoProvider = Provider<CalendarTilesRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return CalendarTilesRepository(db, ref);
});

/// Live tile map. Screens consume via `ref.watch(...).valueOrNull
/// ?? const {}`. Empty map while the first emission is in flight.
final calendarTilesProvider =
    StreamProvider<Map<String, CalendarTile>>((ref) {
  return ref.watch(calendarTilesRepoProvider).watchAll();
});
