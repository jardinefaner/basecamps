// CalendarAgent — the first concrete agent in the agent-per-domain
// architecture (Phase 1).
//
// Owns the full CRUD surface for calendar tiles. Today: create +
// edit. Delete + query land in Phase 1b once the routing layer
// is solid. Replaces the standalone `CreateCalendarTileTool`
// registration; the dispatcher routes calendar inputs through
// this agent, which picks between its internal primitives.

import 'package:basecamp/features/experiment/command/command_agent.dart';
import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:basecamp/features/experiment/command/tools/calendar_tile_tool.dart';
import 'package:basecamp/features/experiment/command/tools/edit_calendar_tile_tool.dart';

class CalendarAgent extends CommandAgent {
  const CalendarAgent();

  @override
  String get name => 'calendar';

  @override
  String get description =>
      'Calendar — schedule trips, events, or themed day plans; '
      'edit or move existing tiles.';

  @override
  List<String> get anchors => const [
        'trip',
        'field trip',
        'event',
        'schedule event',
        'day plan',
        'theme day',
        'calendar',
        'edit trip',
        'move trip',
        'reschedule',
      ];

  @override
  List<CommandTool> get primitives => const [
        CreateCalendarTileTool(),
        EditCalendarTileTool(),
      ];

  @override
  String sharedExtractorContext(CommandContext ctx) {
    // The calendar agent's primitives share heavy use of the
    // group roster. Inject a one-line reminder here so each
    // primitive's prompt doesn't have to re-explain it — the
    // dispatcher prepends this to every primitive's stage-2
    // system prompt.
    return '''
Calendar agent — shared rules:
  * `group_names` / `group_name` use EXACT roster spellings.
    Plural-tolerant on the execute side, but emit what the
    roster says.
  * Dates ALWAYS come from the calendar lookup, never computed.
  * "for everyone" / "all groups" expands to every group in
    the roster, in roster order.
''';
  }
}
