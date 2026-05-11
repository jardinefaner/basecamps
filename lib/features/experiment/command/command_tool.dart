// CommandTool — the primitive every Command Center action
// implements. Per-domain features register their own tools (an
// observation tool, a calendar-tile tool, etc.); the registry
// loads them all and the bar's LLM picks one to call.
//
// The whole "voice-first / anchored speech" architecture rests
// on this. Each tool ships with:
//
//   * a name + JSON schema for its args (OpenAI tool-calling
//     consumes these directly)
//   * a description that includes a list of ANCHOR WORDS the
//     user might say to invoke it ("note,", "trip,", "late
//     pickup,") so the LLM has a strong routing signal
//   * an `isAvailable(ctx)` filter so context-irrelevant tools
//     don't clutter the prompt (an "edit this row" tool only
//     shows when a row is open)
//   * an `execute` callback the bar runs with the chosen args
//
// The registry is just a list. Adding a new tool is a single
// `register(...)` call from the feature module; no central
// classifier prompt to maintain.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Snapshot of "where the user is" when they ran the bar.
/// Drives tool filtering — an `EditObservationTool` is only
/// available when an observation is on screen; a calendar-tile
/// tool can bias when the user is on `/calendar`.
class CommandContext {
  const CommandContext({
    this.route,
    this.activeProgramId,
    this.selectedRecordId,
  });

  /// Route the bar fired from. `/command` from the Lab,
  /// `/calendar`, `/observations`, etc. Null when invoked from a
  /// drawer / global shortcut without a current screen.
  final String? route;
  final String? activeProgramId;
  final String? selectedRecordId;
}

/// Discriminated outcome from `CommandTool.execute`. Lets the
/// bar render a tailored confirmation toast / preview chip
/// without each tool re-implementing the UI.
class CommandResult {
  const CommandResult({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.iconCode,
    required this.iconFontFamily,
    this.destinationPath,
    this.recordId,
  });

  /// Big line — usually the new record's title.
  final String title;

  /// Smaller line under the title — relevant metadata (date,
  /// child names, etc.).
  final String subtitle;

  /// Short uppercase label for the badge (`OBSERVATION`,
  /// `CALENDAR · TRIP`, etc.).
  final String badge;

  /// IconData parts — flat ints because we can't `const`-pass
  /// an IconData here on its own.
  final int iconCode;
  final String? iconFontFamily;

  /// Where the "View" affordance in the toast / feed should
  /// navigate. Null = no nav (just a confirmation).
  final String? destinationPath;

  /// Id of the row this tool just created / updated. Drives the
  /// ambient-context window for follow-up "and..." utterances.
  final String? recordId;

  IconData get icon =>
      IconData(iconCode, fontFamily: iconFontFamily ?? 'MaterialIcons');
}

/// One operation the bar can perform. Every feature module
/// implements one or more of these.
abstract class CommandTool {
  const CommandTool();

  /// Function name sent to OpenAI's tool-calling API. Snake-case
  /// by convention; must be unique across the registry.
  String get name;

  /// Human-readable description shown TO THE MODEL (not the
  /// user). End with an examples block — examples are the
  /// strongest routing signal the model has. Include anchor
  /// words in the description so the model picks this tool when
  /// the user opens with one of them.
  String get description;

  /// JSON-schema object describing this tool's parameters.
  /// Follows OpenAI's function-calling schema:
  ///   {
  ///     "type": "object",
  ///     "properties": { ... },
  ///     "required": [ ... ]
  ///   }
  Map<String, dynamic> get parametersSchema;

  /// Anchor words the user might say to explicitly route to this
  /// tool. Included in the description AND used for a
  /// deterministic fast-path: if input starts with one of these
  /// (case-insensitive, followed by comma / colon / space), the
  /// bar can skip the LLM call entirely and route directly.
  List<String> get anchors => const <String>[];

  /// Per-context availability filter. Override to restrict a
  /// tool to certain screens or program states. Default: always
  /// available.
  bool isAvailable(CommandContext ctx) => true;

  /// Execute the tool with the LLM-supplied args. The
  /// implementation reads / writes via [ref] (repos, providers).
  Future<CommandResult> execute(
    Map<String, dynamic> args,
    Ref ref,
  );

  /// Serialise to OpenAI tool-calling format. The bar collects
  /// all tools' `toOpenAiFunction()` outputs into a single array
  /// for the API call.
  Map<String, dynamic> toOpenAiFunction() {
    return <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': name,
        'description': description,
        'parameters': parametersSchema,
      },
    };
  }
}

/// The registry — a flat list, filtered per-call by context.
/// Each feature module registers its tools here at app start.
class CommandToolRegistry {
  CommandToolRegistry();

  final List<CommandTool> _tools = <CommandTool>[];

  /// Register a new tool. Order doesn't matter for routing
  /// (description does), only for stable iteration in tests.
  void register(CommandTool tool) => _tools.add(tool);

  /// All tools available in [ctx], in registration order. The
  /// bar passes this list to OpenAI as the `tools` parameter.
  List<CommandTool> forContext(CommandContext ctx) {
    return _tools.where((t) => t.isAvailable(ctx)).toList();
  }

  /// Resolve a tool by its OpenAI function name. Returns null
  /// when the model emitted an unknown name (defensive — the
  /// caller should treat that as a parse failure).
  CommandTool? byName(String name) {
    for (final t in _tools) {
      if (t.name == name) return t;
    }
    return null;
  }

  /// Fast-path lookup: if [input]'s first word matches one of a
  /// tool's anchors (case-insensitive, ignoring trailing punct),
  /// return that tool plus the input with the anchor stripped.
  /// Lets the bar bypass the LLM for explicit anchored phrases.
  ({CommandTool tool, String body})? matchAnchor(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    // Pull the first "word group" — letters, spaces, hyphens —
    // until a delimiter (comma / colon / period / line break).
    final match = RegExp(
      r'^([a-zA-Z][a-zA-Z \-]*[a-zA-Z])\s*[,:.]\s*',
    ).firstMatch(trimmed);
    if (match == null) return null;
    final candidate = match.group(1)!.toLowerCase().trim();
    for (final tool in _tools) {
      for (final anchor in tool.anchors) {
        if (anchor.toLowerCase() == candidate) {
          return (
            tool: tool,
            body: trimmed.substring(match.end).trim(),
          );
        }
      }
    }
    return null;
  }
}

final commandToolRegistryProvider = Provider<CommandToolRegistry>((ref) {
  // Tools register themselves via a single helper to keep this
  // provider readable. See `command_tools_registration.dart` for
  // the actual list — splitting the wiring keeps this file
  // import-free of every feature module.
  final registry = CommandToolRegistry();
  registerBuiltInCommandTools(registry, ref);
  return registry;
});

/// Stub — replaced by an import-only sibling file that knows
/// every feature's tools. Defined here as a `late` callback the
/// app can override at startup if we ever need tests / variants
/// to inject a different registration set.
void Function(CommandToolRegistry registry, Ref ref)
    registerBuiltInCommandTools =
    (_, _) => throw StateError(
          'registerBuiltInCommandTools not wired — '
          'import command_tools_registration.dart somewhere.',
        );
