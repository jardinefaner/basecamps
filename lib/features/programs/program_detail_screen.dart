import 'dart:async';

import 'package:basecamp/core/format/text.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/auth/auth_repository.dart';
import 'package:basecamp/features/programs/invite_repository.dart';
import 'package:basecamp/features/programs/member_role.dart';
import 'package:basecamp/features/programs/program_bootstrap.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/sync/live_indicator.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/confirm_dialog.dart';
import 'package:basecamp/ui/save_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

/// `/more/programs/:id` — program detail screen.
///
/// Header:        program name + role pill + rename / delete
/// Members card:  list every program_member row, role pill,
///                admin actions (change role / remove), self
///                action (leave — refused if last admin).
/// Invite card:   admin-only — generate an 8-char code, show
///                outstanding codes, copy / share / revoke.
///
/// Reads come from the local Drift mirror via Riverpod streams;
/// writes go to cloud first (proxied through `InviteRepository`)
/// then update local for instant UI. RLS on the cloud side
/// enforces "admin only" for every sensitive action — the UI
/// gates by role for affordance + clarity, not for security.
class ProgramDetailScreen extends ConsumerWidget {
  const ProgramDetailScreen({required this.programId, super.key});

  final String programId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final programAsync = ref.watch(_programProvider(programId));
    final membersAsync = ref.watch(programMembersProvider(programId));
    final session = ref.watch(currentSessionProvider);
    final myUserId = session?.user.id;

