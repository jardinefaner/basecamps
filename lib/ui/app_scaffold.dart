import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shell wrapper around the two surviving branches: `/launcher` (index
/// 0) and `/today` (index 1). The bottom nav is gone — the launcher is
/// now the sole hub, reached via the hamburger in Today's app bar. A
/// horizontal fling still swaps between the two branches so the old
/// swipe-from-launcher-to-today muscle memory keeps working.
class AppScaffold extends StatefulWidget {
  const AppScaffold({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  /// Back-button / edge-swipe handler at the app root. Every handled
  /// pop on the root becomes a no-op — teachers were accidentally
  /// exiting mid-capture. The system gesture (Android edge swipe,
  /// Android back button) is absorbed silently; to leave the app the
  /// user goes through the home button / app switcher. iOS's
  /// interactive pop gesture never triggers this path at the root,
  /// so it's unaffected.
  void _onPopInvoked(bool didPop, Object? _) {
    // No-op on purpose. PopScope(canPop: false) already blocks the
    // pop — we just don't offer any escape hatch here.
  }

  void _goToBranch(int shellIndex) {
    if (shellIndex < 0 || shellIndex > 1) return;
    // Drop any active input focus (and thus the keyboard) before we
    // swap branches. Branch switches are NOT push/pop events on the
    // outer navigator, so the router-level UnfocusOnTransition
    // observer doesn't fire — without this, typing on one branch and
    // swiping to the other left the keyboard up, and the next
    // keystroke landed in a hidden text field on the previous tab.
    FocusManager.instance.primaryFocus?.unfocus();
    widget.navigationShell.goBranch(
      shellIndex,
      initialLocation: shellIndex == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentShellIndex = widget.navigationShell.currentIndex;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        // Horizontal fling on the page body walks between the two
        // surviving branches. Thresholds are deliberately high so an
        // accidental slow drag across a card won't change tabs — and
        // child horizontal scrollables (week grid, attachment strips,
        // etc.) still win the gesture arena when they're the one
        // being dragged, so we only catch the "no one else is using
        // this gesture" case.
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity < -500) {
              _goToBranch(currentShellIndex + 1);
            } else if (velocity > 500) {
              _goToBranch(currentShellIndex - 1);
            }
          },
          child: widget.navigationShell,
        ),
      ),
    );
  }
}
