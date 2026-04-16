import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

TextTheme appTextTheme(ColorScheme colorScheme) {
  final base = GoogleFonts.interTextTheme();
  final onSurface = colorScheme.onSurface;
  final onSurfaceVariant = colorScheme.onSurfaceVariant;

  return base.copyWith(
    displayLarge: base.displayLarge?.copyWith(
      fontSize: 36,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      color: onSurface,
    ),
    displayMedium: base.displayMedium?.copyWith(
      fontSize: 28,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.25,
      color: onSurface,
    ),
    displaySmall: base.displaySmall?.copyWith(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: onSurface,
    ),
    headlineLarge: base.headlineLarge?.copyWith(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: onSurface,
    ),
    headlineMedium: base.headlineMedium?.copyWith(
      fontSize: 20,
      fontWeight: FontWeight.w500,
      color: onSurface,
    ),
    headlineSmall: base.headlineSmall?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w500,
      color: onSurface,
    ),
    titleLarge: base.titleLarge?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: onSurface,
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
      color: onSurface,
    ),
    titleSmall: base.titleSmall?.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
      color: onSurface,
    ),
    bodyLarge: base.bodyLarge?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.15,
      color: onSurface,
    ),
    bodyMedium: base.bodyMedium?.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.15,
      color: onSurface,
    ),
    bodySmall: base.bodySmall?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.2,
      color: onSurfaceVariant,
    ),
    labelLarge: base.labelLarge?.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
      color: onSurface,
    ),
    labelMedium: base.labelMedium?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      color: onSurfaceVariant,
    ),
    labelSmall: base.labelSmall?.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      color: onSurfaceVariant,
    ),
  );
}
