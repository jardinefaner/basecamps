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

/// Four intents the v0 router knows about. Each maps to a
/// concrete draft type the screen dispatches.
enum CommandIntent {
  /// "phillip helped maya tie her shoe today" → a brand-new
  /// observation row that lands in the cloud-synced
  /// observations table.
  observation,

  /// "and they were laughing the whole time" → APPEND to the
  /// most recent observation about the same kid (or the most
  /// recent one overall when no kid is named). Picked when the
  /// fragment is a continuation of a recent note rather than a
  /// fresh subject.
  appendObservation,

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

/// Append into an existing observation. The screen reads the
/// current row, concatenates [appendNote] to its `note` (with a
/// space), merges any new child ids, and saves back via
/// `updateObservation`. The user-visible result: a single,
/// growing observation that captures the running narrative
/// instead of a flurry of mini-rows.
class AppendObservationCommandDraft extends CommandDraft {
  const AppendObservationCommandDraft({
    required this.observationId,
    required this.appendNote,
    this.addChildIds = const <String>[],
    this.addChildNames = const <String>[],
    this.confidence,
  });

  @override
  CommandIntent get intent => CommandIntent.appendObservation;

  /// Id of the existing observation to update. Resolved by the
  /// LLM against the recent-observations context window.
  final String observationId;

  /// New text to add to the observation's `note`. The screen
  /// joins it onto the existing note with a single space.
  final String appendNote;

  /// Any kid ids the new fragment introduces that weren't on the
  /// original observation. The screen unions these in.
  final List<String> addChildIds;
  final List<String> addChildNames;

  final double? confidence;
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
    this.recentObservations = const <RecentObservation>[],
  });

  final List<LatePickupRosterChild> children;
  final String staffName;
  final String activeGroupName;
  final List<String> availableGroups;

  /// Last few observations the user created in this session.
  /// Drives the append-to-last detection: when a fresh fragment
  /// looks like a continuation of one of these (same kid, no
  /// new subject), the model returns `appendObservation` with
  /// the matching id. Empty on first use; the screen feeds in
  /// recent items as they're committed.
  final List<RecentObservation> recentObservations;
}

/// Thin shape of an observation the LLM only needs for matching.
/// We pass the note (so the model can see content overlap), the
/// tagged child ids (so it can recognise "she" / "they"), and
/// the timestamp (recent matters more than old).
class RecentObservation {
  const RecentObservation({
    required this.id,
    required this.note,
    required this.childIds,
    required this.childNames,
    required this.createdAt,
  });

  final String id;
  final String note;
  final List<String> childIds;
  final List<String> childNames;
  final DateTime createdAt;
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

