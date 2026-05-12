// QuickCreateAgent — universal "title + description, refine
// later" surface. Spins up planning-tab rows (sequences, themes,
// activity-library entries) with the absolute minimum the row
// needs to exist; everything else lives on the row's detail
// screen so a teacher can keep typing instead of context-
// switching mid-thought.

import 'package:basecamp/features/experiment/command/command_agent.dart';
import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:basecamp/features/experiment/command/tools/create_activity_stub_tool.dart';
import 'package:basecamp/features/experiment/command/tools/create_sequence_stub_tool.dart';
import 'package:basecamp/features/experiment/command/tools/create_theme_stub_tool.dart';

class QuickCreateAgent extends CommandAgent {
  const QuickCreateAgent();

  @override
  String get name => 'quick_create';

  @override
  String get description =>
      'Quick-create — spin up a sequence / theme / activity '
      'with just a title + description; refine on the detail '
      'screen later.';

  @override
  List<String> get anchors => const [
        'sequence',
        'new sequence',
        'lesson sequence',
        'theme',
        'new theme',
        'unit',
        'activity',
        'new activity',
        'library',
      ];

  @override
  List<CommandTool> get primitives => const [
        CreateSequenceStubTool(),
        CreateThemeStubTool(),
        CreateActivityStubTool(),
      ];

  @override
  String sharedExtractorContext(CommandContext ctx) {
    return '''
Quick-create agent — shared rules:
  * Pick the primitive that matches the user's phrasing.
    "sequence" / "lesson sequence" → create_sequence_stub
    "theme" / "unit" → create_theme_stub
    "activity" / "library" → create_activity_stub
  * Two-field create: `title` is required, `description` is
    optional. EVERY OTHER FIELD (dates, items, domain tags,
    materials, duration) is deferred to the row's detail
    screen — never emit them here.
  * Title: bare subject, headline-capped, no type prefix
    ("sequence:", "new", "theme on"), no trailing context
    ("for sunflowers", "on Monday").
  * Description: free-form one-liner; empty when the user
    didn't supply one. Don't invent context.
''';
  }
}
