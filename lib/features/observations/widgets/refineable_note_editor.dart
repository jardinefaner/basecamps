import 'dart:async';

import 'package:basecamp/config/env.dart';
import 'package:basecamp/features/observations/ai_refine.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:flutter/material.dart';

/// Note editor with an "AI refine" affordance. Tapping the sparkle
/// rewrites the note for clarity (drops filler, fixes grammar,
/// restructures confusing bits, keeps every fact). The field then
/// becomes a two-page carousel: page 0 is the editable Original, page 1
/// is the read-only Refined. Whichever page is on-screen is what the
/// bound [controller] holds, so saving the parent form saves the
/// visible version.
///
/// The sparkle lives on the Original slide only — the Refined slide is
/// the AI output, so there's nothing to "refine" from that side.
///
/// ### Non-destructive saving
/// When the teacher saves with the Refined slide active, the Original
/// text isn't lost: [onPreservedOriginalChanged] fires with the Original
/// snapshot (the parent persists this as `note_original` in the DB).
/// Opening the same observation later — with [initialOriginal] passed
/// in — restores the carousel on the Refined slide, with a way to flip
/// back to Original or re-refine.
///
/// Falls back to a plain field when the OpenAI key is missing.
class RefineableNoteEditor extends StatefulWidget {
  const RefineableNoteEditor({
    required this.controller,
    this.label,
    this.maxLines = 6,
    this.onChanged,
    this.initialOriginal,
    this.onPreservedOriginalChanged,
    super.key,
  });

  /// Parent-owned controller. Its text always mirrors whichever slide is
  /// visible — so the parent's `.text` at save time is what to store as
  /// the "active" note.
  final TextEditingController controller;
  final String? label;

  /// Soft cap for the editable field while not in carousel mode.
  final int maxLines;

  /// Called whenever the visible slide's text changes (user edits,
  /// swipes between slides, or a refine completes).
  final ValueChanged<String>? onChanged;

  /// When non-null, the widget opens directly in carousel mode with
  /// this as the Original slide and the parent controller's current text
  /// as the Refined slide. Use this to restore a previously-saved refine
  /// state.
  final String? initialOriginal;

  /// Fires when the "what to save as pre-refine text" value changes.
  ///
  /// * `null` — either not in carousel, or the Original slide is active
  ///   (meaning the teacher is reverting to the original; drop the
  ///   preserved copy).
  /// * `String` — the Original slide's current text, to persist as the
  ///   pre-refine snapshot when the parent saves.
  final ValueChanged<String?>? onPreservedOriginalChanged;

  @override
  State<RefineableNoteEditor> createState() => _RefineableNoteEditorState();
}

class _RefineableNoteEditorState extends State<RefineableNoteEditor> {
  /// Internal controller for the Original slide's TextField — independent
  /// of the parent controller so the PageView can keep the Original
  /// slide mounted without its contents being overwritten when we swipe
  /// to Refined (where we set the parent's text to the refined text).
  late final TextEditingController _originalController;

  /// Latest AI-refined text. Non-empty only while in carousel mode.
  String _refinedText = '';

  /// True once we're showing the two-page carousel.
  bool _inCarousel = false;

  /// 0 = Original (editable), 1 = Refined (read-only).
  int _slide = 1;

  late final PageController _pageController;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialOriginal;
    if (initial != null && initial.isNotEmpty) {
      // Restore a previously-saved refine: Original from the DB,
      // Refined = whatever's in the parent controller (the in-use note).
      _inCarousel = true;
      _originalController = TextEditingController(text: initial);
      _refinedText = widget.controller.text;
      _slide = 1;
    } else {
      _originalController = TextEditingController();
    }
    _pageController = PageController(initialPage: _slide);
  }

  @override
  void dispose() {
    _originalController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // -- Refine --

  Future<void> _refine() async {
    // Always refine from the Original text — if we're already in carousel
    // mode and the user edited Original, use that; otherwise use the
    // parent controller (which is the only text in plain mode).
    final sourceText =
        _inCarousel ? _originalController.text : widget.controller.text;
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
      _inCarousel = true;
      _refinedText = refined;
      _slide = 1;
    });
    // Seed the Original controller if we weren't in carousel yet — the
    // Original slide needs its own copy to survive slide swaps.
    if (_originalController.text != trimmed) {
      _originalController.text = trimmed;
    }
    _applyParentController(refined);
    // Animate to Refined only if the PageView is already attached;
    // otherwise the freshly-built PageView honors initialPage.
    if (_pageController.hasClients) {
      unawaited(
        _pageController.animateToPage(
          1,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        ),
      );
    }
    _emitSnapshot();
  }

  // -- Slide mechanics --

  void _onPageChanged(int index) {
    if (_slide == index) return;
    setState(() => _slide = index);
    _applyParentController(
      index == 0 ? _originalController.text : _refinedText,
    );
    _emitSnapshot();
  }

  void _onOriginalChanged(String value) {
    // Mirror edits on the Original slide to the parent controller so
    // "save changes" sees the latest text when Original is active.
    if (_slide == 0) {
      _applyParentController(value);
    }
    // Height / snapshot may both change as the Original grows.
    setState(() {});
    _emitSnapshot();
  }

  void _applyParentController(String text) {
    if (widget.controller.text == text) return;
    widget.controller.text = text;
    widget.controller.selection =
        TextSelection.collapsed(offset: text.length);
    widget.onChanged?.call(text);
  }

  /// Tell the parent what to persist as `note_original` on save.
  void _emitSnapshot() {
    final cb = widget.onPreservedOriginalChanged;
    if (cb == null) return;
    if (!_inCarousel || _slide == 0) {
      cb(null);
    } else {
      cb(_originalController.text);
    }
  }

  // -- Build --

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
            final height = _slideHeight(theme, constraints.maxWidth);
            return SizedBox(
              height: height,
              child: PageView(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                children: [
                  _OriginalSlide(
                    controller: _originalController,
                    onChanged: _onOriginalChanged,
                    sparkle: Env.hasOpenAi
                        ? _RefineButton(
                            loading: _loading,
                            enabled: !_loading &&
                                _originalController.text.trim().isNotEmpty,
                            onTap: _refine,
                            tooltip: 'Regenerate refined version',
                          )
                        : null,
                  ),
                  _RefinedSlide(text: _refinedText),
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

  /// Height that fits whichever slide has more text — so nothing scrolls
  /// inside a card. Min floor so short notes still look like a field.
  double _slideHeight(ThemeData theme, double width) {
    const horizontalPadding = AppSpacing.md * 2;
    const verticalPadding = AppSpacing.md * 2;
    final style = theme.textTheme.bodyMedium?.copyWith(height: 1.4);
    final original = _originalController.text;
    final refined = _refinedText;

    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text.isEmpty ? ' ' : text, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width - horizontalPadding);
      return painter.size.height + verticalPadding;
    }

    const minHeight = 96.0;
    return [measure(original), measure(refined)]
        .fold<double>(minHeight, (a, b) => a > b ? a : b);
  }
}

class _OriginalSlide extends StatelessWidget {
  const _OriginalSlide({
    required this.controller,
    required this.onChanged,
    this.sparkle,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final Widget? sparkle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        Container(
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
        ),
        if (sparkle != null)
          Positioned(right: 6, bottom: 6, child: sparkle!),
      ],
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