    final decision = await _classifyIntent(
      input: trimmed,
      now: now,
      recentObservations: roster.recentObservations,
    );
    switch (decision.intent) {
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
      case CommandIntent.appendObservation:
        // The classifier guarantees a valid target id by this
        // point — `_classifyIntent` falls back to the newest
        // recent observation when the model picks a phantom id,
        // and falls back further to plain `observation` when
        // the recent window is empty.
        return _draftAppendObservation(
          input: trimmed,
          targetId: decision.appendTargetId!,
          roster: roster,
        );
    }
  }

  /// Single-shot intent classifier. Cheap (one 200-token round
  /// trip) and self-corrects fast in the prompt with examples.
  /// Falls back to `observation` on any parse failure — the
  /// gentlest default, since "phillip ate his snack today"
  /// without a verb tag is more likely a note than a trip.
  /// Decision returned by [_classifyIntent]. Carries the intent
  /// plus, for [CommandIntent.appendObservation], the id of the
  /// recent observation to merge into. Other intents leave
  /// [appendTargetId] null.
  static Future<_IntentDecision> _classifyIntent({
    required String input,
    required DateTime now,
    required List<RecentObservation> recentObservations,
  }) async {
    final today = DateFormat('EEEE').format(now);
    final recentBlock = recentObservations.isEmpty
        ? '(none yet)'
        : recentObservations
            .map(
              (r) => '  • [id: ${r.id}] '
                  '${r.childNames.isEmpty ? '(no kid)' : r.childNames.join(' + ')} — '
                  '${r.note.length > 120 ? '${r.note.substring(0, 120)}…' : r.note}',
            )
            .join('\n');
    final body = await OpenAiClient.chat({
      'model': 'gpt-4o-mini',
      'temperature': 0.0,
      'response_format': {'type': 'json_object'},
      'messages': [
        {
          'role': 'system',
          'content': '''
You classify a teacher's short fragment into ONE of four intents
for the BASECamp app. Today is $today.

Recent observations the same teacher just created (most recent
first, capped to a small window):
$recentBlock

Return JSON: {
  "intent": "observation" | "appendObservation" | "calendarTile" | "latePickup",
  "appendTargetId": "<id from above, only when intent=appendObservation>"
}

Definitions + examples:

* observation — A NEW NOTE about something a kid did or said
  today. Past or present tense, descriptive. The default when
  nothing else fits AND the fragment introduces a fresh subject
  (different kid, different topic).
  Examples:
    "phillip helped maya tie her shoe today" → observation
    "she's been crying all morning" → observation (only when
       there's no recent observation about a girl)
    "lunch was great today" → observation

* appendObservation — A CONTINUATION of one of the recent
  observations above. Use when the fragment:
    - starts with a connective ("and", "then", "also", "she/he
      kept", "after that") AND a recent observation has the
      matching subject, OR
    - re-mentions the same kid(s) as a recent observation and
      adds new detail rather than a fresh standalone story.
  When chosen, set "appendTargetId" to the [id: ...] from the
  matching recent line. NEVER guess an id that isn't listed.
  Examples (assuming a recent line exists about Phillip):
    "and they were laughing the whole time" → appendObservation
    "he kept doing it after circle too" → appendObservation
    "she shared with maya after that" → appendObservation
  Pick `observation` instead when:
    - the fragment names a different kid than every recent line.
    - there are no recent lines.
    - more than ~10 minutes have passed since the most recent.

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

When ambiguous between observation and appendObservation, prefer
appendObservation if the recent window has a clear subject match.
When ambiguous overall, prefer observation. Return ONLY the JSON.
''',
        },
        {'role': 'user', 'content': input},
      ],
    });

    const fallback = _IntentDecision(CommandIntent.observation);
    final choices = body['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return fallback;
    final content = ((choices.first as Map<String, dynamic>)['message']
            as Map<String, dynamic>?)?['content'] as String?;
    if (content == null) return fallback;
    try {
      final parsed = jsonDecode(content) as Map<String, dynamic>;
      final raw = (parsed['intent'] as String?)?.trim().toLowerCase();
      final targetIdRaw =
          (parsed['appendTargetId'] as String?)?.trim();
      switch (raw) {
        case 'observation':
          return const _IntentDecision(CommandIntent.observation);
        case 'appendobservation':
        case 'append_observation':
        case 'append-observation':
          // Validate the id against the actual recent window —
          // never trust a model-emitted id that wasn't listed.
          // If the model picked a phantom id, fall back to the
          // newest recent (or to a fresh observation when the
          // window is empty).
          if (targetIdRaw == null || targetIdRaw.isEmpty) {
            if (recentObservations.isEmpty) return fallback;
            return _IntentDecision(
              CommandIntent.appendObservation,
              appendTargetId: recentObservations.first.id,
            );
          }
          final known = recentObservations
              .any((r) => r.id == targetIdRaw);
          if (!known) {
            if (recentObservations.isEmpty) return fallback;
            return _IntentDecision(
              CommandIntent.appendObservation,
              appendTargetId: recentObservations.first.id,
            );
          }
          return _IntentDecision(
            CommandIntent.appendObservation,
            appendTargetId: targetIdRaw,
          );
        case 'calendartile':
        case 'calendar_tile':
        case 'calendar-tile':
          return const _IntentDecision(CommandIntent.calendarTile);
        case 'latepickup':
        case 'late_pickup':
        case 'late-pickup':
          return const _IntentDecision(CommandIntent.latePickup);
      }
    } on FormatException {
      // fall through
    }
    return fallback;
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

  /// Build an append draft. Keeps the prompt small — the
  /// classifier already picked the target; we just need to know
  /// what text to append + which (if any) new kids to merge in.
  static Future<AppendObservationCommandDraft> _draftAppendObservation({
    required String input,
    required String targetId,
    required CommandRoster roster,
  }) async {
    final target = roster.recentObservations
        .firstWhere((r) => r.id == targetId);
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
You're appending detail to an existing observation. The teacher
just said something that continues the previous note (same kid,
related action, follow-up detail).

EXISTING OBSERVATION
  Tagged kids: ${target.childNames.isEmpty ? '(none)' : target.childNames.join(', ')}
  Note so far: "${target.note}"

ROSTER (for matching any newly-mentioned kids):
$rosterLines

Return JSON:
  "appendNote":   the new sentence(s) to append, lightly cleaned
                  (capitalisation, terminal punctuation). Don't
                  re-state what's already in the existing note.
                  Don't introduce yourself or use filler. Past
                  tense to match the existing voice. Keep it
                  short (one sentence is best).
  "addChildIds":  array of [id: ...] from the roster for any kid
                  the new sentence introduces who is NOT already
                  in "Tagged kids" above. Empty array when no new
                  kid is introduced.

Return ONLY the JSON.
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
      throw const CommandLlmException('Empty append response');
    }
    final parsed = jsonDecode(content) as Map<String, dynamic>;
    final appendNote = (parsed['appendNote'] as String?)?.trim() ?? input;
    final newIds = (parsed['addChildIds'] as List<dynamic>?)
            ?.whereType<String>()
            .where((id) => !target.childIds.contains(id))
            .toSet()
            .toList() ??
        const <String>[];

    final byId = {for (final c in roster.children) c.id: c.displayName};
    final addNames =
        newIds.map((id) => byId[id] ?? '(unknown)').toList(growable: false);

    return AppendObservationCommandDraft(
      observationId: targetId,
      appendNote: appendNote,
      addChildIds: newIds,
      addChildNames: addNames,
      confidence: (parsed['confidence'] as num?)?.toDouble(),
    );
  }
}

class _IntentDecision {
  const _IntentDecision(this.intent, {this.appendTargetId});
  final CommandIntent intent;
  final String? appendTargetId;
}
