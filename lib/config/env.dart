abstract final class Env {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://placeholder.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'placeholder-anon-key',
  );

  /// Deepgram API key for live voice-to-text in Observe. Still read
  /// client-side because Deepgram's realtime API uses WebSockets
  /// which Supabase Edge Functions can't proxy directly — moving
  /// this behind an edge function needs a temp-token grant pattern,
  /// which is a separate slice. Until then it stays out of public
  /// web bundles (`Env.hasDeepgram` returns false when the value is
  /// empty, which it always is on the GitHub Pages deploy).
  static const String deepgramApiKey =
      String.fromEnvironment('DEEPGRAM_API_KEY');

  static bool get hasDeepgram => deepgramApiKey.isNotEmpty;

  // OPENAI_API_KEY removed from the client. All OpenAI calls now
  // route through the Supabase Edge Function `openai-chat` (see
  // `lib/features/ai/openai_client.dart`). The key lives only in
  // Supabase's secret store, never in any client bundle. Use
  // `OpenAiClient.isAvailable` instead of the old `Env.hasOpenAi`.
}
