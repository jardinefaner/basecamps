import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Width (px) of the active right-side adaptive sheet, or null
/// when none is open. Surfaces from [showAdaptiveSheet]'s side-
/// panel branch so screens that want their content to **shift
/// left when the panel opens** (so the panel doesn't cover the
/// rightmost cards / list rows / whatever) can read this and
/// reserve right-edge padding.
///
/// Mobile (bottom-sheet path) doesn't touch this — the sheet
/// pushes from the bottom, not the right, so horizontal layout
/// doesn't need to reflow.
class AdaptiveSidePanelNotifier extends Notifier<double?> {
  @override
  double? build() => null;

  // Method-not-setter — opening a panel is a transient event with
  // a paired `close`, not a passive property write.
  // ignore: use_setters_to_change_properties
  void open(double width) {
    state = width;
  }

  void close() {
    state = null;
  }
}

final adaptiveSidePanelWidthProvider =
    NotifierProvider<AdaptiveSidePanelNotifier, double?>(
  AdaptiveSidePanelNotifier.new,
);

/// Adaptive sheet — bottom on phones, right side-panel on wide windows.
///
/// **Why both shapes:**
/// On a phone the bottom sheet is reachable with a thumb and the
/// rising motion matches a system pattern people already understand.
/// On a wide web/desktop window the same UI rendered as a bottom sheet
/// wastes vertical real estate and forces the user to dismiss before
/// they can see the surface they came from. A right-side slide-over
/// fits naturally next to the existing list/detail layout.
///
/// **Same widget body, two host shapes.** Callers don't change their
/// sheet contents — `builder` receives a normal [BuildContext] either
/// way. Both shapes:
///   * Honor `showDragHandle` (drag handle on the bottom sheet, drag-
///     to-dismiss disabled on the side panel — close button instead).
///   * Pass through `isScrollControlled` semantics: the side panel
///     always fills its column height; bottom sheet behavior matches
///     [showModalBottomSheet]'s flag.
///   * Return a `Future<T?>` that completes with whatever is passed
///     to [Navigator.pop], or null on barrier-tap dismissal.
///
/// **Threshold:** flips at `Breakpoint.expanded` (≥840 dp). Below that
/// the bottom sheet still feels right (phones in landscape, tablets
/// in portrait). Above, the side panel reclaims the right edge.
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool showDragHandle = true,
  Color? barrierColor,
  // Side-panel-only knobs. Ignored on the bottom-sheet code path —
  // a bottom sheet uses Material's defaults.
  double sidePanelWidth = 480,
  double sidePanelMaxWidthFraction = 0.45,
}) async {
  final isWide = Breakpoints.isWide(context);
  if (!isWide) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      barrierColor: barrierColor,
      builder: builder,
    );
  }
  // Resolve the same width the panel will paint at so the
  // notifier's value matches the visible panel pixel-for-pixel.
  final mq = MediaQuery.of(context);
  final resolvedWidth = (mq.size.width * sidePanelMaxWidthFraction)
      .clamp(320.0, sidePanelWidth);
  // Publish width via Riverpod so screens can shift their content
  // left under the panel. Cleared in `finally` regardless of how
  // the panel dismisses (Navigator.pop, barrier-tap, route swipe).
  final notifier = ProviderScope.containerOf(context)
      .read(adaptiveSidePanelWidthProvider.notifier)
    ..open(resolvedWidth);
  try {
    return await Navigator.of(context, rootNavigator: true).push<T>(
      _SidePanelRoute<T>(
        builder: builder,
        width: sidePanelWidth,
        maxWidthFraction: sidePanelMaxWidthFraction,
        barrierColor: barrierColor ??
            Theme.of(context).colorScheme.scrim.withValues(alpha: 0.32),
      ),
    );
  } finally {
    notifier.close();
  }
}

/// Right-anchored slide-over route. Borrows the modal-bottom-sheet
/// idea (full-height scrim, tap-out dismisses) and rotates it 90° so
/// the panel slides in from the right and pins to the right edge.
///
/// Picked over `showGeneralDialog` because we want a route on the
/// navigator stack — the system back gesture, the keyboard's escape,
/// and `Navigator.pop` from inside the panel all need to dismiss
/// cleanly, and a route handles all three for free.
class _SidePanelRoute<T> extends PopupRoute<T> {
  _SidePanelRoute({
    required this.builder,
    required this.width,
    required this.maxWidthFraction,
    required this.barrierColor,
  });

  final WidgetBuilder builder;
  final double width;
  final double maxWidthFraction;

  @override
  final Color barrierColor;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 240);

  @override
  Duration get reverseTransitionDuration =>
      const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    final resolvedWidth = (mq.size.width * maxWidthFraction)
        .clamp(320.0, width);
    return Align(
      alignment: Alignment.centerRight,
      child: SafeArea(
        // Bottom-only safe-area inset on the panel itself; the
        // top is intentionally edge-to-edge so the panel content
        // can paint under the status bar (mirroring how a normal
        // route looks).
        top: false,
        right: false,
        child: Material(
          color: theme.colorScheme.surface,
          // Hairline left border instead of a shadow — same visual
          // language as AppCard.
          shape: Border(
            left: BorderSide(
              color: theme.colorScheme.outlineVariant,
              width: 0.5,
            ),
          ),
          child: SizedBox(
            width: resolvedWidth,
            height: double.infinity,
            child: Builder(builder: builder),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
      ),
      child: child,
    );
  }
}

/// Standard close affordance for content rendered through
/// [showAdaptiveSheet]. The bottom-sheet code path already shows a
/// drag handle, so this is mostly for the side-panel host where
/// drag-to-dismiss isn't natural — but rendering it on both keeps
/// the sheet body identical regardless of host shape.
///
/// Place this at the top of your sheet's column. It's a small
/// horizontal row with an `X` button on the right + an optional
/// title on the left.
class AdaptiveSheetHeader extends StatelessWidget {
  const AdaptiveSheetHeader({
    this.title,
    this.actions = const [],
    super.key,
  });

  final String? title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          if (title != null)
            Expanded(
              child: Text(
                title!,
                style: theme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),
          ...actions,
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
