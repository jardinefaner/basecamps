// Command Center dispatcher — orchestrates anchor fast-path,
// LLM tool-call, and tool execution.
//
// One submission → 0..N CommandResults. Most of the time it's
// one — the LLM picks one tool, args are extracted, the tool
// inserts a row, the result is rendered. Multiple results are
// supported (GPT-4o can emit parallel tool calls in a single
// response) so a sentence like "create the trip AND email
// parents" returns two results from one round-trip; the bar
// renders them in sequence.
//
// Cost shape:
//   * Anchored input ("note, ...") — anchor fast-path forces
//     the matching tool via `tool_choice`, so the LLM is just
//     extracting args, not routing. Cheaper + faster +
//     deterministic; same cost as before.
//   * Unanchored input — full tool list goes into the prompt,
//     model picks one + extracts args in ONE round-trip. Down
//     from the prior 2-pass (classify, then extract).
//   * Per-call tokens logged to debugPrint via the provider
//     for cost telemetry.
//
// Future-proof hooks already in place:
//   * Multi-tool calls return List<CommandResult>; today the
//     screen renders all of them, tomorrow it can show a
//     preview-with-multiple-chips UI.
//   * Recent-records context flows from the screen into the
//     dispatcher's system prompt — drives anaphora /
//     append-to-last routing for any tool that needs it.
//   * Provider abstraction means swapping OpenAI for Anthropic
//     / local later is one line at the provider registration.

import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:basecamp/features/experiment/command/llm/llm_provider.dart';
import 'package:basecamp/features/experiment/command/llm/openai_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class CommandDispatcherException implements Exception {
  const CommandDispatcherException(this.message);
  final String message;
  @override
  String toString() => 'CommandDispatcherException: $message';
}

class CommandDispatcher {
  CommandDispatcher(this._ref);

  final Ref _ref;

