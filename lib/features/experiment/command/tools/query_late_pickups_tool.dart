// Read-only late-pickup query — "who's late today?", "how many
// late pickups this week?". Returns count + sample summary.

import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:basecamp/features/experiment/late_pickup_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class QueryLatePickupsTool extends CommandTool {
  const QueryLatePickupsTool();

  @override
  String get name => 'query_late_pickups';

  @override
  String get description => '''
Look up late pickups by date range or child. Returns count +
sample. No DB mutation. Use when the user asks read questions:

  "any late pickups today?"        → date_from/to: today
  "who was late this week?"        → date_from: <Mon>, date_to: <Fri>
  "how many late pickups for phillip?" → child_name: "Phillip"

Always emit both `date_from` and `date_to` (same date twice for
single-day queries). Leave `child_name` empty to include all
kids.
''';

  @override
  String get routerSummary =>
      "Look up late pickups (today's list, by kid, or by date range).";

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'date_from': <String, dynamic>{
            'type': 'string',
            'description': 'ISO 8601 YYYY-MM-DD.',
          },
          'date_to': <String, dynamic>{
            'type': 'string',
            'description': 'ISO 8601 YYYY-MM-DD.',
          },
          'child_name': <String, dynamic>{'type': 'string'},
          'only_card_given': <String, dynamic>{
            'type': 'boolean',
            'description': 'Restrict to entries where the '
                'reminder card was given.',
          },
        },
      };

  @override
  Future<CommandResult> execute(
    Map<String, dynamic> args,
    Ref ref,
  ) async {
    final from = _parseDate((args['date_from'] as String?) ?? '');
    final to = _parseDate((args['date_to'] as String?) ?? '');
    final childName =
        (args['child_name'] as String?)?.trim().toLowerCase() ?? '';
    final onlyCardGiven = args['only_card_given'] is bool
        ? args['only_card_given'] as bool
        : false;

    final entries = await ref.read(lateEntriesProvider.future);
    final matching = entries.where((e) {
      final day = DateTime(e.date.year, e.date.month, e.date.day);
      if (from != null && day.isBefore(from)) return false;
      if (to != null) {
        final endOfDay = DateTime(to.year, to.month, to.day, 23, 59, 59);
        if (day.isAfter(endOfDay)) return false;
      }
      if (childName.isNotEmpty &&
          !e.childName.toLowerCase().contains(childName)) {
        return false;
      }
      if (onlyCardGiven && !e.reminderCardGiven) return false;
      return true;
    }).toList();

    final dateFmt = DateFormat.MMMd();
    final timeFmt = (TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final summary = matching.isEmpty
        ? 'No pickups match'
        : matching
            .take(3)
            .map((e) => '${dateFmt.format(e.date)} ${timeFmt(e.pickupTime)} — '
                '${e.childName}')
            .join(' · ');
    final rangeLabel = (from == null && to == null)
        ? 'all time'
        : '${from == null ? 'start' : dateFmt.format(from)}'
            '–${to == null ? 'end' : dateFmt.format(to)}';
    final headline = '${matching.length} late pickup'
        '${matching.length == 1 ? '' : 's'} · $rangeLabel';

    return CommandResult(
      title: headline,
      subtitle: summary,
      badge: 'LATE PICKUP · LOOKUP',
      iconCode: Icons.search.codePoint,
      iconFontFamily: Icons.search.fontFamily,
      destinationPath: '/late-pickup',
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
}