    return Scaffold(
      appBar: AppBar(
        title: programAsync.when(
          data: (p) => Text(p?.name ?? 'Program'),
          loading: () => const Text('Program'),
          error: (_, _) => const Text('Program'),
        ),
      ),
      body: programAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (program) {
          if (program == null) {
            return const Center(child: Text('Program not found.'));
          }
          return membersAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Error: $err')),
            data: (members) {
              final myRow = members.firstWhere(
                (m) => m.userId == myUserId,
                orElse: () => ProgramMember(
                  programId: programId,
                  userId: myUserId ?? '',
                  role: 'teacher',
                  joinedAt: DateTime.now(),
                ),
              );
              final iAmAdmin = myRow.isAdmin;
              final adminCount = members.where((m) => m.isAdmin).length;
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  _HeaderCard(
                    program: program,
                    myRole: myRow.role,
                    canManage: iAmAdmin,
                    onRename: () =>
                        _renameProgram(context, ref, program),
                    onDelete: () =>
                        _deleteProgram(context, ref, program),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _MembersCard(
                    programId: programId,
                    members: members,
                    myUserId: myUserId,
                    iAmAdmin: iAmAdmin,
                    adminCount: adminCount,
                  ),
                  if (iAmAdmin) ...[
                    const SizedBox(height: AppSpacing.md),
                    _InvitesCard(programId: programId),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _renameProgram(
    BuildContext context,
    WidgetRef ref,
    Program program,
  ) async {
    final controller = TextEditingController(text: program.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename program'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Program name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == program.name) {
      return;
    }
    if (!context.mounted) return;
    await runWithErrorReport(context, () async {
      await ref.read(inviteRepositoryProvider).renameProgram(
            programId: program.id,
            newName: newName,
          );
    });
  }

  Future<void> _deleteProgram(
    BuildContext context,
    WidgetRef ref,
    Program program,
  ) async {
    final ok = await showConfirmDialog(
      context: context,
      title: 'Delete "${program.name}"?',
      message: 'This wipes every child, schedule entry, observation, '
          'note, and member of this program for everyone. Cannot be '
          'undone.',
    );
    if (!ok || !context.mounted) return;
    await runWithErrorReport(context, () async {
      await _moveOffAndDispose(ref, programIdToRemove: program.id, () {
        return ref.read(inviteRepositoryProvider).deleteProgram(program.id);
      });
      // Defer the pop. _moveOffAndDispose just changed the active
      // program (cleared or switched), which fires the router's
      // refresh listenable. If we pop synchronously the program-
      // detail route's Navigator is being torn down both by our
      // pop AND by the router's redirect → `_debugLocked`
      // assertion in finalizeTree. One frame of delay lets the
      // router settle first.
      if (!context.mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.pop();
      });
    });
  }
}

/// After a destructive action that takes the user OFF [programIdToRemove]
/// (delete program, leave program), pick a remaining membership and
/// switch to it instead of clearing the active id and bouncing the
/// user to /welcome. Only when no other membership exists do we clear
/// — that's the actual zero-program state /welcome is for.
///
/// [body] runs the destructive cloud + local write itself; this
/// helper handles the active-program reshuffling around it.
Future<void> _moveOffAndDispose(
  WidgetRef ref,
  Future<void> Function() body, {
  required String programIdToRemove,
}) async {
  final session = ref.read(currentSessionProvider);
  if (session == null) {
    await body();
    return;
  }
  final userId = session.user.id;
  // Snapshot memberships BEFORE running the body — after delete /
  // leave, the row we're about to remove is gone and the local
  // table reflects the post-state. We need the pre-state to know
  // whether there's anywhere to land.
  final memberships =
      await ref.read(programsRepositoryProvider).programsForUser(userId);
  final remaining = memberships.where((p) => p.id != programIdToRemove).toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  await body();

  if (remaining.isEmpty) {
    // True zero-program state — clear active and let the router's
    // welcome redirect fire. This is the only path that should
    // land on /welcome after launch. `clearAll` wipes both the
    // in-memory state and the persisted SharedPreferences hint
    // because the program the hint pointed to is genuinely gone
    // for this user; sign-out uses `clearMemory` to keep the
    // hint instead.
    await ref.read(activeProgramIdProvider.notifier).clearAll();
    return;
  }
  // Land in the oldest remaining program. Switch (not just `set`)
  // so realtime resubscribes + pull runs against the new program
  // — same flow the manual switcher uses.
  await ref
      .read(programAuthBootstrapProvider)
      .switchProgram(remaining.first.id);
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.program,
    required this.myRole,
    required this.canManage,
    required this.onRename,
    required this.onDelete,
  });

  final Program program;
  final String myRole;
  final bool canManage;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  program.name,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              _RolePill(role: myRole),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Created ${DateFormat.yMMMd().format(program.createdAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const LiveIndicator(),
            ],
          ),
          if (canManage) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: onRename,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Rename'),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Delete'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(
                      color: theme.colorScheme.error.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MembersCard extends ConsumerWidget {
  const _MembersCard({
    required this.programId,
    required this.members,
    required this.myUserId,
    required this.iAmAdmin,
    required this.adminCount,
  });

  final String programId;
  final List<ProgramMember> members;
  final String? myUserId;
  final bool iAmAdmin;
  final int adminCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Members', style: theme.textTheme.titleMedium),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${members.length}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          for (final m in members) ...[
            _MemberRow(
              programId: programId,
              member: m,
              iAmAdmin: iAmAdmin,
              isMe: m.userId == myUserId,
              isLastAdmin: m.isAdmin && adminCount <= 1,
            ),
            if (m != members.last) const Divider(height: 16),
          ],
        ],
      ),
    );
  }
}

class _MemberRow extends ConsumerWidget {
  const _MemberRow({
    required this.programId,
    required this.member,
    required this.iAmAdmin,
    required this.isMe,
    required this.isLastAdmin,
  });

