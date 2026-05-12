// Read-only observation query — "any notes about Phillip today?",
// "what did the SSD3 observations say this week?". Returns a
// count + a sample summary; tapping the feed entry navigates to
// /observations where filters can be applied.

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class QueryObservationsTool extends CommandTool {
  const QueryObservationsTool();

  @override
  String get name => 'query_observations';

  @override
  String get description => '''
Look up observations by child, date range, or domain. Returns a
count + a sample — no DB mutation. Use when the user asks a
read question:

  "any notes about phillip today?"     → child_name: "Phillip", date_from/to: today
  "how is maya doing this week?"       → child_name: "Maya", date_from: <Mon>, date_to: <Fri>
  "what was the concern yesterday?"    → sentiment: "concern", date_from/to: yesterday
  "show me SSD3 notes this month"      → domain: "SSD3", date_from: <month-start>, date_to: today

`child_name` matches the roster's EXACT spelling (case-
insensitive). Leave fields empty to broaden the search.
''';

  @override
  String get routerSummary =>
      'Look up observations (about a kid, in a date range, or by domain).';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'child_name': <String, dynamic>{'type': 'string'},
          'date_from': <String, dynamic>{
            'type': 'string',
            'description': 'ISO 8601 YYYY-MM-DD (inclusive).',
          },
          'date_to': <String, dynamic>{
            'type': 'string',
            'description': 'ISO 8601 YYYY-MM-DD (inclusive).',
          },
          'domain': <String, dynamic>{
            'type': 'string',
            'description': 'Domain code (SSD1-9, HLTH1-4, OTHER).',
          },
          'sentiment': <String, dynamic>{
            'type': 'string',
            'enum': ['', 'positive', 'neutral', 'concern'],
          },
        },
      };

  @override
  Future<CommandResult> execute(
    Map<String, dynamic> args,
    Ref ref,
  ) async {
    final childName = (args['child_name'] as String?)?.trim() ?? '';
    final from = _parseDate((args['date_from'] as String?) ?? '');
    final to = _parseDate((args['date_to'] as String?) ?? '');
    final domain = (args['domain'] as String?)?.trim().toLowerCase() ?? '';
    final sentiment = (args['sentiment'] as String?)?.trim() ?? '';

    final repo = ref.read(observationsRepositoryProvider);
    final all = await repo.watchAll().first;
    final dateFmt = DateFormat.MMMd();

    // Pre-filter by the cheap, in-memory predicates FIRST so the
    // expensive per-row child-tag lookup only runs against the
    // candidates that survive everything else. Avoids the N+1
    // round-trip when a user just asks "this week's notes" (no
    // child filter) — the child lookup is skipped entirely.
    final preFiltered = all.where((o) {
      final created = o.createdAt;
      if (from != null && created.isBefore(from)) return false;
      if (to != null) {
        final endOfDay = DateTime(to.year, to.month, to.day, 23, 59, 59);
        if (created.isAfter(endOfDay)) return false;
      }
      if (domain.isNotEmpty && o.domain.toLowerCase() != domain) {
        return false;
      }
      if (sentiment.isNotEmpty &&
          o.sentiment.toLowerCase() != sentiment.toLowerCase()) {
        return false;
      }
      return true;
    }).toList();

    final matches = <Observation>[];
    if (childName.isEmpty) {
      matches.addAll(preFiltered);
    } else {
      final lower = childName.toLowerCase();
      for (final o in preFiltered) {
        final tagged = await repo.childrenForObservation(o.id);
        final hit = tagged.any((c) => c.firstName.toLowerCase() == lower);
        if (hit) matches.add(o);
      }
    }

    final rangeLabel = (from == null && to == null)
        ? 'all time'
        : '${from == null ? 'start' : dateFmt.format(from)}'
            '–${to == null ? 'end' : dateFmt.format(to)}';
    final summary = matches.isEmpty
        ? 'No notes match'
        : matches
            .take(3)
            .map((o) => '${dateFmt.format(o.createdAt.toLocal())}: '
                '${o.note.length > 60 ? '${o.note.substring(0, 60)}…' : o.note}')
            .join(' · ');
    final headlineBits = <String>[
      if (childName.isNotEmpty) childName,
      if (domain.isNotEmpty) domain.toUpperCase(),
      if (sentiment.isNotEmpty) sentiment,
    ];
    final title = matches.isEmpty
        ? 'No notes ${headlineBits.isEmpty ? '' : '· ${headlineBits.join(" · ")} '}'
            '· $rangeLabel'
        : '${matches.length} note${matches.length == 1 ? '' : 's'} '
            '${headlineBits.isEmpty ? '' : '· ${headlineBits.join(" · ")} '}'
            '· $rangeLabel';

    return CommandResult(
      title: title.trim(),
      subtitle: summary,
      badge: 'OBSERVATIONS · LOOKUP',
      iconCode: Icons.search.codePoint,
      iconFontFamily: Icons.search.fontFamily,
      destinationPath: '/observations',
      recordId: matches.firstOrNull?.id,
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
