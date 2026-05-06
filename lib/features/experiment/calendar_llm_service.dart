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
    this.groupNames = const <String>[],
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

  /// Group names the model picked from the roster — empty when
  /// the teacher didn't mention any group, one when they named a
  /// single group ("...with the sunflowers"), MULTIPLE when they
  /// named several ("...for sunflowers and acorns"). The screen
  /// fans out one tile per resolved group on confirm; the active
  /// filter is the fallback when this list is empty.
  final List<String> groupNames;

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
    if (groupNames.isNotEmpty) {
      // Surface the fan-out so the teacher sees BEFORE confirming
      // that this single sentence will mint multiple tiles. The
      // preview chip says "...for Sunflowers + Acorns" instead
      // of silently splitting on confirm.
      parts.add('for ${groupNames.join(' + ')}');
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

/// One row produced by [CalendarLlmService.draftItinerary]. Pure
/// data — the screen converts these into its private
/// `_ItineraryBlock` objects (with stable ids) so regenerate
/// flows can dedupe rather than wipe.
class ItineraryBlockDraft {
  const ItineraryBlockDraft({
    required this.time,
    required this.title,
    this.description,
  });

  final TimeOfDay time;
  final String title;
  final String? description;
}

/// Inputs the screen passes to [CalendarLlmService.draftItinerary].
/// Bundled into a record so the call site doesn't grow a 7-arg
/// signature as we add fields (audience age, language, etc.).
class ItineraryDraftRequest {
  const ItineraryDraftRequest({
    required this.type,
    required this.title,
    this.destination,
    this.theme,
    this.startTime,
    this.endTime,
    this.audienceAgeLabel,
  });

  final CalendarTileType type;
  final String title;
  final String? destination;
  final String? theme;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;

  /// e.g. "3-5 yrs" — used to bias age-appropriate blocks.
  final String? audienceAgeLabel;
}

/// The drop-bar service. One static method; pure conversion.
class CalendarLlmService {
  CalendarLlmService._();

  /// Convert [input] to a draft tile. The screen passes its
  /// current filter state ([activeType], [activeGroupName]) so
  /// the LLM can DEFAULT to that when the user is ambiguous —
  /// the brainstorm's "filter is the type discriminator" rule.
  ///
  /// [availableGroups] is the full roster of group names the
  /// teacher could mean. The model picks one when the user names
  /// it ("with the sunflowers") and falls through to the active
  /// group otherwise. Without this, "sunflowers" in the input
  /// would silently land the tile on whatever filter happened to
  /// be active — exactly the bug the user reported.
  ///
  /// [today] is injected so tests can pin a date; production
  /// passes `DateTime.now()`.
  static Future<CalendarTileDraft> draftFromText({
    required String input,
    required DateTime today,
    required CalendarTileType activeType,
    required String activeGroupName,
    required List<String> availableGroups,
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
            availableGroups: availableGroups,
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

  /// Generate the body of a tile — itinerary blocks for trips,
  /// schedule blocks for day plans. Both flavors return the same
  /// shape (timed list of titled blocks); the prompt branches on
  /// [ItineraryDraftRequest.type] so a trip gets a "leave / arrive
  /// / activity / snack / return" arc and a day plan gets a
  /// classroom day shape ("morning circle / art / outside / story").
  static Future<List<ItineraryBlockDraft>> draftItinerary(
    ItineraryDraftRequest req,
  ) async {
    final body = await OpenAiClient.chat({
      'model': 'gpt-4o-mini',
      'temperature': 0.4,
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': _itinerarySystemPrompt(req)},
        {'role': 'user', 'content': _itineraryUserPrompt(req)},
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
    final raw = parsed['blocks'];
    if (raw is! List || raw.isEmpty) {
      throw const CalendarLlmException('No blocks in response');
    }
    final out = <ItineraryBlockDraft>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final time = _parseTime(
        (entry['time'] as String?)?.trim(),
      );
      final title = (entry['title'] as String?)?.trim();
      if (time == null || title == null || title.isEmpty) continue;
      final desc = (entry['description'] as String?)?.trim();
      out.add(ItineraryBlockDraft(
        time: time,
        title: title,
        description: (desc == null || desc.isEmpty) ? null : desc,
      ));
    }
    if (out.isEmpty) {
      throw const CalendarLlmException('All blocks failed to parse');
    }
    // Sort by time so the rendered list reads top-to-bottom in
    // wall-clock order, regardless of model output order.
    out.sort((a, b) {
      final am = a.time.hour * 60 + a.time.minute;
      final bm = b.time.hour * 60 + b.time.minute;
      return am.compareTo(bm);
    });
    return out;
  }

  // ——— Prompt + parser ————————————————————————————————————————

  static String _systemPrompt({
    required DateTime today,
    required CalendarTileType activeType,
    required String activeGroupName,
    required List<String> availableGroups,
  }) {
    final todayStr = DateFormat('EEEE, MMMM d, y').format(today);
    final groupRoster = availableGroups.isEmpty
        ? '(none)'
        : availableGroups.map((g) => '"$g"').join(', ');
    return '''
You convert short natural-language fragments from an early-childhood teacher
into structured BASECamp calendar tiles.

Context:
  Today is $todayStr.
  Active group filter: $activeGroupName.
  Default tile type when the user is ambiguous: ${activeType.name}.
  All groups in this program: $groupRoster.

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
  "title": JUST the subject — bare and short.

The TITLE is the most important thing to get right. The UI already
shows the type icon, the type label ("TRIP" / "EVENT" / "DAY PLAN"),
the date, and the destination as separate fields — so the title must
NOT repeat any of those. The title is just the subject of the tile.

Good titles:
  Input "field trip to the aquarium tuesday" → title "Aquarium"
  Input "pajama day friday"                  → title "Pajama Day"
  Input "pizza party 11:30"                  → title "Pizza Party"
  Input "ocean theme thursday"               → title "Ocean"
  Input "trip to the zoo with the sunflowers"→ title "Zoo"

Bad titles (don't do these):
  "Field Trip to Aquarium"     ← "Field Trip to" is redundant
  "Pajama Day on Friday"       ← "on Friday" is redundant
  "Trip — Aquarium"            ← prefix is redundant
  "Aquarium Field Trip"        ← suffix is redundant
  "Aquarium (Sunflowers)"      ← group is shown elsewhere

Strip phrases like "field trip to", "trip to", "going to",
"event:", "day:", and trailing dates / group names. Keep just the
proper-noun-ish subject, capitalised like a headline, max 4 words.

Optional keys (omit or use empty string when not in the input):
  "destination": where the trip goes — only for trips. Same noun
                 as the title is fine ("Aquarium" / "Aquarium").
  "startTime":   "HH:MM" 24-hour
  "endTime":     "HH:MM" 24-hour
  "theme":       short theme line — only for dayPlan, can match title
  "description": one short sentence
  "notes":       longer teacher notes (usually empty)
  "groupNames":  array of zero or more group names from the roster
                 above, EXACT spelling (no abbreviations, no
                 plural/singular swaps). Use this when the user
                 names one or MORE groups: "for sunflowers" → one
                 entry; "for sunflowers and acorns" → two entries.

                 SPECIAL CASE — when the user says "all groups",
                 "everyone", "everybody", "all classes", "all kids",
                 "all of them", "for all", "with all", "with the
                 whole school", "everyone is going" — return the
                 ENTIRE roster (every name listed in "All groups in
                 this program" above). Don't return an empty array;
                 don't return just one. The teacher is telling you
                 to fan out across every group.

                 SPECIAL CASE — "both groups" / "both classes" →
                 return both names IF AND ONLY IF the roster has
                 exactly two groups; otherwise fall back to empty.

                 Empty array (or omit) when the user didn't name a
                 group AT ALL, OR when they only mentioned the
                 active group ($activeGroupName) — there's nothing
                 to override in that case. The screen fans out one
                 tile per group when this list has more than one
                 entry, so a single sentence "field trip aquarium
                 for sunflowers and acorns tuesday" creates TWO
                 tiles, both on Tuesday, both for the aquarium.
  "confidence":  number 0.0..1.0, your self-rated confidence

Inference rules:
  * "field trip" / "trip to X" / "outing" → type "trip"
  * "day" / "theme day" / a single word like "ocean day" → type "dayPlan"
  * Otherwise default to the active type ($activeType.name).
  * Times like "8 to 3" mean 08:00 to 15:00 (school hours, PM bias).
  * Times like "9 to 11" stay AM (within school morning).
  * "with the sunflowers" / "for sunflowers" / "sunflowers' " etc.
    → groupNames: ["Sunflowers"]. "for sunflowers AND acorns" /
    "with sunflowers + acorns" / "the sunflowers and acorns are
    going" → groupNames: ["Sunflowers", "Acorns"]. Match leniently
    (case-insensitive, plural/singular tolerant) but RETURN the
    name with the roster's exact spelling.
  * Don't invent a destination if the user didn't mention one.
  * Don't invent times if the user didn't mention any.
  * Don't invent a group if the user didn't mention one.

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

    var title = (json['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) {
      throw const CalendarLlmException('Model produced no title');
    }
    // Belt-and-suspenders: even with the strict prompt, gpt-4o-mini
    // occasionally regresses to "Field Trip to X" or "X on Friday".
    // Strip the obvious prefixes/suffixes here so the rendered tile
    // is always clean. Idempotent — runs cheaply on already-clean
    // titles.
    title = _stripRedundantTitleParts(title);
    if (title.isEmpty) {
      throw const CalendarLlmException('Title was all redundant phrasing');
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
      groupNames: _parseGroupNames(json),
      confidence: (json['confidence'] as num?)?.toDouble(),
    );
  }

  /// Accept either an array (the new schema) or a single string
  /// (defensive — gpt-4o-mini occasionally regresses to
  /// `"groupName": "Sunflowers"` despite the prompt). Strip
  /// blanks, dedupe, preserve order so "sunflowers and acorns"
  /// stays in the order the teacher said.
  static List<String> _parseGroupNames(Map<String, dynamic> json) {
    final out = <String>[];
    final seen = <String>{};
    void add(String? raw) {
      if (raw == null) return;
      final t = raw.trim();
      if (t.isEmpty) return;
      final key = t.toLowerCase();
      if (seen.add(key)) out.add(t);
    }

    final arr = json['groupNames'];
    if (arr is List) {
      for (final v in arr) {
        if (v is String) add(v);
      }
    } else if (arr is String) {
      add(arr);
    }
    // Defensive: legacy `groupName` (singular) field.
    final legacy = json['groupName'];
    if (legacy is String) add(legacy);
    return out;
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

  // ——— Itinerary prompts —————————————————————————————————————

  static String _itinerarySystemPrompt(ItineraryDraftRequest req) {
    final isTrip = req.type == CalendarTileType.trip;
    final shape = isTrip
        ? '''
A FIELD-TRIP ITINERARY for an early-childhood group. The day arcs:
  1. leave school (vehicle / walk / bus)
  2. arrive at destination
  3. main activities (1-3 blocks; whatever fits the destination)
  4. snack or lunch break (always include one if the trip is over 2 hours)
  5. return to school
Cap at 7 blocks. Times follow the start/end window the user provided
(or sensible defaults if absent). Each block is age-appropriate for
small children — no late lunches, no marathon attention spans.
'''
        : '''
A DAY-PLAN SCHEDULE for an early-childhood program. The day arcs:
  1. arrival / drop-off
  2. morning circle or greeting
  3. focused activities tied to the theme (art, sensory, books, music)
  4. snack
  5. outside time
  6. lunch
  7. rest / quiet
  8. afternoon free play / theme follow-up
  9. pickup / closing
Cap at 9 blocks. Tie titles + descriptions back to the THEME so a
"ocean day" has goldfish-shaped crackers at snack, water-table outside,
ocean books at story time — not a generic schedule.
''';

    return '''
You are designing $shape

Return a single JSON object with exactly one key:
  "blocks": an array of objects, each with:
    "time":        "HH:MM" 24-hour, e.g. "08:30"
    "title":       short label, max 5 words, no time prefix
    "description": one short sentence — concrete, classroom-friendly

Rules for titles (same as for the tile itself):
  * No time / date / type prefixes. The block ALREADY shows its
    time as a separate field. "Morning circle" not "8:30 morning
    circle"; "Touch tank" not "Touch tank from 11:30".
  * Title-case, max 5 words.

Rules for descriptions:
  * One sentence. Action-first ("Read 'Big Blue' on the carpet").
  * Tie back to the trip / theme. No filler like "Children will
    have fun and learn."
  * Omit the description if you can't say something specific.

Times are in chronological order. No two blocks at the same time.
Return ONLY the JSON. No markdown, no commentary.
''';
  }

  static String _itineraryUserPrompt(ItineraryDraftRequest req) {
    final lines = <String>['Title: ${req.title}'];
    if (req.destination != null && req.destination!.isNotEmpty) {
      lines.add('Destination: ${req.destination!}');
    }
    if (req.theme != null && req.theme!.isNotEmpty) {
      lines.add('Theme: ${req.theme!}');
    }
    final start = req.startTime;
    final end = req.endTime;
    String fmt(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (start != null && end != null) {
      lines.add('Window: ${fmt(start)} – ${fmt(end)}');
    } else if (start != null) {
      lines.add('Starts: ${fmt(start)}');
    } else {
      // Sensible default: a 7:30–17:30 program day. For trips
      // without explicit times the model picks within this; for
      // day plans this matches the typical BASECamp day length.
      lines.add('Window: 07:30 – 17:30 (typical program day)');
    }
    if (req.audienceAgeLabel != null && req.audienceAgeLabel!.isNotEmpty) {
      lines.add('Audience age: ${req.audienceAgeLabel!}');
    }
    return lines.join('\n');
  }

  // ——— Title cleanup ——————————————————————————————————————————

  /// Trim the prefixes and suffixes the prompt already tells the
  /// model to omit, but that gpt-4o-mini sometimes still emits.
  /// Cleans titles like "Field Trip to Aquarium" → "Aquarium" and
  /// "Pajama Day on Friday" → "Pajama Day".
  ///
  /// Strips, in order:
  ///   1. Type-prefix phrases — "field trip to", "trip to",
  ///      "going to", "outing to", "event:", "day:", etc.
  ///   2. Trailing day-of-week or month-name suffixes —
  ///      "... on Friday", "... May 12", "... next Tuesday".
  ///   3. Trailing parenthesised qualifiers — "(Sunflowers)".
  ///   4. Trailing dashes / colons / pipes left over from #1+#2.
  static String _stripRedundantTitleParts(String input) {
    var s = input.trim();

    // 1. Type-prefix phrases. Anchor at start, case-insensitive.
    //    Note ordering: longer prefixes first so "field trip to"
    //    doesn't get half-matched by "trip to".
    final prefixes = <RegExp>[
      RegExp(r'^field\s*trip\s*(to\s*|—\s*|-\s*|:\s*)?', caseSensitive: false),
      RegExp(r'^class\s*trip\s*(to\s*|—\s*|-\s*|:\s*)?', caseSensitive: false),
      RegExp(r'^trip\s*(to\s*|—\s*|-\s*|:\s*)?', caseSensitive: false),
      RegExp(r'^outing\s*(to\s*|—\s*|-\s*|:\s*)?', caseSensitive: false),
      RegExp(r'^visit\s*(to\s*|—\s*|-\s*|:\s*)?', caseSensitive: false),
      RegExp(r'^going\s*to\s*', caseSensitive: false),
      RegExp(r'^event\s*[:—-]\s*', caseSensitive: false),
      RegExp(r'^day\s*[:—-]\s*', caseSensitive: false),
      RegExp(r'^theme\s*[:—-]\s*', caseSensitive: false),
    ];
    for (final re in prefixes) {
      s = s.replaceFirst(re, '');
      s = s.trim();
    }

    // 2. Trailing day-of-week / "next X" / "this X" / "on X".
    final daySuffix = RegExp(
      r'\s+(on\s+)?(next\s+|this\s+|last\s+)?(mon|tue|wed|thu|fri|sat|sun)'
      r'(day)?$',
      caseSensitive: false,
    );
    s = s.replaceFirst(daySuffix, '').trim();

    // 3. Trailing month + day ("May 12", "May 12, 2026").
    final dateSuffix = RegExp(
      r'\s+(on\s+)?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)'
      r'[a-z]*\s+\d{1,2}(,\s*\d{4})?$',
      caseSensitive: false,
    );
    s = s.replaceFirst(dateSuffix, '').trim();

    // 4. Trailing parenthesised qualifier — "(Sunflowers)".
    final parenSuffix = RegExp(r'\s*\([^)]*\)$');
    s = s.replaceFirst(parenSuffix, '').trim();

    // 5. Trailing dashes / pipes / colons left as a residue.
    s = s.replaceFirst(RegExp(r'[\s\-—|:]+$'), '').trim();

    return s;
  }
}