  final String programId;
  final ProgramMember member;
  final bool iAmAdmin;
  final bool isMe;
  final bool isLastAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // v52: render the human-readable display_name. Bootstrap
    // populates it from auth.users metadata on every membership
    // upsert. Falls back to a UUID-prefix label for legacy
    // (pre-v52) rows that haven't been re-pushed yet.
    final displayName = member.displayName?.trim();
    final hasName = displayName != null && displayName.isNotEmpty;
    final label = isMe
        ? 'You${hasName ? ' · $displayName' : ''}'
        : (hasName
            ? displayName
            : 'Teacher · ${member.userId.substring(0, 8)}');
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            label.initial,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Joined ${DateFormat.yMMMd().format(member.joinedAt)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        _RolePill(role: member.role),
        if (iAmAdmin || isMe)
          PopupMenuButton<_MemberAction>(
            icon: const Icon(Icons.more_vert),
            onSelected: (action) =>
                _runAction(context, ref, action),
            itemBuilder: (_) {
              final items = <PopupMenuEntry<_MemberAction>>[];
              if (iAmAdmin && !isMe) {
                items
                  ..add(
                    PopupMenuItem(
                      value: member.isAdmin
                          ? _MemberAction.demoteToTeacher
                          : _MemberAction.promoteToAdmin,
                      child: Text(
                        member.isAdmin
                            ? 'Demote to teacher'
                            : 'Promote to admin',
                      ),
                    ),
                  )
                  ..add(
                    const PopupMenuItem(
                      value: _MemberAction.remove,
                      child: Text('Remove from program'),
                    ),
                  );
              }
              if (isMe) {
                items.add(
                  PopupMenuItem(
                    value: _MemberAction.leave,
                    enabled: !isLastAdmin,
                    child: Text(
                      isLastAdmin
                          ? 'Leave (last admin)'
                          : 'Leave program',
                    ),
                  ),
                );
              }
              return items;
            },
          ),
      ],
    );
  }

  Future<void> _runAction(
    BuildContext context,
    WidgetRef ref,
    _MemberAction action,
  ) async {
    final repo = ref.read(inviteRepositoryProvider);
    switch (action) {
      case _MemberAction.promoteToAdmin:
      case _MemberAction.demoteToTeacher:
        final newRole = action == _MemberAction.promoteToAdmin
            ? 'admin'
            : 'teacher';
        await runWithErrorReport(context, () async {
          await repo.setMemberRole(
            programId: programId,
            userId: member.userId,
            role: newRole,
          );
        });
      case _MemberAction.remove:
        final ok = await showConfirmDialog(
          context: context,
          title: 'Remove member?',
          message:
              'They lose access to this program. Their existing '
              'data stays in place; new edits stop syncing to '
              'their devices.',
          confirmLabel: 'Remove',
        );
        if (!ok || !context.mounted) return;
        await runWithErrorReport(context, () async {
          await repo.removeMember(
            programId: programId,
            userId: member.userId,
          );
        });
      case _MemberAction.leave:
        if (isLastAdmin) return;
        final ok = await showConfirmDialog(
          context: context,
          title: 'Leave this program?',
          message:
              'You lose access to its data. Re-join with a new '
              'invite code from an admin.',
          confirmLabel: 'Leave',
        );
        if (!ok || !context.mounted) return;
        await runWithErrorReport(context, () async {
          // Same shape as program-delete: switch to a remaining
          // membership instead of forcing the user to /welcome.
          // Welcome is for the zero-program state only.
          await _moveOffAndDispose(
            ref,
            programIdToRemove: programId,
            () => repo.removeMember(
              programId: programId,
              userId: member.userId,
            ),
          );
          // Defer the pop — same race as the delete path:
          // active-program change fires the router refresh,
          // popping in the same tick collides with the router's
          // own teardown and trips `_debugLocked` in
          // finalizeTree.
          if (!context.mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.pop();
          });
        });
    }
  }
}

enum _MemberAction { promoteToAdmin, demoteToTeacher, remove, leave }

class _InvitesCard extends ConsumerWidget {
  const _InvitesCard({required this.programId});

