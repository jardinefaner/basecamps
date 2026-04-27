import 'dart:async';

import 'package:basecamp/features/auth/auth_repository.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Listens to auth-state changes and ensures every signed-in user
/// has a default program with themselves as the admin member, then
/// stamps that program id into [activeProgramIdProvider]. Runs once
/// per sign-in.
///
/// Intentionally not a UI-bound provider — the BasecampApp widget
/// instantiates this in its initState so it fires regardless of
/// which screen is mounted. Without that, a deep-linked /today
/// would render before the bootstrap, and any program-scoped
/// repository would see a null active program.
class ProgramAuthBootstrap {
  ProgramAuthBootstrap(this._ref);

  final Ref _ref;

  /// Subscribes to [currentSessionProvider] and runs
  /// [_onSessionChanged] for every transition. Returns the
  /// subscription so the caller can close it from dispose().
  ProviderSubscription<Session?> start() {
    // Fire once with the current session in case the app launched
    // already signed in (browser refresh, native app reopen).
    final initial = _ref.read(currentSessionProvider);
    if (initial != null) {
      unawaited(_onSessionChanged(initial.user.id));
    }
    return _ref.listen<Session?>(currentSessionProvider, (_, session) {
      if (session == null) {
        // Sign-out: clear the active program. The notifier also
        // wipes itself on auth state, but doing it explicitly here
        // makes the order deterministic (active program clears
        // before any UI rebuild reacts to no-session).
        unawaited(_ref.read(activeProgramIdProvider.notifier).clear());
        return;
      }
      unawaited(_onSessionChanged(session.user.id));
    });
  }

  Future<void> _onSessionChanged(String userId) async {
    try {
      final id = await _ref
          .read(programsRepositoryProvider)
          .ensureDefaultProgram(userId: userId);
      await _ref.read(activeProgramIdProvider.notifier).set(id);
    } on Object catch (e, st) {
      // Bootstrap failure is recoverable — the user's still signed
      // in, just sitting on a no-program state until the next
      // attempt. Logging it lets a dev debug; a user-visible toast
      // would be more noise than signal for a transient DB hiccup.
      debugPrint('Program bootstrap failed: $e\n$st');
    }
  }
}

final programAuthBootstrapProvider = Provider<ProgramAuthBootstrap>((ref) {
  return ProgramAuthBootstrap(ref);
});
