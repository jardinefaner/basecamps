// Delete (soft-delete) a late-pickup row. Repo's `remove` stamps
// deletedAt; the row stays restorable and syncs.

import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:basecamp/features/experiment/late_pickup_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeleteLatePickupTool extends CommandTool {
  const DeleteLatePickupTool();

  @override
  String get name => 'delete_late_pickup';

  @override
  String get description => '''
Soft-delete a late-pickup row. Use when the user wants to undo
an erroneously logged pickup:

  "scratch that pickup"   → target_id from recent records
  "remove phillip's late pickup today"
                         → target_child_name: "Phillip"
''';

  @override
  String get routerSummary => 'Delete (undo) a late-pickup entry.';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'target_id': <String, dynamic>{'type': 'string'},
          'target_child_name': <String, dynamic>{'type': 'string'},
        },
      };

  @override
  Future<CommandResult> execute(
    Map<String, dynamic> args,
    Ref ref,
  ) async {
    final targetId = (args['target_id'] as String?)?.trim() ?? '';
    final targetChild =
        (args['target_child_name'] as String?)?.trim().toLowerCase() ?? '';

    final entries = await ref.read(lateEntriesProvider.future);
    LateEntry? target;
    if (targetId.isNotEmpty) {
      target = entries.where((e) => e.id == targetId).firstOrNull;
    }
    if (target == null && targetChild.isNotEmpty) {
      final today = DateTime.now();
      final candidates = entries.where((e) {
        final sameDay = e.date.year == today.year &&
            e.date.month == today.month &&
            e.date.day == today.day;
        return sameDay && e.childName.toLowerCase().contains(targetChild);
      }).toList();
      if (candidates.length == 1) target = candidates.first;
      else if (candidates.length > 1) {
        throw StateError(
          'delete_late_pickup: $targetChild matches multiple pickups today.',
        );
      }
    }
    if (target == null) {
      throw StateError('delete_late_pickup: no pickup matched.');
    }
    await ref.read(latePickupsRepoProvider).remove(target.id);

    return CommandResult(
      title: 'Deleted · ${target.childName}',
      subtitle: 'Restorable from the trash',
      badge: 'LATE PICKUP · DELETED',
      iconCode: Icons.delete_outline.codePoint,
      iconFontFamily: Icons.delete_outline.fontFamily,
      destinationPath: '/late-pickup',
      recordId: target.id,
    );
  }
}
