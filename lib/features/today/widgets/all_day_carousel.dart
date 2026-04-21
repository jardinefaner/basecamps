import 'dart:async';

import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

/// Horizontally-paging carousel for the all-day banners at the top of
/// Today. When there's one all-day item, we just render its card; with
/// two or more we stack them into a single slot and auto-advance every
/// [autoplayInterval] so the teacher can see everything without the
/// banners eating a second (third, fourth…) card's worth of vertical
/// space.
///
/// Autoplay pauses the moment the teacher swipes manually — picking
/// back up feels intrusive, so once they've taken control the page
/// stays put until they swipe again.
class AllDayCarousel extends StatefulWidget {
  const AllDayCarousel({
    required this.cards,
    this.autoplayInterval = const Duration(seconds: 5),
    super.key,
  });

  /// One widget per page. Already-built ScheduleItemCards in the
  /// typical use; any stretch-width widget works.
  final List<Widget> cards;

  final Duration autoplayInterval;

  @override
  State<AllDayCarousel> createState() => _AllDayCarouselState();
}

class _AllDayCarouselState extends State<AllDayCarousel> {
  late final PageController _controller;
  Timer? _timer;
  int _index = 0;

  // Autoplay is "on until the teacher takes over". Once they drag or
  // explicitly tap a dot, we stop nudging them forward — otherwise the
  // carousel feels like it's fighting them.
  bool _autoplayActive = true;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    if (_shouldAutoplay) _scheduleTick();
  }

  bool get _shouldAutoplay =>
      _autoplayActive && widget.cards.length > 1;

  void _scheduleTick() {
    _timer?.cancel();
    _timer = Timer(widget.autoplayInterval, _tick);
  }

  void _tick() {
    if (!mounted || !_shouldAutoplay) return;
    final next = (_index + 1) % widget.cards.length;
    unawaited(
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void didUpdateWidget(AllDayCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the card list shrank past the current page, snap back. If it
    // grew from 1 to 2+, kick autoplay off.
    if (_index >= widget.cards.length && widget.cards.isNotEmpty) {
      _index = 0;
      _controller.jumpToPage(0);
    }
    if (oldWidget.cards.length != widget.cards.length) {
      if (_shouldAutoplay) {
        _scheduleTick();
      } else {
        _timer?.cancel();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onUserDrag() {
    if (_autoplayActive) {
      setState(() => _autoplayActive = false);
      _timer?.cancel();
    }
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
    // Stay alive: schedule the next auto-tick from THIS page. If the
    // teacher has taken over, _shouldAutoplay is false and we no-op.
    if (_shouldAutoplay) _scheduleTick();
  }

  void _onDotTap(int i) {
    _onUserDrag(); // tapping a dot also counts as taking over
    unawaited(
      _controller.animateToPage(
        i,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) return const SizedBox.shrink();
    if (widget.cards.length == 1) {
      // No carousel chrome for a single card — saves both vertical
      // space and the cognitive "what am I looking at?" on the common
      // single-event day.
      return widget.cards.first;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is UserScrollNotification &&
                n.direction != ScrollDirection.idle) {
              _onUserDrag();
            }
            return false;
          },
          child: SizedBox(
            // Banner cards on Today are "short, banner-like" — the
            // existing ScheduleItemCard for full-day items fits in
            // ~120 px. If a card has a concern strip attached it might
            // push a bit taller; the buffer here covers it.
            height: _estimatedHeight,
            child: PageView.builder(
              controller: _controller,
              onPageChanged: _onPageChanged,
              itemCount: widget.cards.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 2,
                ),
                child: widget.cards[i],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _Dots(
          count: widget.cards.length,
          activeIndex: _index,
          onTap: _onDotTap,
        ),
      ],
    );
  }

  // Simple fixed height — enough for the typical all-day banner (title
  // row + optional concern/attendance strip). Keeping the PageView
  // bounded is the only way to let it live inside the Today sliver
  // list without infinite-height errors.
  double get _estimatedHeight => 132;
}

class _Dots extends StatelessWidget {
  const _Dots({
    required this.count,
    required this.activeIndex,
    required this.onTap,
  });

  final int count;
  final int activeIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: i == activeIndex ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == activeIndex
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          if (i < count - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}
