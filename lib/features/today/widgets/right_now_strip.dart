import 'dart:async';

import 'package:basecamp/core/format/date.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/features/observations/widgets/observation_composer.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Proactive "what should I do right now?" strip on Today.
///
/// Each signal is a derived rule against existing state — no LLM, no
/// network calls. The strip surfaces at most one signal at a time so
/// it never feels nagging; when no rule fires it renders an empty
/// SizedBox and disappears.
///
/// First ship rules:
///   * **Observation gap during program hours.** It's after 9am, the
///     teacher hasn't logged an observation in 2+ hours (or hasn't
///     logged anything yet today), and we're still inside an active
///     program day. Surfaces a card with a one-tap "Log observation"
///     action.
///
/// New rules drop into [_resolveSignals] as additional [_Signal]
/// emissions. The renderer takes the first non-null result, so
/// signal order in that function is the priority order.
class RightNowStrip extends ConsumerWidget {
  const RightNowStrip({required this.now, super.key});

  /// Wall-clock now from the Today screen's `nowTickProvider`. Passed
  /// in (rather than reading the clock here) so the rule fires on the
  /// same minute boundary as the rest of Today's live-clock widgets.
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final obsAsync = ref.watch(observationsProvider);
    final observations =
        obsAsync.asData?.value ?? const <Observation>[];
    final signal = _resolveSignals(now: now, observations: observations);
    if (signal == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: _SignalCard(signal: signal),
    );
  }
}

/// One actionable nudge. Pure data — the renderer wraps it in a card.
class _Signal {
  const _Signal({
    required this.icon,
    required this.label,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;

  /// Short uppercase label rendered above the body. Mirrors the
  /// "TODAY'S CURRICULUM" / "DAILY RITUALS" label idiom from the
  /// other Today strips so they share a typographic rhythm.
  final String label;

  /// One-line body. Shown on the card under the label.
  final String body;

  /// Right-side action button label.
  final String actionLabel;

  /// Action handler. Receives the build context so it can push a
  /// route or open a sheet.
  final FutureOr<void> Function(BuildContext context) onAction;
}

/// Walks the rules in priority order. Returns the first signal that
/// fires; null when nothing's actionable. Pure function — testable
/// in isolation if we ever need it (today's observations + the now
/// clock are the only inputs).
_Signal? _resolveSignals({
  required DateTime now,
  required List<Observation> observations,
}) {
  // Rule 1: observation gap during program hours.
  final obs = _resolveObservationGap(now: now, observations: observations);
  if (obs != null) return obs;
  return null;
}

/// Window: 9:00 → 15:00 local. Inside that range, if the last
/// observation is more than 2 hours old (or nothing's been logged
/// today at all), surface the nudge.
///
/// Why these defaults: most early-childhood programs run roughly
/// 8:30 → 15:30; the 9 → 15 inner window means we don't fire during
/// drop-off (when teachers are doing other things) or pickup (when
/// it's already too late to do morning observations). The 2-hour
/// gap matches the typical "morning meeting / activity / snack"
/// rhythm — long enough that a teacher who's logging steadily won't
/// see it, short enough that a forgotten morning gets caught.
_Signal? _resolveObservationGap({
  required DateTime now,
  required List<Observation> observations,
}) {
  final hour = now.hour;
  if (hour < 9 || hour >= 15) return null;

  final today = now.dayOnly;
  final tomorrow = today.add(const Duration(days: 1));

  // Only consider observations created on today's calendar date —
  // a "last observation 4 hours ago" that came from yesterday isn't
  // a fresh signal worth nudging on.
  final todays = observations.where((o) {
    final ts = o.createdAt.toLocal();
    return !ts.isBefore(today) && ts.isBefore(tomorrow);
  }).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  if (todays.isEmpty) {
    return _Signal(
      icon: Icons.visibility_outlined,
      label: 'NO OBSERVATIONS YET',
      body: "It's $hour${hour < 12 ? 'am' : 'pm'} and nothing's logged "
          "for the day. Capture a quick note while it's fresh.",
      actionLabel: 'Log',
      onAction: _openComposer,
    );
  }
  final lastAt = todays.first.createdAt.toLocal();
  final gap = now.difference(lastAt);
  if (gap.inHours < 2) return null;

  final agoLabel = _formatAgo(gap);
  return _Signal(
    icon: Icons.visibility_outlined,
    label: 'OBSERVATION GAP',
    body: 'Last observation $agoLabel. Log a fresh note while you '
        "remember the moment — it's easier now than later.",
    actionLabel: 'Log',
    onAction: _openComposer,
  );
}

/// Open the observation composer as a modal bottom sheet. Reuses
/// the same surface the FAB's "Add → Observation" path uses, so
/// the two entry points behave identically.
Future<void> _openComposer(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom,
      ),
      child: const Scaffold(
        backgroundColor: Colors.transparent,
        body: ObservationComposer(),
      ),
    ),
  );
}

/// "1h 20m" → "an hour ago"; "2h 0m" → "2 hours ago". Approximate;
/// the goal is glanceable, not exact.
String _formatAgo(Duration d) {
  final hours = d.inHours;
  if (hours < 1) return '${d.inMinutes} min ago';
  if (hours == 1) return '1 hour ago';
  return '$hours hours ago';
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({required this.signal});

  final _Signal signal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            signal.icon,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  signal.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  signal.body,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton.tonal(
            onPressed: () => signal.onAction(context),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
              ),
            ),
            child: Text(signal.actionLabel),
          ),
        ],
      ),
    );
  }
}
