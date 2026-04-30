import 'package:basecamp/app.dart';
import 'package:basecamp/config/env.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
    // Web magic-link flow:
    //
    // PKCE (the default) stores a `code_verifier` in localStorage at
    // sign-in-request time, then expects the verifier to still be
    // there when the user clicks the email link. That breaks when
    // the email is clicked from an in-app email browser, an
    // incognito tab, or a different origin than the request — the
    // verifier is on the wrong context, the exchange fails with
    // "Code verifier could not be found in local storage," and
    // the user is stuck.
    //
    // Implicit flow lands the access token in the URL fragment
    // directly, no verifier needed. Slightly less secure
    // (token-in-URL is briefly visible to anything that scrapes
    // address bars), acceptable for this app.
    //
    // Native (iOS/Android) keeps PKCE — the round-trip is via
    // custom URL scheme, never leaves the original app context, so
    // PKCE works fine and is preferable.
    authOptions: const FlutterAuthClientOptions(
      authFlowType:
          kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce,
    ),
  );

  // PKCE web round-trip: if a stale `?code=<uuid>` URL ever lands
  // here (e.g. legacy bookmarked link from before the implicit-flow
  // switch, or a future re-enable of PKCE on web), try to exchange
  // it for a session BEFORE the router runs its first redirect.
  //
  // On failure (the common case post-implicit-flow switch), wipe
  // the `?code=` param from the address bar so the next refresh
  // doesn't re-trigger the same failure and the user can retry
  // sign-in cleanly. Without this cleanup the URL stays
  // `https://.../?code=<dead>` indefinitely and every reload bricks
  // auth.
  if (kIsWeb) {
    final code = Uri.base.queryParameters['code'];
    if (code != null && code.isNotEmpty) {
      try {
        await Supabase.instance.client.auth.exchangeCodeForSession(code);
      } on Object catch (e) {
        debugPrint('OAuth code exchange failed: $e');
        // Strip `?code=...` from the address bar so we don't loop
        // on the same dead code on every refresh. window.history
        // .replaceState is a no-reload swap — the in-flight Flutter
        // boot continues normally with a clean URL.
        try {
          final base = Uri.base;
          final cleaned = Uri(
            scheme: base.scheme,
            host: base.host,
            port: base.hasPort ? base.port : null,
            path: base.path,
            fragment: base.fragment.isEmpty ? null : base.fragment,
          ).toString();
          web.window.history.replaceState(null, '', cleaned);
        } on Object catch (e) {
          debugPrint('Failed to clean stale code from URL: $e');
        }
      }
    }
  }

  runApp(const ProviderScope(child: BasecampApp()));
}
