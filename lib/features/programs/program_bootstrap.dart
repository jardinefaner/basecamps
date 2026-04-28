import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/auth/auth_repository.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/sync/observations_sync_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
      final repo = _ref.read(programsRepositoryProvider);
      final id = await repo.ensureDefaultProgram(userId: userId);
      await _ref.read(activeProgramIdProvider.notifier).set(id);
      await _maybeBackfillUntaggedRows(repo, programId: id);
      await _maybePushProgramToCloud(programId: id, userId: userId);
      // Slice C: incremental, watermarked pull. Cheap on quiet
      // days (just a "give me rows newer than X" query that
      // returns nothing) and cheap on first launch (capped page
      // size, ~one round-trip per 500 observations). Errors here
      // are non-fatal — local data still shows whatever was last
      // synced; a manual "Sync now" or the next sign-in retries.
      unawaited(_pullObservations(programId: id));
    } on Object catch (e, st) {
      // Bootstrap failure is recoverable — the user's still signed
      // in, just sitting on a no-program state until the next
      // attempt. Logging it lets a dev debug; a user-visible toast
      // would be more noise than signal for a transient DB hiccup.
      debugPrint('Program bootstrap failed: $e\n$st');
    }
  }

  /// Mirrors the active program + this user's membership row to
  /// Supabase. Required for any cloud feature gated by program
  /// membership (Storage RLS on the backup bucket, future per-table
  /// RLS in Slice C). Without it the cloud has no idea this user is
  /// in any program and rejects every cross-table policy check.
  ///
  /// Idempotent on the cloud side via upsert. Guarded by a
  /// SharedPreferences flag so we don't pile on round-trips every
  /// launch — once per (program, install) is enough since the
  /// rows don't change shape.
  ///
  /// Best-effort. If the network is down or RLS rejects, log and
  /// move on. Backup will fail in that case but the rest of the
  /// app keeps working; the next launch retries.
  Future<void> _maybePushProgramToCloud({
    required String programId,
    required String userId,
  }) async {
    final flagKey = 'program_${programId}_pushed_to_cloud';
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(flagKey) ?? false) return;

    try {
      final db = _ref.read(databaseProvider);
      final program = await (db.select(db.programs)
            ..where((p) => p.id.equals(programId)))
          .getSingleOrNull();
      if (program == null) return;

      final supabase = Supabase.instance.client;
      // Upsert the program row (id is the PK; other fields update
      // when re-running). RLS allows this only when created_by
      // matches auth.uid() — the bootstrap always sets created_by
      // to the current user, so the policy passes.
      await supabase.from('programs').upsert(<String, Object?>{
        'id': program.id,
        'name': program.name,
        'created_by': program.createdBy,
        'created_at': program.createdAt.toUtc().toIso8601String(),
        'updated_at': program.updatedAt.toUtc().toIso8601String(),
      });
      // Now the membership row. RLS allows the bootstrap-creator
      // case (user inserting their own first row in a program they
      // just created) so this passes on the first run.
      await supabase.from('program_members').upsert(<String, Object?>{
        'program_id': programId,
        'user_id': userId,
        'role': 'admin',
      });
      await prefs.setBool(flagKey, true);
    } on Object catch (e) {
      // Network failure, RLS rejection, etc. Don't set the flag
      // so the next launch retries. Don't surface to the user;
      // they'll see "backup failed" if the cloud is needed later
      // and that error message is the right place to explain.
      debugPrint('Push program to cloud failed: $e');
    }
  }

  /// Stamps any pre-program-model rows with [programId] the first
  /// time it sees this program. Guarded by a SharedPreferences flag
  /// so we don't re-scan every launch — once per (program, install)
  /// is enough since new rows go in pre-stamped via the repos.
  ///
  /// The flag is per-program-id so a user with multiple programs
  /// (eventual feature) gets a separate one-shot per program. Right
  /// now every install only ever sees one program here.
  Future<void> _maybeBackfillUntaggedRows(
    ProgramsRepository repo, {
    required String programId,
  }) async {
    final flagKey = 'program_${programId}_backfill_v42_done';
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(flagKey) ?? false) return;
    final updated = await repo.backfillUntaggedRows(programId: programId);
    await prefs.setBool(flagKey, true);
    if (updated > 0) {
      debugPrint('Stamped $updated legacy rows with program $programId.');
    }
  }

  /// Slice C pull entry point. Runs the watermarked observations
  /// pull and logs the count without surfacing to the user — a
  /// failed pull just leaves the local DB at whatever it had
  /// before, and the next sign-in or manual "Sync now" retries.
  Future<void> _pullObservations({required String programId}) async {
    try {
      final applied = await _ref
          .read(observationsSyncServiceProvider)
          .pullObservations(programId: programId);
      if (applied > 0) {
        debugPrint('Pulled $applied observations for $programId.');
      }
    } on Object catch (e, st) {
      debugPrint('Pull observations failed: $e\n$st');
    }
  }
}

final programAuthBootstrapProvider = Provider<ProgramAuthBootstrap>((ref) {
  return ProgramAuthBootstrap(ref);
});
