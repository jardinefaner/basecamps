// ObservationsAgent — Phase-2 of agent-per-domain. Wraps the
// existing create + append tools as primitives, adds edit /
// delete / query.

import 'package:basecamp/features/experiment/command/command_agent.dart';
import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:basecamp/features/experiment/command/tools/append_observation_tool.dart';
import 'package:basecamp/features/experiment/command/tools/delete_observation_tool.dart';
import 'package:basecamp/features/experiment/command/tools/edit_observation_tool.dart';
import 'package:basecamp/features/experiment/command/tools/observation_tool.dart';
import 'package:basecamp/features/experiment/command/tools/query_observations_tool.dart';

class ObservationsAgent extends CommandAgent {
  const ObservationsAgent();

  @override
  String get name => 'observations';

  @override
  String get description =>
      'Observations — log notes about kids, append to recent notes, '
      'edit or delete, or look up past notes.';

  @override
  List<String> get anchors => const [
        'note',
        'observation',
        'log',
        'append',
        'also',
        'and',
        'add to that',
        'edit note',
        'edit observation',
        'change note',
        'untag',
        'retag',
        'delete note',
        'remove note',
        'scratch that',
        'find note',
        'look up note',
        'show notes',
        'any notes',
      ];

  @override
  List<CommandTool> get primitives => const [
        CreateObservationTool(),
        AppendObservationTool(),
        EditObservationTool(),
        DeleteObservationTool(),
        QueryObservationsTool(),
      ];

  @override
  String sharedExtractorContext(CommandContext ctx) {
    return '''
Observations agent — shared rules:
  * Tag every named kid via roster ids (look up first names in
    the roster block).
  * Domain codes: SSD1-9, HLTH1-4, OTHER. Pick the closest match
    to what the note describes; don't invent codes.
  * Sentiments: positive | neutral | concern. Default neutral.
  * Append / edit / delete need an `observation_id` from the
    recent-records block above — never invent ids.
''';
  }
}
