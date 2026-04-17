import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

/// Standard card used across feature surfaces. Supports an optional
/// [onLongPress] (used for entering multi-select flows) and a
/// [selected] state that draws a tinted fill + primary outline, so
/// every bulk-select screen in the app shares the same look.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    super.key,
    this.onTap,
    this.onLongPress,
    this.padding,
    this.selected = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry? padding;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: padding ?? AppSpacing.cardPadding,
      child: child,
    );

    final surface = Card(
      clipBehavior: Clip.antiAlias,
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: (onTap != null || onLongPress != null)
          ? InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              child: content,
            )
          : content,
    );

    return surface;
  }
}
