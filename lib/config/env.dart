abstract final class Env {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://placeholder.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'placeholder-anon-key',
  );

  /// Deepgram API key for live voice-to-text in Observe. Currently read
  /// client-side; long-term this belongs behind a Supabase edge function.
  static const String deepgramApiKey =
      String.fromEnvironment('DEEPGRAM_API_KEY');

  static bool get hasDeepgram => deepgramApiKey.isNotEmpty;

  /// OpenAI API key used to classify observations (domain + sentiment)
  /// when the teacher saves. Client-side for now — will move behind a
  /// Supabase edge function before any non-dev release.
  static const String openaiApiKey = String.fromEnvironment('OPENAI_API_KEY');

  static bool get hasOpenAi => openaiApiKey.isNotEmpty;
}
