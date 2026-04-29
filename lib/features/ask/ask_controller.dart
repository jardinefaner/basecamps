import 'dart:convert';

import 'package:basecamp/features/ai/openai_client.dart';
import 'package:basecamp/features/ask/ask_tools.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One message in the visible conversation. Tool call / tool result
/// messages aren't rendered to the user — they live in the
/// controller's private history list for the model's context but
/// never show up here.
class AskMessage {
  const AskMessage({
    required this.role,
    required this.text,
    this.navIntents = const [],
  });

  /// 'user' or 'assistant'. We don't render system prompts, tool
  /// calls, or tool results in the UI.
  final String role;
  final String text;

  /// Action chips to render below the assistant message — one per
  /// `open_screen` tool call the model emitted while answering.
  final List<NavIntent> navIntents;
}

class AskState {
  const AskState({
    required this.messages,
    required this.thinking,
    this.error,
  });

  factory AskState.empty() =>
      const AskState(messages: [], thinking: false);

  final List<AskMessage> messages;
  final bool thinking;
  final String? error;

  AskState copyWith({
    List<AskMessage>? messages,
    bool? thinking,
    String? error,
    bool clearError = false,
  }) {
    return AskState(
      messages: messages ?? this.messages,
      thinking: thinking ?? this.thinking,
      error: clearError ? null : error ?? this.error,
    );
  }
}

/// Controller for the Ask Basecamp agent.
///
/// Runs a tool-calling loop against gpt-4o-mini through the existing
/// `openai-chat` Edge Function proxy. Each user message:
///   1. Append a `user` message to the LLM context.
///   2. POST to OpenAI with the tool catalog from [askToolSchemas].
///   3. If response carries `tool_calls`, execute each via
///      [runAskTool], append the results as `tool` messages, and
///      loop back to step 2. Capped at 5 iterations to bound cost +
///      avoid runaway loops.
///   4. When the response is text-only, append it as an assistant
///      message and stop. The visible UI only ever sees user +
///      assistant text; tool calls are private context.
///
/// Cost notes: gpt-4o-mini is ~$0.15/1M input, $0.60/1M output. A
/// typical query hits 2–4 tool calls and ~3K total tokens, so a
/// single conversation costs ~$0.001. The session caps history at
/// 16 messages to keep long conversations from drifting up.
class AskController extends Notifier<AskState> {
  static const _model = 'gpt-4o-mini';
  static const _maxIterations = 5;
  static const _historyCap = 16;

  /// Full LLM-side message history including tool calls + results.
  /// The visible state.messages is a filtered projection of this.
  final List<Map<String, dynamic>> _history = [
    {'role': 'system', 'content': _systemPrompt},
  ];

  @override
  AskState build() => AskState.empty();

  void clear() {
    _history
      ..clear()
      ..add({'role': 'system', 'content': _systemPrompt});
    state = AskState.empty();
  }

  Future<void> ask(String userText) async {
    final trimmed = userText.trim();
    if (trimmed.isEmpty || state.thinking) return;

    if (!OpenAiClient.isAvailable) {
      state = state.copyWith(
        error: 'Sign in to use Ask Basecamp.',
      );
      return;
    }

    // Append user message to both the model context and the visible
    // transcript at the same time. The visible message has no nav
    // intents yet — they get attached to the assistant reply below.
    _history.add({'role': 'user', 'content': trimmed});
    _trimHistory();
    state = state.copyWith(
      messages: [
        ...state.messages,
        AskMessage(role: 'user', text: trimmed),
      ],
      thinking: true,
      clearError: true,
    );

    final navIntents = <NavIntent>[];
    String? finalText;
    try {
      for (var iter = 0; iter < _maxIterations; iter++) {
        final response = await OpenAiClient.chat({
          'model': _model,
          'temperature': 0.2,
          'messages': _history,
          'tools': askToolSchemas,
        });
        final choices = response['choices'];
        if (choices is! List || choices.isEmpty) {
          throw const FormatException('Empty response from model');
        }
        final message = (choices.first as Map)['message'] as Map?;
        if (message == null) {
          throw const FormatException('Missing message in response');
        }
        final toolCalls = message['tool_calls'];
        if (toolCalls is List && toolCalls.isNotEmpty) {
          // Persist the assistant turn that emitted the tool calls
          // so the next round-trip carries the conversation forward.
          _history.add(Map<String, dynamic>.from(message));
          for (final raw in toolCalls) {
            final call = raw as Map;
            final id = call['id'] as String? ?? '';
            final fn = (call['function'] as Map?) ?? const {};
            final name = fn['name'] as String? ?? '';
            final argsRaw = fn['arguments'] as String? ?? '{}';
            var args = const <String, dynamic>{};
            try {
              final decoded = jsonDecode(argsRaw);
              if (decoded is Map<String, dynamic>) args = decoded;
            } on FormatException {
              args = const {};
            }
            final result = await runAskTool(
              ref: ref,
              name: name,
              args: args,
            );
            if (result.navIntent != null) {
              navIntents.add(result.navIntent!);
            }
            _history.add({
              'role': 'tool',
              'tool_call_id': id,
              'content': encodeToolResult(result.data),
            });
          }
          _trimHistory();
          continue;
        }
        // Plain text reply — final answer.
        final content = message['content'];
        finalText = content is String ? content : null;
        _history.add({
          'role': 'assistant',
          'content': finalText ?? '',
        });
        _trimHistory();
        break;
      }
      finalText ??= "I couldn't finish reasoning about that — try "
          'rephrasing the question?';
      state = state.copyWith(
        messages: [
          ...state.messages,
          AskMessage(
            role: 'assistant',
            text: finalText,
            navIntents: List.unmodifiable(navIntents),
          ),
        ],
        thinking: false,
      );
    } on Object catch (e) {
      state = state.copyWith(
        thinking: false,
        error: '$e',
      );
    }
  }

  /// Cap the LLM-side history so very long sessions stay cheap.
  /// Keeps the system prompt (always first) plus the most recent
  /// `_historyCap - 1` messages.
  void _trimHistory() {
    if (_history.length <= _historyCap) return;
    const keep = _historyCap - 1;
    final tail = _history.sublist(_history.length - keep);
    _history
      ..clear()
      ..add({'role': 'system', 'content': _systemPrompt})
      ..addAll(tail);
  }

  static const _systemPrompt = '''
You are Ask Basecamp — a focused assistant inside an early-childhood
classroom-coordination app. The teacher using you is on the floor with
their kids; answer in 1–3 sentences unless they explicitly ask for
detail. No preambles, no "I'd be happy to," no apologies for missing
data — just answer.

You have tools that read live program state (today's schedule, today's
curriculum, children, adults, observations). Call them when the
question depends on data; never make up names, counts, or schedule
items. If a tool returns nothing useful, say so plainly.

When the user clearly wants to *navigate* somewhere (e.g. "open Sarah's
profile," "show me the schedule"), call open_screen with a route from
the documented list — don't paste links into the text. When the user
wants to *know* something, just answer in text.

Today's date and the program's current state come from your tools, not
from your training data. Trust the tool output over any prior belief.
''';
}

final askControllerProvider =
    NotifierProvider<AskController, AskState>(AskController.new);
