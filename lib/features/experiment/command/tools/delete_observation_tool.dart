// Delete (soft-delete) an observation by id from the recent-
// records window. Repo's `deleteObservation` stamps `deletedAt`,
// the row stays restorable, and the cloud row syncs the delete.

import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeleteObservationTool extends CommandTool {
  const DeleteObservationTool();

  @override
  String get name => 'delete_observation';

  @override
  String get description => '''
Soft-delete an observation referenced from the recent-records
window. Row stamps `deletedAt`, sync engine propagates the
deletion to other devices. Restorable from the trash UI.

Examples:
  "delete that note"          → observation_id from recents
  "remove the last one"       → most-recent observation id
  "scratch that"              → same

NEVER guess an id that isn't in the recent-records block. If
the user names an older observation, route to query first.
''';

  @override
  String get routerSummary => 'Delete a recent observation.';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'observation_id': <String, dynamic>{
            'type': 'string',
            'description': 'Id from the recent-records list.',
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
      throw StateError('delete_observation: observation_id required');
    }
    await ref.read(observationsRepositoryProvider).deleteObservation(id);
    return CommandResult(
      title: 'Observation deleted',
      subtitle: 'Restorable from the trash',
      badge: 'OBSERVATION · DELETED',
      iconCode: Icons.delete_outline.codePoint,
      iconFontFamily: Icons.delete_outline.fontFamily,
      destinationPath: '/observations',
      recordId: id,
    );
  }
}
