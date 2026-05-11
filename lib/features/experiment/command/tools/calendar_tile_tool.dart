// Calendar tile creation tool. Anchors on "trip,", "event,",
// "day plan,". Fans out one tile per resolved group on confirm.

import 'package:basecamp/database/database.dart' show Group;
import 'package:basecamp/features/children/children_repository.dart'
    show groupsProvider;
import 'package:basecamp/features/experiment/calendar_tile_store.dart';
import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class CreateCalendarTileTool extends CommandTool {
  const CreateCalendarTileTool();

  @override
  String get name => 'create_calendar_tile';

  @override
  List<String> get anchors => const [
        'trip',
        'field trip',
        'event',
        'schedule event',
        'day plan',
        'theme day',
        'calendar',
      ];

  @override
  String get description => '''
Schedule a tile on the calendar — trip, in-program event, or
themed day plan.

Anchor words: "trip,", "field trip,", "event,", "day plan,",
"theme day,", "calendar,".

Tile types (`type` arg):
  * "trip"   — an outing somewhere (has a destination).
                 "field trip aquarium tuesday 8 to 3"
  * "event"  — in-program (no destination, optional time window).
                 "pizza party 11:30 friday"
  * "dayPlan" — theme for the whole day (theme line, no times).
                 "ocean day thursday"

The TITLE field is the BARE subject only. The UI renders type
+ date + destination as separate columns, so:
  Good titles: "Aquarium", "Pajama Day", "Pizza Party", "Ocean"
  Bad titles:  "Field Trip to Aquarium", "Pajama Day on Friday",
                "Aquarium (Sunflowers)"
Strip type prefixes ("field trip to", "trip:", "event —") and
trailing dates / group names. Capitalise like a headline, max 4
words.

DATE: ISO 8601 "YYYY-MM-DD" (local). Resolve relative phrases
("next tuesday") against today's date in the system context.
If silent on date, default to tomorrow.

TIMES: "HH:MM" 24-hour. "8 to 3" → 08:00 / 15:00 (school hours,
PM bias). "9 to 11" stays AM (school morning).

GROUPS:
  * "for sunflowers" / "with acorns" → ["Sunflowers"] / ["Acorns"]
  * "for sunflowers and acorns" → ["Sunflowers", "Acorns"]
  * "all groups" / "everyone" / "all classes" → ENTIRE roster.
  * "only X and Y" / "just X and Y" → exact subset, not active.
  * No group named → empty array (screen falls back to active).
Match leniently against the program's roster (case-insensitive,
plural-tolerant), return EXACT spelling from the roster.

NEVER invent a destination if the user didn't mention one.
NEVER invent times if the user didn't mention any.
''';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'tile_type': <String, dynamic>{
            'type': 'string',
            'enum': ['trip', 'event', 'dayPlan'],
          },
          'date': <String, dynamic>{
            'type': 'string',
            'description': 'ISO 8601 YYYY-MM-DD (local).',
          },
          'title': <String, dynamic>{
            'type': 'string',
            'description': 'Bare subject only; no type prefix.',
          },
          'destination': <String, dynamic>{
            'type': 'string',
            'description': 'Trips only. Empty otherwise.',
          },
          'start_time': <String, dynamic>{
            'type': 'string',
            'description': 'HH:MM 24h. Empty when unknown.',
          },
          'end_time': <String, dynamic>{
            'type': 'string',
            'description': 'HH:MM 24h. Empty when unknown.',
          },
          'theme': <String, dynamic>{
            'type': 'string',
            'description': 'Day-plan only. One short line.',
          },
          'description': <String, dynamic>{'type': 'string'},
          'notes': <String, dynamic>{'type': 'string'},
          'group_names': <String, dynamic>{
            'type': 'array',
            'items': <String, dynamic>{'type': 'string'},
            'description':
                'Exact roster spellings of named groups. Empty '
                'array when no group named (screen falls back '
                'to active). Multiple entries fan out one tile '
                'per group.',
          },
        },
        'required': ['tile_type', 'date', 'title'],
      };

  @override
  Future<CommandResult> execute(
    Map<String, dynamic> args,
    Ref ref,
  ) async {
    final type = _parseType((args['tile_type'] as String?) ?? 'event');
    final date = _parseDate((args['date'] as String?) ?? '') ??
        DateTime.now().add(const Duration(days: 1));
    final title = (args['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) {
      throw StateError('create_calendar_tile: missing title');
    }
    final destination = (args['destination'] as String?)?.trim() ?? '';
    final theme = (args['theme'] as String?)?.trim() ?? '';
    final description = (args['description'] as String?)?.trim() ?? '';
    final notes = (args['notes'] as String?)?.trim() ?? '';
    final startTime = _parseTime(args['start_time'] as String?);
    final endTime = _parseTime(args['end_time'] as String?);
    final groupNamesRaw = (args['group_names'] as List?)
            ?.whereType<String>()
            .toList() ??
        const <String>[];

    // Resolve group names against the roster; fall back to the
    // first group if nothing matched (same shape /calendar uses).
    final groups = ref.read(groupsProvider).asData?.value ?? const <Group>[];
    final resolvedIds = <String>[];
    final seen = <String>{};
    for (final name in groupNamesRaw) {
      final needle = name.trim().toLowerCase();
      if (needle.isEmpty) continue;
      final match = groups
          .where((g) => g.name.trim().toLowerCase() == needle)
          .toList();
      if (match.isEmpty) continue;
      if (seen.add(match.first.id)) resolvedIds.add(match.first.id);
    }
    if (resolvedIds.isEmpty && groups.isNotEmpty) {
      resolvedIds.add(groups.first.id);
    }

    // Mint one tile per resolved group (same fan-out the Calendar
    // drop-bar does). Cloud-synced via the existing repo +
    // calendar_tiles table.
    final repo = ref.read(calendarTilesRepoProvider);
    final committedGroupNames = <String>[];
    String? firstTileId;
    for (final groupId in resolvedIds) {
      final tile = CalendarTile(
        id: '${DateTime.now().microsecondsSinceEpoch}-'
            '${UniqueKey().hashCode}',
        type: type,
        date: DateTime.utc(date.year, date.month, date.day),
        groupId: groupId,
        title: title,
      )
        ..destination = destination
        ..startTime = startTime
        ..endTime = endTime
        ..theme = theme
        ..description = description
        ..notes = notes;
      await repo.put(tile);
      firstTileId ??= tile.id;
      final groupName = groups
          .where((g) => g.id == groupId)
          .map((g) => g.name)
          .firstOrNull;
      if (groupName != null) committedGroupNames.add(groupName);
    }

    // Subtitle: date · time · destination · for X + Y.
    final timeFmt = DateFormat('h:mm a');
    final dateFmt = DateFormat.MMMEd();
    final pieces = <String>[dateFmt.format(date)];
    if (startTime != null) {
      pieces.add(timeFmt.format(
        DateTime(0, 1, 1, startTime.hour, startTime.minute),
      ));
    }
    if (destination.isNotEmpty) pieces.add(destination);
    if (committedGroupNames.isNotEmpty) {
      pieces.add('for ${committedGroupNames.join(' + ')}');
    }

    return CommandResult(
      title: title,
      subtitle: pieces.join(' · '),
      badge: 'CALENDAR · ${type.singularLabel.toUpperCase()}',
      iconCode: type.icon.codePoint,
      iconFontFamily: type.icon.fontFamily,
      destinationPath: '/calendar',
      recordId: firstTileId,
    );
  }

  static CalendarTileType _parseType(String raw) {
    final lower = raw.toLowerCase();
    return switch (lower) {
      'trip' => CalendarTileType.trip,
      'dayplan' || 'day_plan' || 'day-plan' => CalendarTileType.dayPlan,
      _ => CalendarTileType.event,
    };
  }

  static DateTime? _parseDate(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      return DateFormat('yyyy-MM-dd').parseStrict(raw);
    } on FormatException {
      return DateTime.tryParse(raw);
    }
  }

  static TimeOfDay? _parseTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!);
    final min = int.tryParse(m.group(2)!);
    if (h == null || min == null) return null;
    if (h < 0 || h > 23 || min < 0 || min > 59) return null;
    return TimeOfDay(hour: h, minute: min);
  }
}
