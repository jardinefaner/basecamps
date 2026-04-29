import 'dart:async';

import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compact "Live · 3s ago" / "Offline" badge that ticks every
/// time the realtime engine receives a change. Drop into the
/// program-detail header (or the Today screen) so a teacher can
/// see at a glance whether their classroom devices are in sync
/// or whether something's stuck.
///
/// Three visual states:
///   * green dot + "Live" → subscribed AND received a recent
///     event (within ~30s).
///   * amber dot + "Live" → subscribed but no events lately.
///     Normal during a quiet period; just means nothing changed.
///   * grey dot + "Offline" → not subscribed (signed out, on
///     sign-in flow, or the realtime channel never opened).
class LiveIndicator extends ConsumerStatefulWidget {
  const LiveIndicator({super.key});

  @override
  ConsumerState<LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends ConsumerState<LiveIndicator> {
  /// Re-render every second to keep the "X seconds ago" label
  /// fresh. Without this, the label freezes at whatever it was
  /// when the last event came in — fine semantically but jarring.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusAsync = ref.watch(realtimeStatusProvider);
    final status = statusAsync.value ??
        ref.read(syncEngineProvider).currentRealtimeStatus;

    final (Color dot, String label) = _resolveTone(theme, status);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dot,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  /// Pick (dot color, label) from current status. Recency window
  /// is 30s — within that the dot is "fresh green," beyond which
  /// it dims to "subscribed but quiet" amber.
  (Color, String) _resolveTone(ThemeData theme, RealtimeStatus status) {
    if (!status.isSubscribed) {
      return (theme.colorScheme.outline, 'Offline');
    }
    final last = status.lastEventAt;
    if (last == null) {
      return (
        theme.colorScheme.tertiary.withValues(alpha: 0.7),
        'Live',
      );
    }
    final ago = DateTime.now().difference(last);
    final fresh = ago < const Duration(seconds: 30);
    final color = fresh
        ? theme.colorScheme.primary
        : theme.colorScheme.tertiary.withValues(alpha: 0.7);
    return (color, 'Live · ${_formatAgo(ago)}');
  }

  static String _formatAgo(Duration d) {
    if (d.inSeconds < 5) return 'just now';
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }
}

/// Stream of realtime status snapshots from the sync engine.
/// `seedValue` plumbs the engine's most recent snapshot so widgets
/// rebuild with the current state on first build instead of
/// flashing through "loading."
final realtimeStatusProvider = StreamProvider<RealtimeStatus>((ref) {
  final engine = ref.watch(syncEngineProvider);
  // Yield the current snapshot first so the UI doesn't flash
  // "loading" before the next event arrives.
  return Stream<RealtimeStatus>.multi((controller) {
    controller.add(engine.currentRealtimeStatus);
    final sub = engine.realtimeStatus.listen(controller.add);
    controller.onCancel = sub.cancel;
  });
});
