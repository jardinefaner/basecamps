import 'dart:async';
import 'dart:math' as math;

import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

/// Small catalogue of per-tab selection animations. Each plays once
/// when its owning tab becomes the current tab, so the change feels
/// alive without becoming busy.
enum NavIconFlavor {
  /// Gentle 10° wiggle plus scale-pop — calendar/Today.
  wiggle,

  /// Vertical squeeze then expand — like an eye blinking.
  blink,

  /// Scale-pop with a light rotational head-bob — people/Children.
  bob,

  /// Pin-drop from above — map/Trips.
  drop,

  /// Three dots pulse outward — More.
  pulse,
}

/// Material-3-flavoured bottom nav built around a row of
/// [_AnimatedNavIcon] cells. Same shape as `NavigationBar` (icon,
/// label, selected indicator pill), but the selected icon plays a
/// bespoke micro-animation per tab and we own the layout so swipe
/// integration above it stays straightforward.
class AnimatedNavBar extends StatelessWidget {
  const AnimatedNavBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<AnimatedNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant,
              width: 0.5,
            ),
          ),
        ),
        child: SizedBox(
          height: 72,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavCell(
                    item: items[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class AnimatedNavItem {
  const AnimatedNavItem({
    required this.outlinedIcon,
    required this.filledIcon,
    required this.label,
    required this.flavor,
  });

  final IconData outlinedIcon;
  final IconData filledIcon;
  final String label;
  final NavIconFlavor flavor;
}

class _NavCell extends StatelessWidget {
  const _NavCell({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AnimatedNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      customBorder: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Indicator(
              selected: selected,
              child: _AnimatedNavIcon(
                flavor: item.flavor,
                outlinedIcon: item.outlinedIcon,
                filledIcon: item.filledIcon,
                selected: selected,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              style: theme.textTheme.labelSmall!.copyWith(
                color: selected
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
              ),
              child: Text(item.label),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rounded, tinted pill behind a selected icon (mirrors the M3
/// NavigationBar indicator). Animates width in on selection.
class _Indicator extends StatelessWidget {
  const _Indicator({required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: selected ? 56 : 40,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.secondaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

/// Renders one tab's icon and replays its flavour's animation every
/// time the tab transitions from unselected → selected.
class _AnimatedNavIcon extends StatefulWidget {
  const _AnimatedNavIcon({
    required this.flavor,
    required this.outlinedIcon,
    required this.filledIcon,
    required this.selected,
  });

  final NavIconFlavor flavor;
  final IconData outlinedIcon;
  final IconData filledIcon;
  final bool selected;

  @override
  State<_AnimatedNavIcon> createState() => _AnimatedNavIconState();
}

class _AnimatedNavIconState extends State<_AnimatedNavIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: _flavorDuration(widget.flavor),
  );

  @override
  void didUpdateWidget(covariant _AnimatedNavIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Play the animation once per un-selected → selected transition.
    if (widget.selected && !oldWidget.selected) {
      _ctrl.stop();
      unawaited(_ctrl.forward(from: 0));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.selected
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return _flavorBuilder(
          flavor: widget.flavor,
          t: _ctrl.value,
          selected: widget.selected,
          child: Icon(
            widget.selected ? widget.filledIcon : widget.outlinedIcon,
            color: color,
            size: 22,
          ),
        );
      },
    );
  }
}

Duration _flavorDuration(NavIconFlavor flavor) {
  switch (flavor) {
    case NavIconFlavor.wiggle:
      return const Duration(milliseconds: 420);
    case NavIconFlavor.blink:
      return const Duration(milliseconds: 240);
    case NavIconFlavor.bob:
      return const Duration(milliseconds: 320);
    case NavIconFlavor.drop:
      return const Duration(milliseconds: 360);
    case NavIconFlavor.pulse:
      return const Duration(milliseconds: 440);
  }
}

/// Maps the raw controller value [t] in `[0, 1]` to a per-flavour
/// transform wrapping [child]. Keeps every flavour's math in one
/// place so the builder above stays a thin switch.
Widget _flavorBuilder({
  required NavIconFlavor flavor,
  required double t,
  required bool selected,
  required Widget child,
}) {
  // A zero-duration "idle" sits at t=0; the controller only advances
  // on transition to selected, so unselected tabs render plain.
  if (!selected || t == 0) return child;

  switch (flavor) {
    case NavIconFlavor.wiggle:
      // Two small oscillations layered with a subtle scale pop.
      final angle = math.sin(t * math.pi * 3) * (1 - t) * 0.18;
      final scale = 1 + math.sin(t * math.pi) * 0.18;
      return Transform.rotate(
        angle: angle,
        child: Transform.scale(scale: scale, child: child),
      );

    case NavIconFlavor.blink:
      // Vertical squeeze → expand, like an eyelid. At t=0.5 the eye
      // is "closed" (scaleY≈0.25); it opens back to 1 by t=1.
      final squeeze = t < 0.5
          ? 1 - (t / 0.5) * 0.75
          : 0.25 + ((t - 0.5) / 0.5) * 0.75;
      return Transform(
        transform: Matrix4.identity()..scaleByDouble(1, squeeze, 1, 1),
        alignment: Alignment.center,
        child: child,
      );

    case NavIconFlavor.bob:
      // Scale-pop + head bobble. A touch of rotation so two people
      // icons feel a bit more animate than a plain scale.
      final scale = 1 + math.sin(t * math.pi) * 0.22;
      final tilt = math.sin(t * math.pi * 2) * (1 - t) * 0.12;
      return Transform.rotate(
        angle: tilt,
        child: Transform.scale(scale: scale, child: child),
      );

    case NavIconFlavor.drop:
      // Slide in from 8dp above with a bounce-ish settle, like a
      // pin dropping onto a map.
      final curved = Curves.easeOutBack.transform(t);
      final dy = -8 * (1 - curved);
      return Transform.translate(
        offset: Offset(0, dy),
        child: child,
      );

    case NavIconFlavor.pulse:
      // Two faint ripple rings expand out from behind the icon,
      // fading as they grow — fits the "more" (ellipsis) tab.
      return Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          _PulseRing(t: t, stagger: 0),
          _PulseRing(t: t, stagger: 0.2),
          child,
        ],
      );
  }
}

class _PulseRing extends StatelessWidget {
  const _PulseRing({required this.t, required this.stagger});

  final double t;
  final double stagger;

  @override
  Widget build(BuildContext context) {
    // Each ring lives in the [stagger, stagger + 0.8] sub-window.
    final local = ((t - stagger) / 0.8).clamp(0.0, 1.0);
    if (local == 0) return const SizedBox.shrink();
    final size = 18 + local * 22;
    final opacity = (1 - local).clamp(0.0, 1.0) * 0.4;
    final theme = Theme.of(context);
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: theme.colorScheme.onSecondaryContainer
                .withValues(alpha: opacity),
            width: 1.2,
          ),
        ),
      ),
    );
  }
}
