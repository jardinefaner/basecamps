import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

/// A bottom-sheet scaffold with a scrollable content area and a pinned
/// action bar along the bottom edge. Use as the direct child of a
/// [showModalBottomSheet] builder.
///
/// The content area's max height is explicitly capped so the pinned
/// action bar is always visible — a plain `Flexible` inside a
/// `mainAxisSize.min` Column doesn't bound its child, which lets long
/// forms push the action button off-screen.
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
    final mq = MediaQuery.of(context);

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

    // Sheet structure:
    // ┌───────────────────────────────┐
    // │ Header (fixed intrinsic)      │
    // ├───────────────────────────────┤
    // │ Scrollable body               │  ← capped by ConstrainedBox
    // ├───────────────────────────────┤
    // │ Action bar (fixed intrinsic)  │
    // └───────────────────────────────┘
    //
    // `maxBodyHeight` leaves enough room for header + action bar +
    // keyboard inset so nothing clips, then lets the content scroll.
    final availableHeight = mq.size.height - mq.padding.top;
    final maxBodyHeight = (availableHeight - mq.viewInsets.bottom) * 0.62;

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
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

          // Scrollable body, bounded by an explicit max height so the
          // action bar below can never be pushed off screen.
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxBodyHeight),
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
