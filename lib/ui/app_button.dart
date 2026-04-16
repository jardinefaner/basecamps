import 'package:flutter/material.dart';

enum _AppButtonVariant { primary, secondary, text }

class AppButton extends StatelessWidget {
  const AppButton.primary({
    required this.onPressed,
    required this.label,
    super.key,
    this.icon,
    this.isLoading = false,
  }) : _variant = _AppButtonVariant.primary;

  const AppButton.secondary({
    required this.onPressed,
    required this.label,
    super.key,
    this.icon,
    this.isLoading = false,
  }) : _variant = _AppButtonVariant.secondary;

  const AppButton.text({
    required this.onPressed,
    required this.label,
    super.key,
    this.icon,
    this.isLoading = false,
  }) : _variant = _AppButtonVariant.text;

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final bool isLoading;
  final _AppButtonVariant _variant;

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = isLoading ? null : onPressed;
    final child = isLoading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label);

    return switch (_variant) {
      _AppButtonVariant.primary => icon != null && !isLoading
          ? ElevatedButton.icon(
              onPressed: effectiveOnPressed,
              icon: Icon(icon, size: 18),
              label: child,
            )
          : ElevatedButton(onPressed: effectiveOnPressed, child: child),
      _AppButtonVariant.secondary => icon != null && !isLoading
          ? OutlinedButton.icon(
              onPressed: effectiveOnPressed,
              icon: Icon(icon, size: 18),
              label: child,
            )
          : OutlinedButton(onPressed: effectiveOnPressed, child: child),
      _AppButtonVariant.text => icon != null && !isLoading
          ? TextButton.icon(
              onPressed: effectiveOnPressed,
              icon: Icon(icon, size: 18),
              label: child,
            )
          : TextButton(onPressed: effectiveOnPressed, child: child),
    };
  }
}
