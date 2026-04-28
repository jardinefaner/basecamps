import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/auth/auth_repository.dart';
import 'package:basecamp/features/programs/program_bootstrap.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/save_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      appBar: AppBar(title: const Text('Programs')),
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
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xxxl * 2,
            ),
            itemCount: programs.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, i) {
              final p = programs[i];
              final isActive = p.id == activeId;
              return _ProgramTile(
                program: p,
                isActive: isActive,
                onTap: isActive
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
  });

  final Program program;
  final bool isActive;
  final VoidCallback? onTap;

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
          if (!isActive)
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
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
      await ref.read(programAuthBootstrapProvider).createAndSwitchProgram(
            name: name,
            userId: widget.userId,
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Created "$name"'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg + viewInsets.bottom,
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
    );
  }
}
