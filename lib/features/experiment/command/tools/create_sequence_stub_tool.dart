// Quick-create a Lesson Sequence stub from the Command Center.
// Two-field create: title + optional description. Everything
// else (items, durations, theme, core question, phase, color,
// engine notes) is configured later on `/sequences/:id`.

import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:basecamp/features/lesson_sequences/lesson_sequences_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CreateSequenceStubTool extends CommandTool {
  const CreateSequenceStubTool();

  @override
  String get name => 'create_sequence_stub';

  @override
  String get description => '''
Spin up a lesson sequence with JUST a title (+ optional one-line
description). Everything else — items, durations, theme link,
core question, phase, color — is configured on the sequence's
detail screen later.

Anchor words: "sequence,", "new sequence,", "lesson sequence,".

Examples:
  "sequence letter a"                  → title: "Letter A"
  "new sequence ocean life"            → title: "Ocean Life"
  "sequence: feelings · social-emotional unit"
      → title: "Feelings", description: "social-emotional unit"

TITLE rules:
  * Headline-capped, max ~6 words.
  * Drop the type prefix ("sequence:", "new sequence").
  * Drop trailing context ("on Monday", "for sunflowers") — that
    belongs on the items, not the sequence.
''';

  @override
  String get routerSummary =>
      'Quick-create a lesson-sequence stub (title + optional description).';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'title': <String, dynamic>{
            'type': 'string',
            'description': 'Bare subject only — no type prefix.',
          },
          'description': <String, dynamic>{
            'type': 'string',
            'description': 'Optional one-liner. Empty if none.',
          },
        },
        'required': ['title'],
      };

  @override
  Future<CommandResult> execute(
    Map<String, dynamic> args,
    Ref ref,
  ) async {
    final title = (args['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) {
      throw StateError('create_sequence_stub: title is required');
    }
    final description = (args['description'] as String?)?.trim() ?? '';
    final id = await ref.read(lessonSequencesRepositoryProvider).addSequence(
          name: title,
          description: description.isEmpty ? null : description,
        );
    return CommandResult(
      title: title,
      subtitle: description.isEmpty
          ? 'Tap to configure items, theme, color…'
          : description,
      badge: 'SEQUENCE · DRAFT',
      iconCode: Icons.layers_outlined.codePoint,
      iconFontFamily: Icons.layers_outlined.fontFamily,
      destinationPath: '/more/sequences/$id',
      recordId: id,
    );
  }
}
