import 'dart:async';

import 'package:basecamp/features/auth/auth_repository.dart';
import 'package:basecamp/features/programs/invite_repository.dart';
import 'package:basecamp/features/programs/join_with_code_sheet.dart';
import 'package:basecamp/features/programs/program_bootstrap.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// `/welcome` — landing page for a signed-in user with no program.
///
/// Slice 3 changed the bootstrap so brand-new accounts no longer
/// auto-create "My program" — that was creating an empty silo
/// before the user could enter the invite code an admin sent
/// them. Now they land here and pick:
///
///  * **Create a program** — name input, then `createAndSwitchProgram`
///    runs the same flow as the programs screen's "+New".
///  * **Join with code** — invite-code sheet. On success switches
///    to the joined program and the redirect bounces to /today.
///
/// The router redirects signed-in users with `activeProgramId == null`
/// here, so this screen is the gate; once they pick something
/// the active id flips and the redirect sends them onward.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              shrinkWrap: true,
              children: [
                Icon(
                  Icons.workspaces_outline,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Welcome to Basecamp',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'You aren’t in a program yet. Join one with an '
                  'invite code from an admin, or start your own.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                _ChoiceCard(
                  icon: Icons.login_outlined,
                  title: 'Join with a code',
                  subtitle:
                      'An admin shared an 8-character code with you.',
                  primary: true,
                  onTap: () => _openJoin(context),
                ),
                const SizedBox(height: AppSpacing.md),
                _ChoiceCard(
                  icon: Icons.add_circle_outline,
                  title: 'Start a new program',
                  subtitle:
                      "It's yours — invite teachers later.",
                  primary: false,
                  onTap: () => _openCreate(context, ref),
                ),
                const SizedBox(height: AppSpacing.xxl),
                Center(
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.logout, size: 16),
                        label: const Text('Sign out'),
                        onPressed: () =>
                            ref.read(authRepositoryProvider).signOut(),
                      ),
                      TextButton.icon(
                        icon: const Icon(
                          Icons.health_and_safety_outlined,
                          size: 16,
                        ),
                        label: const Text('Sync diagnostics'),
                        onPressed: () => context
                            .push('/more/programs/diagnostics'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openJoin(BuildContext context) async {
    final result = await showModalBottomSheet<RedeemResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const JoinWithCodeSheet(),
    );
    if (result != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Joined "${result.programName}"'),
          duration: const Duration(seconds: 2),
        ),
      );
      // The router's active-program redirect will bounce us off
      // /welcome once the bootstrap finishes setting active.
    }
  }

  Future<void> _openCreate(BuildContext context, WidgetRef ref) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CreateProgramSheet(userId: session.user.id),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primary,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconBg = primary
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final iconFg = primary
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurfaceVariant;
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconFg),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

/// Minimal create-program sheet (welcome variant). Mirrors the
/// programs-screen sheet but tuned for the first-time flow:
/// after success we just close and let the router redirect
/// to /today since the active program flipped non-null.
class _CreateProgramSheet extends ConsumerStatefulWidget {
  const _CreateProgramSheet({required this.userId});

  final String userId;

  @override
  ConsumerState<_CreateProgramSheet> createState() =>
      _CreateProgramSheetState();
}

class _CreateProgramSheetState
    extends ConsumerState<_CreateProgramSheet> {
  final _name = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      final newId = await ref
          .read(programAuthBootstrapProvider)
          .createAndSwitchProgram(name: name, userId: widget.userId);
      if (!mounted) return;
      // Pop the modal first, then navigate. Without explicit
      // navigation we'd rely on the router's "active is non-null
      // → bounce off /welcome to /today" redirect; landing on
      // the new program's detail screen gives the user immediate
      // context (here's your program, here's how to invite
      // teachers) and avoids the empty /today flash.
      Navigator.of(context).pop();
      if (!context.mounted) return;
      context.go('/more/programs/$newId');
    } on Object catch (e) {
      debugPrint('Welcome create failed: $e');
      if (!mounted) return;
      // Close the modal first so the user isn't trapped behind
      // it — the recovery dialog covers the failure path.
      Navigator.of(context).pop();
      if (!context.mounted) return;
      await _showCreateFailureDialog(context, ref, error: e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // Outer padding lifts the modal as the keyboard rises;
      // inner SingleChildScrollView lets content scroll when
      // the available area shrinks below the natural height
      // (tablet keyboards eat half the screen).
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Start a program', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Pick something concrete — your school year, the camp, '
              'the after-school cohort. You can rename it later.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Program name',
                hintText: 'e.g. After-school 2026',
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Create'),
                  ),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}

/// Surfaces a recoverable failure on the welcome → Create flow.
/// Without this dialog, the modal sheet would just close on a
/// silent error and the user would tap "Start a new program"
/// again hitting the same wall — the symptom the user reported
/// as "i create a program, and it keeps going back to the same
/// create a program."
///
/// The dialog explains what happened, surfaces the raw server
/// error so the user can paste it back, and gives two recovery
/// affordances:
///   * **Open diagnostics** → the existing sync diagnostics
///     screen, which surfaces JWT vs auth.uid() mismatches +
///     project URL etc.
///   * **Sign out & start over** → forces a fresh PKCE handshake.
///     Often resolves stale-session 42501s in one shot.
Future<void> _showCreateFailureDialog(
  BuildContext context,
  WidgetRef ref, {
  required Object error,
}) async {
  final theme = Theme.of(context);
  final friendlyHint = _hintFor(error);
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Could not create program'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              friendlyHint,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            SelectableText(
              error.toString(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // Defer the route push to the next frame. Popping
              // and pushing in the same tick disposes the
              // dialog's Navigator while another navigation is
              // in flight, which trips the
              // `_debugLocked` assertion in finalizeTree.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) return;
                unawaited(
                  context.push('/more/programs/diagnostics'),
                );
              });
            },
            child: const Text('Open diagnostics'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(authRepositoryProvider).signOut();
            },
            child: const Text('Sign out & start over'),
          ),
        ],
      );
    },
  );
}

/// Maps a thrown `createAndSwitchProgram` error to a human-
/// readable explanation. The most common case is the persistent
/// 42501 "row violates RLS" — explain it in terms a teacher can
/// act on (sign out + sign in usually clears it).
String _hintFor(Object error) {
  final raw = error.toString();
  if (raw.contains('42501') ||
      raw.contains('row-level security')) {
    return 'The cloud rejected the save. This usually means '
        'your sign-in is stale — signing out and back in clears '
        'the cached token. If that doesn’t help, open '
        'diagnostics and paste the error back to support.';
  }
  if (raw.contains('Sign-in expired') ||
      raw.contains('Could not verify sign-in')) {
    return 'Your sign-in lapsed. Sign out and sign in again to '
        'refresh the session.';
  }
  return 'Something went wrong while saving the program to the '
      'cloud. Try signing out and back in. If the error keeps '
      'happening, open diagnostics.';
}
