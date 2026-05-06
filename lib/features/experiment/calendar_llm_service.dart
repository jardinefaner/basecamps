// LLM-backed "drop bar" for the Calendar experiment — turns short
// natural-language fragments ("field trip aquarium next tues 8 to
// 3") into a structured `CalendarTileDraft` that the calendar
// screen can preview + commit.
//
// The brainstorm's keystone bet: a teacher should be able to type
// the way they THINK ("aquarium thursday with the sunflowers")
// instead of filling out a form. The LLM is the conversion layer.
//
// **v0 scope** — just enough to validate the loop:
//   * One verb only: "create a tile".
//   * Routes through the existing `openai-chat` Supabase Edge
//     Function (so the API key never ships in the client).
//   * Returns a draft; the screen owns the preview + commit UX.
//   * No edit verb, no lookup tools, no voice. All deferred.
//
// If this draft pipeline feels right, the next steps are:
//   * Add `editTile` so the same bar can move/resize tiles.
//   * Add `findAvailableSlot` for "find me a 30-min slot Thursday".
//   * Pipe in voice (Deepgram → text → here).

import 'dart:convert';

import 'package:basecamp/features/ai/openai_client.dart';
import 'package:basecamp/features/experiment/calendar_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// What the LLM produced — a normalised draft of a calendar tile,
/// ready for the screen to inflate into a real `_CalendarTile`
/// (after teacher confirmation). Nullable fields are "the model
/// didn't infer this" → the preview shows them as missing rather
/// than guessed-empty.
class CalendarTileDraft {
  const CalendarTileDraft({
    required this.type,
    required this.date,
    required this.title,
    this.destination,
    this.startTime,
    this.endTime,
    this.theme,
    this.description,
    this.notes,
    this.confidence,
  });

  final CalendarTileType type;
  final DateTime date; // local (not UTC) — the screen normalises
  final String title;
  final String? destination;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final String? theme;
  final String? description;
  final String? notes;

  /// 0.0..1.0, the model's self-rated confidence. Used by the
  /// preview to decide whether to ask the teacher to look closely
  /// (low) or just commit on a single tap (high). Null when the
  /// model didn't return one.
  final double? confidence;

  String summaryFor(BuildContext context) {
    final df = DateFormat.MMMEd();
    final parts = <String>[df.format(date)];
    if (startTime != null && endTime != null) {
      parts.add('${startTime!.format(context)}–${endTime!.format(context)}');
    } else if (startTime != null) {
      parts.add(startTime!.format(context));
    }
    if (destination != null && destination!.isNotEmpty) {
      parts.add(destination!);
    }
    return parts.join(' · ');
  }
}

/// Sentinel for "the model gave us nothing usable." Surface to
/// the user as a short error chip ("I couldn't parse that — try
/// again") rather than a stack trace.
class CalendarLlmException implements Exception {
  const CalendarLlmException(this.message);
  final String message;
  @override
  String toString() => 'CalendarLlmException: $message';
}

/// The drop-bar service. One static method; pure conversion.
class CalendarLlmService {
  CalendarLlmService._();

