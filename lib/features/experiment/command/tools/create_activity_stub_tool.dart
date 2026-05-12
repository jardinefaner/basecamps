// Quick-create an Activity-Library entry stub. Title + optional
// one-line summary. Domain tags, duration, materials, age
// variants, and the rich-card fields are configured on the
// activity detail screen.

import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CreateActivityStubTool extends CommandTool {
  const CreateActivityStubTool();

  @override
  String get name => 'create_activity_stub';

  @override
  String get description => '''
Spin up an activity-library entry with just a title (+ optional
summary). Domain tags, duration, materials, age variants — all
configured on `/activity-library/:id` later.

Anchor words: "activity,", "new activity,", "library,".

Examples:
  "activity sensory bin"              → title: "Sensory Bin"
  "new activity letter sound circle"  → title: "Letter Sound Circle"
  "activity yoga · 15 min calm-down"
      → title: "Yoga", description: "15 min calm-down"

TITLE: headline-capped, no type prefix, no duration in the title
(duration goes in description or is set later).
''';

  @override
  String get routerSummary =>
      'Quick-create an activity-library stub (title + optional summary).';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'title': <String, dynamic>{'type': 'string'},
          'description': <String, dynamic>{'type': 'string'},
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
      throw StateError('create_activity_stub: title is required');
    }
    final description = (args['description'] as String?)?.trim() ?? '';
    final id = await ref.read(activityLibraryRepositoryProvider).addItem(
          title: title,
          summary: description.isEmpty ? null : description,
        );
    return CommandResult(
      title: title,
      subtitle: description.isEmpty
          ? 'Tap to set domain, duration, materials…'
          : description,
      badge: 'ACTIVITY · DRAFT',
      iconCode: Icons.bookmark_add_outlined.codePoint,
      iconFontFamily: Icons.bookmark_add_outlined.fontFamily,
      destinationPath: '/more/library',
      recordId: id,
    );
  }
}
