import 'package:flutter/widgets.dart';

/// Width-based breakpoint enum. Ordered so that `.index` comparisons
/// (`>=`, `<=`) mean "at least as wide" / "no wider than".
enum Breakpoint { compact, medium, expanded, large }

/// Simple width-based breakpoints used across list and detail screens.
///
/// The thresholds roughly follow Material 3's window-size classes:
///   - compact  : < 600   (phone portrait)
///   - medium   : 600-840 (phone landscape / small tablet portrait)
///   - expanded : 840-1200 (tablet landscape / small desktop)
///   - large    : >= 1200 (desktop / wide window)
class Breakpoints {
  const Breakpoints._();

  static const double medium = 600;
  static const double expanded = 840;
  static const double large = 1200;

  /// Resolve the current [Breakpoint] from the nearest [MediaQuery].
  static Breakpoint of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < medium) return Breakpoint.compact;
    if (width < expanded) return Breakpoint.medium;
    if (width < large) return Breakpoint.expanded;
    return Breakpoint.large;
  }

  /// True when we're at `expanded` or wider — the point at which a list
  /// screen should switch from a single column to a grid.
  static bool isWide(BuildContext context) =>
      of(context).index >= Breakpoint.expanded.index;

  /// Width threshold (in dp) at which the app paints a permanent
  /// launcher sidebar instead of the slide-in Drawer. Slightly wider
  /// than `expanded` so a 320dp sidebar plus a 580dp content column
  /// fits cleanly. Routes that own a Scaffold should suppress their
  /// own Drawer + hamburger button at or above this threshold —
  /// otherwise the menu sits redundantly next to a sidebar already
  /// showing the same content.
  static const double sidebarThreshold = 900;

  /// True when the responsive shell is painting a permanent sidebar.
  /// Routes use this to drop their own Drawer + leading menu button
  /// on the same breakpoint.
  static bool hasPersistentSidebar(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= sidebarThreshold;

  /// Default column count for grid-style list screens. Individual screens
  /// may pick a different ramp — see call sites for overrides.
  ///
  ///   compact  -> 1
  ///   medium   -> 1
  ///   expanded -> 2
  ///   large    -> 3
  static int columnsFor(BuildContext context) {
    switch (of(context)) {
      case Breakpoint.compact:
      case Breakpoint.medium:
        return 1;
      case Breakpoint.expanded:
        return 2;
      case Breakpoint.large:
        return 3;
    }
  }
}

/// Rebuilds when the window crosses a breakpoint. Thin sugar over
/// [LayoutBuilder] so callers can write `BreakpointBuilder(builder: (c, bp) {...})`
/// instead of re-resolving the breakpoint every time.
class BreakpointBuilder extends StatelessWidget {
  const BreakpointBuilder({required this.builder, super.key});

  final Widget Function(BuildContext context, Breakpoint breakpoint) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, _) => builder(context, Breakpoints.of(context)),
    );
  }
}
