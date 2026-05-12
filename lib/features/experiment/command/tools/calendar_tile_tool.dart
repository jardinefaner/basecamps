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

GROUPS — RETURN EVERY GROUP THE USER NAMED, NOT JUST THE FIRST:
The `group_names` field is an ARRAY. The kiosk fans out one tile
per group in this array. If you return only the first group when
the user named several, the trip will only appear on that one
group's calendar and the other groups will silently miss it.

Example transformations (verbatim from teacher prompts):
  • "trip aquarium tuesday for sunflowers and acorns"
      → group_names: ["Sunflowers", "Acorns"]
  • "field trip park for sunflowers, acorns, and pandas"
      → group_names: ["Sunflowers", "Acorns", "Pandas"]
  • "pizza party friday for everyone" / "all groups"
      → group_names: <every group on the roster, in order>
  • "ocean day for sunflowers"
      → group_names: ["Sunflowers"]
  • "trip park" (no group mentioned)
      → group_names: [] (screen falls back to current filter)

How to read the user's phrase:
  • Split on "and", "&", commas — every named group goes in.
  • "everyone" / "all groups" / "all classes" / "the whole
    program" → emit every group on the roster (not an empty
    array — that means "no group mentioned").
  • "only X and Y" / "just X and Y" → emit X and Y exactly,
    no others.
  • Match leniently against the program's roster (case-
    insensitive, plural-tolerant). Return the EXACT spelling
    from the roster.

NEVER invent a destination if the user didn't mention one.
NEVER invent times if the user didn't mention any.
''';

  @override
  String get routerSummary =>
      'Schedule a calendar tile — trip, in-program event, or theme day.';

  @override
  String extractorSystemPrompt(CommandContext ctx) {
    return '''
You are extracting arguments for `create_calendar_tile`. The
router already decided this is the right tool — your only job
is to fill the slots accurately.

$description

Worked examples specific to this tool:

USER: "trip aquarium tuesday for sunflowers and acorns 8 to 3"
ARGS: {
  "tile_type": "trip",
  "date": "<Tuesday from the lookup>",
  "title": "Aquarium",
  "destination": "Aquarium",
  "start_time": "08:00",
  "end_time": "15:00",
  "group_names": ["Sunflowers", "Acorns"]
}

USER: "pizza party friday 11:30 for everyone"
ARGS: {
  "tile_type": "event",
  "date": "<Friday from the lookup>",
  "title": "Pizza Party",
  "start_time": "11:30",
  "group_names": <every group from the roster, in order>
}

USER: "ocean day thursday for sunflowers"
ARGS: {
  "tile_type": "dayPlan",
  "date": "<Thursday from the lookup>",
  "title": "Ocean",
  "theme": "Ocean day",
  "group_names": ["Sunflowers"]
}

Self-check before emitting:
  1. Date — every weekday word in the user's input maps to the
     exact ISO date from the lookup. Don't compute.
  2. Groups — count the groups in the input ("sunflowers and
     acorns" = 2). `group_names` must include all of them.
  3. Times — only present when the user said a time.
  4. Title — bare subject only. No type prefix, no date, no
     group names.
''';
  }

  @override
  List<String> validate(
    String userInput,
    Map<String, dynamic> args,
    CommandContext ctx,
  ) {
    final errors = <String>[];
    final lower = userInput.toLowerCase();

    // Group fan-out validation: every roster group whose name
    // appears in the input must be in group_names. This catches
    // the "for sunflowers and acorns → only Sunflowers" bug
    // class directly.
    final emittedGroups = ((args['group_names'] as List?) ?? const [])
        .whereType<String>()
        .map((s) => s.trim().toLowerCase())
        .toSet();
    final missingGroups = <String>[];
    for (final g in ctx.groupNames) {
      final needle = g.trim().toLowerCase();
      if (needle.isEmpty) continue;
      if (!_inputMentionsGroup(lower, needle)) continue;
      if (emittedGroups.contains(needle)) continue;
      missingGroups.add(g);
    }
    if (missingGroups.isNotEmpty) {
      errors.add(
        "You missed these groups the user named: ${missingGroups.join(', ')}. "
        'Re-emit with `group_names` including ALL of them (use the '
        'exact roster spellings).',
      );
    }

    // Weekday validation: if the user said a weekday, the emitted
    // date should match the lookup for that weekday. Catches the
    // "said Wednesday, picked Tuesday" bug class.
    final mentionedWeekday = _mentionedWeekday(lower);
    final emittedDate = args['date']?.toString() ?? '';
    if (mentionedWeekday != null && emittedDate.isNotEmpty) {
      final emittedWeekday = _weekdayOfIsoDate(emittedDate);
      if (emittedWeekday != null && emittedWeekday != mentionedWeekday) {
        errors.add(
          'You returned date=$emittedDate, which is a $emittedWeekday. '
          'The user said $mentionedWeekday. Pick the matching $mentionedWeekday '
          'date from the calendar lookup.',
        );
      }
    }
    return errors;
  }

  /// True when [lowerInput] mentions [groupName] (lowercased,
  /// plural-tolerant). Word-boundary match so "sunflower" inside
  /// "sunflowery" doesn't false-positive.
  bool _inputMentionsGroup(String lowerInput, String groupName) {
    if (groupName.isEmpty) return false;
    final escaped = RegExp.escape(groupName);
    // Allow optional trailing 's' so "Sunflower" matches "sunflowers".
    final stem = groupName.endsWith('s')
        ? groupName.substring(0, groupName.length - 1)
        : groupName;
    final escapedStem = RegExp.escape(stem);
    return RegExp('\\b$escaped\\b').hasMatch(lowerInput) ||
        RegExp('\\b${escapedStem}s?\\b').hasMatch(lowerInput);
  }

  /// Find a weekday word in the input, return its name lowercased.
  /// Returns null when no weekday is mentioned.
  String? _mentionedWeekday(String lowerInput) {
    const weekdays = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    for (final wd in weekdays) {
      if (RegExp('\\b$wd\\b').hasMatch(lowerInput)) return wd;
    }
    return null;
  }

  /// Parse an ISO date string and return its lowercased weekday
  /// name, or null on parse failure.
  String? _weekdayOfIsoDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      const names = [
        'monday',
        'tuesday',
        'wednesday',
        'thursday',
        'friday',
        'saturday',
        'sunday',
      ];
      return names[d.weekday - 1];
    } on FormatException {
      return null;
    }
  }

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
