import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper around Supabase's auth stream so the rest of the app
/// reads sessions through Riverpod, never `Supabase.instance` directly.
/// That keeps tests easy (override the provider) and keeps the auth
/// dependency to a single file.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  /// Current session, or null when signed out. Synchronous read for
  /// guards / redirects that can't wait on the stream.
  Session? get currentSession => _client.auth.currentSession;

  /// Stream of every auth state transition (sign-in, sign-out, token
  /// refresh, etc). Riverpod's [authStateProvider] watches this and
  /// the router rebuilds on changes.
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  /// Custom URL scheme for the auth round-trip on native iOS/Android.
  /// Registered in `ios/Runner/Info.plist` (CFBundleURLTypes) and in
  /// `android/app/src/main/AndroidManifest.xml` (an intent-filter on
  /// MainActivity). Must also be added to Supabase's allowed
  /// Redirect URLs list — without that Supabase won't accept the
  /// destination and bounces the user to the Site URL fallback.
  static const String _nativeAuthRedirect =
      'com.example.basecamps://login-callback/';

  /// Resolves the redirect URL for an in-progress web auth round-
  /// trip. Strips any query/fragment off the current URL so the
  /// callback lands on a clean app URL — `Uri.base` on a route
  /// like `/basecamps/sign-in?something=x#hash` would otherwise
  /// preserve the cruft and confuse the post-sign-in router.
  ///
  /// Why we don't just leave `redirectTo: null` and trust Supabase
  /// to use Site URL: supabase_flutter web defaults a missing
  /// redirect to `window.location.origin` (just the host, no
  /// path), and that bare-origin URL is sometimes in the Redirect
  /// URLs allowlist (matching a wildcard or root entry). Supabase
  /// then honors it over Site URL and lands the user at
  /// `https://<host>/?code=...`, which 404s on GitHub Pages
  /// because the project is at `/basecamps/`, not the root.
  ///
  /// Reading the base path from the running app means the same
  /// code works for local dev (`http://localhost:5000/`) and
  /// production (`https://jardinefaner.github.io/basecamps/`)
  /// without a build-time flag.
  static String _webAuthRedirect() {
    final base = Uri.base;
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: base.path,
    ).toString();
  }

  /// Kicks off the Google OAuth flow. Used on native (iOS/Android),
  /// where it works cleanly via the custom URL scheme deep link. The
  /// browser leaves to Google's consent screen, then Supabase's
  /// callback, then routes back to this app's MainActivity /
  /// SceneDelegate via [_nativeAuthRedirect]; supabase_flutter's
  /// app-link listener picks up the session.
  ///
  /// Web sign-in goes through [signInWithMagicLink] instead — Google
  /// OAuth + GitHub Pages + PKCE turned out to be a maze of edge cases
  /// (Workspace policies, redirect-host validation, hash routing
  /// collisions) that swallowed real time without payoff. Magic link
  /// works in one step on every browser.
  ///
  /// Returns true when the redirect was initiated. The actual session
  /// arrives later via [onAuthStateChange].
  Future<bool> signInWithGoogle() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? _webAuthRedirect() : _nativeAuthRedirect,
    );
  }

  /// Email magic-link sign-in. Used as the primary web path (where
  /// Google OAuth has been finicky). Supabase emails the address a
  /// link the user clicks once — clicking it lands them back at the
  /// app URL with an auth token, supabase_flutter parses it, and the
  /// session lands.
  ///
  /// Works on native too as a fallback, but the default native flow
  /// is Google OAuth.
  ///
  /// Throws on Supabase errors (rate-limit, invalid email, etc); the
  /// sign-in screen catches and surfaces the message inline.
  Future<void> signInWithMagicLink({required String email}) {
    return _client.auth.signInWithOtp(
      email: email,
      // Same web vs native split as signInWithGoogle. The web path
      // builds an explicit URL from Uri.base so the magic-link
      // email's embedded redirect lands at /basecamps/, not at the
      // bare origin (which 404s — see [_webAuthRedirect] for the
      // long version of why).
      emailRedirectTo:
          kIsWeb ? _webAuthRedirect() : _nativeAuthRedirect,
    );
  }

  /// Drops the local session and clears any cached user data Supabase
  /// holds. The auth state stream emits `signedOut` on completion.
  Future<void> signOut() => _client.auth.signOut();
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(Supabase.instance.client);
});

/// Streams the current Supabase auth state. Router watches this to
/// gate every route on `session != null`.
///
/// Seeded with the current session so the very first frame after
/// launch already knows whether we're signed in — without it, a hot
/// reload or refresh would always render the sign-in screen for one
/// frame before the stream emitted.
final authStateProvider = StreamProvider<AuthState>((ref) async* {
  final repo = ref.watch(authRepositoryProvider);
  final seed = repo.currentSession;
  if (seed != null) {
    // Synthesize an initial event so listeners (the router redirect)
    // have something to react to before the real stream emits.
    yield AuthState(AuthChangeEvent.initialSession, seed);
  }
  yield* repo.onAuthStateChange;
});

/// Synchronous accessor for the current session. Cheap — reads the
/// already-cached value in the Supabase client. Good for redirect
/// callbacks that need an answer right now, not a stream.
final currentSessionProvider = Provider<Session?>((ref) {
  // Keep this in sync with auth state changes by depending on the
  // stream provider's last value. Riverpod will recompute whenever a
  // new AuthState lands.
  ref.watch(authStateProvider);
  return ref.read(authRepositoryProvider).currentSession;
});
