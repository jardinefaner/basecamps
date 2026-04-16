import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

/// A bottom-sheet scaffold with a scrollable content area and a pinned
/// action bar along the bottom edge. Use as the direct child of a
/// [showModalBottomSheet] builder.
///
/// - Content scrolls independently of the action bar, so the primary
///   button is always reachable without scrolling through the form.
/// - Bottom safe-area and keyboard insets are respected.
/// - A subtle divider line sits between content and action bar.
/// - A close (✕) button is rendered in the top-right by default so the
///   user has an explicit way out when the sheet is opened with
///   `isDismissible: false` (which we use to avoid accidental dismisses
///   from stray taps outside the sheet).
class StickyActionSheet extends StatelessWidget {
  const StickyActionSheet({
    required this.title,
    required this.child,
    required this.actionBar,
    this.titleTrailing,
    this.subtitle,
    this.showCloseButton = false,
    super.key,
  });

  final String title;
  final Widget? titleTrailing;
  final Widget? subtitle;
  final Widget child;
  final Widget actionBar;
  final bool showCloseButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insets = MediaQuery.of(context).viewInsets.bottom;

    final trailingWidgets = <Widget>[];
    if (titleTrailing != null) trailingWidgets.add(titleTrailing!);
    if (showCloseButton) {
      trailingWidgets.add(
        IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.sm,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title, style: theme.textTheme.titleLarge),
                    ),
                    ...trailingWidgets,
                  ],
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(
                      right: AppSpacing.lg,
                      top: AppSpacing.xs,
                    ),
                    child: DefaultTextStyle(
                      style: theme.textTheme.bodySmall!,
                      child: subtitle!,
                    ),
                  ),
              ],
            ),
          ),

          // Scrollable body
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: child,
            ),
          ),

          // Pinned action bar
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.md,
                  AppSpacing.xl,
                  AppSpacing.md,
                ),
                child: actionBar,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
