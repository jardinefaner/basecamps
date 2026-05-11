// Append-to-last-observation tool. Anchors on "append,",
// "also,", and detects continuation phrases via the recent-
// records context in the system prompt.

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppendObservationTool extends CommandTool {
  const AppendObservationTool();

  @override
  String get name => 'append_observation';

  @override
  List<String> get anchors => const [
        'append',
        'also',
        'and',
        'add to that',
      ];

  @override
  String get description => '''
APPEND text to one of the recent observations listed in the
system context above. Use when the user's fragment is a
CONTINUATION of a recent note:
  * Opens with a connective: "and", "then", "also", "after that"
  * Pronoun ("he", "she", "they") matches a recent observation's
    tagged kid
  * Re-names the same kid + adds new detail rather than starting
    fresh

Anchor words: "append,", "also,", "and,", "add to that,".

Examples (assuming a recent observation about Phillip exists):
  "and they were laughing the whole time" → append
  "he kept doing it after circle too" → append
  "she shared with maya after that" → append (+ tag Maya)

If NO recent observation matches the subject, or the user is
clearly starting a fresh story, use `create_observation`
instead.

NEVER invent an `observation_id` that isn't listed in the
recent-records block above.
''';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'observation_id': <String, dynamic>{
            'type': 'string',
            'description': 'Id from the recent-records list.',
          },
          'append_note': <String, dynamic>{
            'type': 'string',
            'description':
                'Sentence(s) to append. Lightly cleaned, past '
                'tense, no filler. Do not restate existing note.',
          },
          'add_child_ids': <String, dynamic>{
            'type': 'array',
            'items': <String, dynamic>{'type': 'string'},
            'description':
                'Newly-mentioned roster ids not already on the '
                'observation. Empty when no new kid introduced.',
          },
        },
        'required': ['observation_id', 'append_note'],
      };

  @override
  Future<CommandResult> execute(
    Map<String, dynamic> args,
    Ref ref,
  ) async {
    final id = (args['observation_id'] as String?)?.trim() ?? '';
    final appendNote = (args['append_note'] as String?)?.trim() ?? '';
    final addChildIds = (args['add_child_ids'] as List?)
            ?.whereType<String>()
            .toList() ??
        const <String>[];
    if (id.isEmpty || appendNote.isEmpty) {
      throw StateError('append_observation: missing required args');
    }

    final repo = ref.read(observationsRepositoryProvider);
    final db = ref.read(databaseProvider);

    // Pull the existing observation + its tagged children. No
    // public `byId` exists today; query Drift directly with a
    // narrow SELECT. Cheaper than adding a one-call helper for
    // a Lab tool that may or may not survive promotion.
    final existing = await (db.select(db.observations)
          ..where((o) => o.id.equals(id)))
        .getSingleOrNull();
    if (existing == null) {
      throw StateError('append_observation: observation not found');
    }
    final taggedChildren = await repo.childrenForObservation(id);
    final existingChildIds =
        taggedChildren.map((c) => c.id).toList();

    final mergedNote = '${existing.note} $appendNote'
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final mergedChildIds = <String>{
      ...existingChildIds,
      ...addChildIds,
    }.toList();

    await repo.updateObservation(
      id: id,
      note: mergedNote,
      childIds: mergedChildIds,
    );

    return CommandResult(
      title: '+ $appendNote',
      subtitle: 'Appended to: '
          '"${existing.note.length > 60 ? '${existing.note.substring(0, 60)}…' : existing.note}"',
      badge: 'APPEND',
      iconCode: Icons.note_add_outlined.codePoint,
      iconFontFamily: Icons.note_add_outlined.fontFamily,
      destinationPath: '/observations',
      recordId: id,
    );
  }
}
