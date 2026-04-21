import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

/// Rich "activity card" display. Used (a) in the creation wizard's
/// preview step, and (b) in the library list tile for rows that have
/// the rich fields filled in.
///
/// Every field is optional so this widget works for both legacy preset
/// rows (title only) and fully-generated cards. Empty sections are
/// skipped so the card collapses gracefully.
class ActivityCardPreview extends StatelessWidget {
  const ActivityCardPreview({
    required this.title,
    this.audienceLabel,
    this.hook,
    this.summary,
    this.keyPoints = const <String>[],
    this.learningGoals = const <String>[],
    this.engagementTimeMin,
    this.sourceUrl,
    this.sourceAttribution,
    this.compact = false,
    super.key,
  });

  final String title;
  final String? audienceLabel;
  final String? hook;
  final String? summary;
  final List<String> keyPoints;
  final List<String> learningGoals;
  final int? engagementTimeMin;
  final String? sourceUrl;
  final String? sourceAttribution;

  /// When true, renders a tighter layout (smaller type, no source
  /// footer) for list tiles. Default false = full preview layout.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Audience chip + engagement time row (omit when both
            // missing — no empty strip).
            if (audienceLabel != null || engagementTimeMin != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    if (audienceLabel != null)
                      _MetaChip(
                        icon: Icons.group_outlined,
                        label: audienceLabel!,
                        tint: theme.colorScheme.primary,
                      ),
                    if (engagementTimeMin != null)
                      _MetaChip(
                        icon: Icons.schedule_outlined,
                        label: '$engagementTimeMin min',
                        tint: theme.colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
            Text(
              title,
              style: (compact
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.w700, height: 1.2),
            ),
            if (hook != null && hook!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                hook!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (summary != null && summary!.isNotEmpty) ...[
              SizedBox(height: compact ? AppSpacing.xs : AppSpacing.md),
              Text(
                summary!,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                maxLines: compact ? 3 : null,
                overflow: compact ? TextOverflow.ellipsis : null,
              ),
            ],
            if (!compact && keyPoints.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              const _SectionHeader(label: 'KEY POINTS'),
              const SizedBox(height: AppSpacing.xs),
              for (final p in keyPoints) _Bullet(text: p),
            ],
            if (!compact && learningGoals.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              const _SectionHeader(label: 'LEARNING GOALS'),
              const SizedBox(height: AppSpacing.xs),
              for (final g in learningGoals) _Bullet(text: g),
            ],
            if (!compact && (sourceUrl != null || sourceAttribution != null)) ...[
              const SizedBox(height: AppSpacing.lg),
              _SourceFooter(
                url: sourceUrl,
                attribution: sourceAttribution,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tint.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: tint),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: tint,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceFooter extends StatelessWidget {
  const _SourceFooter({this.url, this.attribution});

  final String? url;
  final String? attribution;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display = attribution ?? url ?? '';
    if (display.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(
          Icons.link,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            display,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
