import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    super.key,
    this.onTap,
    this.padding,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding ?? AppSpacing.cardPadding,
      child: child,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: onTap != null
          ? InkWell(onTap: onTap, child: content)
          : content,
    );
  }
}
