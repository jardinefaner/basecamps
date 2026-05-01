import 'dart:async';
import 'dart:math';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/program_bootstrap.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Slice 3: invite codes + member admin (rename/role/remove/leave).
///
/// Cloud-direct: invites only live on the cloud (no local mirror).
/// Listing the program's outstanding invites is a one-shot
/// `select` filtered by program; redemption goes through the
/// `accept-invite` edge function so the recipient (who isn't a
/// member yet) can bypass the `program_members` insert RLS.
///
/// Member admin (rename role / remove / leave) hits both cloud
/// (the row of truth) and Drift (so realtime / sync render the
/// updated state without waiting for a pull). Reads come from the
/// local copy because the program switcher already pulls
/// `program_members` on bootstrap.
class InviteRepository {
  InviteRepository(this._db, this._client);

  final AppDatabase _db;
  final SupabaseClient _client;

  // -- Generate invite code -----------------------------------------

  /// Default expiry — short enough that an unused code goes stale,
  /// long enough that "I'll send it tonight" works.
  static const _defaultLifetime = Duration(days: 7);

  /// Alphabet for the invite code. Excludes 0/O/1/I to avoid
  /// reading-aloud confusion. 32 chars, 8-char codes ≈ 1.1 trillion
  /// possibilities — enumeration-resistant on its own, plus the
  /// recipient can only redeem via the edge function which the
  /// runtime rate-limits.
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static final _rng = Random.secure();

  /// Generate + insert a new invite for [programId]. Returns the
  /// row so the caller can render the code (copy + share-sheet)
  /// immediately. PK collisions are vanishingly rare at 8 chars
  /// from a 32-char alphabet, but the loop retries on the unlikely
  /// duplicate. Caller must be an admin of the program (RLS
  /// enforces; this method just calls the upsert).
  Future<InviteRow> createInvite({
    required String programId,
    String role = 'teacher',
    Duration lifetime = _defaultLifetime,
    /// When set, the invite binds the redeemer's auth user id onto
    /// this specific Adult row at acceptance time (v54 identity
    /// binding). Null = generic membership invite, same as the
    /// pre-v54 flow.
    String? adultId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('createInvite requires a signed-in user');
    }
    final expiresAt = DateTime.now().toUtc().add(lifetime);
    var attempts = 0;
    while (true) {
      attempts++;
      final code = _generateCode();
      try {
        final inserted = await _client.from('program_invites').insert({
          'code': code,
          'program_id': programId,
          'role': role,
          'created_by': user.id,
          'expires_at': expiresAt.toIso8601String(),
          'adult_id': ?adultId,
        }).select().single();
        return InviteRow.fromJson(inserted);
      } on PostgrestException catch (e) {
        // PGRST205 = "table not in schema cache" → migration not
        // applied. Surface a developer-friendly message so a
        // teacher hitting this on a half-deployed Supabase
        // project knows it's a deploy issue, not a bug.
        if (e.code == 'PGRST205' || e.code == '42P01') {
          throw const InviteSetupError(
            'Invites aren’t set up on the server yet. Apply '
            'migration 0012_program_invites.sql in the Supabase '
            'dashboard.',
          );
        }
        // 23505 = unique_violation. Retry up to 5 times before
        // giving up — a deterministic upper bound that should
        // never fire in practice.
        if (e.code == '23505' && attempts < 5) continue;
        rethrow;
      }
    }
  }

