import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/auth/auth_repository.dart';
import 'package:basecamp/features/programs/program_bootstrap.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/settings/program_settings.dart';
import 'package:basecamp/features/sync/sync_card.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Program-wide configuration screen — grace knobs, danger zone,
/// account, and sync status — split across two tabs:
///
///   * **Settings** — late-arrival grace + pickup-overdue grace +
///     the signed-in account + a danger-zone "Clear all data" action.
///   * **Sync** — last-sync freshness card + a link out to the deep
///     sync diagnostics screen for the persistent-RLS-debug case.
///
/// Before this consolidation, sync surfacing was split between the
/// settings screen (SyncCard), `/more/programs` (per-program rows),
/// and `/more/programs/diagnostics` (deep checks). Pulling the daily
/// "is my data on the cloud?" signal next to the settings the
/// teacher actually opens means they don't have to hunt for it.
class ProgramSettingsScreen extends ConsumerWidget {
  const ProgramSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.scaffoldBackgroundColor,
          title: const Text('Program'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Settings'),
              Tab(text: 'Sync'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _SettingsTab(),
            _SyncTab(),
          ],
        ),
      ),
    );
  }
}

class _SettingsTab extends ConsumerWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(programSettingsProvider);
    final notifier = ref.read(programSettingsProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _GraceCard(
          title: 'Late-arrival grace',
          subtitle: "Minutes past a child's expected drop-off "
              'before the "Late" flag fires on Today. Tune up to '
              'quiet traffic-jam noise; tune down if you want '
              'earlier signal.',
          value: settings.latenessGraceMinutes,
          onChanged: notifier.setLatenessGrace,
        ),
        const SizedBox(height: AppSpacing.md),
        _GraceCard(
          title: 'Pickup overdue grace',
          subtitle: "Minutes past a child's expected pickup before "
              'they appear in the overdue-pickups strip. Parents '
              'running a few minutes late is routine; this knob '
              'decides when it stops being routine.',
          value: settings.pickupGraceMinutes,
          onChanged: notifier.setPickupGrace,
        ),
        const SizedBox(height: AppSpacing.xxl),
        const _AccountCard(),
        const SizedBox(height: AppSpacing.xxl),
        const _DangerZone(),
      ],
    );
  }
}

class _SyncTab extends ConsumerWidget {
  const _SyncTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const SyncCard(),
        const SizedBox(height: AppSpacing.lg),
        const _ReconnectMembershipCard(),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Diagnostics', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'If syncing looks wrong — rows missing, edits not '
                'showing up on the other device — open diagnostics. '
                'It surfaces the JWT, server identity, and runs a '
                'live INSERT probe so the exact RLS error becomes '
                'copyable.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      context.push('/more/programs/diagnostics'),
                  icon: const Icon(Icons.bug_report_outlined, size: 18),
                  label: const Text('Open diagnostics'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Switch program', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Manage memberships, switch which program is active, '
                'or join another with an invite code.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/more/programs'),
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('Programs'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Heal action for the "I'm admin locally but cloud thinks I'm not"
/// state — re-runs the bootstrap's program + membership upsert so
/// the user's role + membership row in cloud matches what local
/// has. Shows up on a 403 from program_invites or any other
/// admin-gated read; users who never need it can ignore the card.
class _ReconnectMembershipCard extends ConsumerStatefulWidget {
  const _ReconnectMembershipCard();

  @override
  ConsumerState<_ReconnectMembershipCard> createState() =>
      _ReconnectMembershipCardState();
}

class _ReconnectMembershipCardState
    extends ConsumerState<_ReconnectMembershipCard> {
  bool _busy = false;
  String? _result;

  Future<void> _run() async {
    final activeId = ref.read(activeProgramIdProvider);
    if (activeId == null) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      await ref
          .read(programAuthBootstrapProvider)
          .reconnectMembership(activeId);
      if (!mounted) return;
      setState(() {
        _result = '✓ Membership reconnected.';
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _result = '✗ Failed: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Reconnect membership',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'If creating invites or admin actions are erroring with '
            '403, your cloud membership row may be out of sync with '
            'this device. Re-pushes the program + membership rows so '
            'cloud RLS matches your local admin role.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _run,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_sync_outlined, size: 18),
              label: Text(_busy ? 'Reconnecting…' : 'Reconnect now'),
            ),
          ),
          if (_result != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _result!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _result!.startsWith('✗')
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shows the signed-in Google account and a sign-out button.
class _AccountCard extends ConsumerWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(currentSessionProvider);
    final email = session?.user.email ?? '—';
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Account',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Signed in as $email.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Sign out'),
                onPressed: () async {
                  await ref.read(authRepositoryProvider).signOut();
                  // Router redirect picks it up — nothing to do here.
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Standard card layout for a single grace-minutes setting.
class _GraceCard extends StatelessWidget {
  const _GraceCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Slider(
                  max: 60,
                  divisions: 12,
                  value: value.toDouble(),
                  label: '$value min',
                  onChanged: (v) => onChanged(v.round()),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  '$value min',
                  style: theme.textTheme.titleSmall,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Clear all data" section — wipes every Drift row AND on-device
/// UI state (SharedPreferences) behind a two-step confirmation.
class _DangerZone extends ConsumerStatefulWidget {
  const _DangerZone();

  @override
  ConsumerState<_DangerZone> createState() => _DangerZoneState();
}

class _DangerZoneState extends ConsumerState<_DangerZone> {
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.35),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: theme.colorScheme.error,
                  size: 18,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'DANGER ZONE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Clear all data',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Wipes every child, adult, group, room, activity, '
              'observation, attendance record, concern note, form '
              'submission, and vehicle check from this device. Also '
              'resets program settings and on-device preferences '
              '(last-expanded group, mode toggles, grace windows). '
              'Cannot be undone.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _working ? null : _confirmAndClear,
                icon: _working
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_sweep_outlined, size: 18),
                label: Text(_working ? 'Clearing…' : 'Clear all data'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(
                    color: theme.colorScheme.error.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Two-step confirmation: first the usual "Are you sure?" with a
  /// scary-enough message, then a second dialog that only gates on
  /// the user explicitly typing "CLEAR" — enough friction that a
  /// brushed tap never survives to the actual wipe.
  Future<void> _confirmAndClear() async {
    final firstOk = await showConfirmDialog(
      context: context,
      title: 'Clear all program data?',
      message: 'Every row on every screen goes. This cannot be undone. '
          "You'll be asked to confirm again on the next step.",
      confirmLabel: 'Continue',
    );
    if (!firstOk || !mounted) return;
    final typed = await _confirmByTyping(context);
    if (typed != true || !mounted) return;

    setState(() => _working = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final db = ref.read(databaseProvider);
      await db.clearAllData();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'All data cleared. Close and reopen the app for a '
              'fully-reset state.',
            ),
            duration: Duration(seconds: 6),
          ),
        );
    } on Object catch (e) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Clear failed: $e')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Second-step confirmation: teacher types CLEAR to enable the
  /// destructive button.
  Future<bool?> _confirmByTyping(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final ready = controller.text.trim().toUpperCase() == 'CLEAR';
            return AlertDialog(
              title: const Text('Really clear everything?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Type CLEAR (all caps) to confirm. There is no '
                    'undo after this.',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Type CLEAR',
                    ),
                    onChanged: (_) => setModalState(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: ready
                      ? () => Navigator.of(ctx).pop(true)
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                    foregroundColor: Theme.of(ctx).colorScheme.onError,
                  ),
                  child: const Text('Wipe'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
