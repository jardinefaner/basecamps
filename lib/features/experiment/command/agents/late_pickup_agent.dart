// LatePickupAgent — Phase-2 of agent-per-domain. Wraps the
// existing create primitive, adds edit / delete / query.

import 'package:basecamp/features/experiment/command/command_agent.dart';
import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:basecamp/features/experiment/command/tools/delete_late_pickup_tool.dart';
import 'package:basecamp/features/experiment/command/tools/edit_late_pickup_tool.dart';
import 'package:basecamp/features/experiment/command/tools/late_pickup_tool.dart';
import 'package:basecamp/features/experiment/command/tools/query_late_pickups_tool.dart';

class LatePickupAgent extends CommandAgent {
  const LatePickupAgent();

  @override
  String get name => 'late_pickup';

  @override
  String get description =>
      'Late pickup — log a kid picked up after closing, mark '
      'reminder card given, edit / delete entries, or look up '
      "today's list.";

  @override
  List<String> get anchors => const [
        'late pickup',
        'late',
        'pickup',
        'mark card given',
        'reminder card',
        'edit pickup',
        'delete pickup',
        'remove pickup',
        'whos late',
        'show pickups',
      ];

  @override
  List<CommandTool> get primitives => const [
        CreateLatePickupTool(),
        EditLatePickupTool(),
        DeleteLatePickupTool(),
        QueryLatePickupsTool(),
      ];

  @override
  String sharedExtractorContext(CommandContext ctx) {
    return '''
Late-pickup agent — shared rules:
  * Resolve the named kid against the roster's first names. Use
    the roster id for child_id; fall back to child_name only
    when the lookup misses.
  * Pickup time is HH:MM 24-hour. Missing time → "now" (the
    create primitive auto-stamps the current time).
  * `reminder_card_given` true if the user said anything like
    "reminder card", "card given", "left a note".
''';
  }
}
