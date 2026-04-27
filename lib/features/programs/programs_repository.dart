import 'dart:async';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/auth/auth_repository.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      // Pick the most recently created — when a switcher ships, the
      // user's last-active selection (in SharedPreferences) overrides
      // this default.
      existing.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return existing.first.id;
    }
    return createProgram(
      name: 'My program',
      userId: userId,
    );
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
    // Same list as the v42 migration in database.dart. Kept in
    // sync by hand — if a new entity table lands, both lists need
    // an entry.
    const tables = [
      'children',
      'groups',
      'vehicles',
      'trips',
      'adults',
      'roles',
      'parents',
      'rooms',
      'schedule_templates',
      'schedule_entries',
      'observations',
      'activity_library',
      'lesson_sequences',
      'themes',
      'parent_concern_notes',
      'form_submissions',
    ];
    var totalUpdated = 0;
    await _db.transaction(() async {
      for (final table in tables) {
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
    // Hydrate the persisted value asynchronously. UI initially sees
    // null; the bootstrap fills it in within a few frames of
    // launch / sign-in.
    unawaited(_hydrate());
    return null;
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kPrefKey);
    if (stored != null && stored.isNotEmpty) {
      state = stored;
    }
  }

  Future<void> _clearPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefKey);
  }

  /// Writes [id] as the active program both in memory (state) and
  /// to SharedPreferences. Used by the bootstrap on sign-in and by
  /// a future "switch program" action.
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
