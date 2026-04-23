import 'package:basecamp/features/settings/program_settings.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Program-wide settings screen. Currently: late-arrival grace +
/// overdue-pickup grace. Small on purpose — more knobs earn a spot
/// when they have a concrete teacher complaint driving them.
class ProgramSettingsScreen extends ConsumerWidget {
  const ProgramSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(programSettingsProvider);
    final notifier = ref.read(programSettingsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Program settings')),
      body: ListView(
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
        ],
      ),
    );
  }
}

/// Standard card layout for a single grace-minutes setting. Slider
/// snapped to 5-min increments so teachers don't have to fiddle for
/// an exact value — 10, 15, 20 are the pragmatic options and the
/// slider enforces that.
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
