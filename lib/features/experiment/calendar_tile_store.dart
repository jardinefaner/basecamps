// Calendar tile store — Riverpod-backed in-memory state for the
// Calendar lab.
//
// The tile classes used to live as private types inside
// `calendar_screen.dart`, with a `Map<String, _CalendarTile>`
// field on the screen's State. That kept the state nicely scoped,
// but it meant the Command Center couldn't WRITE tiles — every
// drop-bar add from `/command` landed in the Command Center's
// own session log and the Calendar screen never saw it.
//
// Lifting to Riverpod fixes the orphan: any screen can read the
// current set of tiles + push a new one via the notifier.
// In-memory only (no Drift / no cloud) — same lab proof scope as
// before; promoting to persistence is a separate move once the
// surface earns it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ═════════════════════════════════════════════════════════════════
// Tile model
// ═════════════════════════════════════════════════════════════════

/// Three flavors today. Each one surfaces a different field set
/// in the expand sheet, but they share the same storage shape —
/// optional fields, populated on demand. This is the "one
/// primitive with optional fields" model the brainstorm landed
/// on.
enum CalendarTileType {
  trip('Trips', Icons.directions_bus_filled_outlined, 'trip'),
  event('Events', Icons.celebration_outlined, 'event'),
  dayPlan('Day plans', Icons.wb_sunny_outlined, 'day plan');

  const CalendarTileType(this.pluralLabel, this.icon, this.singularLabel);

  final String pluralLabel;
  final IconData icon;
  final String singularLabel;
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
  final String? groupId; // null = "all groups"
  String title;

  // Optional fields — populated by the expand sheet on demand.
  // Empty/null means "the user hasn't set this." Keeping them as
  // mutable fields (not constructor args) reflects the design:
  // create with just a title, fill in the rest when needed.
  String description = '';
  String destination = ''; // trips
  TimeOfDay? startTime; // trips, events
  TimeOfDay? endTime; // trips, events
  String theme = ''; // day plans
  String notes = ''; // any

  /// AI-scaffolded body: a list of timed blocks. For TRIPS, this is
  /// the itinerary (8:00 leave, 8:30 arrive, 9–11 jellies + sharks,
  /// …). For DAY PLANS, this is the day's schedule (8:30 morning
  /// circle, 9:00 art, …). Empty until the teacher hits "generate";
  /// editable in place after.
  List<ItineraryBlock> itinerary = <ItineraryBlock>[];
}

/// One row in [CalendarTile.itinerary]. Times are local (no
/// timezone — the parent tile carries the date). All fields except
/// id are user-editable; id is stable so the regenerate flow can
/// dedupe rather than wipe.
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
// Notifier + provider
// ═════════════════════════════════════════════════════════════════

/// Holds the lab calendar's tiles in a single map. Every screen
/// reads through `ref.watch(calendarTilesProvider)`; writes go
/// through `ref.read(calendarTilesProvider.notifier).put / remove`.
class CalendarTilesNotifier extends Notifier<Map<String, CalendarTile>> {
  @override
  Map<String, CalendarTile> build() => <String, CalendarTile>{};

  /// Insert or replace a tile by id. Re-emits a NEW map so
  /// `ref.watch` consumers rebuild — Riverpod uses identity to
  /// detect changes and a mutation-in-place wouldn't trigger.
  void put(CalendarTile tile) {
    state = <String, CalendarTile>{...state, tile.id: tile};
  }

  /// Mutate an existing tile in place + bump the map identity so
  /// watchers rebuild. The CalendarTile object itself is mutable
  /// (date, title, fields all settable), so screens can edit
  /// fields directly and call [touch] to publish.
  void touch(String id) {
    if (!state.containsKey(id)) return;
    state = <String, CalendarTile>{...state};
  }

  void remove(String id) {
    if (!state.containsKey(id)) return;
    final next = <String, CalendarTile>{...state}..remove(id);
    state = next;
  }
}

final calendarTilesProvider =
    NotifierProvider<CalendarTilesNotifier, Map<String, CalendarTile>>(
  CalendarTilesNotifier.new,
);
