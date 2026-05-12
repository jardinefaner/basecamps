// Quick-create a Theme stub from the Command Center. Title +
// optional description. Dates default to today → today + 7 days
// (one-week placeholder); the teacher adjusts on the theme
// detail screen along with activities + subthemes.

import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:basecamp/features/themes/themes_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CreateThemeStubTool extends CommandTool {
  const CreateThemeStubTool();

  @override
  String get name => 'create_theme_stub';

  @override
  String get description => '''
Spin up a theme with just a name (+ optional one-line notes).
Dates default to today through today+7. The teacher adjusts
dates and adds activities/subthemes on `/themes/:id`.

Anchor words: "theme,", "new theme,", "unit,".

Examples:
  "theme ocean"          → title: "Ocean"
  "new theme winter"     → title: "Winter"
  "theme bugs · k-2 focus"
      → title: "Bugs", description: "k-2 focus"

TITLE: bare subject, headline-capped, no type prefix.
''';

  @override
  String get routerSummary =>
      'Quick-create a theme stub (title + optional one-liner).';

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
      throw StateError('create_theme_stub: title is required');
    }
    final description = (args['description'] as String?)?.trim() ?? '';
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 7));
    final id = await ref.read(themesRepositoryProvider).addTheme(
          name: title,
          startDate: start,
          endDate: end,
          notes: description.isEmpty ? null : description,
        );
    return CommandResult(
      title: title,
      subtitle: description.isEmpty
          ? 'Today → +7 days · tap to set dates'
          : description,
      badge: 'THEME · DRAFT',
      iconCode: Icons.palette_outlined.codePoint,
      iconFontFamily: Icons.palette_outlined.fontFamily,
      destinationPath: '/more/themes',
      recordId: id,
    );
  }
}
