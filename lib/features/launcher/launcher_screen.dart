import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

/// Hidden "spotlight" surface that sits to the left of the Today tab.
/// Accessible via a rightward swipe from Today (swipe right on branch
/// 1 → goBranch(0)). No bottom-nav tile of its own — intentionally, so
/// the regular five tabs stay clean.
///
/// Commit A wires the branch + scaffolding in place. Commit B fills in
/// search, quick actions, and the dynamic sections of everything on
/// hand (kids, specialists, destinations, library items).
class LauncherScreen extends StatelessWidget {
  const LauncherScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search,
                  size: 56,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Launcher',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Search and jump anywhere — coming next commit.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Swipe left to return to Today.',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
