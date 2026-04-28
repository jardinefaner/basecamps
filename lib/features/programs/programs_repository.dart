import 'dart:async';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/auth/auth_repository.dart';
import 'package:basecamp/features/sync/synced_tables.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Drift-backed CRUD + bootstrap for the program model.
///
/// Programs are the unit of sharing in Basecamp's multi-user
/// architecture. Every signed-in user belongs to one or more
/// programs; every data row will eventually carry a `program_id`
/// (Slice C migration). For v1 each user gets a single default
/// program at first sign-in and we don't surface a switcher yet.
///
/// Cloud sync is not in this slice — the local table is the source
/// of truth for now. When Slice C lands, mirror inserts/updates push
/// to Supabase via the same repository.
class ProgramsRepository {
  ProgramsRepository(this._db);

  final AppDatabase _db;

  /// Stream of every program the given user belongs to. Used by the
  /// (future) program switcher; for now it's a one-row stream
  /// because every user only has one program.
  Stream<List<Program>> watchProgramsForUser(String userId) {
    final query = _db.select(_db.programs).join([
      innerJoin(
        _db.programMembers,
        _db.programMembers.programId.equalsExp(_db.programs.id) &
            _db.programMembers.userId.equals(userId),
      ),
    ]);
    return query.watch().map(
          (rows) => [for (final r in rows) r.readTable(_db.programs)],
        );
  }

  /// One-shot list version of [watchProgramsForUser]. The bootstrap
  /// uses this to decide whether a default program needs creating
  /// without subscribing for the lifetime of the call.
  Future<List<Program>> programsForUser(String userId) async {
    final query = _db.select(_db.programs).join([
      innerJoin(
        _db.programMembers,
        _db.programMembers.programId.equalsExp(_db.programs.id) &
            _db.programMembers.userId.equals(userId),
      ),
    ]);
    final rows = await query.get();
    return [for (final r in rows) r.readTable(_db.programs)];
  }

  /// Inserts a new program owned by [userId] and adds [userId] as
  /// the admin member in one transaction. Returns the created
  /// program's id. Used by [ensureDefaultProgram] on first sign-in
  /// and (later) by an explicit "Create another program" action.
  Future<String> createProgram({
    required String name,
    required String userId,
    String role = 'admin',
  }) async {
    final programId = newId();
    await _db.transaction(() async {
      await _db.into(_db.programs).insert(
            ProgramsCompanion.insert(
              id: programId,
              name: name,
              createdBy: userId,
            ),
          );
      await _db.into(_db.programMembers).insert(
            ProgramMembersCompanion.insert(
              programId: programId,
              userId: userId,
              role: Value(role),
            ),
          );
    });
    return programId;
  }

  /// Bootstrap step run on every sign-in. Idempotent:
  ///   - If `userId` already belongs to ≥1 program, returns the id
  ///     of the most recently created one (deterministic pick when
  ///     multi-program lands).
  ///   - Otherwise creates a default "My program" with the user as
  ///     admin and returns the new id.
  ///
  /// The caller (auth bootstrap) hands the result to the active-
  /// program notifier so the rest of the app knows which program's
  /// data to show.
  Future<String> ensureDefaultProgram({
    required String userId,
  }) async {
    final existing = await programsForUser(userId);
    if (existing.isNotEmpty) {
      // Pick the **oldest** — i.e. the first program the user ever
      // created. Bug fix (2026-04-28): the previous "most recent"
      // tiebreaker meant a fresh device that had already mistakenly
      // forked its own program (before the cross-device hydrate
      // landed) would keep picking the empty fork. The original
      // program is by definition the older one, so prefer it. The
      // multi-program switcher (when it ships) overrides this via
      // SharedPreferences anyway, so this only matters for users
      // sitting on the v1 single-program assumption.
      existing.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return existing.first.id;
    }
    return createProgram(
      name: 'My program',
      userId: userId,
    );
  }

  /// Pulls the user's cloud `program_members` rows and the matching
  /// `programs` rows into the local DB. Bug fix (2026-04-28): a
  /// fresh device (e.g. signing in on the phone after using the
  /// laptop) had an empty local DB, so [ensureDefaultProgram] saw
  /// "no programs for this user" and created a brand-new one —
  /// orphaning the laptop's data under a different program id.
  ///
  /// This method runs **before** `ensureDefaultProgram` so the
  /// local lookup finds the cloud-discovered programs and reuses
  /// the laptop's id instead of forking. Idempotent:
  /// `insertOnConflictUpdate` against the same composite PKs.
  ///
  /// Best-effort: any cloud failure (offline, transient RLS blip)
  /// falls through to "create local default", which is the same
  /// recovery path as before this fix — so adding it can't make
  /// things worse, only better.
  Future<int> hydrateCloudProgramsForUser({
    required String userId,
    required SupabaseClient supabase,
  }) async {
    // Step 1: which programs does the cloud think this user is in?
    // RLS only returns rows where `user_id = auth.uid()`, so a
    // simple `.select()` is enough — no extra filter needed for
    // safety, only for clarity.
    final memberRowsRaw = await supabase
        .from('program_members')
        .select('program_id, user_id, role, joined_at')
        .eq('user_id', userId);
    final memberRows = List<Map<String, dynamic>>.from(memberRowsRaw);
    if (memberRows.isEmpty) return 0;

    // Step 2: pull the corresponding programs rows. The select
    // RLS policy on `programs` allows reading any program the
    // user is a member of, so this returns one row per id we
    // just discovered.
    final programIds = [
      for (final m in memberRows) m['program_id'] as String,
    ];
    final programRowsRaw =
        await supabase.from('programs').select().inFilter('id', programIds);
    final programRows = List<Map<String, dynamic>>.from(programRowsRaw);

    // Step 3: write everything into the local DB. Membership
    // first would violate the FK from program_members → programs,
    // so insert programs first, then memberships.
    var written = 0;
    await _db.transaction(() async {
      for (final row in programRows) {
        await _db.into(_db.programs).insertOnConflictUpdate(
              ProgramsCompanion.insert(
                id: row['id'] as String,
                name: row['name'] as String,
                createdBy: row['created_by'] as String,
                createdAt: Value(_parseTs(row['created_at'])),
                updatedAt: Value(_parseTs(row['updated_at'])),
              ),
            );
        written++;
      }
      for (final m in memberRows) {
        await _db.into(_db.programMembers).insertOnConflictUpdate(
              ProgramMembersCompanion.insert(
                programId: m['program_id'] as String,
                userId: m['user_id'] as String,
                role: Value(m['role'] as String? ?? 'teacher'),
                joinedAt: Value(_parseTs(m['joined_at'])),
              ),
            );
        written++;
      }
    });
    return written;
  }

