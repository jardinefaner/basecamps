// LLM-backed parser for the late-pickup log experiment. Same
// pattern as `calendar_llm_service.dart`: a teacher types a
// fragment ("phillip is late, gave reminder card"), the model
// returns a structured row that lands on the log sheet.
//
// What the LLM autofills:
//   * Date — today (injected; never asked).
//   * Pickup time — now (injected; only overridden if the
//     teacher names a different time).
//   * Staff name — the signed-in adult (injected; never asked).
//   * Parent name — looked up from the matched child's profile;
//     only fallback is what the teacher typed.
//
// What the LLM extracts from the input:
//   * Child match — fuzzy lookup against the program's roster.
//     The teacher might type "phillip", "phillip stewart", or
//     "Phil S.". Lower-case roster names and substring-match.
//   * Reminder card given — boolean. Triggers on "reminder
//     card", "card given", "left a card", etc.
//   * Notes — anything else the teacher said that isn't part
//     of the structured fields.

import 'dart:convert';

import 'package:basecamp/features/ai/openai_client.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// One row on the log sheet, freshly parsed. Pure data — the
/// screen converts this into its private `_LatePickupEntry` with
/// a stable id when the teacher confirms.
class LatePickupDraft {
  const LatePickupDraft({
    required this.date,
    required this.pickupTime,
    required this.childId,
    required this.childName,
    required this.parentName,
    required this.reminderCardGiven,
    required this.staffName,
    this.notes,
  });

  final DateTime date; // local midnight
  final TimeOfDay pickupTime;

  /// Resolved child id (when the LLM matched against the roster);
  /// null when the teacher named a child the model couldn't find.
  /// Display still renders [childName].
  final String? childId;
  final String childName;
  final String parentName;
  final bool reminderCardGiven;
  final String staffName;
  final String? notes;
}

class LatePickupLlmException implements Exception {
  const LatePickupLlmException(this.message);
  final String message;
  @override
  String toString() => 'LatePickupLlmException: $message';
}

/// Roster row the screen passes in. Just enough to disambiguate
/// the match — `id` to stamp on the draft, `firstName`/`lastName`
/// for matching + display, `parentName` for the autofill.
class LatePickupRosterChild {
  const LatePickupRosterChild({
    required this.id,
    required this.firstName,
    this.lastName,
    this.parentName,
  });

  final String id;
  final String firstName;
  final String? lastName;
  final String? parentName;

  String get displayName {
    final l = (lastName ?? '').trim();
    if (l.isEmpty) return firstName.trim();
    return '${firstName.trim()} $l';
  }
}

class LatePickupLlmService {
  LatePickupLlmService._();

