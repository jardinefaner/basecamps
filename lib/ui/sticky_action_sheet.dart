import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

/// A bottom-sheet scaffold with a scrollable content area and a pinned
/// action bar along the bottom edge. Use as the direct child of a
/// [showModalBottomSheet] builder.
///
/// Layout:
/// ┌───────────────────────────────┐
/// │ Header (intrinsic)            │
/// ├───────────────────────────────┤
/// │ Expanded scrollable body      │
/// ├───────────────────────────────┤
/// │ Action bar (intrinsic)        │
/// └───────────────────────────────┘
///
/// Implementation note: we use `Column(mainAxisSize.max)` + `Expanded`
/// inside a size-bounded ConstrainedBox. `mainAxisSize.min` + `Flexible`
/// looks right but doesn't actually bound the child — Flutter gives
/// Flexible its intrinsic size in that configuration, so long forms push
/// the action bar off-screen. Column-max + Expanded inside a bounded
/// container gives proper flex distribution.
///
/// The sheet will fill the available height. That's fine for modal form
/// sheets — teachers expect the action bar at the bottom edge. Short
/// forms just show extra whitespace between the last field and the
/// action bar.
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final keyboard = mq.viewInsets.bottom;
        final availableHeight = (constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : mq.size.height) -
            keyboard;
        final maxHeight = availableHeight.clamp(220.0, double.infinity);

        return Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: SizedBox(
            height: maxHeight,
            child: Column(
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
                            child: Text(
                              title,
                              style: theme.textTheme.titleLarge,
                            ),
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

                // Scrollable body in the middle — takes all leftover space.
                Expanded(
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
          ),
        );
      },
    );
  }
}
