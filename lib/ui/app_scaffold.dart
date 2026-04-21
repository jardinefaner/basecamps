import 'package:basecamp/ui/animated_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shell branch indexing. The launcher sits at index 0 (no nav tile);
/// the five regular tabs occupy indices 1..5 so the bottom nav shows
/// them in order. Reserving a named constant keeps the ordering
/// self-documenting even though only the first-tab index is read.
const int _firstTabBranchIndex = 1;

const _navItems = <AnimatedNavItem>[
  AnimatedNavItem(
    outlinedIcon: Icons.today_outlined,
    filledIcon: Icons.today,
    label: 'Today',
    flavor: NavIconFlavor.wiggle,
  ),
  AnimatedNavItem(
    outlinedIcon: Icons.visibility_outlined,
    filledIcon: Icons.visibility,
    label: 'Observe',
    flavor: NavIconFlavor.blink,
  ),
  AnimatedNavItem(
    outlinedIcon: Icons.people_outline,
    filledIcon: Icons.people,
    label: 'Children',
    flavor: NavIconFlavor.bob,
  ),
  AnimatedNavItem(
    outlinedIcon: Icons.map_outlined,
    filledIcon: Icons.map,
    label: 'Trips',
    flavor: NavIconFlavor.drop,
  ),
  AnimatedNavItem(
    outlinedIcon: Icons.more_horiz,
    filledIcon: Icons.more_horiz,
    label: 'More',
    flavor: NavIconFlavor.pulse,
  ),
];

class AppScaffold extends StatefulWidget {
  const AppScaffold({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  int get _lastBranchIndex => _firstTabBranchIndex + _navItems.length - 1;

  /// Nav-bar selection derived from the current shell branch. Returns
  /// -1 when the launcher branch is active, which [AnimatedNavBar]
  /// interprets as "no tile selected" so the indicator pill fades off
  /// every tile while the launcher is on screen.
  int get _navSelectedIndex {
    final shellIndex = widget.navigationShell.currentIndex;
    if (shellIndex < _firstTabBranchIndex) return -1;
    return shellIndex - _firstTabBranchIndex;
  }

  /// Back-button / edge-swipe handler at the app root. Every handled
  /// pop on the root becomes a no-op — teachers were accidentally
  /// exiting mid-capture. The system gesture (Android edge swipe,
  /// Android back button) is absorbed silently; to leave the app the
  /// user goes through the home button / app switcher. iOS's
  /// interactive pop gesture never triggers this path at the root,
  /// so it's unaffected.
  void _onPopInvoked(bool didPop, Object? _) {
    // No-op on purpose. PopScope(canPop: false) already blocks the
    // pop — we just don't offer any escape hatch here. The moment
    // we start routing the back gesture somewhere (e.g. double-tap
    // to exit) teachers hit it accidentally.
  }

  void _goToBranch(int shellIndex) {
    if (shellIndex < 0 || shellIndex > _lastBranchIndex) return;
    // Drop any active input focus (and thus the keyboard) before we
    // swap branches. Branch switches are NOT push/pop events on the
    // outer navigator, so the router-level UnfocusOnTransition
    // observer doesn't fire — without this, typing on Observe and
    // swiping to Today left the keyboard up, and the next keystroke
    // landed in a hidden text field on the previous tab.
    FocusManager.instance.primaryFocus?.unfocus();
    widget.navigationShell.goBranch(
      shellIndex,
      initialLocation: shellIndex == widget.navigationShell.currentIndex,
    );
  }

  /// Nav-bar tile index → shell branch index.
  void _onNavTileSelected(int navIndex) {
    _goToBranch(navIndex + _firstTabBranchIndex);
  }

  @override
  Widget build(BuildContext context) {
    final currentShellIndex = widget.navigationShell.currentIndex;
    // Launcher is a full-surface mode — no bottom nav, so it reads
    // as "different plane" from the regular tabs. Swipe still works
    // to return to Today.
    final onLauncher = currentShellIndex < _firstTabBranchIndex;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        // Horizontal fling on the page body walks through branches.
        // Thresholds are deliberately high so an accidental slow drag
        // across a card won't change tabs — and child horizontal
        // scrollables (week grid, attachment strips, etc.) still win
        // the gesture arena when they're the one being dragged, so we
        // only catch the "no one else is using this gesture" case.
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
        bottomNavigationBar: onLauncher
            ? null
            : AnimatedNavBar(
                items: _navItems,
                selectedIndex: _navSelectedIndex,
                onSelected: _onNavTileSelected,
              ),
      ),
    );
  }
}