  /// Convert [input] into a draft log row. Surface-injected
  /// context (today, now, [staffName]) means the teacher only
  /// has to mention what's NEW in this row — typically the
  /// child's name plus optional reminder-card / notes.
  static Future<LatePickupDraft> draftFromText({
    required String input,
    required DateTime now,
    required String staffName,
    required List<LatePickupRosterChild> roster,
  }) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const LatePickupLlmException('Empty input');
    }
    if (roster.isEmpty) {
      throw const LatePickupLlmException(
        'No children loaded yet — try again in a moment.',
      );
    }

    final body = await OpenAiClient.chat({
      'model': 'gpt-4o-mini',
      'temperature': 0.1,
      'response_format': {'type': 'json_object'},
      'messages': [
        {
          'role': 'system',
          'content': _systemPrompt(
            now: now,
            staffName: staffName,
            roster: roster,
          ),
        },
        {'role': 'user', 'content': trimmed},
      ],
    });

    final choices = body['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const LatePickupLlmException('Model returned no choices');
    }
    final message = (choices.first as Map<String, dynamic>)['message']
        as Map<String, dynamic>?;
    final content = message?['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      throw const LatePickupLlmException('Model returned empty content');
    }
    final parsed = jsonDecode(content) as Map<String, dynamic>;
    return _resolveDraft(
      parsed,
      now: now,
      staffName: staffName,
      roster: roster,
    );
  }

  static String _systemPrompt({
    required DateTime now,
    required String staffName,
    required List<LatePickupRosterChild> roster,
  }) {
    final today = DateFormat('EEEE, MMMM d, y').format(now);
    final timeNow = DateFormat('h:mm a').format(now);
    final rosterLines = roster
        .take(150) // hard cap so the prompt stays sane on huge programs
        .map(
          (c) => '  • ${c.displayName} '
              '${c.parentName == null || c.parentName!.isEmpty ? '' : '(parent: ${c.parentName})'} '
              '[id: ${c.id}]',
        )
        .join('\n');
    return '''
You convert a short note from a BASECamp staff member into a structured
late-pickup log row. The staff member usually just names the kid (e.g.
"phillip is late") plus optional notes about a reminder card or context.

Context (already known — do NOT echo back unless the staff member overrode it):
  Today: $today
  Time now: $timeNow
  Staff member: $staffName

Children roster (match the staff member's input against these — fuzzy
matching is OK; first-name only is OK; case insensitive):
$rosterLines

Return a single JSON object with these keys:

  "childId":   the [id: ...] from the roster line that matches. Empty
               string if you can't confidently match.
  "childName": the matched child's display name (full, with last name
               if available). Falls back to whatever the staff member
               literally typed when no match.
  "parentName": the parent name from the matched roster line. Empty
               string when the matched child has no parent on file.
  "pickupTime": "HH:MM" 24-hour. DEFAULT to the "Time now" above unless
                the staff explicitly named a different time
                ("she got picked up at 6:15", "around 5:45").
  "reminderCardGiven": boolean. True when the staff said anything
                       like "reminder card", "card given", "left a
                       card", "tagged with the slip". False otherwise.
  "notes":     short free-text. Only what's NOT already captured in the
               structured fields above. Empty string when the staff
               just named the kid (typical case).

Rules:
  * Match leniently. "phillip" → "Phillip Stewart" if there's only one
    Phillip; ambiguous matches → empty childId so the screen can
    surface a chooser.
  * NEVER invent a child id. Use only ids in the roster above.
  * Don't fill notes with restated structured info — keep it for the
    bits that don't fit a column.

Return ONLY the JSON. No markdown, no commentary.
''';
  }

  static LatePickupDraft _resolveDraft(
    Map<String, dynamic> json, {
    required DateTime now,
    required String staffName,
    required List<LatePickupRosterChild> roster,
  }) {
    String str(String key) => (json[key] as String?)?.trim() ?? '';

    final childId = str('childId').isEmpty ? null : str('childId');
    final matched = childId == null
        ? null
        : roster.firstWhere(
            (c) => c.id == childId,
            orElse: () => roster.first,
          );
    // If the model returned an unknown id, treat as no-match.
    final resolvedChild =
        matched != null && matched.id == childId ? matched : null;

    final childName = resolvedChild?.displayName ??
        (str('childName').isEmpty
            ? '(unmatched)'
            : str('childName'));

    final parentName = resolvedChild?.parentName?.trim().isNotEmpty == true
        ? resolvedChild!.parentName!.trim()
        : str('parentName');

    final timeStr = str('pickupTime');
    final pickupTime = _parseTime(timeStr) ?? TimeOfDay.fromDateTime(now);

    final reminder = json['reminderCardGiven'];
    final reminderBool = reminder is bool
        ? reminder
        : (reminder is String && reminder.toLowerCase() == 'true');

    final notesStr = str('notes');

    return LatePickupDraft(
      date: DateTime(now.year, now.month, now.day),
      pickupTime: pickupTime,
      childId: resolvedChild?.id,
      childName: childName,
      parentName: parentName,
      reminderCardGiven: reminderBool,
      staffName: staffName,
      notes: notesStr.isEmpty ? null : notesStr,
    );
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

