// Command Agents — the next layer above CommandTools.
//
// Phase 1 of the agent-per-domain refactor. Background:
// `CommandTool` was designed for "one tool, one action" (e.g.
// `create_calendar_tile`). As the bar grew toward full CRUD —
// edit a tile, delete it, query a date range — the flat tool
// list stopped scaling. Stage-1 routing across 16+ sibling tools
// gets less accurate, prompts have to grow to cover every
// variant, and per-domain context (which kid was last tagged?
// which tile was just created?) had no natural home.
//
// An **agent** owns a domain end-to-end:
//   * One name + description the top-level router picks against.
//   * A set of internal **primitives** (CommandTool implementations
//     scoped to the domain): create, edit, delete, query, etc.
//   * A shared context block injected into every primitive's
//     stage-2 prompt — date lookup, roster snippets, the agent's
//     own recent-records window.
//
// The dispatcher routes:
//   1. Top-level: agent or anchor-matched tool.
//   2. If agent: agent picks one of its primitives (anchor → fast
//      path, otherwise a tiny LLM router scoped to this agent's
//      primitives only).
//   3. Stage-2 extractor on the chosen primitive (same machinery
//      `CommandDispatcher` uses today; the agent just supplies the
//      candidate-primitive list and the shared-context block).
//   4. Validator + critique-retry, also per-primitive.
//   5. Execute the primitive.
//
// Why this isn't just "more tools in the registry":
//   * Routing accuracy: 4 agents > 16 tools for the first hop.
//   * Prompt locality: edit_tile's prompt never sees observation
//     few-shots.
//   * Independent iteration: regress the observation agent and
//     calendar keeps working.
//   * Conversation memory: each agent owns its own recent-records
//     window so "and change its date to Friday" goes to the right
//     domain.

import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One domain's worth of CRUD + query operations. Concrete
/// agents declare a name (`calendar`, `observations`, etc.),
/// a one-line description for the top-level router, an optional
/// set of anchor words for the deterministic fast-path, and the
/// list of [CommandTool] primitives they own.
abstract class CommandAgent {
  const CommandAgent();

  /// Domain identifier — `calendar`, `observations`, `late_pickup`.
  /// Stable identifier the dispatcher uses internally.
  String get name;

  /// Human-readable summary the top-level router sees. ONE line.
  /// "Calendar — schedule, edit, delete, or look up tiles."
  String get description;

  /// Optional anchor words that route deterministically to this
  /// agent without calling the top-level router LLM. Same role
  /// `CommandTool.anchors` plays today. Use first words a teacher
  /// might open with — "trip,", "calendar,", "event,".
  List<String> get anchors => const <String>[];

  /// The internal CRUD primitives this agent owns. The agent's
  /// internal router picks ONE of these per submit. Order
  /// doesn't matter for routing but does for stable iteration.
  List<CommandTool> get primitives;

  /// Per-agent context injected into every primitive's stage-2
  /// system prompt — date lookup, roster details, the agent's
  /// own recent-records window. The dispatcher concatenates this
  /// with the primitive's own `extractorSystemPrompt(ctx)` so
  /// shared context lives in one place per domain instead of
  /// being copy-pasted into every primitive.
  ///
  /// Default: empty. Override when the agent has cross-primitive
  /// context worth caching (e.g., calendar's day lookup + group
  /// roster are the same for every CRUD action).
  String sharedExtractorContext(CommandContext ctx) => '';

  /// Per-context availability filter. Default: always available.
  /// Override to restrict an agent to certain routes or program
  /// states (e.g., a "trip-finance" agent only available when a
  /// trip is selected).
  bool isAvailable(CommandContext ctx) => true;

  /// Resolve a primitive by its OpenAI function name.
  CommandTool? primitiveByName(String name) {
    for (final p in primitives) {
      if (p.name == name) return p;
    }
    return null;
  }

  /// Optional override for agents that want to do work AFTER the
  /// primitive executes — usually to bookkeeping (e.g., bump a
  /// "last edited" cache so the next utterance routes back to
  /// the same record). Default: no-op.
  Future<void> postExecute({
    required CommandTool primitive,
    required Map<String, dynamic> args,
    required CommandResult result,
    required Ref ref,
  }) async {}
}

/// Registry of agents in the app. Parallel to [CommandToolRegistry]
/// but for the new abstraction. Existing tools (observations,
/// late-pickup, append-observation) stay in the tool registry
/// during the migration — the dispatcher checks agents first,
/// falls through to tools.
class CommandAgentRegistry {
  CommandAgentRegistry();

  final List<CommandAgent> _agents = <CommandAgent>[];

  void register(CommandAgent agent) => _agents.add(agent);

  List<CommandAgent> forContext(CommandContext ctx) {
    return _agents.where((a) => a.isAvailable(ctx)).toList();
  }

  CommandAgent? byName(String name) {
    for (final a in _agents) {
      if (a.name == name) return a;
    }
    return null;
  }

  /// Anchor fast-path — if [input]'s first word matches one of an
  /// agent's anchors, return that agent (the dispatcher still has
  /// to pick the right primitive within it).
  CommandAgent? matchAnchor(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    // Strip leading punctuation, then take the first alpha word.
    final firstWord =
        RegExp(r'^([a-zA-Z][a-zA-Z \-]*[a-zA-Z])\s*[,:.]?\s*')
            .firstMatch(trimmed)
            ?.group(1)
            ?.toLowerCase()
            .trim();
    if (firstWord == null || firstWord.isEmpty) return null;
    for (final a in _agents) {
      for (final anchor in a.anchors) {
        if (anchor.toLowerCase() == firstWord) return a;
      }
    }
    return null;
  }
}

final commandAgentRegistryProvider = Provider<CommandAgentRegistry>((ref) {
  final reg = CommandAgentRegistry();
  // Built-in agents register themselves at startup via
  // `registerBuiltInCommandAgents` (called from main.dart alongside
  // the existing `wireCommandToolRegistry`).
  registerBuiltInCommandAgents(reg);
  return reg;
});

/// App-startup hook. main.dart imports + calls this so newly-added
/// agents land in the registry without each one needing its own
/// `Provider` chain. Mirror of the existing
/// `registerBuiltInCommandTools` pattern.
///
/// Default = no-op so test environments / alternate entry points
/// don't crash. The real implementation lives in
/// `command_agents_registration.dart`.
// Non-nullable default so a registry read that happens BEFORE
// `wireCommandAgentRegistry` runs in main() doesn't silently
// produce an empty registry. Matches the existing tool-registry
// pattern.
void Function(CommandAgentRegistry) _registerBuiltIn = (_) {};
void registerBuiltInCommandAgents(CommandAgentRegistry reg) {
  _registerBuiltIn(reg);
}

/// Called from `main.dart` (via a side-effect import) to install
/// the real registration function before the first
/// `commandAgentRegistryProvider` read.
void wireCommandAgentRegistry(
  void Function(CommandAgentRegistry) fn,
) {
  _registerBuiltIn = fn;
}
