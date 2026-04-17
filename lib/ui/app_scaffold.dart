import 'package:basecamp/ui/animated_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

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

  void _goToBranch(int index) {
    if (index < 0 || index >= _navItems.length) return;
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = widget.navigationShell.currentIndex;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        // Horizontal fling on the page body walks through tabs left
        // and right. Velocity threshold is deliberately high so an
        // accidental slow drag across a card won't change tabs — a
        // child horizontal scroll (e.g. the week grid) also wins the
        // gesture arena when it's the one being actively dragged, so
        // we only catch the "no one else is using this gesture" case.
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity < -500) {
              _goToBranch(currentIndex + 1);
            } else if (velocity > 500) {
              _goToBranch(currentIndex - 1);
            }
          },
          child: widget.navigationShell,
        ),
        bottomNavigationBar: AnimatedNavBar(
          items: _navItems,
          selectedIndex: currentIndex,
          onSelected: _goToBranch,
        ),
      ),
    );
  }
}
