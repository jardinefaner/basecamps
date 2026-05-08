// Command Center — single LLM router for the voice-first
// experiment.
//
// One bar, many possible actions. The teacher types or dictates
// a fragment; the model classifies INTENT (what kind of thing
// they're trying to make / do) and EXTRACTS fields. The screen
// dispatches the resulting draft to the right destination —
// observations get persisted, calendar tiles + late-pickup rows
// land on their existing in-memory lab models.
//
// This is a Lab proof. If it earns its keep, the real moves are:
//   * dock the bar at the bottom of every screen
//   * add `appendToLastRecord` for "and she also said..." flows
//   * add `query` for "show me Phillip's last week"
//   * unify with the per-screen drop bars (calendar, late pickup)
//     so there's only ONE input affordance in the whole app

import 'dart:convert';

import 'package:basecamp/features/ai/openai_client.dart';
import 'package:basecamp/features/experiment/calendar_llm_service.dart';
import 'package:basecamp/features/experiment/calendar_tile_store.dart';
import 'package:basecamp/features/experiment/late_pickup_llm_service.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:intl/intl.dart';

/// Three intents the v0 router knows about. Each maps to a
/// concrete draft type the screen dispatches.
enum CommandIntent {
  /// "phillip helped maya tie her shoe today" → an observation
  /// row that lands in the cloud-synced observations table.
  observation,

  /// "field trip aquarium next tuesday for sunflowers" → a
  /// calendar tile (lab in-memory).
  calendarTile,

  /// "phillip is late, gave reminder card" → a late-pickup row
  /// (lab in-memory).
  latePickup,
}

/// Discriminated draft — the screen pattern-matches to know what
/// surface to render the preview chip in.
sealed class CommandDraft {
  const CommandDraft();
  CommandIntent get intent;
}

class ObservationCommandDraft extends CommandDraft {
  const ObservationCommandDraft({
    required this.note,
    required this.domain,
    required this.sentiment,
    required this.childIds,
    required this.childNames,
    this.confidence,
  });

  @override
  CommandIntent get intent => CommandIntent.observation;

  final String note;
  final ObservationDomain domain;
  final ObservationSentiment sentiment;
  final List<String> childIds;
  final List<String> childNames; // display only
  final double? confidence;

  String summary() {
    final kids = childNames.isEmpty ? 'no child tagged' : childNames.join(' + ');
    return '$kids · ${domain.code} · ${sentiment.name}';
  }
}

class CalendarTileCommandDraft extends CommandDraft {
  const CalendarTileCommandDraft({required this.calendar});

  @override
  CommandIntent get intent => CommandIntent.calendarTile;

  final CalendarTileDraft calendar;
}

class LatePickupCommandDraft extends CommandDraft {
  const LatePickupCommandDraft({required this.latePickup});

  @override
  CommandIntent get intent => CommandIntent.latePickup;

  final LatePickupDraft latePickup;
}

/// Sentinel for parse failures. The bar surfaces this as a small
/// red chip with the message; the user retries.
class CommandLlmException implements Exception {
  const CommandLlmException(this.message);
  final String message;
  @override
  String toString() => 'CommandLlmException: $message';
}

/// Inputs the screen passes to the router. The kid + adult roster
/// drive both the intent classifier (so "phillip" disambiguates)
/// and per-intent extraction (parents, staff name).
class CommandRoster {
  const CommandRoster({
    required this.children,
    required this.staffName,
    required this.activeGroupName,
    required this.availableGroups,
  });

  final List<LatePickupRosterChild> children;
  final String staffName;
  final String activeGroupName;
  final List<String> availableGroups;
}

class CommandLlmService {
  CommandLlmService._();

