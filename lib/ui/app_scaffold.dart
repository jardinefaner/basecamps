import 'package:basecamp/ui/animated_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    label: 'Kids',
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
  DateTime? _lastBackPress;

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

  /// Back-button handler at the app root. On Android, the system back
  /// button would otherwise exit the app instantly from the root tab —
  /// teachers reported accidentally doing this mid-capture. Now the first
  /// back press flashes a toast, and a second press within 2 seconds
  /// actually exits. iOS and web aren't affected.
  Future<void> _onPopInvoked(bool didPop, Object? _) async {
    if (didPop) return;
    final now = DateTime.now();
    final last = _lastBackPress;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      await SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  void _goToBranch(int shellIndex) {
    if (shellIndex < 0 || shellIndex > _lastBranchIndex) return;
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
        bottomNavigationBar: AnimatedNavBar(
          items: _navItems,
          selectedIndex: _navSelectedIndex,
          onSelected: _onNavTileSelected,
        ),
      ),
    );
  }
}
