import 'package:basecamp/app.dart';
import 'package:basecamp/config/env.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  // PKCE web round-trip: if we just landed back from Google's OAuth
  // consent screen, the URL carries `?code=<uuid>` and we need to
  // exchange it for a session BEFORE the router runs its first
  // redirect — otherwise GoRouter sees no session, bounces us to
  // /sign-in, and Supabase's automatic detect-session-in-URL races
  // the route push and loses (the address bar ends up at
  // `?code=...#/sign-in` with the user stuck on the sign-in screen).
  //
  // Doing the exchange explicitly here makes the timing
  // deterministic: we await the network call, the session lands in
  // currentSession, then the router starts and routes straight to
  // /today.
  if (kIsWeb) {
    final code = Uri.base.queryParameters['code'];
    if (code != null && code.isNotEmpty) {
      try {
        await Supabase.instance.client.auth.exchangeCodeForSession(code);
      } on Object catch (e) {
        // Bad / stale code, network blip, RLS rejection — log it and
        // let the user start a fresh sign-in. Better than throwing
        // and bricking the entire app on a recoverable auth glitch.
        debugPrint('OAuth code exchange failed: $e');
      }
    }
  }

  runApp(const ProviderScope(child: BasecampApp()));
}
