import 'package:basecamp/theme/colors.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/theme/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

ThemeData lightTheme() => _buildTheme(AppColors.light);
ThemeData darkTheme() => _buildTheme(AppColors.dark);

ThemeData _buildTheme(ColorScheme colorScheme) {
  final textTheme = appTextTheme(colorScheme);

  return ThemeData(
    useMaterial3: true,
    brightness: colorScheme.brightness,
    colorScheme: colorScheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: colorScheme.surface,
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      // Solid surface so the floating SliverAppBar occludes content
      // behind it when it snaps back in on scroll-up. The earlier
      // transparent fill let text show through the bar.
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: colorScheme.onSurface,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
      // Pin the overlay style to the theme's brightness so battery /
      // clock / signal stay readable on both.
      //
      // Note: SystemUiOverlayStyle.dark means *dark icons* (for light
      // backgrounds) and .light means *light icons* — the naming is
      // counterintuitive.
      systemOverlayStyle: colorScheme.brightness == Brightness.light
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.cardBorderRadius,
        side: BorderSide(color: colorScheme.outline, width: 0.5),
      ),
      color: colorScheme.surfaceContainer,
      margin: EdgeInsets.zero,
    ),
    // 600ms wait before tooltips appear, app-wide. Workaround for
    // Flutter web's Tooltip jitter — when the cursor moves through
    // a row of IconButtons with default-zero waitDuration, each
    // tooltip flashes in/out as the pointer crosses the boundary,
    // which reads as flicker. A short delay lets the cursor settle
    // before any tooltip materialises and quick hovers don't
    // trigger anything at all.
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 600),
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      backgroundColor: colorScheme.surface,
      indicatorColor: colorScheme.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(
        textTheme.labelMedium!.copyWith(color: colorScheme.onSurfaceVariant),
      ),
      iconTheme: WidgetStatePropertyAll(
        IconThemeData(color: colorScheme.onSurfaceVariant, size: 22),
      ),
      height: 64,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainer,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colorScheme.outline, width: 0.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colorScheme.outline, width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.primary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        side: BorderSide(color: colorScheme.outline),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        textStyle: textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      thickness: 0.5,
      space: 0,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 0,
    ),
    // Floating snackbars across the app. The default
    // SnackBarBehavior.fixed paints a full-width bar at the bottom
    // of the screen that occludes whatever lives there — most
    // notably the FAB on Today (the "Add" button) and the
    // sticky-action-sheet save buttons on every modal editor. A
    // teacher tapping save → snackbar → can't tap the same area
    // again until the snackbar dismisses is a real productivity
    // bite. With behavior: floating, Material 3 automatically
    // nudges any visible FAB up to make room AND clips the bar
    // to a margin so it doesn't span the full bottom edge.
    //
    // Margin leaves the bar inset from the screen edge so a
    // dismissed snackbar doesn't scrub past underlying buttons on
    // the swipe path. 16dp matches the FAB inset Material uses by
    // default.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      backgroundColor: colorScheme.inverseSurface,
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onInverseSurface,
      ),
      actionTextColor: colorScheme.inversePrimary,
      // Inset so the floating bar doesn't span the full width on
      // tablet — leaves room for the FAB on Today and any
      // permanent sidebar to remain tappable beside it.
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      elevation: 1,
    ),
  );
}
