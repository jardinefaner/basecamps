import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/auth/auth_repository.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:basecamp/features/sync/sync_specs.dart';
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

  /// Last user id we ran [_onSessionChanged] for. Guards against
  /// the bootstrap firing on every JWT rotation — supabase-flutter
  /// notifies `currentSessionProvider` whenever the session
  /// refreshes, but the user is the same. Without this guard the
  /// bootstrap would do a full hydrate + push every refresh,
  /// which (a) wastes bandwidth and (b) created a feedback loop
  /// when the bootstrap itself called `refreshSession()` — the
  /// refresh notified the listener, which re-ran bootstrap, which
  /// refreshed again, until Supabase auth rate-limited at 429 and
  /// the user effectively got signed out.
  String? _lastProcessedUserId;

  /// While [_onSessionChanged] is in flight, callers (specifically
  /// the router redirect) need to know not to bounce the user to
  /// /welcome — the active-program id is null because we haven't
  /// finished hydrating yet, not because the user has no
  /// memberships. Toggled via [programBootstrapInProgressProvider]
  /// from inside [_onSessionChanged].

  /// Subscribes to [currentSessionProvider] and runs
  /// [_onSessionChanged] for every transition. Returns the
  /// subscription so the caller can close it from dispose().
  ProviderSubscription<Session?> start() {
    // Fire once with the current session in case the app launched
    // already signed in (browser refresh, native app reopen).
    final initial = _ref.read(currentSessionProvider);
    if (initial != null) {
      _lastProcessedUserId = initial.user.id;
      unawaited(_onSessionChanged(initial.user.id));
    }
    return _ref.listen<Session?>(currentSessionProvider, (_, session) {
      if (session == null) {
        _lastProcessedUserId = null;
        // Sign-out: clear the in-memory state only.
        //
        // We deliberately do NOT wipe the local DB here. The wipe
        // used to live on this path (fire-and-forget), which raced
        // with a fast sign-in: the user signs out, the wipe starts
        // async, the user signs back in, the new bootstrap's pull
        // writes adults / kids / etc., then the in-flight wipe
        // finishes and *deletes the just-pulled rows*. Visible
        // result: "I created an adult, signed out and back in,
        // and now it's gone — but it's still in Supabase."
        //
        // The wipe still runs when it should — see _maybeWipeForUserChange
        // at the start of _onSessionChanged. That path is awaited
        // atomically inside the sign-in sequence so it can't race
        // with the pull that follows it.
        unawaited(_ref.read(activeProgramIdProvider.notifier).clear());
        unawaited(_ref.read(syncEngineProvider).unsubscribeFromRealtime());
        return;
      }
      // Skip JWT rotations / re-emits — they don't change who's
      // signed in. Only run bootstrap on actual user transitions.
      if (_lastProcessedUserId == session.user.id) return;
      _lastProcessedUserId = session.user.id;
      unawaited(_onSessionChanged(session.user.id));
    });
  }

  Future<void> _onSessionChanged(String userId) async {
    // Flip the in-progress flag while we hydrate cloud + decide an
    // active program. The router redirect reads this to suppress
    // the /welcome bounce during the fresh-sign-in window when
    // activeProgramIdProvider is transiently null. Always reset to
    // false on exit (success or failure) so a stuck flag doesn't
    // leave the redirect waiting forever.
    _ref.read(programBootstrapInProgressProvider.notifier).set(true);
    try {
      // First step: if the user on this device changed since the
      // last sign-in, wipe the previous user's data so it doesn't
      // bleed into this one's view. Awaited (synchronous within
      // the bootstrap) so it can't race the pull that follows.
      // No-op when the same user signs back in — preserves their
      // local rows + watermarks.
      await _maybeWipeForUserChange(userId);

      final repo = _ref.read(programsRepositoryProvider);
      // Cross-device fix (2026-04-28): pull the user's existing
      // cloud programs into the local DB *before* we decide
      // whether to create a default. Without this step a fresh
      // device (signing in on the phone after using the laptop)
      // would see "no local programs for this user", create a new
      // one, and orphan the laptop's data under a different
      // program id. Best-effort: if cloud is unreachable we fall
      // through to the legacy "create local default" path, which
      // is the same recovery as before — adding this step can't
      // make things worse, only better.
      try {
        final hydrated = await repo.hydrateCloudProgramsForUser(
          userId: userId,
          supabase: Supabase.instance.client,
        );
        if (hydrated > 0) {
          debugPrint('Hydrated $hydrated cloud program/membership rows.');
        }
      } on Object catch (e) {
        debugPrint('Cloud program hydrate skipped: $e');
      }
      // Decide which program (if any) to set active. Hard rule:
      // **never auto-create a default program**. A signed-in user
      // with zero memberships belongs on /welcome, where they
      // pick "Join with code" or "Start a new program" — not on
      // a silently-minted "My program" that hides whatever data
      // they were expecting.
      //
      // We used to auto-create when local Drift had rows tagged
      // `program_id IS NULL` (legacy pre-program-model users), but
      // (a) that path silently inserts a program for every fresh
      // sign-in on a device that previously had a different
      // account's data, and (b) every install is now well past
      // v42 so genuinely-untagged rows shouldn't exist anyway.
      // Welcome is the safer landing.
      final notifier = _ref.read(activeProgramIdProvider.notifier);
      final persisted = await notifier.readPersisted();
      final memberships = await repo.programsForUser(userId);
      String? id;
      if (persisted != null &&
          memberships.any((p) => p.id == persisted)) {
        id = persisted;
      } else if (memberships.isNotEmpty) {
        final sorted = [...memberships]
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        id = sorted.first.id;
      }
      if (id == null) {
        await notifier.clear();
        return;
      }
      await notifier.set(id);
      await _maybeBackfillUntaggedRows(repo, programId: id);
      // Always upsert the program + membership rows on every
      // launch — idempotent + cheap (two upserts), and the only
      // way to recover from a previous launch where the push
      // silently failed (e.g. RLS recursion before 0011 landed).
      // Without this, a user stuck in that state would never be
      // able to push / sync because their cloud membership row
      // was missing.
      await _ensureProgramAndMembershipInCloud(
        programId: id,
        userId: userId,
      );
      // Incremental watermarked pull of every synced table. Cheap
      // on quiet days; capped page size on first launch.
      unawaited(_pullAllTables(programId: id));
      // Realtime channel so changes from other devices land
      // within milliseconds. Echo-safe + idempotent.
      unawaited(
        _ref.read(syncEngineProvider).subscribeToRealtime(
              programId: id,
              specs: kAllSpecs,
            ),
      );
    } on Object catch (e, st) {
      // Bootstrap failure is recoverable — the user's still signed
      // in, just sitting on a no-program state until the next
      // attempt. Logging it lets a dev debug; a user-visible toast
      // would be more noise than signal for a transient DB hiccup.
      debugPrint('Program bootstrap failed: $e\n$st');
    } finally {
      // Clear the in-progress flag on every exit path (success,
      // membership-not-found, or thrown). This re-fires the router's
      // refreshListenable so the redirect re-evaluates with the now-
      // settled active-program id.
      _ref.read(programBootstrapInProgressProvider.notifier).set(false);
    }
  }

  /// SharedPreferences key for the last user.id who signed into
  /// this device. Used to decide whether the bootstrap should wipe
  /// existing local data on sign-in (different user → wipe;
  /// same user → keep, even after a sign-out + sign-back-in
  /// roundtrip).
  static const _kLastSignedInUserIdKey = 'last_signed_in_user_id';

  /// If the persisted last-user differs from the current one, wipe
  /// every program's local data before the bootstrap continues.
  /// Awaited so the wipe completes before any pull writes new
  /// rows — the previous fire-and-forget wipe on sign-out raced
  /// with a fast sign-in's pull and ate the just-pulled rows.
  ///
  /// Persists the current userId at the end so the next sign-in
  /// has something to compare against. First-launch (no previous
  /// id stored) doesn't wipe — the local DB is empty anyway.
  Future<void> _maybeWipeForUserChange(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getString(_kLastSignedInUserIdKey);
    if (previous != null && previous != userId) {
      debugPrint(
        'User changed on this device ($previous → $userId); '
        'wiping local program data before re-hydrate.',
      );
      try {
        await _ref.read(databaseProvider).wipeAllProgramData();
      } on Object catch (e, st) {
        // A failed wipe is bad but not catastrophic — the new
        // user's pull will write its own rows alongside the old
        // user's. Surface in logs and keep going so the user
        // isn't stuck on a blank app.
        debugPrint('Wipe-on-user-change failed: $e\n$st');
      }
    }
    await prefs.setString(_kLastSignedInUserIdKey, userId);
  }

  /// Mirrors the active program + this user's membership row to
  /// Supabase on every launch. Idempotent: both writes are upserts
  /// against composite PKs, so re-running is a no-op when nothing
  /// changed. Required for any cloud feature gated by program
  /// membership — sync push/pull, realtime subscribe, storage
  /// upload — and the only way to recover from a state where a
  /// prior push silently failed (e.g. RLS recursion before 0011
  /// landed left the membership row missing in cloud).
  ///
  /// Used to be guarded by a SharedPreferences "already pushed"
  /// flag (commit history: `_maybePushProgramToCloud`) so we'd
  /// skip the round-trip after the first success. We dropped the
  /// flag because a single silent failure left the user
  /// permanently stuck — the flag prevented retries, every later
  /// push 403'd against the missing membership, and the user saw
  /// "I created a row but it didn't sync" with no path to recover.
  /// Two cheap upserts per launch is the right trade.
  ///
  /// Best-effort. If the network is down or RLS rejects, log and
  /// move on; the next launch retries.
  Future<void> _ensureProgramAndMembershipInCloud({
    required String programId,
    required String userId,
  }) async {
    try {
      final db = _ref.read(databaseProvider);
      final program = await (db.select(db.programs)
            ..where((p) => p.id.equals(programId)))
          .getSingleOrNull();
      if (program == null) return;

      // Only the creator can push the program / membership rows
      // through RLS:
      //   * `programs` INSERT policy → `auth.uid() = created_by`
      //   * `programs` UPDATE policy → `is_program_admin`
      //   * `program_members` INSERT policy → admin-of-program OR
      //     self-as-program-creator
      //
      // For invitees and other non-creators, the program row was
      // pushed by the original creator and the membership row was
      // inserted by the `accept-invite` edge function (service-
      // role bypass). Re-pushing from a non-creator's bootstrap
      // would 42501 every launch — exactly the symptom we hit
      // when "rooms" sync push started failing because the
      // bootstrap had already poisoned the membership state.
      // Skip cleanly.
      if (program.createdBy != userId) return;

      // Don't refresh the session here. Calling
      // `refreshSession()` rotates the JWT, which notifies
      // currentSessionProvider, which re-fires this bootstrap,
      // which... refreshes again. The earlier user-id guard in
      // `start()` short-circuits the loop, but even one extra
      // refresh per launch hits Supabase auth's rate limit when
      // chained with `createAndSwitchProgram`'s refresh on
      // user-initiated create. Just trust the session that's
      // already in scope — supabase-flutter auto-refreshes
      // ahead of expiry on its own clock.

      final supabase = Supabase.instance.client;
      // Upsert the program row (id is the PK; other fields update
      // when re-running). RLS allows this only when created_by
      // matches auth.uid() — guaranteed since we just checked.
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
      // Membership upsert. The composite PK (program_id, user_id)
      // makes this idempotent — a re-run for the same pair is a
      // no-op if the row already exists, or fixes the role if it
      // somehow drifted. RLS allows: admin of the program OR
      // self-insert when the user is the program's `created_by`.
      // Bootstrap created the program with `created_by = auth.uid()`
      // so this passes on first launch and on every subsequent one.
      await supabase.from('program_members').upsert(<String, Object?>{
        'program_id': programId,
        'user_id': userId,
        'role': 'admin',
      });
    } on Object catch (e) {
      // Network failure, RLS rejection, etc. The next launch retries
      // because we no longer guard with a SharedPreferences flag.
      debugPrint('Ensure program/membership in cloud failed: $e');
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

  /// Switch the active program to [newProgramId]. Public entry
  /// point for the program switcher (Slice 2). The sequence:
  ///
  /// 1. **Flush pending pushes.** A row edited just before the
  ///    switch is sitting in the engine's 250ms debounce queue;
  ///    if we let it fire after the switch, the push happens with
  ///    the new active program in scope. Force-flush now so old-
  ///    program writes hit cloud before we move on.
  /// 2. **Unsubscribe realtime.** Clean break — no stray events
  ///    from the old program leaking into the new one's view.
  /// 3. **Set active.** Persist the new id in SharedPreferences so
  ///    a relaunch picks the same program.
  /// 4. **Pull.** Walk the tier list and pull deltas for the new
  ///    program. On first switch this is the full table set
  ///    (since `sync_state` has no watermark for the new program).
  /// 5. **Subscribe realtime.** Fresh channel filtered to the new
  ///    program id.
  ///
  /// Idempotent — switching to the program already active no-ops
  /// after the active-id check, but still flushes pending pushes
  /// (cheap and gives the caller a sync point).
  Future<void> switchProgram(String newProgramId) async {
    final current = _ref.read(activeProgramIdProvider);
    final engine = _ref.read(syncEngineProvider);
    await engine.flushPendingPushes(kAllSpecs);
    if (current == newProgramId) return;
    await engine.unsubscribeFromRealtime();
    await _ref.read(activeProgramIdProvider.notifier).set(newProgramId);
    await _pullAllTables(programId: newProgramId);
    await engine.subscribeToRealtime(
      programId: newProgramId,
      specs: kAllSpecs,
    );
  }

  /// Create a new program owned by the current user, push it to
  /// cloud, and switch to it. Used by the "New program" sheet on
  /// the programs screen. Different from `_maybePushProgramToCloud`
  /// because this path always pushes (no SharedPreferences flag —
  /// the program was created seconds ago, no possible duplicate).
  ///
  /// Returns the new program id so the caller can pop the sheet
  /// and surface a toast like "Switched to 'My after-school'".
  Future<String> createAndSwitchProgram({
    required String name,
    required String userId,
  }) async {
    // The persistent 42501 ("new row violates RLS for 'programs'")
    // means the server's `auth.uid()` doesn't match what we send
    // as `created_by`. Before doing the cloud upsert, prove the
    // session is actually valid server-side:
    //
    //   1. `refreshSession()` rotates the JWT.
    //   2. `getUser()` contacts the server with the new JWT —
    //      if it succeeds, we know `auth.uid()` server-side
    //      matches the returned user.id. If it fails, the
    //      session is broken (refresh token expired, project
    //      mismatch, etc.) and we abort with a clean error
    //      that tells the user to sign in again.
    //
    // Without step 2, `currentUser?.id` returns a cached value
    // even when the JWT is no longer valid — the create flow
    // proceeds with a `created_by` that the server rejects.
    final auth = Supabase.instance.client.auth;
    try {
      await auth.refreshSession();
    } on Object catch (e) {
      throw StateError(
        'Sign-in expired and the refresh failed: $e\n'
        'Sign out and sign back in, then try again.',
      );
    }
    final UserResponse verified;
    try {
      verified = await auth.getUser();
    } on Object catch (e) {
      throw StateError(
        'Could not verify sign-in with the server: $e\n'
        'Sign out and sign back in, then try again.',
      );
    }
    final live = verified.user?.id;
    if (live == null) {
      throw StateError(
        'Sign-in lapsed. Sign out and sign back in, then try again.',
      );
    }
    final effectiveUserId = live;
    final repo = _ref.read(programsRepositoryProvider);
    final id =
        await repo.createProgram(name: name, userId: effectiveUserId);
    final supabase = Supabase.instance.client;
    final db = _ref.read(databaseProvider);
    final program = await (db.select(db.programs)
          ..where((p) => p.id.equals(id)))
        .getSingleOrNull();
    // Cloud push is REQUIRED for cross-device sync. If the upsert
    // fails the local row exists but no other device can ever see
    // this program — we'd silently end up with one program per
    // device, all under the same email, none of them syncing.
    // Surface the error so the user knows + can retry, and
    // unwind the local row so a retry doesn't accumulate orphans.
    if (program != null) {
      try {
        await supabase.from('programs').upsert(<String, Object?>{
          'id': program.id,
          'name': program.name,
          'created_by': program.createdBy,
          'created_at': program.createdAt.toUtc().toIso8601String(),
          'updated_at': program.updatedAt.toUtc().toIso8601String(),
        });
        await supabase.from('program_members').upsert(<String, Object?>{
          'program_id': id,
          'user_id': effectiveUserId,
          'role': 'admin',
        });
      } on Object catch (e, st) {
        debugPrint('Cloud push of new program failed: $e\n$st');
        // Roll back the local program so a retry doesn't leave
        // an orphan in the user's "Programs" list. The cascade
        // delete on `program_members` cleans the membership row.
        await (db.delete(db.programs)..where((p) => p.id.equals(id))).go();
        rethrow;
      }
    }
    // Fast switch — a fresh program has zero data on the cloud
    // side (we just created it), so the full `switchProgram`
    // (which awaits a tier-by-tier `_pullAllTables`) would just
    // burn seconds on round-trips that all return empty. Bug:
    // when the create sheet awaited the long switch, the modal
    // sat with a spinner long enough that the user thought
    // nothing was happening. Instead: flush, set active, kick
    // pull + realtime in the background and return immediately.
    final engine = _ref.read(syncEngineProvider);
    await engine.flushPendingPushes(kAllSpecs);
    await engine.unsubscribeFromRealtime();
    await _ref.read(activeProgramIdProvider.notifier).set(id);
    unawaited(_pullAllTables(programId: id));
    unawaited(
      engine.subscribeToRealtime(programId: id, specs: kAllSpecs),
    );
    return id;
  }

  /// Slice C pull entry point. Walks the FK-ordered tier list
  /// from `kSpecTiers` — pulls every table in a tier in parallel
  /// (Future.wait), but waits for the tier to finish before
  /// starting the next so FK targets land before dependents.
  ///
  /// Cost shape: 16 sequential 1s round-trips (the old loop)
  /// becomes 3 tier-batches (~1s each) for ~3s total — 5x faster
  /// on first launch. Quiet-day pulls were already fast (empty
  /// deltas) but now they're even faster.
  ///
  /// Each table's pull is independent — a failure on one (RLS
  /// blip, transient network error) doesn't stop the rest.
  Future<void> _pullAllTables({required String programId}) async {
    final engine = _ref.read(syncEngineProvider);
    var total = 0;
    for (final tier in kSpecTiers) {
      // Parallel within the tier; sequential between tiers.
      final results = await Future.wait([
        for (final spec in tier)
          engine
              .pullTable(spec: spec, programId: programId)
              .then<int>((applied) {
            if (applied > 0) {
              debugPrint('Pulled $applied ${spec.table} for $programId.');
            }
            return applied;
          }).catchError((Object e, StackTrace st) {
            debugPrint('Pull ${spec.table} failed: $e\n$st');
            return 0;
          }),
      ]);
      for (final n in results) {
        total += n;
      }
    }
    if (total > 0) {
      debugPrint('Sync pull complete — $total rows applied across '
          '${kAllSpecs.length} tables.');
    }
  }
}

final programAuthBootstrapProvider = Provider<ProgramAuthBootstrap>((ref) {
  return ProgramAuthBootstrap(ref);
});

/// True while [ProgramAuthBootstrap._onSessionChanged] is hydrating
/// cloud programs and deciding the active program for a fresh sign-
/// in. The router redirect reads this so it doesn't bounce a freshly-
/// authenticated user to /welcome during the few hundred ms while
/// active-program-id is transiently null. Toggled inside the
/// bootstrap; nobody else writes it.
class _BootstrapInProgressNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  // Single-method imperative setter — easier to read at the
  // callsite than `notifier.state = value` for a state with one
  // semantic meaning.
  // ignore: use_setters_to_change_properties, avoid_positional_boolean_parameters
  void set(bool value) {
    state = value;
  }
}

final programBootstrapInProgressProvider =
    NotifierProvider<_BootstrapInProgressNotifier, bool>(
  _BootstrapInProgressNotifier.new,
);