  /// Convert [input] to a draft tile. The screen passes its
  /// current filter state ([activeType], [activeGroupName]) so
  /// the LLM can DEFAULT to that when the user is ambiguous —
  /// the brainstorm's "filter is the type discriminator" rule.
  ///
  /// [today] is injected so tests can pin a date; production
  /// passes `DateTime.now()`.
  static Future<CalendarTileDraft> draftFromText({
    required String input,
    required DateTime today,
    required CalendarTileType activeType,
    required String activeGroupName,
  }) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const CalendarLlmException('Empty input');
    }

    final body = await OpenAiClient.chat({
      'model': 'gpt-4o-mini',
      'temperature': 0.2,
      'response_format': {'type': 'json_object'},
      'messages': [
        {
          'role': 'system',
          'content': _systemPrompt(
            today: today,
            activeType: activeType,
            activeGroupName: activeGroupName,
          ),
        },
        {'role': 'user', 'content': trimmed},
      ],
    });

    final choices = body['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const CalendarLlmException('Model returned no choices');
    }
    final message = (choices.first as Map<String, dynamic>)['message']
        as Map<String, dynamic>?;
    final content = message?['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      throw const CalendarLlmException('Model returned empty content');
    }

    final parsed = jsonDecode(content) as Map<String, dynamic>;
    return _parseDraft(parsed, today: today, fallbackType: activeType);
  }

  // ——— Prompt + parser ————————————————————————————————————————

  static String _systemPrompt({
    required DateTime today,
    required CalendarTileType activeType,
    required String activeGroupName,
  }) {
    final todayStr = DateFormat('EEEE, MMMM d, y').format(today);
    return '''
You convert short natural-language fragments from an early-childhood teacher
into structured BASECamp calendar tiles.

Context:
  Today is $todayStr.
  Active group filter: $activeGroupName.
  Default tile type when the user is ambiguous: ${activeType.name}.

A "tile" is one of three kinds:
  trip     — an outing somewhere (has a destination)
  event    — an in-program event (no destination, may have a time window)
  dayPlan  — a theme for the whole day (no destination, no time window;
             carries a "theme" field instead of a description)

Return a single JSON object. Required keys:
  "type":  "trip" | "event" | "dayPlan"
  "date":  ISO 8601 date "YYYY-MM-DD" (local time, not UTC).
           Resolve relative phrases like "next tuesday" against the
           "today" above. If the user is silent on the date, default to
           tomorrow.
  "title": short tile label, max 6 words, capitalised like a headline.

Optional keys (omit or use empty string when not in the input):
  "destination": where the trip goes — only for trips
  "startTime":   "HH:MM" 24-hour
  "endTime":     "HH:MM" 24-hour
  "theme":       short theme line — only for dayPlan
  "description": one short sentence
  "notes":       longer teacher notes (usually empty)
  "confidence":  number 0.0..1.0, your self-rated confidence

Inference rules:
  * "field trip" / "trip to X" / "outing" → type "trip"
  * "day" / "theme day" / a single word like "ocean day" → type "dayPlan"
  * Otherwise default to the active type ($activeType.name).
  * Times like "8 to 3" mean 08:00 to 15:00 (school hours, PM bias).
  * Times like "9 to 11" stay AM (within school morning).
  * Don't invent a destination if the user didn't mention one.
  * Don't invent times if the user didn't mention any.

Return ONLY the JSON. No markdown, no commentary.
''';
  }

  static CalendarTileDraft _parseDraft(
    Map<String, dynamic> json, {
    required DateTime today,
    required CalendarTileType fallbackType,
  }) {
    final typeStr = (json['type'] as String?)?.trim().toLowerCase();
    final type = _parseType(typeStr) ?? fallbackType;

    final dateStr = (json['date'] as String?)?.trim();
    final date = _parseDate(dateStr) ?? today.add(const Duration(days: 1));

    final title = (json['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) {
      throw const CalendarLlmException('Model produced no title');
    }

    String? str(String key) {
      final v = json[key];
      if (v is! String) return null;
      final t = v.trim();
      return t.isEmpty ? null : t;
    }

    return CalendarTileDraft(
      type: type,
      date: date,
      title: title,
      destination: str('destination'),
      startTime: _parseTime(str('startTime')),
      endTime: _parseTime(str('endTime')),
      theme: str('theme'),
      description: str('description'),
      notes: str('notes'),
      confidence: (json['confidence'] as num?)?.toDouble(),
    );
  }

  static CalendarTileType? _parseType(String? raw) {
    switch (raw) {
      case 'trip':
        return CalendarTileType.trip;
      case 'event':
        return CalendarTileType.event;
      case 'dayplan':
      case 'day_plan':
      case 'day-plan':
        return CalendarTileType.dayPlan;
    }
    return null;
  }

  static DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    try {
      return DateFormat('yyyy-MM-dd').parseStrict(raw);
    } on FormatException {
      // Tolerate slightly wrong formats — the model occasionally
      // emits "May 12" or "5/12/2026". DateTime.tryParse handles
      // a surprising number of these (incl. ISO with time).
      return DateTime.tryParse(raw);
    }
  }

  static TimeOfDay? _parseTime(String? raw) {
    if (raw == null) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw);
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!);
    final min = int.tryParse(m.group(2)!);
    if (h == null || min == null) return null;
    if (h < 0 || h > 23 || min < 0 || min > 59) return null;
    return TimeOfDay(hour: h, minute: min);
  }
}
