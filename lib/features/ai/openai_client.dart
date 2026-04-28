import 'dart:convert';

import 'package:basecamp/config/env.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Single chokepoint for every OpenAI chat-completions call in the
/// app. All four AI features (observation classify, observation
/// refine, library card generation, AI authoring) post their
/// payload through this helper instead of hitting `api.openai.com`
/// directly.
///
/// Why: shipping the OpenAI API key in a public web bundle is a
/// secret leak. Routing every call through the `openai-chat`
/// Supabase Edge Function keeps the key server-side. The proxy
/// requires a signed-in user's JWT (Supabase verifies it before the
/// function code runs) so anonymous browsers can't drain the bill.
///
/// On native dev / TestFlight builds the proxy is also the right
/// path even though the bundle isn't public — it removes the need
/// to ship the key in dart_defines.json and centralizes future
/// concerns (rate limiting, model allowlisting, audit logging).
class OpenAiClient {
  /// True when there's a signed-in Supabase session whose JWT we
  /// can attach to the proxy call. False before sign-in, right
  /// after sign-out, OR when Supabase isn't initialized at all
  /// (test environment, where `Supabase.initialize` hasn't run).
  /// Callers gate their AI features on this so the UI degrades
  /// gracefully in any of those states.
  static bool get isAvailable {
    try {
      return Supabase.instance.client.auth.currentSession != null;
    } on Object {
      // `Supabase.instance` asserts on uninitialized access; tests
      // that don't bring up a fake Supabase land here. Treat
      // uninitialized exactly like "no session."
      return false;
    }
  }

  /// Posts [payload] to the openai-chat Edge Function. Payload
  /// shape mirrors OpenAI's `/v1/chat/completions` request body
  /// exactly — model, messages, temperature, response_format, etc.
  /// Returns the parsed JSON response on 2xx, throws otherwise.
  ///
  /// Throws [OpenAiClientException] for non-2xx responses with the
  /// status code + response body so callsites can decide how to
  /// degrade (fall back to a local classifier, surface to user, etc).
  static Future<Map<String, dynamic>> chat(
    Map<String, dynamic> payload,
  ) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      throw const OpenAiClientException(
        statusCode: 401,
        message: 'Not signed in — proxy requires a Supabase session',
      );
    }
    final url = Uri.parse('${Env.supabaseUrl}/functions/v1/openai-chat');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        // The user's JWT — Supabase Edge Functions verify it
        // before the function body runs (verify_jwt is the default).
        'Authorization': 'Bearer ${session.accessToken}',
      },
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenAiClientException(
        statusCode: response.statusCode,
        message: response.body,
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}

/// Surfaced for any HTTP failure on the proxy call. Most callsites
/// handle this by silently falling back to a non-AI codepath; a few
/// surface it via snackbar.
class OpenAiClientException implements Exception {
  const OpenAiClientException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() =>
      'OpenAiClientException($statusCode): $message';
}
