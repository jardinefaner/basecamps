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

  /// Custom URL scheme for OAuth round-trip on native iOS/Android.
  /// Registered in `ios/Runner/Info.plist` (CFBundleURLTypes) and in
  /// `android/app/src/main/AndroidManifest.xml` (an intent-filter on
  /// MainActivity). Must also be added to Supabase's allowed
  /// Redirect URLs list — without that Supabase won't accept the
  /// destination and bounces the user to the Site URL fallback.
  ///
  /// Web ignores this and uses the current origin instead.
  static const String _nativeOauthRedirect =
      'com.example.basecamps://login-callback/';

  /// Kicks off the Google OAuth flow. The browser leaves to Google's
  /// consent screen, then to Supabase's callback, then back to our
  /// app — to the current origin on web, or to [_nativeOauthRedirect]
  /// on iOS/Android (which the OS routes to this app's MainActivity /
  /// SceneDelegate, where supabase_flutter's app-link listener picks
  /// up the fragment and updates the session).
  ///
  /// Returns true when the redirect was initiated. The actual session
  /// arrives later via [onAuthStateChange].
  Future<bool> signInWithGoogle() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : _nativeOauthRedirect,
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
