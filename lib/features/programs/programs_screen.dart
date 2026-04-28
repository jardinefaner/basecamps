import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/auth/auth_repository.dart';
import 'package:basecamp/features/programs/invite_repository.dart';
import 'package:basecamp/features/programs/join_with_code_sheet.dart';
import 'package:basecamp/features/programs/program_bootstrap.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/save_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// `/more/programs` — multi-program switcher (Slice 2).
///
/// Lists every program the signed-in user belongs to. Tapping a row
/// switches the active program (the rest of the app rebuilds because
/// every Riverpod provider that watches `activeProgramIdProvider`
/// rebuilds, and every program-scoped read is now filtered to the
/// new id — see Slice 1).
///
/// Empty state never renders for signed-in users — the auth bootstrap
/// always ensures at least one program. We render the empty path
/// anyway for the brief gap between sign-in and bootstrap finish.
class ProgramsScreen extends ConsumerWidget {
  const ProgramsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    final activeId = ref.watch(activeProgramIdProvider);
    if (session == null) {
      return const Scaffold(
        body: Center(child: Text('Sign in to manage programs.')),
      );
    }
    final userId = session.user.id;
    final programsAsync = ref.watch(_programsForUserProvider(userId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Programs'),
        actions: [
          IconButton(
            tooltip: 'Sync diagnostics',
            icon: const Icon(Icons.health_and_safety_outlined),
            onPressed: () => context.push('/more/programs/diagnostics'),
          ),
          // Labeled action so "join" is discoverable. The previous
          // icon-only login icon read as auth/sign-in to teachers,
          // not as "join another program with a code."
          TextButton.icon(
            icon: const Icon(Icons.qr_code_2_outlined, size: 18),
            label: const Text('Join'),
            onPressed: () => _openJoinSheet(context),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreateSheet(context, ref, userId: userId),
        icon: const Icon(Icons.add),
        label: const Text('New program'),
      ),
      body: programsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (programs) {
          if (programs.isEmpty) {
            return const _EmptyState();
          }
          // Programs followed by a "join another with a code"
          // affordance. The trailing card is the most discoverable
          // path — the app-bar "Join" button is right there too,
          // but a teacher scanning the list of programs they're
          // already in expects "add another" hints at the bottom.
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xxxl * 2,
            ),
            itemCount: programs.length + 1,
            separatorBuilder: (_, _) =>
                const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, i) {
              if (i == programs.length) {
                return _JoinAnotherCard(
                  onTap: () => _openJoinSheet(context),
                );
              }
              final p = programs[i];
              final isActive = p.id == activeId;
              return _ProgramTile(
                program: p,
                isActive: isActive,
                onTap: () => context.push('/more/programs/${p.id}'),
                onSwitch: isActive
                    ? null
                    : () => _switchTo(context, ref, p),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _switchTo(
    BuildContext context,
    WidgetRef ref,
    Program program,
  ) async {
    await runWithErrorReport(context, () async {
      await ref
          .read(programAuthBootstrapProvider)
          .switchProgram(program.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Switched to "${program.name}"'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  Future<void> _openCreateSheet(
    BuildContext context,
    WidgetRef ref, {
    required String userId,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NewProgramSheet(userId: userId),
    );
  }

  Future<void> _openJoinSheet(BuildContext context) async {
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
    }
  }
}

/// Cached stream of the signed-in user's programs. Family-keyed by
/// userId so a sign-out + sign-in doesn't blend two users' lists.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final _programsForUserProvider =
    StreamProvider.family<List<Program>, String>((ref, userId) {
  return ref
      .watch(programsRepositoryProvider)
      .watchProgramsForUser(userId);
});

class _ProgramTile extends StatelessWidget {
  const _ProgramTile({
    required this.program,
    required this.isActive,
    required this.onTap,
    required this.onSwitch,
  });

  final Program program;
  final bool isActive;

  /// Tapping the row body opens the detail screen (members,
  /// invites, admin actions). Always non-null — even the active
  /// program has a detail screen worth opening.
  final VoidCallback onTap;

  /// Quick-switch button on non-active rows. Null on the active
  /// row (already current — nothing to switch to). Lets the user
  /// flip programs without opening detail first.
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel =
        'Created ${DateFormat.yMMMd().format(program.createdAt)}';
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          // Program glyph — uses the active accent when this is the
          // current program, surface variant otherwise.
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              isActive
                  ? Icons.check_rounded
                  : Icons.workspaces_outline,
              size: 20,
              color: isActive
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        program.name,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: AppSpacing.sm),
                      _ActivePill(),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  dateLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!isActive && onSwitch != null)
            TextButton(
              onPressed: onSwitch,
              child: const Text('Switch'),
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

/// Trailing card on the programs list that opens the
/// JoinWithCodeSheet. Visually de-emphasized vs the program
/// tiles above it (dashed border tint, no chevron) so it reads
/// as an action rather than an existing membership.
class _JoinAnotherCard extends StatelessWidget {
  const _JoinAnotherCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.qr_code_2_outlined,
                  size: 22,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Join another program',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Have an invite code from an admin? Tap to enter it.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.add,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivePill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Active',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.workspaces_outline,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No programs yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tap "New program" to create one. Each program has '
              'its own roster, schedule, and library.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewProgramSheet extends ConsumerStatefulWidget {
  const _NewProgramSheet({required this.userId});

  final String userId;

  @override
  ConsumerState<_NewProgramSheet> createState() => _NewProgramSheetState();
}

class _NewProgramSheetState extends ConsumerState<_NewProgramSheet> {
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
    await runWithErrorReport(context, () async {
      final newId = await ref
          .read(programAuthBootstrapProvider)
          .createAndSwitchProgram(name: name, userId: widget.userId);
      if (!mounted) return;
      // Pop the modal sheet, then navigate to the freshly created
      // program's detail screen so the user sees their new
      // program (members card, invite codes, etc.) right away
      // instead of bouncing back to the list and having to find
      // the row.
      Navigator.of(context).pop();
      if (!context.mounted) return;
      unawaited(context.push('/more/programs/$newId'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Created "$name"'),
          duration: const Duration(seconds: 2),
        ),
      );
    });
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // Keyboard-aware modal: outer padding lifts with the
      // keyboard, inner SingleChildScrollView lets content
      // scroll when the visible area is smaller than the sheet's
      // natural height.
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
              Text(
                'New program',
                style: theme.textTheme.titleLarge,
              ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Each program has its own roster, schedule, and '
              'library. Members you invite can collaborate inside '
              'that one program.',
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
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
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
