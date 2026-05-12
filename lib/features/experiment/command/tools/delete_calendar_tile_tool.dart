// Delete-a-calendar-tile primitive. Soft-delete (deleted_at stamp)
// so other devices learn about the removal on next pull and the
// row stays restorable. Identification mirrors edit: by recent
// record id OR by title-substring + optional date.

import 'package:basecamp/features/experiment/calendar_tile_store.dart';
import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class DeleteCalendarTileTool extends CommandTool {
  const DeleteCalendarTileTool();

  @override
  String get name => 'delete_calendar_tile';

  @override
  String get description => '''
Delete (soft-delete) a calendar tile. The row stays in the
database with `deleted_at` stamped so other devices learn about
the removal and the entry can be restored later.

Identify the target ONE of two ways:
  * `target_id` — when the user references a tile from the
    recent-records window above ("delete it", "remove the trip
    I just made").
  * `target_title` + optional `target_date` — when the user
    names the tile ("delete the aquarium trip on Tuesday").

Examples:
  "delete the pizza party"
    → target_title: "Pizza Party"
  "cancel tomorrow's aquarium trip"
    → target_title: "Aquarium", target_date: "<tomorrow>"
  "remove it"  (after just creating a tile)
    → target_id: "<recent>"
''';

  @override
  String get routerSummary =>
      'Delete (cancel) an existing calendar tile.';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'target_id': <String, dynamic>{
            'type': 'string',
            'description': 'Id from the recent-records list.',
          },
          'target_title': <String, dynamic>{
            'type': 'string',
            'description': 'Substring to match against the tile '
                "title (case-insensitive).",
          },
          'target_date': <String, dynamic>{
            'type': 'string',
            'description': 'ISO 8601 YYYY-MM-DD. Optional.',
          },
        },
      };

  @override
  Future<CommandResult> execute(
    Map<String, dynamic> args,
    Ref ref,
  ) async {
    final targetId = (args['target_id'] as String?)?.trim() ?? '';
    final targetTitle = (args['target_title'] as String?)?.trim() ?? '';
    final targetDate = _parseDate((args['target_date'] as String?) ?? '');

    // Await the future so a cold-start delete doesn't see an
    // empty map and throw a misleading "no tile matched".
    final tilesMap = await ref.read(calendarTilesProvider.future);

    CalendarTile? target;
    if (targetId.isNotEmpty) target = tilesMap[targetId];
    if (target == null && targetTitle.isNotEmpty) {
      final needle = targetTitle.toLowerCase();
      final candidates = tilesMap.values.where((t) {
        if (!t.title.toLowerCase().contains(needle)) return false;
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
          'delete_calendar_tile: $targetTitle matches ${candidates.length} '
          'tiles. Re-issue with a more specific target_title or target_date.',
        );
      }
    }
    if (target == null) {
      throw StateError(
        'delete_calendar_tile: no tile matched '
        '${targetId.isNotEmpty ? 'id=$targetId' : 'title="$targetTitle"'}.',
      );
    }

    await ref.read(calendarTilesRepoProvider).remove(target.id);

    final dateFmt = DateFormat.MMMEd();
    return CommandResult(
      title: 'Deleted · ${target.title}',
      subtitle: dateFmt.format(target.date),
      badge: 'CALENDAR · DELETED',
      iconCode: Icons.event_busy.codePoint,
      iconFontFamily: Icons.event_busy.fontFamily,
      destinationPath: '/calendar',
      recordId: target.id,
    );
  }

  static DateTime? _parseDate(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      return DateFormat('yyyy-MM-dd').parseStrict(raw);
    } on FormatException {
      return DateTime.tryParse(raw);
    }
  }
}
