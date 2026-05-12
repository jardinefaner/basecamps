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
    final normalized = _normalizeUserInput(trimmed);
    final registry = _ref.read(commandToolRegistryProvider);

    // ════════════════════════════════════════════════════════════
    // STAGE 1 — pick the tool
    //
    // Anchor fast-path first ("note,", "trip,", "late pickup,"
    // map directly to a tool with zero LLM cost). If the input
    // doesn't anchor, fall through to a tiny stage-1 LLM call
    // that just picks a tool name from a one-line-per-tool menu.
    // ════════════════════════════════════════════════════════════
    final anchor = registry.matchAnchor(normalized);
    CommandTool? selected;
    String body = normalized;
    if (anchor != null) {
      selected = anchor.tool;
      body = anchor.body.isEmpty ? normalized : anchor.body;
      if (kDebugMode) {
        debugPrint('[command-dispatch] stage1=anchor tool=${selected.name}');
      }
    } else {
      final tools = registry.forContext(ctx);
      if (tools.isEmpty) {
        throw const CommandDispatcherException(
          'No tools available in this context',
        );
      }
      selected = await _stage1Route(normalized, tools, ctx);
      if (selected == null) {
        throw const CommandDispatcherException(
          "Couldn't tell which tool to use — try rephrasing.",
        );
      }
      if (kDebugMode) {
        debugPrint('[command-dispatch] stage1=llm tool=${selected.name}');
      }
    }

    // ════════════════════════════════════════════════════════════
    // STAGE 2 — extract slots for the chosen tool
    //
    // Tool-specific system prompt + tool-specific few-shots.
    // Forced to emit exactly this tool via `tool_choice`. Then
    // validate; if the validator flags missing groups / wrong
    // date / etc, re-call ONCE with the validator's critique.
    // ════════════════════════════════════════════════════════════
    var args = await _stage2Extract(
      tool: selected,
      body: body,
      ctx: ctx,
      critique: null,
    );

    final errors = selected.validate(body, args, ctx);
    if (errors.isNotEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[command-dispatch] stage2 validation failed: ${errors.join(' | ')}',
        );
      }
      args = await _stage2Extract(
        tool: selected,
        body: body,
        ctx: ctx,
        critique: errors,
      );
    }

    if (kDebugMode) {
      debugPrint(
        '[command-dispatch] in="$input" norm="$normalized" '
        'tool=${selected.name} args=$args',
      );
    }

    // ════════════════════════════════════════════════════════════
    // EXECUTE
    // ════════════════════════════════════════════════════════════
    final CommandResult raw;
    try {
      raw = await selected.execute(args, _ref);
    } on Object catch (e, st) {
      debugPrint('[command-dispatch] ${selected.name} threw: $e\n$st');
      final summary = e.toString().split('\n').first;
      throw CommandDispatcherException(
        "Couldn't run ${selected.name} — $summary",
      );
    }
    return [
      CommandResult(
        title: raw.title,
        subtitle: raw.subtitle,
        badge: raw.badge,
        iconCode: raw.iconCode,
        iconFontFamily: raw.iconFontFamily,
        destinationPath: raw.destinationPath,
        recordId: raw.recordId,
        toolName: selected.name,
        toolArgs: args,
        userInput: input,
      ),
    ];
  }

  /// STAGE 1 — pick exactly one tool. The prompt is a flat menu
  /// of one-line summaries; the LLM emits the tool name via a
  /// synthetic `pick_tool` function so we get a structured
  /// answer back. gpt-4o-mini handles this fine and the prompt
  /// is tiny.
  Future<CommandTool?> _stage1Route(
    String body,
    List<CommandTool> tools,
    CommandContext ctx,
  ) async {
    final provider = _ref.read(llmProviderProvider);
    final pickTool = _PickToolTool(tools);
    final response = await provider.complete(
      messages: [
        LlmMessage.system('''
You route teacher inputs to the right BASECamp tool. Read the
fragment and pick the single best match from the menu below.
Emit ONLY a `pick_tool` function call with the chosen name.

Tools:
${tools.map((t) => '  • ${t.name} — ${t.routerSummary}').join('\n')}

Tie-breakers:
  * If the user's fragment continues a recent record (pronouns
    "he/she/they", connectives "and/then/also"), prefer
    `append_observation`.
  * If unsure between create_observation and create_calendar_tile:
    a date or destination → calendar tile; a child name + behaviour
    → observation.
'''),
        LlmMessage.user(body),
      ],
      availableTools: [pickTool],
      forceToolName: pickTool.name,
    );
    if (response.toolCalls.isEmpty) return null;
    final picked = response.toolCalls.first.args['tool']?.toString() ?? '';
    return _ref.read(commandToolRegistryProvider).byName(picked);
  }

  /// STAGE 2 — extract args for the chosen tool. Focused prompt:
  /// only this tool's description / few-shots, plus the shared
  /// context (today's date, day lookup, roster). Forced via
  /// `tool_choice` to emit this exact tool, so we don't pay the
  /// model to re-route.
  Future<Map<String, dynamic>> _stage2Extract({
    required CommandTool tool,
    required String body,
    required CommandContext ctx,
    required List<String>? critique,
  }) async {
    final provider = _ref.read(llmProviderProvider);
    final systemPrompt = _stage2SystemPrompt(tool, ctx);
    // Prepend the date to the USER MESSAGE so it's in the model's
    // immediate context for the forced tool call. With `tool_choice`
    // forcing a function emit, the model sometimes rushes args
    // without re-reading the system prompt — keeping the date right
    // next to the input it's parsing makes weekday-to-date resolution
    // a copy-paste away.
    final now = DateTime.now();
    final todayLine =
        'Today is ${DateFormat('EEEE, MMMM d, y').format(now)}.';
    final base = critique == null
        ? body
        : '''
$body

Your previous attempt had these problems — fix them and re-emit:
${critique.map((e) => '  • $e').join('\n')}
''';
    final userMessage = '$todayLine\n\n$base';
    final response = await provider.complete(
      messages: [
        LlmMessage.system(systemPrompt),
        LlmMessage.user(userMessage),
      ],
      availableTools: [tool],
      forceToolName: tool.name,
    );
    if (response.toolCalls.isEmpty) {
      throw const CommandDispatcherException(
        "Couldn't extract args — try rephrasing.",
      );
    }
    return response.toolCalls.first.args;
  }

  /// Stage-2 system prompt = shared context (date lookup +
  /// roster + recent records) + the tool's own extractor
  /// prompt + a tight self-check footer. Tool-specific examples
  /// live in `tool.extractorSystemPrompt(ctx)` so they don't
  /// pollute other tools' prompts.
  String _stage2SystemPrompt(CommandTool tool, CommandContext ctx) {
    final now = DateTime.now();
    final today = DateFormat('EEEE, MMMM d, y').format(now);
    final timeNow = DateFormat('h:mm a').format(now);
    final dayLookup = _buildDayLookup(now);
    final recentBlock = ctx.recentRecords.isEmpty
        ? '  (none yet)'
        : ctx.recentRecords
            .map((r) => '  • [${r.type} id=${r.id}] '
                '${_summaryWindow(r.summary)} '
                '— ${_relativeTime(r.createdAt, now)}')
            .join('\n');
    return '''
Context for slot extraction:
  Today: $today
  Time now: $timeNow
  Active program: ${ctx.activeProgramId ?? '(none)'}

Calendar lookup (use these EXACT dates — never compute):
$dayLookup

Program roster — groups (return EXACT spellings):
${_rosterBlock('Groups', ctx.groupNames)}

Program roster — kids (first names, deduped):
${_rosterBlock('Kids', ctx.childNames)}

Recent records:
$recentBlock

${tool.extractorSystemPrompt(ctx)}

NEVER guess an id that isn't in the recent-records list.
Use empty strings for unknown fields rather than inventing.
''';
  }


  /// Light pre-processing of the user's input to fix obvious
  /// variants the LLM otherwise has to guess at. Cheap, runs
  /// before every prompt. Each transform is reversible-ish so a
  /// bad rewrite at worst forces a retry, not a wrong action.
  String _normalizeUserInput(String raw) {
    var s = raw.trim();
    // Weekday abbreviations that LLMs sometimes mis-resolve.
    const weekdayAbbrev = {
      r'\bmon\b': 'Monday',
      r'\btue\b': 'Tuesday',
      r'\btues\b': 'Tuesday',
      r'\bwed\b': 'Wednesday',
      r'\bweds\b': 'Wednesday',
      r'\bthu\b': 'Thursday',
      r'\bthur\b': 'Thursday',
      r'\bthurs\b': 'Thursday',
      r'\bfri\b': 'Friday',
      r'\bsat\b': 'Saturday',
      r'\bsun\b': 'Sunday',
    };
    for (final entry in weekdayAbbrev.entries) {
      s = s.replaceAllMapped(
        RegExp(entry.key, caseSensitive: false),
        (_) => entry.value,
      );
    }
    // List-separator normalisation so the LLM has consistent
    // signals for "split into multiple groups."
    s = s.replaceAll('&', ' and ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
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

/// Synthetic tool used only by stage 1 — gives the LLM a single
/// function to call (`pick_tool`) with an enum-restricted `tool`
/// parameter so the routing answer comes back as a structured
/// choice instead of free-form text. Never registered in the
/// global registry; spun up per-call from the live tool list so
/// the enum reflects exactly what's available in the current
/// context.
class _PickToolTool extends CommandTool {
  _PickToolTool(this._availableTools);

  final List<CommandTool> _availableTools;

  @override
  String get name => 'pick_tool';

  @override
  String get description =>
      'Pick the single tool that matches the user fragment.';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'tool': <String, dynamic>{
            'type': 'string',
            'enum': [for (final t in _availableTools) t.name],
            'description': 'Name of the chosen tool.',
          },
        },
        'required': ['tool'],
      };

  @override
  Future<CommandResult> execute(
    Map<String, dynamic> args,
    Ref ref,
  ) async {
    // Stage 1 never executes — its only job is to return the
    // picked tool name to the dispatcher. Throw loudly if a
    // caller accidentally routes through here.
    throw StateError('_PickToolTool.execute should never be called');
  }
}