  /// Codes shown to admins as a list — outstanding (not yet
  /// redeemed, not yet expired) on top, then the rest. Direct
  /// cloud query; this isn't synced locally because the only
  /// caller is the program-detail admin sheet.
  ///
  /// Failure handling:
  ///   * **42P01 / PGRST205** (table missing) — surfaces an
  ///     [InviteSetupError] with a clear "apply migration 0012"
  ///     hint.
  ///   * **42501** (RLS forbids select) — returns an empty list
  ///     and logs. This happens when the local `program_members`
  ///     row marks the user as admin but the cloud row is missing
  ///     or has a different role (e.g. residue from a pre-fix
  ///     wipe-race or a half-completed `accept-invite`). The UI
  ///     shows "no codes yet" and a "Re-sync membership" path can
  ///     surface a heal action — but at least we don't crash. The
  ///     caller / bootstrap still re-pushes the membership on
  ///     every launch via `_ensureProgramAndMembershipInCloud`,
  ///     so the next sign-in heals automatically.
  ///   * **other PostgrestException** — rethrown so the UI can
  ///     surface a real error.
  Future<List<InviteRow>> listInvites(String programId) async {
    try {
      final rows = await _client
          .from('program_invites')
          .select()
          .eq('program_id', programId)
          .order('created_at', ascending: false);
      return [
        for (final r in List<Map<String, dynamic>>.from(rows))
          InviteRow.fromJson(r),
      ];
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205' || e.code == '42P01') {
        throw const InviteSetupError(
          'Invites aren’t set up on the server yet. Apply '
          'migration 0012_program_invites.sql in the Supabase '
          'dashboard.',
        );
      }
      if (e.code == '42501') {
        // Cloud RLS denied SELECT — the user's `program_members`
        // row in cloud doesn't reflect admin role even though the
        // local copy thinks it does. Return empty so the UI
        // doesn't crash; the next bootstrap re-runs the membership
        // upsert which fixes the underlying mismatch.
        return const <InviteRow>[];
      }
      rethrow;
    }
  }

  /// Revoke an outstanding code. Admin-only on the cloud side;
  /// this method just calls delete and lets RLS enforce.
  Future<void> revokeInvite(String code) async {
    await _client.from('program_invites').delete().eq('code', code);
  }

  // -- Redeem a code (recipient flow) -------------------------------

  /// Calls the `accept-invite` edge function. Returns the joined
  /// program's id + name so the caller can switch + toast. The
  /// function is the only path that can insert a membership row
  /// for a user who isn't already in the program — direct INSERT
  /// would 403 against the `program_members_insert` policy.
  Future<RedeemResult> redeemCode(String code) async {
    final cleaned = code.trim().toUpperCase();
    if (cleaned.isEmpty) {
      throw const RedeemError('missing_code', 'Please enter a code.');
    }
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'accept-invite',
        body: {'code': cleaned},
      );
    } on FunctionException catch (e) {
      // 404 = function not deployed. Surface the deployment
      // requirement explicitly instead of a generic "couldn't
      // reach server" — matches the migration-not-applied case
      // for invites.
      if (e.status == 404) {
        throw const RedeemError(
          'function_not_deployed',
          'Joining isn’t set up on the server yet. The admin '
          'needs to deploy the `accept-invite` edge function: '
          'supabase functions deploy accept-invite',
        );
      }
      rethrow;
    } on Object catch (e) {
      // Network-level / load-failed errors don't come through as
      // FunctionException — they bubble up as ClientException,
      // SocketException, etc. The most common cause in practice
      // is "function not deployed yet" so the URL is reachable
      // (Supabase's project domain answers) but returns the same
      // 404-ish unreachable-state via a non-HTTP failure on
      // some platforms. Bundle them all into the deploy hint —
      // genuine network outages are rare and the fix is the same
      // (try again later); a missing edge function is the
      // typical first-time-setup miss.
      final raw = e.toString();
      if (raw.contains('load failed') ||
          raw.contains('ClientException') ||
          raw.contains('SocketException') ||
          raw.contains('Failed host lookup') ||
          raw.contains('functions')) {
        throw RedeemError(
          'function_unreachable',
          "Couldn't reach the server's invite function. Most "
          'likely the `accept-invite` edge function hasn’t been '
          'deployed yet. The admin needs to run: supabase '
          'functions deploy accept-invite\n\nIf the function IS '
          'deployed, check your network and try again.\n\n'
          'Raw error: $e',
        );
      }
      rethrow;
    }
    final body = response.data;
    if (body is! Map) {
      throw const RedeemError(
        'server',
        'Couldn’t reach the server. Try again in a moment.',
      );
    }
    final map = Map<String, dynamic>.from(body);
    if (response.status != 200) {
      throw RedeemError(
        (map['error'] as String?) ?? 'server',
        _humanize(map['error'] as String?),
      );
    }
    return RedeemResult(
      programId: map['program_id'] as String,
      programName: map['program_name'] as String? ?? 'Program',
      role: map['role'] as String? ?? 'teacher',
    );
  }

  // -- Member admin -------------------------------------------------

  /// List the program's members. Local read — the membership rows
  /// landed via the bootstrap's `hydrateCloudProgramsForUser` and
  /// stay current via the (future) realtime subscription on
  /// program_members. Includes auth metadata only when a separate
  /// query supplies it; v1 exposes user_id + role.
  Stream<List<ProgramMember>> watchMembers(String programId) {
    return (_db.select(_db.programMembers)
          ..where((m) => m.programId.equals(programId)))
        .watch();
  }

  /// Change a member's role. Admin-only via RLS; this method just
  /// proxies the upsert. Updates local immediately for snappy UI;
  /// the realtime subscription would catch this anyway, but the
  /// instant feedback is worth the duplicate write.
  Future<void> setMemberRole({
    required String programId,
    required String userId,
    required String role,
  }) async {
    await _client.from('program_members').update({'role': role})
        .eq('program_id', programId)
        .eq('user_id', userId);
    await (_db.update(_db.programMembers)
          ..where((m) =>
              m.programId.equals(programId) & m.userId.equals(userId)))
        .write(ProgramMembersCompanion(role: Value(role)));
  }

  /// Remove a member from the program. Used by both:
  ///  * "Remove member" (admin removes someone else)
  ///  * "Leave program" (user removes themselves — the
  ///    `program_members_delete` policy allows self-delete)
  ///
  /// Caller is responsible for the "last admin can't leave" check
  /// (we count current admins client-side and refuse before
  /// calling). The cloud has no trigger enforcing this for v1.
  Future<void> removeMember({
    required String programId,
    required String userId,
  }) async {
    await _client.from('program_members').delete()
        .eq('program_id', programId)
        .eq('user_id', userId);
    await (_db.delete(_db.programMembers)
          ..where((m) =>
              m.programId.equals(programId) & m.userId.equals(userId)))
        .go();
    // If the user is removing themselves (= "leave program"),
    // wipe the program's local data so they don't keep seeing
    // stale rooms / children / schedule entries from a program
    // they no longer belong to. Removing OTHER members leaves
    // local data intact — those rows still belong to *this*
    // user's view of the program.
    final me = _client.auth.currentUser?.id;
    if (me != null && me == userId) {
      await _db.wipeProgramData(programId);
    }
  }

  /// Rename the program. Admin-only via RLS. Also pushes through
  /// the existing `programs` sync spec so the rename mirrors to
  /// every member's device on next pull.
  Future<void> renameProgram({
    required String programId,
    required String newName,
  }) async {
    await _client.from('programs').update({
      'name': newName,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', programId);
    await (_db.update(_db.programs)..where((p) => p.id.equals(programId)))
        .write(
      ProgramsCompanion(
        name: Value(newName),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Delete the program entirely. Admin-only. Cloud cascade wipes
  /// every program-scoped row + cascade table; realtime ON DELETE
  /// events would drift over to other devices, but a force-pull on
  /// next launch is the more reliable signal. Locally we mirror
  /// the cascade so the device is consistent immediately.
  Future<void> deleteProgram(String programId) async {
    // Use `.select()` so we can verify rows actually got deleted
    // — without it, supabase-dart returns void and an RLS
    // rejection (or "no rows matched") is indistinguishable from
    // a real success. The user reported "I delete a program but
    // it comes back" — that was this silent-success path.
    final deleted = await _client
        .from('programs')
        .delete()
        .eq('id', programId)
        .select('id');
    final rows = List<Map<String, dynamic>>.from(deleted);
    if (rows.isEmpty) {
      throw StateError(
        'Cloud refused the delete — probably because you aren’t '
        'an admin of this program (or the row was already gone). '
        'Try signing out and back in to refresh permissions.',
      );
    }
    // Wipe the program's local data wholesale — Drift's FK
    // cascades on programs → program_members work, but the
    // program-scoped data tables (children, rooms, etc.) don't
    // FK to programs locally (program_id is plain text, not a
    // FK), so we have to scrub them explicitly. Same code path
    // used for "leave program" so the row footprint is
    // consistent across both flows.
    await _db.wipeProgramData(programId);
  }

  // -- Internals ----------------------------------------------------

  static String _generateCode() {
    final buf = StringBuffer();
    for (var i = 0; i < 8; i++) {
      buf.write(_alphabet[_rng.nextInt(_alphabet.length)]);
    }
    return buf.toString();
  }

  static String _humanize(String? errorCode) {
    return switch (errorCode) {
      'missing_code'  => 'Please enter a code.',
      'invalid_code'  => 'That code doesn’t match any invite.',
      'expired'       => 'That code has expired. Ask for a fresh one.',
      'already_used'  => 'That code has already been used.',
      'unauthenticated' =>
          'You need to sign in before redeeming a code.',
      'program_not_found' =>
          'That program no longer exists. Ask the admin for a new code.',
      _ => 'Couldn’t join — try again in a moment.',
    };
  }
}

/// Thrown when an invite operation hits a "this isn't deployed
/// yet" condition — the cloud table is missing or the edge
/// function is missing. Different exception type from
/// [RedeemError] so the UI can show a developer-actionable
/// message instead of the standard recipient-facing one.
class InviteSetupError implements Exception {
  const InviteSetupError(this.message);

  final String message;

  @override
  String toString() => 'InviteSetupError: $message';
}

/// One row from `program_invites`.
class InviteRow {
  const InviteRow({
    required this.code,
    required this.programId,
    required this.role,
    required this.createdBy,
    required this.expiresAt,
    required this.createdAt,
    this.acceptedBy,
    this.acceptedAt,
    this.adultId,
  });

  factory InviteRow.fromJson(Map<String, dynamic> json) => InviteRow(
        code: json['code'] as String,
        programId: json['program_id'] as String,
        role: json['role'] as String? ?? 'teacher',
        createdBy: json['created_by'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
        acceptedBy: json['accepted_by'] as String?,
        acceptedAt: json['accepted_at'] != null
            ? DateTime.parse(json['accepted_at'] as String).toUtc()
            : null,
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
        adultId: json['adult_id'] as String?,
      );

  final String code;
  final String programId;
  final String role;
  final String createdBy;
  final DateTime expiresAt;
  final String? acceptedBy;
  final DateTime? acceptedAt;
  final DateTime createdAt;

  /// v54 identity-binding hook. When set, redeeming this invite
  /// stamps `adults.auth_user_id` on the named row.
  final String? adultId;

  bool get isAccepted => acceptedBy != null;
  bool get isExpired =>
      !isAccepted && expiresAt.isBefore(DateTime.now().toUtc());
  bool get isOutstanding => !isAccepted && !isExpired;
}

/// Successful redemption result returned to the caller.
class RedeemResult {
  const RedeemResult({
    required this.programId,
    required this.programName,
    required this.role,
  });

  final String programId;
  final String programName;
  final String role;
}

/// Thrown by [InviteRepository.redeemCode] when redemption fails.
/// `code` is the machine-readable error from the edge function;
/// `message` is the user-facing humanized version.
class RedeemError implements Exception {
  const RedeemError(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'RedeemError($code: $message)';
}

final inviteRepositoryProvider = Provider<InviteRepository>((ref) {
  return InviteRepository(
    ref.watch(databaseProvider),
    Supabase.instance.client,
  );
});

/// Members of a program (reactive). Used by the program-detail
/// screen's member list. Family-keyed by program id.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final programMembersProvider =
    StreamProvider.family<List<ProgramMember>, String>((ref, programId) {
  return ref.watch(inviteRepositoryProvider).watchMembers(programId);
});

/// Outstanding invites for a program (one-shot, refreshable).
/// FutureProvider so the admin sheet can `ref.invalidate(...)` to
/// refresh after creating/revoking a code.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final programInvitesProvider =
    FutureProvider.family<List<InviteRow>, String>((ref, programId) {
  return ref.watch(inviteRepositoryProvider).listInvites(programId);
});

/// Redeems [code] and switches the active program to the joined
/// one on success. Wraps the bootstrap's `switchProgram` so a
/// successful join feels seamless — sync pulls + realtime
/// subscribe before the user lands on /today.
Future<RedeemResult> redeemAndSwitch({
  required WidgetRef ref,
  required String code,
}) async {
  final result = await ref.read(inviteRepositoryProvider).redeemCode(code);
  // Hydrate the joined program into local Drift before switching.
  // Without this, switchProgram has no local program row to find
  // and the user lands on an "active id set but no row" state
  // that surfaces as a blank screen until next launch.
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) {
    throw const RedeemError(
      'unauthenticated',
      'Sign in expired. Please sign in again and try the code.',
    );
  }
  await ref.read(programsRepositoryProvider).hydrateCloudProgramsForUser(
        userId: user.id,
        supabase: Supabase.instance.client,
      );
  // Verify the membership actually landed locally — defensive
  // against a partial hydrate (network blip mid-pull). Without
  // this check, switchProgram would silently set active to a
  // program that doesn't exist locally.
  final memberships =
      await ref.read(programsRepositoryProvider).programsForUser(user.id);
  if (!memberships.any((p) => p.id == result.programId)) {
    throw const RedeemError(
      'server',
      'Joined the program but the data didn’t finish syncing. '
          'Try again in a moment.',
    );
  }
  await ref.read(programAuthBootstrapProvider).switchProgram(result.programId);
  return result;
}
