import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:basecamp/features/sync/sync_specs.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Cloud-sync card for Program Settings (and the *only* surface for
/// "is this device in sync with the cloud?").
///
/// What it shows:
///   - The active program's name (so a user with multiple programs
///     can confirm which one they're operating on without bouncing
///     to the programs screen).
///   - "Last synced N min ago" — derived from the most recent
///     `lastPulledAt` across the per-table watermark in `sync_state`.
///   - "Sync now" button — manual force-pull of every synced table
///     for callers who don't want to wait for the next debounce.
///   - An error banner if the last manual sync failed.
///
/// What it deliberately doesn't say: anything about backups. The
/// previous BackupCard offered an opaque JSON snapshot push/restore
/// flow that was redundant with live sync — every row already
/// mirrors to cloud per-row, so the snapshot was a divergent second
/// source of truth. Retired in favor of this card being the single
/// "your data is on the cloud, here's the freshness signal" surface.
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
      // Same FK-ordered tier walk as the bootstrap — parallel
      // within each tier, sequential between. force=true bypasses
      // the 30-second debounce on each spec so this is a real
      // pull, not a "show me the cached debounce result."
      final engine = ref.read(syncEngineProvider);
      final perTable = <String, int>{};
      for (final tier in kSpecTiers) {
        final results = await Future.wait([
          for (final spec in tier)
            engine
                .pullTable(
                  spec: spec,
                  programId: programId,
                  force: true,
                )
                .then((n) => MapEntry(spec.table, n)),
        ]);
        for (final entry in results) {
          perTable[entry.key] = entry.value;
        }
      }
      if (!mounted) return;
      final total = perTable.values.fold<int>(0, (a, b) => a + b);
      // Honest reporting — list every table that pulled anything.
      // Hides "Pulled 5 rows" when 4 of those were sequence/theme
      // rows and the user expected to see rooms.
      final hits = perTable.entries.where((e) => e.value > 0).toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final summary = total == 0
          ? 'Already up to date — no new rows in any of the '
              '${kAllSpecs.length} tables for this program. If '
              "you're expecting data from another device, check "
              'Sync audit (Diagnostics card) — your devices may '
              'be on different programs.'
          : 'Pulled $total row${total == 1 ? '' : 's'}: '
              '${hits.map((e) => '${e.value} ${e.key}').join(', ')}';
      setState(() => _lastResult = summary);
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
    final programId = ref.watch(activeProgramIdProvider);
    final programAsync = programId == null
        ? const AsyncValue<Program?>.data(null)
        : ref.watch(_activeProgramRowProvider(programId));
    final lastSyncAsync = programId == null
        ? const AsyncValue<DateTime?>.data(null)
        : ref.watch(_lastSyncedAtProvider(programId));

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Cloud sync', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Everything you create syncs across your devices '
              'automatically while you’re signed in. Nothing '
              'to back up — every row lives on the cloud the moment '
              'it’s saved.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _StatusRow(
              label: 'Program',
              value: programAsync.when(
                data: (p) => p?.name ?? '—',
                loading: () => '…',
                error: (_, _) => '—',
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            _StatusRow(
              label: 'Last synced',
              value: lastSyncAsync.when(
                data: _formatLastSync,
                loading: () => '…',
                error: (_, _) => 'unknown',
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
                onPressed: _busy || programId == null ? null : _handleSync,
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

  /// Render the relative-time label users actually want: "just
  /// now" / "5 min ago" / "2 h ago" / "Apr 27, 3:14 PM" for older.
  /// Absolute beyond 24h because "yesterday" is ambiguous across
  /// timezone changes.
  static String _formatLastSync(DateTime? at) {
    if (at == null) return 'never';
    final now = DateTime.now();
    final diff = now.difference(at);
    if (diff.inSeconds < 30) return 'just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min ago';
    }
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return DateFormat.MMMd().add_jm().format(at);
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Reactive single-program lookup for the sync card's header. Family-
/// keyed by program id so a switch lights up the new name without a
/// stale frame.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final _activeProgramRowProvider =
    StreamProvider.family<Program?, String>((ref, id) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.programs)..where((p) => p.id.equals(id)))
      .watchSingleOrNull();
});

/// "When was the last successful pull?" — the max `lastPulledAt`
/// across every sync_state row for this program. Returns null when
/// no row exists yet (first launch, never pulled).
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final _lastSyncedAtProvider =
    StreamProvider.family<DateTime?, String>((ref, programId) {
  final db = ref.watch(databaseProvider);
  // Pick the most recent watermark across the per-table rows. If
  // sync_state is empty for this program (no pull has ever
  // succeeded) we return null and the UI renders "never".
  final query = db.select(db.syncState)
    ..where((s) => s.programId.equals(programId))
    ..orderBy([(s) => OrderingTerm.desc(s.lastPulledAt)])
    ..limit(1);
  return query
      .watchSingleOrNull()
      .map((row) => row?.lastPulledAt);
});
