import 'dart:async';
import 'dart:convert';
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
        // Cloud RLS denied SELECT — local `program_members` row
        // says we're admin but the cloud row doesn't match.
        // Surface a real error so the UI can show a "membership
        // out of sync — sign out + back in to reconnect" hint
        // instead of silently rendering "No codes yet" (which
        // hid the actual problem and made admins think their
        // codes were lost).
        throw const InvitePermissionError(
          "Your admin membership for this program is out of sync "
          'with the server. Sign out and back in to reconnect, '
          'then try again.',
        );
      }
      rethrow;
    }
  }

  /// Revoke an outstanding code. Admin-only on the cloud side;
  /// this method just calls delete and lets RLS enforce.
  Future<void> revokeInvite(String code) async {
    await _client.from('program_invites').delete().eq('code', code);
  }

  /// Outstanding invites bound to a specific Adult row. Used by the
  /// admin's adult-detail view to show "Maya has a pending code"
  /// and offer revoke/re-issue. Outstanding = not yet redeemed +
  /// not yet expired; pre-filtered server-side so the client list
  /// is the actionable subset.
  Future<List<InviteRow>> listOutstandingForAdult(String adultId) async {
    try {
      final rows = await _client
          .from('program_invites')
          .select()
          .eq('adult_id', adultId)
          .filter('accepted_by', 'is', null)
          .gte('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false);
      return [
        for (final r in List<Map<String, dynamic>>.from(rows))
          InviteRow.fromJson(r),
      ];
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205' || e.code == '42P01') {
        // Migrations 0012 / 0031 not applied yet — same hint as the
        // generic listInvites path.
        throw const InviteSetupError(
          'Invites aren’t set up on the server yet. Apply the '
          'invite migrations in the Supabase dashboard.',
        );
      }
      if (e.code == '42501') return const [];
      rethrow;
    }
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
      // 400 / 401 / 500 — the function returned a structured
      // error body (`{ error: 'invalid_code' | 'expired' | ... }`).
      // Extract the code from `e.details` and run it through the
      // same humaniser the success path uses, so the user sees
      // "That code has expired" instead of a raw FunctionException.
      // Without this branch, every non-200 except 404 was leaking
      // through as a stack trace in the UI.
      final code = _extractErrorCode(e.details);
      if (code != null) {
        throw RedeemError(code, _humanize(code));
      }
      // Unknown shape — fall through to a generic message but
      // keep the status code in the technical field so a
      // developer-mode UI can still surface the raw response.
      throw RedeemError(
        'server_${e.status}',
        'Couldn’t join — the server returned an error '
        '(status ${e.status}). Try again in a moment.',
      );
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
      adultBoundId: map['adult_bound'] as String?,
      adultBindWarning: map['adult_bind_warning'] as String?,
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

  /// Pull `error` out of a `FunctionException.details` payload.
  ///
  /// Supabase's edge function client gives us `details` as
  /// EITHER a parsed `Map<String, dynamic>` (when the response is
  /// well-formed JSON) OR a raw `String` (when content-type
  /// isn't application/json, or when the function crashed before
  /// it could format a body). We handle both: parse strings as
  /// JSON if they look like an object, otherwise pull the `error`
  /// key from a Map directly. Returns null when the body is
  /// shapeless — the caller falls back to a generic status-code
  /// message.
  static String? _extractErrorCode(Object? details) {
    if (details == null) return null;
    Map<String, dynamic>? map;
    if (details is Map) {
      map = Map<String, dynamic>.from(details);
    } else if (details is String) {
      final trimmed = details.trim();
      if (!trimmed.startsWith('{')) return null;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) map = Map<String, dynamic>.from(decoded);
      } on FormatException {
        return null;
      }
    }
    if (map == null) return null;
    final raw = map['error'];
    return raw is String && raw.isNotEmpty ? raw : null;
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

