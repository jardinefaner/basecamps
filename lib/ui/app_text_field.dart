import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
    this.validator,
    this.prefixIcon,
    this.maxLines = 1,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final IconData? prefixIcon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decoration = InputDecoration(
      hintText: hint,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
    );

    final field = validator != null
        ? TextFormField(
            controller: controller,
            decoration: decoration,
            obscureText: obscureText,
            keyboardType: keyboardType,
            onChanged: onChanged,
            validator: validator,
            maxLines: maxLines,
          )
        : TextField(
            controller: controller,
            decoration: decoration,
            obscureText: obscureText,
            keyboardType: keyboardType,
            onChanged: onChanged,
            maxLines: maxLines,
          );

    if (label == null) return field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label!, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        field,
      ],
    );
  }
}
