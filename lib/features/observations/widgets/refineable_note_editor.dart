import 'dart:async';

import 'package:basecamp/config/env.dart';
import 'package:basecamp/features/observations/ai_refine.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:flutter/material.dart';

/// Note editor with an "AI refine" affordance. Tapping the sparkle
/// rewrites the note for clarity (drops filler, fixes grammar,
/// restructures confusing bits, keeps every fact). Instead of a
/// commit/cancel gate, the note area becomes a two-page carousel:
/// page 0 = Original (editable), page 1 = Refined (read-only). Whichever
/// page is on-screen is what the bound [controller] holds — so saving
/// the parent form saves the visible version. Tapping the sparkle again
/// regenerates the refined page from whatever the original now says.
///
/// Falls back to a plain field when the OpenAI key is missing — the
/// sparkle just isn't shown.
class RefineableNoteEditor extends StatefulWidget {
  const RefineableNoteEditor({
    required this.controller,
    this.label,
    this.maxLines = 6,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String? label;

  /// Soft cap for the editable Original page. Only used pre-refine; once
  /// in carousel mode pages grow to fit their content so teachers never
  /// have to scroll inside a card.
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  State<RefineableNoteEditor> createState() => _RefineableNoteEditorState();
}

class _RefineableNoteEditorState extends State<RefineableNoteEditor> {
  bool _loading = false;

  /// When both are non-null we're in carousel mode. [_originalSlide] is
  /// the source-of-truth for page 0 (kept in sync with the controller
  /// while page 0 is visible). [_refinedSlide] is the latest AI output.
  String? _originalSlide;
  String? _refinedSlide;

  /// 0 = Original (editable), 1 = Refined (read-only). Only meaningful
  /// in carousel mode.
  int _slide = 1;

  late final PageController _pageController =
      PageController(initialPage: _slide);

  bool get _inCarousel =>
      _originalSlide != null && _refinedSlide != null;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _refine() async {
    // Pull the freshest input: in carousel mode the current controller
    // text is the visible slide, which might be refined — but we want
    // to re-generate from the (possibly edited) original.
    final sourceText = _inCarousel
        ? (_slide == 0 ? widget.controller.text : _originalSlide!)
        : widget.controller.text;
    final trimmed = sourceText.trim();
    if (trimmed.isEmpty) return;

    setState(() => _loading = true);
    final result = await refineObservationText(trimmed);
    if (!mounted) return;
    if (result == null || result.trim().isEmpty) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't refine right now.")),
      );
      return;
    }
    final refined = result.trim();
    setState(() {
      _loading = false;
      _originalSlide = trimmed;
      _refinedSlide = refined;
      _slide = 1;
    });
    // Animate straight to the refined page so the teacher sees the
    // improvement first. Jump (no animation) if the controller wasn't
    // attached yet.
    if (_pageController.hasClients) {
      unawaited(
        _pageController.animateToPage(
          1,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      _pageController.jumpToPage(1);
    }
    _applySlideToController(refined);
  }

  void _onPageChanged(int index) {
    if (!_inCarousel || _slide == index) return;
    // Commit any keystrokes made on the Original page before leaving it.
    if (_slide == 0) {
      _originalSlide = widget.controller.text;
    }
    setState(() => _slide = index);
    _applySlideToController(
      index == 0 ? _originalSlide! : _refinedSlide!,
    );
  }

  void _applySlideToController(String text) {
    if (widget.controller.text == text) return;
    widget.controller.text = text;
    widget.controller.selection =
        TextSelection.collapsed(offset: text.length);
    widget.onChanged?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _inCarousel ? _buildCarousel(theme) : _buildPlain(theme),
    );
  }

  Widget _buildPlain(ThemeData theme) {
    return Stack(
      key: const ValueKey('plain'),
      children: [
        AppTextField(
          controller: widget.controller,
          label: widget.label,
          maxLines: widget.maxLines,
          onChanged: widget.onChanged,
        ),
        if (Env.hasOpenAi)
          Positioned(
            right: 6,
            bottom: 6,
            child: _RefineButton(
              loading: _loading,
              enabled: !_loading &&
                  widget.controller.text.trim().isNotEmpty,
              onTap: _refine,
            ),
          ),
      ],
    );
  }

  Widget _buildCarousel(ThemeData theme) {
    // Let pages size themselves to their text — we don't want scrolling
    // inside a card. PageView needs a bounded height, so we measure both
    // slides with a TextPainter and take the max.
    return Column(
      key: const ValueKey('carousel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Row(
            children: [
              Expanded(
                child: Text(widget.label!, style: theme.textTheme.titleSmall),
              ),
              Icon(
                Icons.auto_awesome,
                size: 13,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                _slide == 0 ? 'Original' : 'AI refined',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final height = _slideHeight(
              theme,
              constraints.maxWidth,
            );
            return SizedBox(
              height: height,
              child: Stack(
                children: [
                  PageView(
                    controller: _pageController,
                    onPageChanged: _onPageChanged,
                    children: [
                      _OriginalSlide(
                        controller: widget.controller,
                        onChanged: (v) {
                          _originalSlide = v;
                          widget.onChanged?.call(v);
                          // Rebuild for any slide-height recompute.
                          setState(() {});
                        },
                      ),
                      _RefinedSlide(text: _refinedSlide ?? ''),
                    ],
                  ),
                  if (Env.hasOpenAi)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: _RefineButton(
                        loading: _loading,
                        enabled: !_loading,
                        onTap: _refine,
                        tooltip: 'Regenerate refined version',
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        _Dots(
          count: 2,
          activeIndex: _slide,
          onTap: (i) {
            if (_pageController.hasClients) {
              unawaited(
                _pageController.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                ),
              );
            }
          },
        ),
      ],
    );
  }

  /// Height that fits whichever slide is taller, so neither ever scrolls
  /// internally. Includes the card padding we add in the slide widgets.
  double _slideHeight(ThemeData theme, double width) {
    // Account for the card padding we apply inside slides.
    const horizontalPadding = AppSpacing.md * 2;
    const verticalPadding = AppSpacing.md * 2;
    final style = theme.textTheme.bodyMedium?.copyWith(height: 1.4);
    final original = _originalSlide ?? widget.controller.text;
    final refined = _refinedSlide ?? '';

    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text.isEmpty ? ' ' : text, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width - horizontalPadding);
      return painter.size.height + verticalPadding;
    }

    // Floor at ~3 lines of text so short notes still look like a field.
    const minHeight = 96.0;
    final h = [measure(original), measure(refined)]
        .fold<double>(minHeight, (a, b) => a > b ? a : b);
    return h;
  }
}

class _OriginalSlide extends StatelessWidget {
  const _OriginalSlide({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        maxLines: null,
        minLines: 3,
        textCapitalization: TextCapitalization.sentences,
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
        decoration: const InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          isCollapsed: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

class _RefinedSlide extends StatelessWidget {
  const _RefinedSlide({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
        ),
      ),
    );
  }
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
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: i == activeIndex ? 20 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i == activeIndex
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RefineButton extends StatelessWidget {
  const _RefineButton({
    required this.loading,
    required this.enabled,
    required this.onTap,
    this.tooltip,
  });

  final bool loading;
  final bool enabled;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip ?? 'AI refine — clarify, trim filler',
      child: Material(
        color: enabled
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),
            child: loading
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: enabled
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
          ),
        ),
      ),
    );
  }
}
