// Read-only query primitive for the Calendar agent. Returns a
// summary of tiles matching the filter ("what's on the calendar
// for Friday?", "any trips this week?"). No DB mutation —
// reads `calendarTilesProvider` and formats the answer.

import 'package:basecamp/features/experiment/calendar_tile_store.dart';
import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class QueryCalendarTilesTool extends CommandTool {
  const QueryCalendarTilesTool();

  @override
  String get name => 'query_calendar_tiles';

  @override
  String get description => '''
Look up calendar tiles by date range and/or type. Returns a
SUMMARY of what's scheduled — no DB mutation. Use when the user
asks a read question:

  "what's on the calendar friday?"          → date_from: friday, date_to: friday
  "any trips this week?"                    → date_from: mon, date_to: fri, tile_type: trip
  "show me next week's events"              → date_from: next-mon, date_to: next-fri, tile_type: event
  "what trips are coming up?"               → date_from: today, date_to: <today+14>, tile_type: trip
  "is there anything scheduled tomorrow?"   → date_from: tomorrow, date_to: tomorrow

Always emit both `date_from` and `date_to` (use the same date
twice for a single day). Leave `tile_type` empty to include
every type.
''';

  @override
  String get routerSummary =>
      'Look up what is scheduled on the calendar (read-only).';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'date_from': <String, dynamic>{
            'type': 'string',
            'description': 'ISO 8601 YYYY-MM-DD start (inclusive).',
          },
          'date_to': <String, dynamic>{
            'type': 'string',
            'description': 'ISO 8601 YYYY-MM-DD end (inclusive).',
          },
          'tile_type': <String, dynamic>{
            'type': 'string',
            'enum': ['', 'trip', 'event', 'dayPlan'],
            'description': 'Restrict to one type. Empty = all.',
          },
        },
        'required': ['date_from', 'date_to'],
      };

  @override
  Future<CommandResult> execute(
    Map<String, dynamic> args,
    Ref ref,
  ) async {
    final from = _parseDate((args['date_from'] as String?) ?? '');
    final to = _parseDate((args['date_to'] as String?) ?? '');
    final typeFilter = (args['tile_type'] as String?)?.trim() ?? '';
    if (from == null || to == null) {
      throw StateError('query_calendar_tiles: date_from + date_to required');
    }
    final tilesMap = await ref.read(calendarTilesProvider.future);
    final matching = tilesMap.values.where((t) {
      final d = t.date.toLocal();
      final day = DateTime(d.year, d.month, d.day);
      if (day.isBefore(from) || day.isAfter(to)) return false;
      if (typeFilter.isNotEmpty && t.type.name != typeFilter) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final dateFmt = DateFormat.MMMEd();
    final summary = matching.isEmpty
        ? 'Nothing scheduled'
        : matching
            .take(5)
            .map((t) => '${dateFmt.format(t.date.toLocal())}: ${t.title}')
            .join(' · ');
    final rangeLabel = _isSameDay(from, to)
        ? dateFmt.format(from)
        : '${dateFmt.format(from)} – ${dateFmt.format(to)}';
    final title = matching.isEmpty
        ? 'Nothing on $rangeLabel'
        : matching.length == 1
            ? '1 ${typeFilter.isEmpty ? 'tile' : typeFilter} on $rangeLabel'
            : '${matching.length} '
                '${typeFilter.isEmpty ? 'tiles' : '${typeFilter}s'} '
                '· $rangeLabel';

    return CommandResult(
      title: title,
      subtitle: summary,
      badge: 'CALENDAR · LOOKUP',
      iconCode: Icons.search.codePoint,
      iconFontFamily: Icons.search.fontFamily,
      destinationPath: '/calendar',
      recordId: matching.firstOrNull?.id,
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

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
