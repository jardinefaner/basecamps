// Spotlight-style domain picker shown above the command bar
// whenever the user types something that prefix-matches one of
// the known composer keywords ("obs", "trip", "calendar"…).
//
// The picker is a thin presentation widget — the screen owns the
// matching logic and the on-pick callback. We keep it stateless so
// it can be rebuilt on every keystroke without churning controllers.

import 'package:basecamp/features/experiment/command/composer/composer_kind.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

class DomainPickerStrip extends StatelessWidget {
  const DomainPickerStrip({
    required this.matches,
    required this.onPick,
    super.key,
  });

  /// Filtered list — empty hides the strip entirely.
  final List<ComposerKind> matches;
  final ValueChanged<ComposerKind> onPick;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < matches.length; i++) ...[
            if (i > 0)
              Divider(
                height: 0.5,
                thickness: 0.5,
                color: theme.colorScheme.outlineVariant,
              ),
            InkWell(
              onTap: () => onPick(matches[i]),
              borderRadius: i == 0
                  ? const BorderRadius.vertical(
                      top: Radius.circular(AppSpacing.sm),
                    )
                  : i == matches.length - 1
                      ? const BorderRadius.vertical(
                          bottom: Radius.circular(AppSpacing.sm),
                        )
                      : BorderRadius.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      matches[i].icon,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            matches[i].label,
                            style: theme.textTheme.bodyMedium,
                          ),
                          Text(
                            matches[i].description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Future hint: a "↵" glyph for the highlighted
                    // suggestion (when we add keyboard-driven nav).
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
