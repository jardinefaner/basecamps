// Observation create tool — anchored on "note,", "observation,",
// "log,".

import 'package:basecamp/features/adults/adults_repository.dart'
    show currentAdultProvider;
import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CreateObservationTool extends CommandTool {
  const CreateObservationTool();

  @override
  String get name => 'create_observation';

  @override
  List<String> get anchors => const [
        'observation',
        'note',
        'log',
      ];

  @override
  String get description => '''
Log a NEW teaching-moment note about one or more children.

This is the default tool when the user describes something that
happened today (past or present tense, descriptive, kid-focused)
and there isn't a stronger match (no future date, no late-pickup
verb, no anchor for another tool).

Anchor words: "note,", "observation,", "log,", "log this —".

Examples:
  "note, maya helped phillip tie his shoe"
  "observation: she was crying all morning"
  "log this — lunch was great today, kids loved the carrots"
  "phillip helped maya tie his shoe today"    (no anchor, still routes here)

Domain values (pick the closest BASECamp curriculum slot;
default to OTHER when unsure):
  SSD1 — identity & connection
  SSD2 — emotional awareness
  SSD3 — self-regulation
  SSD4 — empathy
  SSD5 — communication
  SSD6 — problem solving
  SSD7 — independence
  SSD8 — creativity
  SSD9 — curiosity
  HLTH1 — physical activity
  HLTH2 — nutrition
  HLTH3 — rest / hygiene / safety
  HLTH4 — outdoor / nature
  OTHER — anything else

Sentiment: "positive" for things to celebrate, "concern" for
behaviour the teacher would flag, "neutral" otherwise.
''';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'note': <String, dynamic>{
            'type': 'string',
            'description':
                "Clean, classroom-friendly version of the user's "
                'sentence. 1-2 sentences, past tense.',
          },
          'domain': <String, dynamic>{
            'type': 'string',
            'enum': [
              'SSD1', 'SSD2', 'SSD3', 'SSD4', 'SSD5',
              'SSD6', 'SSD7', 'SSD8', 'SSD9',
              'HLTH1', 'HLTH2', 'HLTH3', 'HLTH4', 'OTHER',
            ],
          },
          'sentiment': <String, dynamic>{
            'type': 'string',
            'enum': ['positive', 'neutral', 'concern'],
          },
          'childIds': <String, dynamic>{
            'type': 'array',
            'items': <String, dynamic>{'type': 'string'},
            'description':
                'Roster ids of every child explicitly named. '
                'Empty array when no kid is named.',
          },
        },
        'required': ['note', 'domain', 'sentiment'],
      };

  @override
  Future<CommandResult> execute(
    Map<String, dynamic> args,
    Ref ref,
  ) async {
    final repo = ref.read(observationsRepositoryProvider);
    final domain = _parseDomain((args['domain'] as String?) ?? 'OTHER');
    final sentiment = _parseSentiment(
      (args['sentiment'] as String?) ?? 'neutral',
    );
    final note = (args['note'] as String?)?.trim() ?? '';
    final childIds = (args['childIds'] as List?)
            ?.whereType<String>()
            .toList() ??
        const <String>[];
    final id = await repo.addObservation(
      domains: [domain],
      sentiment: sentiment,
      note: note,
      childIds: childIds,
      authorName: ref.read(currentAdultProvider).asData?.value?.name,
    );
    return CommandResult(
      title: note,
      subtitle:
          '${childIds.isEmpty ? 'no child tagged' : '${childIds.length} kid(s)'} · '
          '${domain.code} · ${sentiment.name}',
      badge: 'OBSERVATION',
      iconCode: Icons.edit_note_outlined.codePoint,
      iconFontFamily: Icons.edit_note_outlined.fontFamily,
      destinationPath: '/observations',
      recordId: id,
    );
  }

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
    return switch (raw.toLowerCase()) {
      'positive' => ObservationSentiment.positive,
      'concern' => ObservationSentiment.concern,
      _ => ObservationSentiment.neutral,
    };
  }
}
