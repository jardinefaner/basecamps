// Edit an existing observation. Identifies the target by
// `observation_id` from the recent-records window (works for
// the just-typed note: "actually, change the domain to SSD2").
// Applies only the fields the user explicitly mentioned.

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EditObservationTool extends CommandTool {
  const EditObservationTool();

  @override
  String get name => 'edit_observation';

  @override
  String get description => '''
Edit an existing observation referenced from the recent-records
window above. Use when the user wants to change something about
a note they just made:

  "actually that was SSD2, not SSD3"        → domains: ["SSD2"]
  "mark it concern"                         → sentiment: "concern"
  "also tag zamir"                          → add_child_ids: [<zamir>]
  "change the note to: he shared with maya" → note: "He shared with Maya"
  "untag phillip"                           → remove_child_ids: [<phillip>]

NEVER invent an `observation_id` that isn't listed in the
recent-records block. If the user is referencing an older
observation that isn't in recents, route to a query first to
find it.
''';

  @override
  String get routerSummary =>
      "Edit a recent observation (note text, domain, sentiment, tagged kids).";

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'observation_id': <String, dynamic>{
            'type': 'string',
            'description': 'Id from the recent-records list.',
          },
          'note': <String, dynamic>{
            'type': 'string',
            'description': 'Replace the note text entirely. Use '
                '`append_observation` instead to ADD to the note.',
          },
          'domain': <String, dynamic>{
            'type': 'string',
            'description': 'New domain code (SSD1-9, HLTH1-4, OTHER). '
                'Omit to leave alone.',
          },
          'sentiment': <String, dynamic>{
            'type': 'string',
            'enum': ['', 'positive', 'neutral', 'concern'],
          },
          'add_child_ids': <String, dynamic>{
            'type': 'array',
            'items': <String, dynamic>{'type': 'string'},
            'description': 'Child ids to ADD to the tag set.',
          },
          'remove_child_ids': <String, dynamic>{
            'type': 'array',
            'items': <String, dynamic>{'type': 'string'},
            'description': 'Child ids to REMOVE from the tag set.',
          },
        },
        'required': ['observation_id'],
      };

  @override
  Future<CommandResult> execute(
    Map<String, dynamic> args,
    Ref ref,
  ) async {
    final id = (args['observation_id'] as String?)?.trim() ?? '';
    if (id.isEmpty) {
      throw StateError('edit_observation: observation_id required');
    }
    final repo = ref.read(observationsRepositoryProvider);
    final db = ref.read(databaseProvider);

    // Snapshot current state — repo doesn't expose a typed `byId`
    // for observations so we hit Drift directly.
    final existing = await (db.select(db.observations)
          ..where((o) => o.id.equals(id)))
        .getSingleOrNull();
    if (existing == null) {
      throw StateError('edit_observation: observation not found id=$id');
    }
    final currentChildren = await repo.childrenForObservation(id);
    final currentChildIds =
        currentChildren.map((c) => c.id).toSet();

    final newNote = (args['note'] as String?)?.trim();
    final newDomainRaw = (args['domain'] as String?)?.trim() ?? '';
    final newSentimentRaw =
        (args['sentiment'] as String?)?.trim().toLowerCase() ?? '';
    final addIds = ((args['add_child_ids'] as List?) ?? const [])
        .whereType<String>()
        .toSet();
    final removeIds = ((args['remove_child_ids'] as List?) ?? const [])
        .whereType<String>()
        .toSet();
    final mergedChildIds = <String>{
      ...currentChildIds,
      ...addIds,
    }..removeAll(removeIds);

    final newDomain = newDomainRaw.isEmpty
        ? null
        : _parseDomain(newDomainRaw);
    final newSentiment = newSentimentRaw.isEmpty
        ? null
        : _parseSentiment(newSentimentRaw);

    await repo.updateObservation(
      id: id,
      note: newNote,
      domains: newDomain == null ? null : <ObservationDomain>[newDomain],
      sentiment: newSentiment,
      childIds:
          mergedChildIds.toSet().toList()..sort(),
    );

    final subtitlePieces = <String>[];
    if (newNote != null) subtitlePieces.add('note changed');
    if (newDomain != null) subtitlePieces.add('domain ${newDomain.code}');
    if (newSentiment != null) subtitlePieces.add(newSentiment.name);
    if (addIds.isNotEmpty) subtitlePieces.add('+${addIds.length} kid(s)');
    if (removeIds.isNotEmpty) {
      subtitlePieces.add('-${removeIds.length} kid(s)');
    }
    return CommandResult(
      title: 'Updated · ${_truncate(existing.note, 60)}',
      subtitle:
          subtitlePieces.isEmpty ? 'no change' : subtitlePieces.join(' · '),
      badge: 'OBSERVATION · EDITED',
      iconCode: Icons.edit_note.codePoint,
      iconFontFamily: Icons.edit_note.fontFamily,
      destinationPath: '/observations',
      recordId: id,
    );
  }

  static String _truncate(String s, int n) =>
      s.length <= n ? s : '${s.substring(0, n - 1)}…';

  static ObservationDomain _parseDomain(String raw) {
    final lower = raw.toLowerCase();
    return switch (lower) {
      'ssd1' => ObservationDomain.ssd1,
      'ssd2' => ObservationDomain.ssd2,
      'ssd3' => ObservationDomain.ssd3,
      'ssd4' => ObservationDomain.ssd4,
      'ssd5' => ObservationDomain.ssd5,
      'ssd6' => ObservationDomain.ssd6,
      'ssd7' => ObservationDomain.ssd7,
      'ssd8' => ObservationDomain.ssd8,
      'ssd9' => ObservationDomain.ssd9,
      'hlth1' => ObservationDomain.hlth1,
      'hlth2' => ObservationDomain.hlth2,
      'hlth3' => ObservationDomain.hlth3,
      'hlth4' => ObservationDomain.hlth4,
      _ => ObservationDomain.other,
    };
  }

  static ObservationSentiment _parseSentiment(String raw) {
    return switch (raw) {
      'positive' => ObservationSentiment.positive,
      'concern' => ObservationSentiment.concern,
      _ => ObservationSentiment.neutral,
    };
  }
}
