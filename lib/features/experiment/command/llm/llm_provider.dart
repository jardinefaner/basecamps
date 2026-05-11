// Provider-agnostic shapes for the Command Center's LLM layer.
//
// Today the only implementation is `OpenAiProvider` (over our
// `OpenAiClient` Supabase Edge Function proxy), but every later
// move — switching to Anthropic, adding a local model, routing
// some intents to a cheaper model — plugs in by writing one
// more concrete `LlmProvider`. The tool definitions, the
// dispatcher, the registry, the screen — none of them know
// which provider answered. That's the future-proof core.
//
// Cost: per Command Bar submission, the flow used to be TWO
// calls (classify intent, then extract fields). With tool-
// calling it's ONE — same input tokens, half the round-trip
// latency, no per-pass overhead, and a strictly enforced arg
// schema. The anchor fast-path skips the LLM entirely when the
// user opens with an explicit anchor word ("note,", "trip,"),
// saving the entire call.

import 'package:basecamp/features/experiment/command/command_tool.dart';

/// One message in the conversation sent to an LLM. Mirrors
/// OpenAI's `messages` shape but provider-neutral — the
/// OpenAI implementation converts to its wire format; future
/// providers convert to theirs.
class LlmMessage {
  const LlmMessage.system(this.content)
      : role = LlmRole.system,
        toolCallId = null,
        toolName = null;
  const LlmMessage.user(this.content)
      : role = LlmRole.user,
        toolCallId = null,
        toolName = null;
  const LlmMessage.tool(
    this.content, {
    required this.toolCallId,
    required this.toolName,
  }) : role = LlmRole.tool;

  final LlmRole role;
  final String content;

  /// For [LlmRole.tool] messages — the call id this is a result for.
  final String? toolCallId;
  final String? toolName;
}

enum LlmRole { system, user, assistant, tool }

/// One tool invocation the model emitted. Multiple calls per
/// response are allowed (GPT-4o parallel tool calls); the
/// dispatcher executes them sequentially in declaration order.
class LlmToolCall {
  const LlmToolCall({
    required this.id,
    required this.toolName,
    required this.args,
  });

  /// Provider-supplied identifier; round-trips back as the
  /// `toolCallId` on follow-up tool-result messages when the
  /// dispatcher does multi-turn loops (query tools, etc).
  final String id;
  final String toolName;
  final Map<String, dynamic> args;
}

/// Token bookkeeping returned by the provider. Lets the
/// dispatcher log + accumulate cost-per-tool-call. Optional —
/// providers without an exact count return null.
class TokenUsage {
  const TokenUsage({
    required this.inputTokens,
    required this.outputTokens,
  });

  final int inputTokens;
  final int outputTokens;
}

/// What the model emitted on a single round-trip.
class LlmResponse {
  const LlmResponse({
    required this.toolCalls,
    this.assistantText,
    this.usage,
  });

  /// Zero, one, or many. Zero is valid — the model decided no
  /// tool applies (probably means rephrase). One is the common
  /// case. Many means the user asked for several actions in
  /// one breath.
  final List<LlmToolCall> toolCalls;

  /// Free-text the model spoke alongside the tool calls.
  /// Today the dispatcher ignores this; the future "system
  /// initiates conversation" surface reads it.
  final String? assistantText;
  final TokenUsage? usage;
}

/// The contract every concrete provider satisfies. Future
/// Anthropic / local / etc. providers implement this.
abstract class LlmProvider {
  Future<LlmResponse> complete({
    required List<LlmMessage> messages,
    required List<CommandTool> availableTools,

    /// When non-null, force the model to call this exact tool.
    /// Used by the anchor fast-path: we already know which
    /// tool the user wants; we just need the LLM to extract
    /// args. Falls back to free choice when null.
    String? forceToolName,
  });
}