  /// Single entry point the bar calls. Returns the executed
  /// tool results — the bar surfaces them as preview chips,
  /// snackbars, feed rows.
  Future<List<CommandResult>> submit({
    required String input,
    required CommandContext ctx,
  }) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const CommandDispatcherException('Empty input');
    }

    final registry = _ref.read(commandToolRegistryProvider);

    // 1. Anchor fast-path — strip the anchor word, force the
    //    matched tool. Still calls the LLM (we need args
    //    extracted), but `tool_choice` short-circuits routing.
    final anchor = registry.matchAnchor(trimmed);
    if (anchor != null) {
      return _runWithTools(
        body: anchor.body.isEmpty ? trimmed : anchor.body,
        tools: [anchor.tool],
        forceToolName: anchor.tool.name,
        ctx: ctx,
      );
    }

    // 2. No anchor → context-filtered tool list, model picks.
    final tools = registry.forContext(ctx);
    if (tools.isEmpty) {
      throw const CommandDispatcherException(
        'No tools available in this context',
      );
    }
    return _runWithTools(
      body: trimmed,
      tools: tools,
      forceToolName: null,
      ctx: ctx,
    );
  }

  Future<List<CommandResult>> _runWithTools({
    required String body,
    required List<CommandTool> tools,
    required String? forceToolName,
    required CommandContext ctx,
  }) async {
    final provider = _ref.read(llmProviderProvider);
    final response = await provider.complete(
      messages: [
        LlmMessage.system(_systemPrompt(ctx)),
        LlmMessage.user(body),
      ],
      availableTools: tools,
      forceToolName: forceToolName,
    );

    if (response.toolCalls.isEmpty) {
      throw const CommandDispatcherException(
        "Couldn't parse — try rephrasing.",
      );
    }

    final registry = _ref.read(commandToolRegistryProvider);
    final results = <CommandResult>[];
    final failures = <String>[];
    for (final call in response.toolCalls) {
      final tool = registry.byName(call.toolName);
      if (tool == null) {
        // Hallucinated tool name. Skip + log; the dispatcher
        // returns whatever real tools ran.
        debugPrint(
          '[command-dispatch] unknown tool ${call.toolName}; skipped',
        );
        failures.add('${call.toolName}: not registered');
        continue;
      }
      try {
        final result = await tool.execute(call.args, _ref);
        results.add(result);
      } on Object catch (e, st) {
        // One bad tool execution shouldn't kill sibling calls,
        // but we DO want to surface the name + first line of the
        // error to the user so a misconfigured tool doesn't fail
        // silently as "Couldn't run that".
        debugPrint(
          '[command-dispatch] ${call.toolName} threw: $e\n$st',
        );
        final summary = e.toString().split('\n').first;
        failures.add('${call.toolName}: $summary');
      }
    }
    if (results.isEmpty) {
      final detail = failures.isEmpty
          ? 'try rephrasing.'
          : failures.join('; ');
      throw CommandDispatcherException("Couldn't run that — $detail");
    }
    return results;
  }

  /// System prompt rendered into the LLM call. Carries today's
  /// date, route bias, and the recent-records window for
  /// anaphora resolution.
  String _systemPrompt(CommandContext ctx) {
    final now = DateTime.now();
    final today = DateFormat('EEEE, MMMM d, y').format(now);
    final timeNow = DateFormat('h:mm a').format(now);
    final routeLine = ctx.route == null
        ? '(none — global / drawer entry)'
        : ctx.route!;
    final recentBlock = ctx.recentRecords.isEmpty
        ? '(none yet)'
        : ctx.recentRecords
            .map((r) => '  • [${r.type} id=${r.id}] '
                '${_summaryWindow(r.summary)} '
                '— ${_relativeTime(r.createdAt, now)}')
            .join('\n');
    // Pre-compute the next 14 days as an explicit lookup table.
    // Without this, gpt-4o-mini routinely picks the wrong day
    // when the user says "Wednesday" — it has to do weekday→date
    // math against the single Today line and gets it wrong on
    // even simple phrasings. Reading off a table eliminates that
    // class of bug.
    final dayLookup = _buildDayLookup(now);
    return '''
You are the BASECamp Command Center. The user is a teacher in
an early-childhood program. They type or speak short fragments;
you pick the right tool and call it with the args extracted from
their words. Pick exactly ONE tool unless the user clearly named
multiple actions ("create the trip AND email parents") — then
emit multiple tool calls in parallel.

Context:
  Today: $today
  Time now: $timeNow
  Active program: ${ctx.activeProgramId ?? '(none)'}
  Current screen: $routeLine
  Selected record: ${ctx.selectedRecordId ?? '(none)'}

Program roster — groups (return EXACT spellings from this list
when filling group_names; do not invent names):
${_rosterBlock('Groups', ctx.groupNames)}

Program roster — kids (first names, deduped — return EXACT
spellings when filling child_name fields):
${_rosterBlock('Kids', ctx.childNames)}

Calendar lookup (use these EXACT dates — do not compute):
$dayLookup

Rules for date phrases:
  * "today" → today's date (the row marked TODAY above)
  * "tomorrow" → today's date + 1 from the table
  * "<weekday>" with NO modifier → the NEXT occurrence of that
    weekday. If today is the named weekday, use today.
  * "next <weekday>" → the occurrence in NEXT WEEK, never the
    one in this week. So if today is Tuesday and user says
    "next Wednesday," that's the Wednesday in next week's row.
  * "this <weekday>" → the occurrence in THIS WEEK (same row as
    today). If that day has already passed this week, fall
    back to the upcoming one anyway.

Recent records the teacher just created (most recent first):
$recentBlock

If the user's fragment is a CONTINUATION of one of these
(connectives "and / then / also", pronouns "he / she / they"
matching a recent record's subject), prefer the matching
append / edit tool with the record's id from above. If the
fragment introduces a fresh subject, pick a create tool.

Each tool's description tells you when it applies + lists its
ANCHOR WORDS — words the user might open with that map
directly to that tool ("note,", "trip,", "late pickup,"). When
in doubt, prefer the most reversible action.

NEVER guess an id that isn't in the recent-records list. Use
empty strings for unknown fields rather than inventing.
''';
  }

  /// Renders the roster as a single-line bullet list. Returns
  /// `(none)` when the list is empty so the LLM doesn't try to
  /// invent names — it'll fall back to whatever the user typed
  /// verbatim, which the tool's lookup can still handle.
  String _rosterBlock(String label, List<String> names) {
    if (names.isEmpty) return '  (none — $label list not loaded)';
    return names.map((n) => '  • $n').join('\n');
  }

  /// Render the next 14 days as a weekday-ordered lookup so the
  /// LLM can pick "Wednesday" → exact ISO date without doing
  /// any date math. Marks today and tomorrow so relative phrases
  /// resolve unambiguously.
  String _buildDayLookup(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final iso = DateFormat('yyyy-MM-dd');
    final pretty = DateFormat('EEE MMM d');
    final lines = <String>[];
    for (var i = 0; i < 14; i++) {
      final d = today.add(Duration(days: i));
      final tag = i == 0
          ? ' (TODAY)'
          : i == 1
              ? ' (tomorrow)'
              : '';
      lines.add('  • ${pretty.format(d)} = ${iso.format(d)}$tag');
    }
    return lines.join('\n');
  }

  String _summaryWindow(String s) =>
      s.length > 120 ? '${s.substring(0, 120)}…' : s;

  String _relativeTime(DateTime then, DateTime now) {
    final diff = now.difference(then);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('M/d').format(then);
  }
}

final commandDispatcherProvider = Provider<CommandDispatcher>((ref) {
  return CommandDispatcher(ref);
});
