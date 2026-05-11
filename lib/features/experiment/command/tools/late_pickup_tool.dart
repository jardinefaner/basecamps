// Late-pickup row creation tool. Anchors on "late pickup,",
// "late,". Resolves the child against the roster + autofills
// parent + staff name from context.

import 'package:basecamp/database/database.dart' show Child;
import 'package:basecamp/features/adults/adults_repository.dart'
    show currentAdultProvider;
import 'package:basecamp/features/children/children_repository.dart'
    show childrenProvider;
import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:basecamp/features/experiment/late_pickup_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CreateLatePickupTool extends CommandTool {
  const CreateLatePickupTool();

  @override
  String get name => 'create_late_pickup';

  @override
  List<String> get anchors => const [
        'late pickup',
        'late',
        'pickup',
      ];

  @override
  String get description => '''
Log a kid picked up AFTER program closing today. Strong verb
signals: "is late", "picked up late", "running late", "stayed
past closing". Anchor words: "late pickup,", "late,".

Examples:
  "phillip is late" → late pickup
  "legend dawson 6 pm gave reminder card" → late pickup
  "zamir was picked up at 5:45" → late pickup

The TIME, DATE, STAFF NAME, and PARENT NAME are all autofilled
from the system context — don't ask for them. Just pass what
the user actually said:

  * `child_id` — match the named kid against the roster. Use
    the roster id. Match leniently (case-insensitive, first
    name OK). Empty when no confident match (the screen
    surfaces the raw name).
  * `pickup_time` — only when the user named a specific time
    ("6:15"). Otherwise leave empty; the screen stamps "now".
  * `reminder_card_given` — true if the user said anything
    like "reminder card", "card given", "left a note".
  * `notes` — anything else that doesn't fit the structured
    fields.
''';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'child_id': <String, dynamic>{
            'type': 'string',
            'description': 'Roster id; empty when no match.',
          },
          'child_name': <String, dynamic>{
            'type': 'string',
            'description':
                'Display name fallback when child_id is empty. '
                "When child_id matches, use that child's name.",
          },
          'pickup_time': <String, dynamic>{
            'type': 'string',
            'description': 'HH:MM 24h. Empty = now.',
          },
          'reminder_card_given': <String, dynamic>{'type': 'boolean'},
          'notes': <String, dynamic>{'type': 'string'},
        },
        'required': ['child_name'],
      };

  @override
  Future<CommandResult> execute(
    Map<String, dynamic> args,
    Ref ref,
  ) async {
    final children =
        ref.read(childrenProvider).asData?.value ?? const <Child>[];
    final adult = ref.read(currentAdultProvider).asData?.value;
    final staffName = (adult?.name.trim() ?? '').isEmpty
        ? 'Staff'
        : adult!.name.trim();

    final childIdRaw = (args['child_id'] as String?)?.trim() ?? '';
    final childNameRaw = (args['child_name'] as String?)?.trim() ?? '';
    final pickupTimeRaw = (args['pickup_time'] as String?)?.trim() ?? '';
    final reminderCardGiven =
        args['reminder_card_given'] is bool && args['reminder_card_given'] as bool;
    final notes = (args['notes'] as String?)?.trim() ?? '';

    // Resolve the child + autofill parent.
    Child? matched;
    if (childIdRaw.isNotEmpty) {
      final candidates =
          children.where((c) => c.id == childIdRaw).toList();
      if (candidates.isNotEmpty) matched = candidates.first;
    }
    final childDisplayName = matched != null
        ? _displayName(matched)
        : (childNameRaw.isEmpty ? '(unmatched)' : childNameRaw);
    final parentName = matched?.parentName?.trim() ?? '';

    final now = DateTime.now();
    final pickupTime = _parseTime(pickupTimeRaw) ?? TimeOfDay.fromDateTime(now);

    final entry = LateEntry(
      id: '${now.microsecondsSinceEpoch}-${UniqueKey().hashCode}',
      date: DateTime(now.year, now.month, now.day),
      pickupTime: pickupTime,
      childId: matched?.id,
      childName: childDisplayName,
      parentName: parentName,
      reminderCardGiven: reminderCardGiven,
      staffName: staffName,
      notes: notes,
    );
    await ref.read(latePickupsRepoProvider).add(entry);

    final timeLabel =
        TimeOfDay(hour: pickupTime.hour, minute: pickupTime.minute);
    final pieces = <String>[
      '${timeLabel.hour.toString().padLeft(2, '0')}:'
          '${timeLabel.minute.toString().padLeft(2, '0')}',
    ];
    if (parentName.isNotEmpty) pieces.add(parentName);
    if (reminderCardGiven) pieces.add('📩 reminder card');

    return CommandResult(
      title: childDisplayName,
      subtitle: pieces.join(' · '),
      badge: 'LATE PICKUP',
      iconCode: Icons.access_time.codePoint,
      iconFontFamily: Icons.access_time.fontFamily,
      destinationPath: '/late-pickup',
      recordId: entry.id,
    );
  }

  static String _displayName(Child c) {
    final last = (c.lastName ?? '').trim();
    return last.isEmpty
        ? c.firstName.trim()
        : '${c.firstName.trim()} $last';
  }

  static TimeOfDay? _parseTime(String raw) {
    if (raw.isEmpty) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw);
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!);
    final min = int.tryParse(m.group(2)!);
    if (h == null || min == null) return null;
    if (h < 0 || h > 23 || min < 0 || min > 59) return null;
    return TimeOfDay(hour: h, minute: min);
  }
}