  static DateTime _parseTs(Object? value) {
    if (value == null) return DateTime.now().toUtc();
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString())?.toUtc() ??
        DateTime.now().toUtc();
  }

  /// Renames a program. Bumps `updatedAt` for any future sync
  /// last-write-wins logic. Repository-only check on permissions
  /// for now — the (future) UI gates this behind an admin role.
  Future<void> rename({
    required String programId,
    required String newName,
  }) async {
    await (_db.update(_db.programs)
          ..where((p) => p.id.equals(programId)))
        .write(
      ProgramsCompanion(
        name: Value(newName),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Member list for [programId]. Used by the (future) program
  /// settings screen when the invite flow lands.
  Future<List<ProgramMember>> membersOf(String programId) {
    return (_db.select(_db.programMembers)
          ..where((m) => m.programId.equals(programId)))
        .get();
  }

  /// One-shot stamp of every untagged row in every entity table
  /// with [programId]. Idempotent — only touches rows where
  /// `program_id IS NULL`, so re-running is cheap (no rows match
  /// after the first pass) and safe.
  ///
  /// Called by the auth bootstrap right after [ensureDefaultProgram]
  /// when the user signs in for the first time on a device that
  /// already has data (legacy local DB pre-program model). Future
  /// inserts go through repositories that stamp the column at
  /// write time, so this should only ever update rows on the
  /// transition migration.
  Future<int> backfillUntaggedRows({required String programId}) async {
    // Reads from kSyncedTableNames — same single source of truth
    // the schema-heal and the cloud sync layer use. Adding a new
    // synced table updates this backfill automatically.
    var totalUpdated = 0;
    await _db.transaction(() async {
      for (final table in kSyncedTableNames) {
        final rowsAffected = await _db.customUpdate(
          'UPDATE "$table" SET "program_id" = ? '
          'WHERE "program_id" IS NULL',
          variables: [Variable<String>(programId)],
        );
        totalUpdated += rowsAffected;
      }
    });
    return totalUpdated;
  }
}

final programsRepositoryProvider = Provider<ProgramsRepository>((ref) {
  return ProgramsRepository(ref.read(databaseProvider));
});

/// Active program id, persisted in SharedPreferences. Resolves to
/// null when no user is signed in or when the bootstrap hasn't run
/// yet. Listeners (eventually: every repository scoped to a
/// program) react when the active program changes — switching wipes
/// the visible roster, schedule, etc and reads the new program's
/// data.
///
/// The bootstrap that populates this lives in `ProgramAuthBootstrap`
/// (run from BasecampApp's initState on auth-state changes).
class ActiveProgramNotifier extends Notifier<String?> {
  static const _kPrefKey = 'active_program_id';

  @override
  String? build() {
    // Listen to auth state — sign-out clears the active program
    // since it belongs to a specific user's membership graph.
    ref.listen(currentSessionProvider, (_, session) {
      if (session == null) {
        state = null;
        unawaited(_clearPersisted());
      }
    });
    // Note: we used to async-hydrate from SharedPreferences here,
    // but that raced with [ProgramAuthBootstrap._onSessionChanged]
    // which also writes to state via [set]. If hydrate's getString
    // returned the old SP value AFTER bootstrap's set wrote the
    // new one, state ended up clobbered by the stale id — and
    // every downstream pull / push / realtime subscribe operated
    // against a program the user wasn't a cloud-member of, which
    // surfaced as silent 403s and "I created a row but it didn't
    // sync." Bootstrap is now the single authoritative writer:
    // it reads `readPersisted()` once, decides, and calls `set`.
    return null;
  }

  /// One-shot read of the persisted active program id. Bootstrap
  /// uses this to favor the user's last-active selection when they
  /// belong to multiple programs, falling back to "oldest" only
  /// when the persisted id isn't a current membership.
  ///
  /// Read-only — does NOT touch [state] (that's bootstrap's job
  /// via [set]). Avoids the race the old `_hydrate` had.
  Future<String?> readPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kPrefKey);
    if (stored == null || stored.isEmpty) return null;
    return stored;
  }

  Future<void> _clearPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefKey);
  }

  /// Writes [id] as the active program both in memory (state) and
  /// to SharedPreferences. Called by the bootstrap on sign-in /
  /// session change and by the program switcher screen.
  Future<void> set(String id) async {
    state = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefKey, id);
  }

  /// Clears the active program (sign-out, program deletion). Memory
  /// + persisted both go null.
  Future<void> clear() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefKey);
  }
}

final activeProgramIdProvider =
    NotifierProvider<ActiveProgramNotifier, String?>(
  ActiveProgramNotifier.new,
);
