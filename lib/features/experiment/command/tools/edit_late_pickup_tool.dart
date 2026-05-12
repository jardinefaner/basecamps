// Edit-a-late-pickup primitive. Mark the reminder card as given,
// change the pickup time, edit notes, or update the parent name.
// Target is the most-recent late pickup id from the recent-records
// window OR a child-name match against today's entries.

import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:basecamp/features/experiment/late_pickup_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EditLatePickupTool extends CommandTool {
  const EditLatePickupTool();

  @override
  String get name => 'edit_late_pickup';

  @override
  String get description => '''
Edit a late-pickup row. Use when the user wants to update a
pickup they (or another staff) just logged:

  "mark reminder card given"               → reminder_card_given: true
  "actually it was 6:15 not 5:45"          → pickup_time: "18:15"
  "add a note: dad said sorry"             → notes: "Dad said sorry"
  "change the parent to grandma"           → parent_name: "Grandma"

Identify the target ONE of two ways:
  * `target_id` — from the recent-records window above
  * `target_child_name` — when the user names the kid in today's
    late-pickup list ("update phillip's late pickup")
''';

  @override
  String get routerSummary =>
      'Edit a late-pickup row (mark card given, fix time, add note).';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'target_id': <String, dynamic>{'type': 'string'},
          'target_child_name': <String, dynamic>{'type': 'string'},
          'reminder_card_given': <String, dynamic>{'type': 'boolean'},
          'pickup_time': <String, dynamic>{
            'type': 'string',
            'description': 'HH:MM 24h. Empty = leave alone.',
          },
          'parent_name': <String, dynamic>{'type': 'string'},
          'notes': <String, dynamic>{'type': 'string'},
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
        return sameDay &&
            e.childName.toLowerCase().contains(targetChild);
      }).toList();
      if (candidates.length == 1) target = candidates.first;
      else if (candidates.length > 1) {
        throw StateError(
          'edit_late_pickup: $targetChild matches ${candidates.length} '
          'pickups today. Use target_id from recent records.',
        );
      }
    }
    if (target == null) {
      throw StateError('edit_late_pickup: no pickup matched.');
    }

    final reminder = args['reminder_card_given'] is bool
        ? args['reminder_card_given'] as bool
        : target.reminderCardGiven;
    final pickupTime = _parseTime(args['pickup_time'] as String?) ??
        target.pickupTime;
    final parentName = (args['parent_name'] as String?)?.trim();
    final notes = (args['notes'] as String?)?.trim();

    final mutated = LateEntry(
      id: target.id,
      date: target.date,
      pickupTime: pickupTime,
      childId: target.childId,
      childName: target.childName,
      parentName:
          parentName?.isNotEmpty == true ? parentName! : target.parentName,
      reminderCardGiven: reminder,
      staffName: target.staffName,
      notes: notes?.isNotEmpty == true ? notes! : target.notes,
    );
    await ref.read(latePickupsRepoProvider).update(mutated);

    final pieces = <String>[
      '${pickupTime.hour.toString().padLeft(2, '0')}:'
          '${pickupTime.minute.toString().padLeft(2, '0')}',
    ];
    if (reminder) pieces.add('📩 card given');
    if (parentName?.isNotEmpty == true) pieces.add(parentName!);

    return CommandResult(
      title: 'Updated · ${mutated.childName}',
      subtitle: pieces.join(' · '),
      badge: 'LATE PICKUP · EDITED',
      iconCode: Icons.edit.codePoint,
      iconFontFamily: Icons.edit.fontFamily,
      destinationPath: '/late-pickup',
      recordId: mutated.id,
    );
  }

  static TimeOfDay? _parseTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!);
    final min = int.tryParse(m.group(2)!);
    if (h == null || min == null) return null;
    if (h < 0 || h > 23 || min < 0 || min > 59) return null;
    return TimeOfDay(hour: h, minute: min);
  }
}
