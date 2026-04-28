import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/sync/observations_sync_service.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sync-status card for Program Settings. Conceptually distinct
/// from BackupCard:
///   - **Backup** is an opaque JSON snapshot for "I lost my
///     laptop." One file per program, restore wipes-and-replays.
///   - **Sync** is per-row, per-table cloud mirroring. Incremental
///     and watermarked — push happens automatically on every
///     local write; pull runs on sign-in and on this button.
///
/// Right now sync only covers Observations (Slice C v1). When the
/// next table comes online (Schedule? Children?) the button kicks
/// pull on every wired table.
class SyncCard extends ConsumerStatefulWidget {
  const SyncCard({super.key});

  @override
  ConsumerState<SyncCard> createState() => _SyncCardState();
}

class _SyncCardState extends ConsumerState<SyncCard> {
  bool _busy = false;
  String? _lastResult;
  String? _error;

  Future<void> _handleSync() async {
    final programId = ref.read(activeProgramIdProvider);
    if (programId == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _lastResult = null;
    });
    try {
      // force=true bypasses the 30-second debounce — the user
      // explicitly asked for a refresh, don't tell them to wait.
      final applied = await ref
          .read(observationsSyncServiceProvider)
          .pullObservations(programId: programId, force: true);
      if (!mounted) return;
      setState(() {
        _lastResult = applied == 0
            ? 'Already up to date.'
            : 'Pulled $applied observation${applied == 1 ? '' : 's'}.';
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Sync failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Cloud sync', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Observations sync to the cloud automatically as you '
              'create them. Tap below to pull any changes from your '
              'other devices right now.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync, size: 18),
                label: const Text('Sync now'),
                onPressed: _busy ? null : _handleSync,
              ),
            ),
            if (_lastResult != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _lastResult!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
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
}
