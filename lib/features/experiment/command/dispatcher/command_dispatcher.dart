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

import 'package:basecamp/features/experiment/command/command_agent.dart';
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
    final toolRegistry = _ref.read(commandToolRegistryProvider);
    final agentRegistry = _ref.read(commandAgentRegistryProvider);

    // ════════════════════════════════════════════════════════════
    // ROUTING — agent OR tool
    //
    // Layered routing (cheapest → most expensive):
    //   1. Agent anchor match → use that agent's internal router
    //   2. Tool anchor match  → run that tool directly (legacy
    //      path while we migrate domains into agents)
    //   3. Top-level LLM picks an agent OR a still-flat tool
    //
    // Agents own multi-primitive domains (calendar = create +
    // edit + delete + query). Tools are single-action units left
    // over from the pre-agent architecture; they ride alongside
    // until each domain has its own agent.
    // ════════════════════════════════════════════════════════════
    CommandTool? selected;
    CommandAgent? selectedAgent;
    String body = normalized;

    final agentAnchor = agentRegistry.matchAnchor(normalized);
    if (agentAnchor != null && agentAnchor.isAvailable(ctx)) {
      selectedAgent = agentAnchor;
      body = _stripFirstWord(normalized);
      if (kDebugMode) {
        debugPrint(
          '[command-dispatch] stage1=anchor agent=${selectedAgent.name}',
        );
      }
    } else {
      final toolAnchor = toolRegistry.matchAnchor(normalized);
      if (toolAnchor != null) {
        selected = toolAnchor.tool;
        body = toolAnchor.body.isEmpty ? normalized : toolAnchor.body;
        if (kDebugMode) {
          debugPrint(
            '[command-dispatch] stage1=anchor tool=${selected.name}',
          );
        }
      } else {
        // No anchor — run the top-level LLM router across BOTH
        // agents and remaining tools.
        final tools = toolRegistry.forContext(ctx);
        final agents = agentRegistry.forContext(ctx);
        if (tools.isEmpty && agents.isEmpty) {
          throw const CommandDispatcherException(
            'No tools or agents available in this context',
          );
        }
        final picked = await _stage1RouteUnified(
          body: normalized,
          tools: tools,
          agents: agents,
          ctx: ctx,
        );
        if (picked == null) {
          throw const CommandDispatcherException(
            "Couldn't tell which tool to use — try rephrasing.",
          );
        }
        if (picked is CommandAgent) {
          selectedAgent = picked;
        } else if (picked is CommandTool) {
          selected = picked;
        }
        if (kDebugMode) {
          debugPrint(
            '[command-dispatch] stage1=llm '
            'agent=${selectedAgent?.name ?? '-'} '
            'tool=${selected?.name ?? '-'}',
          );
        }
      }
    }

    // ════════════════════════════════════════════════════════════
    // AGENT PATH — agent picks its primitive, then we run
    // stage 2 extractor on that primitive with the agent's shared
    // context block prepended.
    // ════════════════════════════════════════════════════════════
    if (selectedAgent != null) {
      final primitive = await _pickAgentPrimitive(
        agent: selectedAgent,
        body: body,
        ctx: ctx,
      );
      if (primitive == null) {
        throw CommandDispatcherException(
          "Couldn't decide which ${selectedAgent.name} action to take.",
        );
      }
      selected = primitive;
    }

    if (selected == null) {
      throw const CommandDispatcherException(
        "Couldn't decide on a tool.",
      );
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
      agent: selectedAgent,
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
        agent: selectedAgent,
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

  /// Unified top-level router: pick an agent OR a still-flat tool.
  /// Both share the menu so the LLM doesn't have to know about the
  /// internal taxonomy. Returns the picked agent / tool as the
  /// caller asked.
  Future<Object?> _stage1RouteUnified({
    required String body,
    required List<CommandTool> tools,
    required List<CommandAgent> agents,
    required CommandContext ctx,
  }) async {
    final provider = _ref.read(llmProviderProvider);
    final pickTool = _PickRouteTool(tools: tools, agents: agents);
    final agentLines =
        agents.map((a) => '  • ${a.name} (agent) — ${a.description}');
    final toolLines =
        tools.map((t) => '  • ${t.name} — ${t.routerSummary}');
    final response = await provider.complete(
      messages: [
        LlmMessage.system('''
You route teacher inputs to the right BASECamp handler. Read the
fragment and pick the single best match from the menu below.
Emit ONLY a `pick_route` function call with the chosen name.

Agents own a whole domain (CRUD + query within calendars, etc.).
Tools are single actions. When in doubt and a relevant agent exists,
prefer the agent.

Menu:
${[...agentLines, ...toolLines].join('\n')}

Tie-breakers:
  * If the user's fragment continues a recent record (pronouns
    "he/she/they", connectives "and/then/also"), prefer the
    relevant agent / append tool.
  * If unsure between observation and calendar:
    a date or destination → calendar; a child name + behaviour
    → observation.
'''),
        LlmMessage.user(body),
      ],
      availableTools: [pickTool],
      forceToolName: pickTool.name,
    );
    if (response.toolCalls.isEmpty) return null;
    final pickedName =
        response.toolCalls.first.args['name']?.toString() ?? '';
    final agent = _ref.read(commandAgentRegistryProvider).byName(pickedName);
    if (agent != null) return agent;
    return _ref.read(commandToolRegistryProvider).byName(pickedName);
  }

  /// Agent-internal router — given that the top-level picked
  /// [agent], decide which of the agent's primitives runs. Same
  /// shape as the top-level router but scoped to one domain.
  Future<CommandTool?> _pickAgentPrimitive({
    required CommandAgent agent,
    required String body,
    required CommandContext ctx,
  }) async {
    final primitives = agent.primitives;
    if (primitives.length == 1) {
      // Trivial case — no need to spend an LLM call.
      return primitives.first;
    }
    final provider = _ref.read(llmProviderProvider);
    final pickTool = _PickToolTool(primitives);
    final response = await provider.complete(
      messages: [
        LlmMessage.system('''
You are routing within the ${agent.name} agent. The teacher's
fragment is already known to be in this domain. Pick ONE
primitive from the list below.

${primitives.map((p) => '  • ${p.name} — ${p.routerSummary}').join('\n')}

Defaults / tie-breakers:
  * "create" / "add" / "schedule" / "new" → a create primitive.
  * "edit" / "change" / "move" / "rename" / "update" → edit.
  * "delete" / "remove" / "cancel" → delete (if available).
  * Plain pronouns ("it", "that one", "the one I just made")
    + a change verb → the edit primitive on the recent record.
'''),
        LlmMessage.user(body),
      ],
      availableTools: [pickTool],
      forceToolName: pickTool.name,
    );
    if (response.toolCalls.isEmpty) return null;
    final picked = response.toolCalls.first.args['tool']?.toString() ?? '';
    return agent.primitiveByName(picked);
  }

  /// STAGE 2 — extract args for the chosen tool. Focused prompt:
  /// only this tool's description / few-shots, plus the shared
  /// context (today's date, day lookup, roster). Forced via
  /// `tool_choice` to emit this exact tool, so we don't pay the
  /// model to re-route.
  Future<Map<String, dynamic>> _stage2Extract({
    required CommandTool tool,
    required CommandAgent? agent,
    required String body,
    required CommandContext ctx,
    required List<String>? critique,
  }) async {
    final provider = _ref.read(llmProviderProvider);
    final systemPrompt = _stage2SystemPrompt(tool, agent, ctx);
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
  String _stage2SystemPrompt(
    CommandTool tool,
    CommandAgent? agent,
    CommandContext ctx,
  ) {
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

${agent?.sharedExtractorContext(ctx) ?? ''}

${tool.extractorSystemPrompt(ctx)}

NEVER guess an id that isn't in the recent-records list.
Use empty strings for unknown fields rather than inventing.
''';
  }

  /// Strip the leading anchor word ("trip", "calendar") from
  /// [input] so the agent's primitives don't have to re-parse it.
  String _stripFirstWord(String input) {
    final match = RegExp(r'^([a-zA-Z][a-zA-Z \-]*[a-zA-Z])\s*[,:.]?\s*')
        .firstMatch(input);
    if (match == null) return input;
    return input.substring(match.end).trim();
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

/// Synthetic tool used by the unified top-level router — emits
/// either an agent name or a tool name via an enum-restricted
/// parameter. The dispatcher resolves the name against both
/// registries.
class _PickRouteTool extends CommandTool {
  _PickRouteTool({
    required List<CommandTool> tools,
    required List<CommandAgent> agents,
  })  : _tools = tools,
        _agents = agents;

  final List<CommandTool> _tools;
  final List<CommandAgent> _agents;

  @override
  String get name => 'pick_route';

  @override
  String get description =>
      'Pick the single handler (agent or tool) that matches the input.';

  @override
  Map<String, dynamic> get parametersSchema => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'name': <String, dynamic>{
            'type': 'string',
            'enum': [
              for (final a in _agents) a.name,
              for (final t in _tools) t.name,
            ],
            'description':
                'Name of the chosen agent or tool from the menu.',
          },
        },
        'required': ['name'],
      };

  @override
  Future<CommandResult> execute(
    Map<String, dynamic> args,
    Ref ref,
  ) async {
    throw StateError('_PickRouteTool.execute should never be called');
  }
}

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
