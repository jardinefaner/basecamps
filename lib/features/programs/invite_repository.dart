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
        }).select().single();
        return InviteRow.fromJson(inserted);
      } on PostgrestException catch (e) {
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
  Future<List<InviteRow>> listInvites(String programId) async {
    final rows = await _client
        .from('program_invites')
        .select()
        .eq('program_id', programId)
        .order('created_at', ascending: false);
    return [
      for (final r in List<Map<String, dynamic>>.from(rows))
        InviteRow.fromJson(r),
    ];
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
    final response = await _client.functions.invoke(
      'accept-invite',
      body: {'code': cleaned},
    );
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
    await _client.from('programs').delete().eq('id', programId);
    await (_db.delete(_db.programs)..where((p) => p.id.equals(programId)))
        .go();
    // Drift's FK cascade rules wipe membership + all program-scoped
    // cascade rows on this device automatically.
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
      _ => 'Couldn’t join — try again in a moment.',
    };
  }
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
      );

  final String code;
  final String programId;
  final String role;
  final String createdBy;
  final DateTime expiresAt;
  final String? acceptedBy;
  final DateTime? acceptedAt;
  final DateTime createdAt;

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
  // Hydrate the joined program into local Drift before switching
  // so the active-program lookup finds it.
  final user = Supabase.instance.client.auth.currentUser;
  if (user != null) {
    await ref.read(programsRepositoryProvider).hydrateCloudProgramsForUser(
          userId: user.id,
          supabase: Supabase.instance.client,
        );
  }
  await ref.read(programAuthBootstrapProvider).switchProgram(result.programId);
  return result;
}
