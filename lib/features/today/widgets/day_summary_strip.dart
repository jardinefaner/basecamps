import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

/// Compact "at a glance" strip directly under the date label. Four
/// stats: activities scheduled today, children in groups with activities,
/// specialists on today, and pending items — either "N concerns
/// logged" or "N obs to log" depending on which is more actionable in
/// this moment. Taps on the concerns / pending-obs stats deep-link to
/// the relevant screen; the first two are display-only.
class DaySummaryStrip extends StatelessWidget {
  const DaySummaryStrip({
    required this.activities,
    required this.children,
    required this.specialists,
    required this.concerns,
    required this.pendingObs,
    this.onTapConcerns,
    this.onTapPending,
    super.key,
  });

  final int activities;
  final int children;
  final int specialists;
  final int concerns;
  final int pendingObs;
  final VoidCallback? onTapConcerns;
  final VoidCallback? onTapPending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              icon: Icons.event_available_outlined,
              value: '$activities',
              label: activities == 1 ? 'activity' : 'activities',
            ),
          ),
          _Divider(),
          Expanded(
            child: _Stat(
              icon: Icons.groups_outlined,
              value: '$children',
              label: children == 1 ? 'child' : 'children',
            ),
          ),
          _Divider(),
          Expanded(
            child: _Stat(
              icon: Icons.person_outline,
              value: '$specialists',
              label: specialists == 1 ? 'specialist' : 'specialists',
            ),
          ),
          _Divider(),
          Expanded(
            child: concerns > 0
                ? _Stat(
                    icon: Icons.priority_high_rounded,
                    value: '$concerns',
                    label: concerns == 1 ? 'concern' : 'concerns',
                    accent: theme.colorScheme.error,
                    onTap: onTapConcerns,
                  )
                : _Stat(
                    icon: Icons.edit_note_outlined,
                    value: pendingObs == 0 ? '—' : '$pendingObs',
                    label: pendingObs == 0
                        ? 'caught up'
                        : (pendingObs == 1 ? 'to log' : 'to log'),
                    accent: pendingObs > 0 ? theme.colorScheme.primary : null,
                    onTap: pendingObs > 0 ? onTapPending : null,
                  ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.value,
    required this.label,
    this.accent,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueColor = accent ?? theme.colorScheme.onSurface;
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: accent ?? theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                color: valueColor,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
    if (onTap == null) return child;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: child,
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}
