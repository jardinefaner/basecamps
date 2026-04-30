import 'dart:async';

import 'package:basecamp/features/backup/backup_repository.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cloud-backup card for the Program Settings screen.
///
/// Shows the most-recent cloud-snapshot timestamp (or "never") and
/// two actions:
///   - **Back up now** — uploads a fresh snapshot of the active
///     program. Idempotent on the server; the bucket holds exactly
///     one object per program.
///   - **Restore from cloud** — replaces local rows with the cloud
///     snapshot's data. Confirmed via a dialog because it overwrites
///     unsynced local edits.
///
/// Auto-pull on sign-in lands in a follow-up; for now, manual buttons
/// keep the timing predictable.
class BackupCard extends ConsumerStatefulWidget {
  const BackupCard({super.key});

  @override
  ConsumerState<BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends ConsumerState<BackupCard> {
  /// Last-known cloud snapshot info — null until [_refresh] reads it
  /// from Supabase, or when no snapshot exists yet.
  CloudSnapshotInfo? _info;

  /// Loaded once on init and after every push/pull. Tracks whether
  /// we've at least asked Supabase, so the UI can show a placeholder
  /// vs. "never backed up."
  bool _loaded = false;

  bool _busyPush = false;
  bool _busyPull = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    // Re-refresh whenever the active program switches — without
    // this listen the "Last backed up" line stays stale (showing
    // the previous program's snapshot) until the user navigates
    // away and back.
    ref.listenManual<String?>(activeProgramIdProvider, (_, _) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    final programId = ref.read(activeProgramIdProvider);
    if (programId == null) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    try {
      final info = await ref
          .read(backupRepositoryProvider)
          .cloudSnapshotInfo(programId);
      if (!mounted) return;
      setState(() {
        _info = info;
        _loaded = true;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  Future<void> _handlePush() async {
    final programId = ref.read(activeProgramIdProvider);
    if (programId == null) return;
    setState(() {
      _busyPush = true;
      _error = null;
    });
    try {
      final at = await ref
          .read(backupRepositoryProvider)
          .pushSnapshotToCloud(programId);
      if (!mounted) return;
      setState(() {
        _info = CloudSnapshotInfo(updatedAt: at);
      });
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Backed up to the cloud.')),
        );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Backup failed: $e');
    } finally {
      if (mounted) setState(() => _busyPush = false);
    }
  }

  Future<void> _handlePull() async {
    final programId = ref.read(activeProgramIdProvider);
    if (programId == null) return;
    final ok = await showConfirmDialog(
      context: context,
      title: 'Restore from cloud?',
      message: 'This replaces every child, observation, and form on '
          'this device with the cloud snapshot. Anything you edited '
          'here that isn’t backed up will be lost.',
      confirmLabel: 'Restore',
    );
    if (!ok || !mounted) return;
    setState(() {
      _busyPull = true;
      _error = null;
    });
    try {
      await ref
          .read(backupRepositoryProvider)
          .pullSnapshotFromCloud(programId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Restored from cloud.')),
        );
    } on BackupSchemaMismatch catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Restore failed: $e');
    } finally {
      if (mounted) setState(() => _busyPull = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastLabel = !_loaded
        ? 'Checking…'
        : _info == null
            ? 'Never backed up.'
            : 'Last backed up ${_relativeLabel(_info!.updatedAt)}.';

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Cloud backup', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              lastLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  icon: _busyPush
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined, size: 18),
                  label: const Text('Back up now'),
                  onPressed:
                      _busyPush || _busyPull ? null : _handlePush,
                ),
                OutlinedButton.icon(
                  icon: _busyPull
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_download_outlined, size: 18),
                  label: const Text('Restore from cloud'),
                  // Restore disabled when there's nothing to restore.
                  onPressed: _busyPush ||
                          _busyPull ||
                          !_loaded ||
                          _info == null
                      ? null
                      : _handlePull,
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Coarse relative-time label for the "Last backed up X" line.
  /// Shorter/more readable than a full date stamp for the common
  /// "minutes-to-hours-ago" case; falls back to a date for older
  /// snapshots.
  String _relativeLabel(DateTime utc) {
    final now = DateTime.now().toUtc();
    final diff = now.difference(utc);
    if (diff.isNegative) return 'just now';
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return '$m minute${m == 1 ? '' : 's'} ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h hour${h == 1 ? '' : 's'} ago';
    }
    if (diff.inDays < 7) {
      final d = diff.inDays;
      return '$d day${d == 1 ? '' : 's'} ago';
    }
    final local = utc.toLocal();
    return 'on ${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