  final String programId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final invitesAsync = ref.watch(programInvitesProvider(programId));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Invite codes',
                style: theme.textTheme.titleMedium,
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: () => _generate(context, ref),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New code'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Share a code with a teacher. They sign in, tap '
            '"Join with code" on the programs screen, and land '
            'in this program.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          invitesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => Text('Couldn’t load invites: $err'),
            data: (invites) {
              if (invites.isEmpty) {
                return Text(
                  'No codes yet. Tap "New code" to generate one.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              }
              return Column(
                children: [
                  for (final i in invites)
                    _InviteRow(
                      invite: i,
                      onCopy: () => _copy(context, i),
                      onShare: () => _share(context, i),
                      onRevoke: () => _revoke(context, ref, i),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _generate(BuildContext context, WidgetRef ref) async {
    await runWithErrorReport(context, () async {
      final invite = await ref.read(inviteRepositoryProvider).createInvite(
            programId: programId,
          );
      ref.invalidate(programInvitesProvider(programId));
      if (!context.mounted) return;
      // Auto-copy the code so the common path (generate → paste
      // into a text/email to a teacher) is one tap. tryCopyToClipboard
      // returns false on platforms where clipboard access is denied
      // (Safari without a recent user gesture, locked-down browsers,
      // certain Android keyboards) — the dialog shows the code text
      // either way, so the user can copy manually if the auto-copy
      // skipped.
      final copied = await tryCopyToClipboard(invite.code);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            copied
                ? 'Code copied — share it with the teacher'
                : 'Code generated — copy it from the dialog',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      await showDialog<void>(
        context: context,
        builder: (ctx) => _NewCodeDialog(invite: invite),
      );
    });
  }

  Future<void> _copy(BuildContext context, InviteRow invite) async {
    final copied = await tryCopyToClipboard(invite.code);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(copied ? 'Code copied' : "Couldn't copy — long-press to select"),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _share(BuildContext context, InviteRow invite) async {
    await SharePlus.instance.share(
      ShareParams(
        text:
            'Join my Basecamp program with this code: ${invite.code} '
            '(expires ${DateFormat.yMMMd().format(invite.expiresAt)})',
      ),
    );
  }

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    InviteRow invite,
  ) async {
    final ok = await showConfirmDialog(
      context: context,
      title: 'Revoke this code?',
      message: 'It can’t be redeemed after this.',
      confirmLabel: 'Revoke',
    );
    if (!ok || !context.mounted) return;
    await runWithErrorReport(context, () async {
      await ref.read(inviteRepositoryProvider).revokeInvite(invite.code);
      ref.invalidate(programInvitesProvider(programId));
    });
  }
}

class _InviteRow extends StatelessWidget {
  const _InviteRow({
    required this.invite,
    required this.onCopy,
    required this.onShare,
    required this.onRevoke,
  });

  final InviteRow invite;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = invite.isAccepted
        ? 'Used'
        : invite.isExpired
            ? 'Expired'
            : 'Expires ${DateFormat.yMMMd().format(invite.expiresAt)}';
    final statusColor = invite.isAccepted || invite.isExpired
        ? theme.colorScheme.outline
        : theme.colorScheme.onSurfaceVariant;
    final dimmed = invite.isAccepted || invite.isExpired;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invite.code,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 1.5,
                    color: dimmed
                        ? theme.colorScheme.outline
                        : null,
                  ),
                ),
                Text(
                  status,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          if (!dimmed) ...[
            IconButton(
              tooltip: 'Copy code',
              onPressed: onCopy,
              icon: const Icon(Icons.copy_outlined),
            ),
            IconButton(
              tooltip: 'Share',
              onPressed: onShare,
              icon: const Icon(Icons.ios_share),
            ),
            IconButton(
              tooltip: 'Revoke',
              onPressed: onRevoke,
              icon: Icon(
                Icons.cancel_outlined,
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NewCodeDialog extends StatelessWidget {
  const _NewCodeDialog({required this.invite});

  final InviteRow invite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Invite code ready'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            invite.code,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontFamily: 'monospace',
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Single-use. Expires '
            '${DateFormat.yMMMd().format(invite.expiresAt)}.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
        FilledButton.icon(
          onPressed: () async {
            await tryCopyToClipboard(invite.code);
            if (context.mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.copy_outlined, size: 18),
          label: const Text('Copy'),
        ),
      ],
    );
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = role == 'admin';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: isAdmin
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        isAdmin ? 'Admin' : 'Teacher',
        style: theme.textTheme.labelSmall?.copyWith(
          color: isAdmin
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// Single-program lookup. Lives here (and not in
// programs_repository.dart) because it's the only place that
// reads a single program by id; adding it to the repo would
// invite drift between this stream and the multi-program list.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final _programProvider =
    StreamProvider.family<Program?, String>((ref, id) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.programs)..where((p) => p.id.equals(id)))
      .watchSingleOrNull();
});