/// Cloud rejected SELECT on `program_invites` with RLS 42501.
/// The user's local copy of `program_members` thinks they're an
/// admin but the cloud row doesn't match — often residue from a
/// half-completed `accept-invite` or a pre-fix wipe race. The
/// UI surfaces this with a "sign out + back in to reconnect"
/// hint; bootstrap's `_ensureProgramAndMembershipInCloud` heals
/// the underlying state on next sign-in.
class InvitePermissionError implements Exception {
  const InvitePermissionError(this.message);

  final String message;

  @override
  String toString() => 'InvitePermissionError: $message';
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
    this.adultBoundId,
    this.adultBindWarning,
  });

  final String programId;
  final String programName;
  final String role;

  /// When the invite carried an `adult_id`, this is the Adult row
  /// the user got bound to (after a successful stamp). Null when
  /// the invite was a regular program-join with no adult linkage.
  final String? adultBoundId;

  /// Non-null when the edge function tried to bind to an Adult
  /// row but couldn't. Values:
  ///   * `"existing_bind:<adultId>"` — user is already bound to a
  ///     different adult in this program. Admin needs to reconcile.
  ///   * `"adult_not_found"` — adult row was deleted between
  ///     invite creation and redemption.
  ///   * `"update_error:<message>"` — cloud update threw.
  /// The join itself still succeeded; the warning is a hint the
  /// UI surfaces so the user knows historical data may be
  /// orphaned.
  final String? adultBindWarning;

  /// Friendly version of [adultBindWarning], or null when there's
  /// nothing to surface.
  String? get adultBindUserMessage {
    final raw = adultBindWarning;
    if (raw == null) return null;
    if (raw.startsWith('existing_bind:')) {
      return "You're already linked to another profile in this "
          'program. Ask an admin to merge them so your historical '
          'observations and schedule travel with you.';
    }
    if (raw == 'adult_not_found') {
      return 'Joined the program, but the staff profile this code '
          'was tied to is no longer there. Ask the admin to create '
          'a fresh code.';
    }
    return "Joined the program. Couldn't link to your pre-created "
        'staff profile (server reported: $raw). Ask the admin to '
        'help you re-link.';
  }
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
    StreamProvider.autoDispose.family<List<ProgramMember>, String>(
        (ref, programId) {
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

/// Outstanding invites for a single adult — used by the adult
/// detail screen to surface "code already pending, here it is"
/// instead of silently issuing a duplicate every time the admin
/// taps invite. Refresh by `ref.invalidate(...)` after a
/// create/revoke.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final adultOutstandingInvitesProvider =
    FutureProvider.family<List<InviteRow>, String>((ref, adultId) {
  return ref
      .watch(inviteRepositoryProvider)
      .listOutstandingForAdult(adultId);
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
  // Hydrate with retry. The original code did a single hydrate +
  // assertion-or-throw, which deadlocked the user when a transient
  // network blip made `programsForUser` return empty: the invite
  // was already consumed cloud-side (the edge function succeeded),
  // so retrying from the join sheet wouldn't help, and the user
  // had to relaunch to recover. Now: retry the hydrate up to three
  // times with backoff. If still no local membership after that,
  // PROCEED to `switchProgram` anyway — `switchProgram` itself does
  // a tier-by-tier pull that re-populates everything; in the worst
  // case the user lands on an empty program for a few seconds
  // while the pull finishes, instead of being stuck behind a
  // dead spinner.
  Future<bool> hydrateAndCheck() async {
    await ref.read(programsRepositoryProvider).hydrateCloudProgramsForUser(
          userId: user.id,
          supabase: Supabase.instance.client,
        );
    final memberships = await ref
        .read(programsRepositoryProvider)
        .programsForUser(user.id);
    return memberships.any((p) => p.id == result.programId);
  }

  var landed = await hydrateAndCheck();
  for (var attempt = 1; !landed && attempt < 3; attempt++) {
    await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
    landed = await hydrateAndCheck();
  }
  // No `landed` check that throws — soldier on. switchProgram's
  // pull is the actual source of truth; the local membership row
  // will reach Drift via that pull even if the hydrate missed.

  await ref.read(programAuthBootstrapProvider).switchProgram(result.programId);
  return result;
}
