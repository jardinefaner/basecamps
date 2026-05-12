// Edit-an-existing-calendar-tile primitive (Phase-1 Calendar
// agent). Identifies the target tile either by `target_id`
// (pulled from the agent's recent-records window — "change the
// trip I just made…") or by a soft-match on `target_title` +
// `target_date` for older tiles ("move the aquarium trip on
// Tuesday to Wednesday").
//
// The same `changes` shape mirrors the create primitive so the
// LLM can transfer its mental model 1:1 — fewer surprises, fewer
// "I extracted the new title but forgot which tile to apply it to"
// failures.

import 'package:basecamp/database/database.dart' show Group;
import 'package:basecamp/features/children/children_repository.dart'
    show groupsProvider;
import 'package:basecamp/features/experiment/calendar_tile_store.dart';
import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class EditCalendarTileTool extends CommandTool {
  const EditCalendarTileTool();

  @override
  String get name => 'edit_calendar_tile';

  @override
  String get description => '''
Edit a calendar tile that already exists. Use when the user
references a tile that's been created (just now or earlier) and
wants to change one of its fields — date, time, title,
destination, theme, notes, or the group it belongs to.

The TARGET (which tile to edit) is identified ONE of two ways:
  * `target_id` — when the user references a tile in the
    recent-records window above ("the trip I just made",
    pronouns "it", "that one"). Use the id verbatim.
  * `target_title` + optional `target_date` — when the user
    names the tile ("the aquarium trip on Tuesday"). The execute
    step does a fuzzy match on local tiles. Provide as much as
    the user said; the tool errors politely if it can't pin down
    a single match.

CHANGES — populate ONLY the fields the user actually mentioned.
Empty / absent means "leave alone." NEVER copy fields from the
old tile back into the changes — that's redundant and risks
overwriting concurrent edits.

Examples:
  "change tomorrow's aquarium trip to friday"
    → target_title: "Aquarium", changes: { date: "<Friday>" }
  "rename the pizza party to ice cream party"
    → target_title: "Pizza Party", changes: { title: "Ice Cream Party" }
  "move it to 9 AM"  (after just creating a tile)
    → target_id: "<recent>", changes: { start_time: "09:00" }
''';

  @override
  String get routerSummary =>
      'Edit an existing calendar tile (date, title, time, etc).';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'target_id': <String, dynamic>{
            'type': 'string',
            'description': 'Id from the recent-records list. '
                'Empty when the user names the tile by content.',
          },
          'target_title': <String, dynamic>{
            'type': 'string',
            'description': 'Substring to match against the tile '
                "title (case-insensitive). Empty when target_id is set.",
          },
          'target_date': <String, dynamic>{
            'type': 'string',
            'description': 'ISO 8601 YYYY-MM-DD of the tile being '
                'edited. Optional; narrows the match.',
          },
          'changes': <String, dynamic>{
            'type': 'object',
            'description': 'Only fields the user explicitly '
                'changed. Empty / absent = leave alone.',
            'properties': <String, dynamic>{
              'date': <String, dynamic>{'type': 'string'},
              'title': <String, dynamic>{'type': 'string'},
              'destination': <String, dynamic>{'type': 'string'},
              'start_time': <String, dynamic>{'type': 'string'},
              'end_time': <String, dynamic>{'type': 'string'},
              'theme': <String, dynamic>{'type': 'string'},
              'description': <String, dynamic>{'type': 'string'},
              'notes': <String, dynamic>{'type': 'string'},
              'group_name': <String, dynamic>{
                'type': 'string',
                'description': 'Move the tile to a different '
                    'group. EXACT roster spelling.',
              },
            },
          },
        },
        'required': ['changes'],
      };

  @override
  Future<CommandResult> execute(
    Map<String, dynamic> args,
    Ref ref,
  ) async {
    final targetId = (args['target_id'] as String?)?.trim() ?? '';
    final targetTitle = (args['target_title'] as String?)?.trim() ?? '';
    final targetDate = _parseDate((args['target_date'] as String?) ?? '');
    final changes = (args['changes'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    final tilesMap = ref.read(calendarTilesProvider).asData?.value ??
        const <String, CalendarTile>{};

    CalendarTile? target;
    if (targetId.isNotEmpty) {
      target = tilesMap[targetId];
    }
    if (target == null && targetTitle.isNotEmpty) {
      final needle = targetTitle.toLowerCase();
      final candidates = tilesMap.values.where((t) {
        final titleMatch = t.title.toLowerCase().contains(needle);
        if (!titleMatch) return false;
        if (targetDate != null) {
          final d = t.date.toLocal();
          return d.year == targetDate.year &&
              d.month == targetDate.month &&
              d.day == targetDate.day;
        }
        return true;
      }).toList();
      if (candidates.length == 1) {
        target = candidates.first;
      } else if (candidates.length > 1) {
        throw StateError(
          'edit_calendar_tile: $targetTitle matches ${candidates.length} '
          'tiles. Re-issue with a more specific target_title or a target_date.',
        );
      }
    }
    if (target == null) {
      throw StateError(
        'edit_calendar_tile: no tile matched '
        '${targetId.isNotEmpty ? 'id=$targetId' : 'title="$targetTitle"'}. '
        'Was the tile already created on this device?',
      );
    }

    // Apply changes. Each field is independently optional —
    // absent / empty-string means "leave alone."
    final newDate = _parseDate((changes['date'] as String?) ?? '');
    final newTitle = (changes['title'] as String?)?.trim();
    final newDestination = (changes['destination'] as String?)?.trim();
    final newStart = _parseTime(changes['start_time'] as String?);
    final newEnd = _parseTime(changes['end_time'] as String?);
    final newTheme = (changes['theme'] as String?)?.trim();
    final newDescription = (changes['description'] as String?)?.trim();
    final newNotes = (changes['notes'] as String?)?.trim();
    final newGroupName = (changes['group_name'] as String?)?.trim();

    final mutated = CalendarTile(
      id: target.id,
      type: target.type,
      date: newDate != null
          ? DateTime.utc(newDate.year, newDate.month, newDate.day)
          : target.date,
      groupId: _resolveGroupId(ref, newGroupName) ?? target.groupId,
      title: newTitle?.isNotEmpty == true ? newTitle! : target.title,
    )
      ..destination = newDestination?.isNotEmpty == true
          ? newDestination!
          : target.destination
      ..startTime = newStart ?? target.startTime
      ..endTime = newEnd ?? target.endTime
      ..theme = newTheme?.isNotEmpty == true ? newTheme! : target.theme
      ..description = newDescription?.isNotEmpty == true
          ? newDescription!
          : target.description
      ..notes = newNotes?.isNotEmpty == true ? newNotes! : target.notes
      ..itinerary = target.itinerary;

    final repo = ref.read(calendarTilesRepoProvider);
    await repo.put(mutated);

    final dateFmt = DateFormat.MMMEd();
    final timeFmt = DateFormat('h:mm a');
    final pieces = <String>[dateFmt.format(mutated.date)];
    if (mutated.startTime case final TimeOfDay t) {
      pieces.add(timeFmt.format(DateTime(0, 1, 1, t.hour, t.minute)));
    }
    if (mutated.destination.isNotEmpty) pieces.add(mutated.destination);

    return CommandResult(
      title: 'Updated · ${mutated.title}',
      subtitle: pieces.join(' · '),
      badge: 'CALENDAR · EDITED',
      iconCode: Icons.edit_calendar.codePoint,
      iconFontFamily: Icons.edit_calendar.fontFamily,
      destinationPath: '/calendar',
      recordId: mutated.id,
    );
  }

  String? _resolveGroupId(Ref ref, String? rawName) {
    final name = rawName?.trim() ?? '';
    if (name.isEmpty) return null;
    final groups = ref.read(groupsProvider).asData?.value ?? const <Group>[];
    String norm(String s) {
      final lower = s.trim().toLowerCase();
      return lower.endsWith('s')
          ? lower.substring(0, lower.length - 1)
          : lower;
    }

    final needle = norm(name);
    for (final g in groups) {
      if (norm(g.name) == needle) return g.id;
    }
    return null;
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