  /// Two-pass routing:
  ///   1. classify intent (a single small LLM call, JSON-mode).
  ///   2. dispatch to the matching domain service for full
  ///      extraction. Reuses calendar + late-pickup services so
  ///      we don't duplicate prompts.
  ///
  /// Two passes (instead of one giant prompt) keeps each prompt
  /// small + reuses the carefully tuned per-domain prompts the
  /// existing labs have already proven out.
  static Future<CommandDraft> draftFromText({
    required String input,
    required DateTime now,
    required CommandRoster roster,
  }) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const CommandLlmException('Empty input');
    }

    final intent = await _classifyIntent(input: trimmed, now: now);
    switch (intent) {
      case CommandIntent.calendarTile:
        final draft = await CalendarLlmService.draftFromText(
          input: trimmed,
          today: now,
          activeType: CalendarTileType.event,
          activeGroupName: roster.activeGroupName,
          availableGroups: roster.availableGroups,
        );
        return CalendarTileCommandDraft(calendar: draft);
      case CommandIntent.latePickup:
        final draft = await LatePickupLlmService.draftFromText(
          input: trimmed,
          now: now,
          staffName: roster.staffName,
          roster: roster.children,
        );
        return LatePickupCommandDraft(latePickup: draft);
      case CommandIntent.observation:
        return _draftObservation(
          input: trimmed,
          now: now,
          roster: roster,
        );
    }
  }

  /// Single-shot intent classifier. Cheap (one 200-token round
  /// trip) and self-corrects fast in the prompt with examples.
  /// Falls back to `observation` on any parse failure — the
  /// gentlest default, since "phillip ate his snack today"
  /// without a verb tag is more likely a note than a trip.
  static Future<CommandIntent> _classifyIntent({
    required String input,
    required DateTime now,
  }) async {
    final today = DateFormat('EEEE').format(now);
    final body = await OpenAiClient.chat({
      'model': 'gpt-4o-mini',
      'temperature': 0.0,
      'response_format': {'type': 'json_object'},
      'messages': [
        {
          'role': 'system',
          'content': '''
You classify a teacher's short fragment into ONE of three intents
for the BASECamp app. Today is $today.

Return JSON: { "intent": "observation" | "calendarTile" | "latePickup" }

Definitions + examples:

* observation — A NOTE about something a kid did or said today.
  Past or present tense, descriptive. The default when nothing
  else fits.
  Examples:
    "phillip helped maya tie her shoe today" → observation
    "she's been crying all morning" → observation
    "he was so proud of his drawing" → observation
    "lunch was great today, kids loved the carrots" → observation

* calendarTile — Schedules or plans a future thing on a date.
  Field trip, in-program event, themed day plan.
  Examples:
    "field trip aquarium next tuesday 8 to 3" → calendarTile
    "pajama day friday" → calendarTile
    "pizza party at 11:30 next week" → calendarTile
    "ocean theme day thursday" → calendarTile

* latePickup — Logs a kid who got picked up late TODAY.
  Has a strong verb signal: "is late", "picked up late",
  "running late", "stayed past closing".
  Examples:
    "phillip is late" → latePickup
    "legend dawson 6 pm gave reminder card" → latePickup
    "zamir was picked up at 5:45" → latePickup

When ambiguous, prefer observation — it's the safest fallback
because the action it triggers (a note) is the most reversible.
Return ONLY the JSON.
''',
        },
        {'role': 'user', 'content': input},
      ],
    });

    final choices = body['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      return CommandIntent.observation;
    }
    final content = ((choices.first as Map<String, dynamic>)['message']
            as Map<String, dynamic>?)?['content'] as String?;
    if (content == null) return CommandIntent.observation;
    try {
      final parsed = jsonDecode(content) as Map<String, dynamic>;
      final raw = (parsed['intent'] as String?)?.trim().toLowerCase();
      switch (raw) {
        case 'observation':
          return CommandIntent.observation;
        case 'calendartile':
        case 'calendar_tile':
        case 'calendar-tile':
          return CommandIntent.calendarTile;
        case 'latepickup':
        case 'late_pickup':
        case 'late-pickup':
          return CommandIntent.latePickup;
      }
    } on FormatException {
      // fall through
    }
    return CommandIntent.observation;
  }

  /// Extract observation fields from a freeform note. Domain
  /// classification is bundled here (instead of a second round-
  /// trip to `ai_classifier.dart`) because the LLM has the
  /// note's text already and one call is cheaper than two.
  static Future<ObservationCommandDraft> _draftObservation({
    required String input,
    required DateTime now,
    required CommandRoster roster,
  }) async {
    final rosterLines = roster.children
        .take(150)
        .map((c) => '  • ${c.displayName} [id: ${c.id}]')
        .join('\n');

    final body = await OpenAiClient.chat({
      'model': 'gpt-4o-mini',
      'temperature': 0.2,
      'response_format': {'type': 'json_object'},
      'messages': [
        {
          'role': 'system',
          'content': '''
You convert a teacher's note into a structured BASECamp
observation row.

Children roster (match the note's mentions; case-insensitive,
first-name OK; use exactly the spelling shown):
$rosterLines

Return JSON with these keys:
  "note":      A clean, classroom-friendly version of what the
               teacher said. 1-2 sentences. Past tense. Don't
               invent details, but light editing for grammar /
               capitalisation is OK.
  "domain":    One of: SSD1 SSD2 SSD3 SSD4 SSD5 SSD6 SSD7 SSD8
               SSD9 HLTH1 HLTH2 HLTH3 HLTH4 OTHER
               Pick the closest BASECamp curriculum domain.
               When unsure, use OTHER.
  "sentiment": One of: positive | neutral | concern
               Use "concern" when the note describes hurt
               feelings, conflict, distress, or behaviour the
               teacher would want to flag.
  "childIds":  Array of [id: ...] values from the roster, for
               every child explicitly named in the note. Empty
               array when no kid is named (group-level note).
  "confidence": 0.0..1.0 self-rated.

Domain crib sheet:
  SSD1 — identity & connection (belonging, friendship)
  SSD2 — emotional awareness (naming feelings)
  SSD3 — self-regulation (calming, persistence)
  SSD4 — empathy (caring for others)
  SSD5 — communication (expressing needs, listening)
  SSD6 — problem solving / decision making
  SSD7 — independence (self-help, autonomy)
  SSD8 — creativity (art, story, play)
  SSD9 — curiosity (asking, exploring)
  HLTH1 — physical activity / movement
  HLTH2 — nutrition / food choices
  HLTH3 — rest / hygiene / safety
  HLTH4 — outdoor / nature

Return ONLY the JSON. No markdown.
''',
        },
        {'role': 'user', 'content': input},
      ],
    });

    final choices = body['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const CommandLlmException('Model returned no choices');
    }
    final content = ((choices.first as Map<String, dynamic>)['message']
            as Map<String, dynamic>?)?['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      throw const CommandLlmException('Empty observation response');
    }
    final parsed = jsonDecode(content) as Map<String, dynamic>;
    final note = (parsed['note'] as String?)?.trim() ?? input;
    final domainRaw = (parsed['domain'] as String?)?.trim().toLowerCase() ?? '';
    final sentRaw =
        (parsed['sentiment'] as String?)?.trim().toLowerCase() ?? 'neutral';
    final ids = (parsed['childIds'] as List<dynamic>?)
            ?.whereType<String>()
            .toSet()
            .toList() ??
        const <String>[];

    // Resolve names off the roster for display in the preview.
    final byId = {for (final c in roster.children) c.id: c.displayName};
    final names =
        ids.map((id) => byId[id] ?? '(unknown)').toList(growable: false);

    return ObservationCommandDraft(
      note: note,
      domain: _parseDomain(domainRaw),
      sentiment: _parseSentiment(sentRaw),
      childIds: ids,
      childNames: names,
      confidence: (parsed['confidence'] as num?)?.toDouble(),
    );
  }

  static ObservationDomain _parseDomain(String raw) {
    return switch (raw) {
      'ssd1' => ObservationDomain.ssd1,
      'ssd2' => ObservationDomain.ssd2,
      'ssd3' => ObservationDomain.ssd3,
      'ssd4' => ObservationDomain.ssd4,
      'ssd5' => ObservationDomain.ssd5,
      'ssd6' => ObservationDomain.ssd6,
      'ssd7' => ObservationDomain.ssd7,
      'ssd8' => ObservationDomain.ssd8,
      'ssd9' => ObservationDomain.ssd9,
      'hlth1' => ObservationDomain.hlth1,
      'hlth2' => ObservationDomain.hlth2,
      'hlth3' => ObservationDomain.hlth3,
      'hlth4' => ObservationDomain.hlth4,
      _ => ObservationDomain.other,
    };
  }

  static ObservationSentiment _parseSentiment(String raw) {
    return switch (raw) {
      'positive' => ObservationSentiment.positive,
      'concern' => ObservationSentiment.concern,
      _ => ObservationSentiment.neutral,
    };
  }
}
