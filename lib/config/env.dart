abstract final class Env {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://placeholder.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'placeholder-anon-key',
  );

  /// Public URL where recipients open the app to redeem invites.
  /// Pass `--dart-define=APP_SHARE_URL=https://your.deploy.url` at
  /// build time. The default points at the live GitHub Pages
  /// deploy so a build without the override still works; override
  /// it for staging / a custom domain.
  ///
  /// Note: base path matters. The web bundle ships under
  /// `/basecamps/` (see .github/workflows/web.yml), and go_router
  /// uses hash routing by default on web — so a deep link to a
  /// route like `/redeem/<code>` looks like
  /// `https://<host>/basecamps/#/redeem/<code>`.
  static const String appShareUrl = String.fromEnvironment(
    'APP_SHARE_URL',
    defaultValue: 'https://jardinefaner.github.io/basecamps',
  );

  // OPENAI_API_KEY removed from the client (commit 452eb75). All
  // OpenAI calls now route through the Supabase Edge Function
  // `openai-chat`. The long-lived key lives only in Supabase's
  // secret store. Use `OpenAiClient.isAvailable` to gate features.
  //
  // DEEPGRAM_API_KEY removed from the client too. The Edge Function
  // `deepgram-token` exchanges the long-lived project key (server-
  // side secret) for a 30-second JWT every time the client wants
  // to open a realtime listen socket. The JWT is the only Deepgram
  // credential the client ever sees, scoped to a single capture.
  // See `voice_service.dart` for the grant-then-connect flow.
}
