import 'package:basecamp/app.dart';
import 'package:basecamp/config/env.dart';
// Conditional import — the stub is a no-op on every native build,
// the web file calls window.history.replaceState. Without the
// conditional, `package:web` (which is web-only) would be pulled
// into Android/iOS compilation and break the kernel build with
// `'JSObject' isn't a type` errors.
import 'package:basecamp/url_cleanup_stub.dart'
    if (dart.library.js_interop) 'package:basecamp/url_cleanup_web.dart'
    as url_cleanup;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  // Web auth round-trip cleanup. Two flavors of OAuth callback can
  // land us back here, both of which need to be consumed AND wiped
  // from the URL BEFORE GoRouter starts — otherwise GoRouter sees
  // the OAuth fragment as a route path and throws "no routes for
  // location."
  //
  //   1. PKCE / `?code=<uuid>` (query). Legacy / future re-enable
  //      of PKCE on web. We attempt `exchangeCodeForSession`; on
  //      failure we still clean the URL so a stale code doesn't
  //      re-fire on every refresh.
  //   2. Implicit / `#access_token=...&refresh_token=...` (fragment).
  //      The current default for Google OAuth on web (see
  //      `authFlowType: AuthFlowType.implicit` above). supabase-
  //      flutter is supposed to consume the fragment automatically
  //      during initialize() when `detectSessionInUri` is on (its
  //      default), but the URL fragment can survive that call —
  //      and GoRouter, which uses fragment-based routing on web,
  //      then trips trying to interpret `access_token=...` as a
  //      route. We belt-and-suspenders it: re-extract via
  //      `getSessionFromUrl` if the session didn't land, then
  //      always wipe the fragment so the router boots clean.
  if (kIsWeb) {
    final code = Uri.base.queryParameters['code'];
    if (code != null && code.isNotEmpty) {
      try {
        await Supabase.instance.client.auth.exchangeCodeForSession(code);
      } on Object catch (e) {
        debugPrint('OAuth code exchange failed: $e');
      }
      _cleanWebUrl();
    }

    // Implicit-flow callback. The fragment carries `access_token=...`
    // along with `refresh_token`, `expires_at`, etc. Even if Supabase
    // has already consumed it, we wipe the URL — having the fragment
    // still in the address bar would crash the first GoRouter redirect.
    final fragment = Uri.base.fragment;
    if (fragment.contains('access_token=')) {
      try {
        // No-op when Supabase already pulled the session during
        // initialize(); reapplies otherwise. We only call this when
        // the fragment is present, so a normal cold launch never
        // hits it.
        if (Supabase.instance.client.auth.currentSession == null) {
          await Supabase.instance.client.auth.getSessionFromUrl(Uri.base);
        }
      } on Object catch (e) {
        debugPrint('Implicit-flow session recovery failed: $e');
      }
      _cleanWebUrl();
    }
  }

  runApp(const ProviderScope(child: BasecampApp()));
}

/// Strip query + fragment off the address bar without reloading.
/// Used after a successful (or failed) auth round-trip so the
/// router doesn't try to interpret `?code=...` or `#access_token=...`
/// as a route. No-op on every native build (the conditional import
/// resolves to `url_cleanup_stub.dart` there).
void _cleanWebUrl() {
  try {
    final base = Uri.base;
    final cleaned = Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: base.path,
    ).toString();
    url_cleanup.replaceUrl(cleaned);
  } on Object catch (e) {
    debugPrint('Failed to clean URL: $e');
  }
}
