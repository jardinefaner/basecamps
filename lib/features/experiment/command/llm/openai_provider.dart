// OpenAI-specific LlmProvider — wraps the existing
// `OpenAiClient` Supabase Edge Function proxy. The dispatcher
// holds a reference to this typed as `LlmProvider`, so swapping
// in `AnthropicProvider` / `LocalProvider` later is a one-line
// change at the registration site.

import 'dart:convert';

import 'package:basecamp/features/ai/openai_client.dart';
import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:basecamp/features/experiment/command/llm/llm_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OpenAiProvider implements LlmProvider {
  const OpenAiProvider();

  /// Model id sent to the proxy. `gpt-4o-mini` is the
  /// cheapest model that supports tool-calling reliably.
  /// Override to `gpt-4o` if we need a smarter classifier or
  /// `gpt-4.1-mini` once that lands.
  static const String _model = 'gpt-4o-mini';

  /// Low temperature — tool routing should be deterministic.
  /// Per-tool extractors that need creativity (the observation
  /// note rewrite, the AI scaffolding) can stay at 0.4 — they
  /// run in their own provider calls, not this routing one.
  static const double _temperature = 0.1;

  @override
  Future<LlmResponse> complete({
    required List<LlmMessage> messages,
    required List<CommandTool> availableTools,
    String? forceToolName,
  }) async {
    final body = <String, dynamic>{
      'model': _model,
      'temperature': _temperature,
      'messages': messages.map(_serializeMessage).toList(),
      if (availableTools.isNotEmpty)
        'tools': availableTools.map((t) => t.toOpenAiFunction()).toList(),
      'tool_choice': _toolChoice(availableTools, forceToolName),
    };
    final raw = await OpenAiClient.chat(body);
    return _parse(raw);
  }

  // ——— Serialization helpers —————————————————————————————————

  Map<String, dynamic> _serializeMessage(LlmMessage m) {
    switch (m.role) {
      case LlmRole.system:
        return {'role': 'system', 'content': m.content};
      case LlmRole.user:
        return {'role': 'user', 'content': m.content};
      case LlmRole.assistant:
        return {'role': 'assistant', 'content': m.content};
      case LlmRole.tool:
        return {
          'role': 'tool',
          'content': m.content,
          'tool_call_id': m.toolCallId,
          if (m.toolName != null) 'name': m.toolName,
        };
    }
  }

  /// OpenAI's `tool_choice` shape:
  ///   * empty tool list → omit (model returns plain text).
  ///   * forceToolName set → `{type:function, function:{name:X}}`.
  ///   * otherwise `'auto'`.
  dynamic _toolChoice(
    List<CommandTool> tools,
    String? forceToolName,
  ) {
    if (tools.isEmpty) return 'none';
    if (forceToolName != null) {
      return <String, dynamic>{
        'type': 'function',
        'function': <String, dynamic>{'name': forceToolName},
      };
    }
    return 'auto';
  }

  LlmResponse _parse(Map<String, dynamic> raw) {
    try {
      final choices = raw['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        return const LlmResponse(toolCalls: []);
      }
      final message =
          (choices.first as Map<String, dynamic>)['message']
              as Map<String, dynamic>?;
      if (message == null) return const LlmResponse(toolCalls: []);
      final assistantText = message['content'] as String?;

      final toolCallsRaw = message['tool_calls'] as List<dynamic>? ?? [];
      final toolCalls = <LlmToolCall>[];
      for (final entry in toolCallsRaw) {
        if (entry is! Map) continue;
        final id = entry['id'] as String? ?? '';
        final fn = entry['function'] as Map?;
        if (fn == null) continue;
        final name = fn['name'] as String? ?? '';
        if (name.isEmpty) continue;
        final argsStr = fn['arguments'] as String? ?? '{}';
        var args = const <String, dynamic>{};
        try {
          final decoded = jsonDecode(argsStr);
          if (decoded is Map) {
            args = Map<String, dynamic>.from(decoded);
          }
        } on FormatException {
          // Model emitted invalid JSON. Skip this call; the
          // dispatcher's missing-tool branch surfaces the
          // error to the user.
          continue;
        }
        toolCalls.add(LlmToolCall(id: id, toolName: name, args: args));
      }

      final usage = raw['usage'] as Map<String, dynamic>?;
      final tokenUsage = usage == null
          ? null
          : TokenUsage(
              inputTokens: (usage['prompt_tokens'] as num?)?.toInt() ?? 0,
              outputTokens:
                  (usage['completion_tokens'] as num?)?.toInt() ?? 0,
            );
      // Telemetry — every successful round-trip logs its
      // token usage so we can spot cost regressions per-tool /
      // per-screen. debugPrint stays out of release builds.
      if (tokenUsage != null) {
        debugPrint(
          '[command-llm] in=${tokenUsage.inputTokens} '
          'out=${tokenUsage.outputTokens} '
          'calls=${toolCalls.length}',
        );
      }

      return LlmResponse(
        toolCalls: toolCalls,
        assistantText: assistantText?.trim().isEmpty == true
            ? null
            : assistantText,
        usage: tokenUsage,
      );
    } on Object catch (e, st) {
      debugPrint('[command-llm] parse failed: $e\n$st');
      return const LlmResponse(toolCalls: []);
    }
  }
}

final llmProviderProvider = Provider<LlmProvider>((ref) {
  return const OpenAiProvider();
});
