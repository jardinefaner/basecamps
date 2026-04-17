import 'package:basecamp/config/env.dart';
import 'package:basecamp/features/observations/ai_refine.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:flutter/material.dart';

/// Note editor with an "AI refine" affordance. Tapping the sparkle sends
/// the current text to gpt-4o-mini for a light polish (same words, just
/// cleaner punctuation + line breaks), then flips the field into a
/// two-slide compare: Original vs. AI refined. The teacher picks which
/// one to keep.
///
/// Falls back to a plain text field when the OpenAI key is missing — the
/// sparkle just isn't shown. Errors during refine surface as a SnackBar;
/// the original text is never touched unless the teacher taps "Use refined".
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
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  State<RefineableNoteEditor> createState() => _RefineableNoteEditorState();
}

class _RefineableNoteEditorState extends State<RefineableNoteEditor> {
  bool _loading = false;

  /// When non-null, the editor is in compare mode and [_refined] is the
  /// AI suggestion. Picking "Use refined" copies it into the controller;
  /// "Cancel" drops it.
  String? _refined;

  /// Snapshot of the text we sent to the model — this is "Original" on
  /// the left slide. Lets us compare against mid-refine edits, and is
  /// what we show the teacher.
  String? _original;

  /// 0 = Original, 1 = AI refined. Drives both the SegmentedButton and
  /// the AnimatedSwitcher underneath.
  int _slideIndex = 1;

  Future<void> _refine() async {
    final text = widget.controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _loading = true);
    final result = await refineObservationText(text);
    if (!mounted) return;
    if (result == null || result.trim().isEmpty) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't refine right now.")),
      );
      return;
    }
    // If the model returned something identical to what we sent, there's
    // nothing to compare — just let the teacher know.
    if (result.trim() == text) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already clean — no changes.')),
      );
      return;
    }
    setState(() {
      _loading = false;
      _original = text;
      _refined = result.trim();
      _slideIndex = 1;
    });
  }

  void _useRefined() {
    final refined = _refined;
    if (refined == null) return;
    widget.controller.text = refined;
    widget.controller.selection =
        TextSelection.collapsed(offset: refined.length);
    widget.onChanged?.call(refined);
    setState(() {
      _refined = null;
      _original = null;
    });
  }

  void _cancelCompare() {
    setState(() {
      _refined = null;
      _original = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inCompare = _refined != null;

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: inCompare ? _buildCompare(theme) : _buildEditor(theme),
    );
  }

  Widget _buildEditor(ThemeData theme) {
    return Column(
      key: const ValueKey('editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
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
        ),
      ],
    );
  }

  Widget _buildCompare(ThemeData theme) {
    final original = _original ?? '';
    final refined = _refined ?? '';
    return Column(
      key: const ValueKey('compare'),
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
                size: 14,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Refined',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Center(
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                label: Text('Original'),
                icon: Icon(Icons.edit_note_outlined),
              ),
              ButtonSegment(
                value: 1,
                label: Text('AI refined'),
                icon: Icon(Icons.auto_awesome),
              ),
            ],
            selected: {_slideIndex},
            onSelectionChanged: (s) =>
                setState(() => _slideIndex = s.first),
            showSelectedIcon: false,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            // Left/right slide matching the SegmentedButton direction.
            final goingRight = child.key == const ValueKey('slide-1');
            final offset = Tween<Offset>(
              begin: Offset(goingRight ? 0.08 : -0.08, 0),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: offset, child: child),
            );
          },
          child: _ComparePanel(
            key: ValueKey('slide-$_slideIndex'),
            text: _slideIndex == 0 ? original : refined,
            isRefined: _slideIndex == 1,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: AppButton.secondary(
                onPressed: _cancelCompare,
                label: 'Keep original',
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppButton.primary(
                onPressed: _useRefined,
                label: 'Use refined',
              ),
            ),
          ],
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
  });

  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'AI refine — keep your words, polish formatting',
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

class _ComparePanel extends StatelessWidget {
  const _ComparePanel({
    required this.text,
    required this.isRefined,
    super.key,
  });

  final String text;
  final bool isRefined;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = Border.all(
      color: isRefined
          ? theme.colorScheme.primary.withValues(alpha: 0.4)
          : theme.colorScheme.outlineVariant,
      width: isRefined ? 1.2 : 1,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isRefined
            ? theme.colorScheme.primary.withValues(alpha: 0.06)
            : theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: border,
      ),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
      ),
    );
  }
}
