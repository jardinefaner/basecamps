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

  /// Kicks off the Google OAuth flow. On web the browser navigates to
  /// Google's consent screen, then back to Supabase's callback, then
  /// to our app. Supabase's redirectTo defaults to the current origin
  /// when null — passing the explicit origin avoids surprises in the
  /// rare case the host changes during the redirect chain.
  ///
  /// Returns true when the redirect was initiated. The actual session
  /// arrives later via [onAuthStateChange] when the browser comes
  /// back to our origin.
  Future<bool> signInWithGoogle() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      // On web Supabase reads the current origin; passing null lets it
      // do the right thing in dev (localhost) and prod (Pages URL)
      // without a build flag. On native we'd configure a deep-link
      // scheme — out of scope for this slice (live target is web).
      redirectTo: kIsWeb ? null : null,
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
