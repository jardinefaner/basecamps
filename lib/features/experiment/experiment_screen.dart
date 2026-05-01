import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/adaptive_sheet.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';

/// Sandbox surface for trying things out before they earn a real home.
///
/// Current experiment: **inline-edit activity card.** The FAB drops a
/// preformatted card onto the canvas with three placeholder labels —
/// **Activity Name** (bold), Describe, and Reference Link (styled like
/// a hyperlink). Each label is tap-to-edit in place: the placeholder
/// disappears, a TextField takes over with the same style, the user
/// types, and on blur/enter the field commits back to a Text. No
/// page-by-page form, no save button — the card *is* the form.
///
/// Double-tap the card to open the advanced editor in an adaptive
/// sheet (bottom on phones, side panel on web). That surface gives
/// the same three fields more room to breathe — labels, multi-line
/// description, link validation — without making the inline path
/// feel like a watered-down version.
///
/// Title is the only required field; the other two are optional.
/// Drafts live in memory only — this screen has no persistence.
/// When this experiment graduates, lift it into its own feature
/// directory and wire it to the activity-library repo.
class ExperimentScreen extends StatefulWidget {
  const ExperimentScreen({super.key});

  @override
  State<ExperimentScreen> createState() => _ExperimentScreenState();
}

class _ExperimentScreenState extends State<ExperimentScreen> {
  // In-memory only — this is a sandbox, not a feature. When the
  // pattern graduates we'll back it with the activity-library repo;
  // until then drafts just live for the lifetime of the screen.
  final List<_ActivityDraft> _drafts = [];

  void _addDraft() {
    setState(() {
      _drafts.add(_ActivityDraft());
    });
  }

  Future<void> _openAdvanced(_ActivityDraft draft) async {
    await showAdaptiveSheet<void>(
      context: context,
      builder: (_) => _AdvancedActivityEditor(
        draft: draft,
        // Bubble the changes back as a setState so the underlying
        // card re-renders with whatever the sheet edited. No save
        // button on the sheet either — close is commit.
        onChanged: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Experiment')),
      body: _drafts.isEmpty
          // Empty state intentionally barren — the FAB is the only
          // affordance on a blank canvas. Once the user taps it, the
          // first card slides in and the canvas takes over.
          ? const SizedBox.expand()
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: _drafts.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _ActivityDraftCard(
                  // ValueKey on the draft instance so reordering
                  // (future) doesn't recycle inline-edit state across
                  // cards.
                  key: ValueKey(_drafts[i]),
                  draft: _drafts[i],
                  onChanged: () => setState(() {}),
                  onAdvancedEdit: () => _openAdvanced(_drafts[i]),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addDraft,
        tooltip: 'New activity',
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Mutable draft model for an experimental activity card. Plain class,
/// not a `@freezed` record, because the inline-edit UX writes back
/// field-by-field and `copyWith` per keystroke would be churn.
class _ActivityDraft {
  String title = '';
  String description = '';
  String link = '';
}

/// Preformatted card with three inline-editable fields:
///   * **Activity Name** — bold, primary line. Required (the user is
///     expected to fill this; we don't enforce it on the inline path
///     since the only way to "commit" is the card existing — but the
///     advanced editor labels it as required).
///   * Describe — body text, one or two lines.
///   * Reference Link — primary-tinted + underlined so it reads as a
///     URL even before any text is entered.
///
/// Single-tap a field → the field becomes a TextField at the same
/// style, autofocused, ready to type. Blur or enter commits.
///
/// Double-tap anywhere on the card → opens the advanced editor in an
/// adaptive sheet. The two gestures coexist via Flutter's gesture
/// arena: the field's onTap is delayed by the double-tap timeout when
/// a parent onDoubleTap is registered, which is the standard cost of
/// nesting these — acceptable here because the double-tap path is the
/// power-user shortcut, not the primary flow.
class _ActivityDraftCard extends StatelessWidget {
  const _ActivityDraftCard({
    required this.draft,
    required this.onChanged,
    required this.onAdvancedEdit,
    super.key,
  });

  final _ActivityDraft draft;
  final VoidCallback onChanged;
  final VoidCallback onAdvancedEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final titleStyle = (theme.textTheme.titleMedium ?? const TextStyle())
        .copyWith(fontWeight: FontWeight.w700);
    final bodyStyle = theme.textTheme.bodyMedium ?? const TextStyle();
    final linkStyle = bodyStyle.copyWith(
      color: cs.primary,
      decoration: TextDecoration.underline,
      decorationColor: cs.primary,
    );

    // Placeholders share the field's style but with the muted
    // `onSurfaceVariant` color so they read as "tap to fill" rather
    // than committed text. Same rule for the link placeholder — keep
    // the underline so the affordance is recognisable even empty.
    final placeholderTitleStyle = titleStyle.copyWith(
      color: cs.onSurfaceVariant.withValues(alpha: 0.55),
    );
    final placeholderBodyStyle = bodyStyle.copyWith(
      color: cs.onSurfaceVariant.withValues(alpha: 0.55),
    );
    final placeholderLinkStyle = linkStyle.copyWith(
      color: cs.onSurfaceVariant.withValues(alpha: 0.55),
      decorationColor: cs.onSurfaceVariant.withValues(alpha: 0.55),
    );

    return GestureDetector(
      // Double-tap target covers the whole card — the user shouldn't
      // have to aim for a button to graduate to advanced edit.
      onDoubleTap: onAdvancedEdit,
      // Opaque so the gesture detector receives taps even on empty
      // padding between fields (otherwise the AppCard's transparent
      // gaps swallow them).
      behavior: HitTestBehavior.opaque,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _InlineEditableText(
              value: draft.title,
              placeholder: 'Activity Name',
              style: titleStyle,
              placeholderStyle: placeholderTitleStyle,
              onChanged: (v) {
                draft.title = v;
                onChanged();
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            _InlineEditableText(
              value: draft.description,
              placeholder: 'Describe',
              style: bodyStyle,
              placeholderStyle: placeholderBodyStyle,
              maxLines: 3,
              onChanged: (v) {
                draft.description = v;
                onChanged();
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            _InlineEditableText(
              value: draft.link,
              placeholder: 'Reference Link',
              style: linkStyle,
              placeholderStyle: placeholderLinkStyle,
              keyboardType: TextInputType.url,
              onChanged: (v) {
                draft.link = v;
                onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Single inline-editable text field. Renders as a styled [Text] with
/// the placeholder when not editing; tap swaps in a [TextField] with
/// the same visual style so there's zero layout shift between read
/// and edit modes. Blur or `onSubmitted` commits and swaps back.
///
/// Why not always a TextField? Two reasons:
///   1. A TextField always paints a cursor when focused and renders
///      hint text in a different (typically lighter) style — the read
///      state would never quite match a Text widget rendered with the
///      same `style`.
///   2. The double-tap-to-open-advanced gesture on the parent card
///      conflicts with a TextField's own gesture handling; switching
///      to Text in the read state lets the parent's onDoubleTap fire
///      cleanly when the user isn't actively editing.
class _InlineEditableText extends StatefulWidget {
  const _InlineEditableText({
    required this.value,
    required this.placeholder,
    required this.style,
    required this.placeholderStyle,
    required this.onChanged,
    this.maxLines = 1,
    this.keyboardType,
  });

  final String value;
  final String placeholder;
  final TextStyle style;
  final TextStyle placeholderStyle;
  final ValueChanged<String> onChanged;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  State<_InlineEditableText> createState() => _InlineEditableTextState();
}

class _InlineEditableTextState extends State<_InlineEditableText> {
  bool _editing = false;
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
    _focus = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _InlineEditableText old) {
    super.didUpdateWidget(old);
    // Sync the controller when the parent's value changes from
    // outside (e.g. the advanced editor sheet wrote back) and we're
    // not currently editing — otherwise the user's in-progress edit
    // would get overwritten.
    if (!_editing && widget.value != _ctrl.text) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocusChange)
      ..dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    // Blur = commit. Covers tapping elsewhere on the card, tapping
    // another field, swiping to dismiss the keyboard, the user
    // double-tapping into the advanced editor, etc.
    if (!_focus.hasFocus && _editing) _commit();
  }

  void _startEdit() {
    if (_editing) return;
    setState(() {
      _editing = true;
      _ctrl.text = widget.value;
    });
    // Focus on the next frame so the TextField has been built and
    // can actually take focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _commit() {
    if (!_editing) return;
    setState(() => _editing = false);
    widget.onChanged(_ctrl.text);
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return TextField(
        controller: _ctrl,
        focusNode: _focus,
        style: widget.style,
        maxLines: widget.maxLines,
        keyboardType: widget.keyboardType,
        textInputAction: widget.maxLines == 1
            ? TextInputAction.done
            : TextInputAction.newline,
        // Collapsed decoration removes the default underline + extra
        // padding so the TextField occupies the same vertical space
        // as the Text it replaces — no jumpiness when toggling.
        decoration: const InputDecoration.collapsed(hintText: ''),
        onSubmitted: widget.maxLines == 1 ? (_) => _commit() : null,
      );
    }
    final isEmpty = widget.value.isEmpty;
    return GestureDetector(
      // Opaque so taps on the line (including the empty space to the
      // right of short text) all enter edit mode.
      behavior: HitTestBehavior.opaque,
      onTap: _startEdit,
      child: Text(
        isEmpty ? widget.placeholder : widget.value,
        style: isEmpty ? widget.placeholderStyle : widget.style,
        maxLines: widget.maxLines,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Bottom-sheet (or side-panel on web) advanced editor. Same three
/// fields as the inline card but rendered with full text-field
/// chrome — labels, multi-line description, helper text — for users
/// who want a more deliberate authoring experience than tap-to-edit.
///
/// Mirrors writes back through [onChanged] on every keystroke, so
/// the underlying card stays in sync as the user types. No save
/// button — close is commit (matching the inline path).
class _AdvancedActivityEditor extends StatefulWidget {
  const _AdvancedActivityEditor({
    required this.draft,
    required this.onChanged,
  });

  final _ActivityDraft draft;
  final VoidCallback onChanged;

  @override
  State<_AdvancedActivityEditor> createState() =>
      _AdvancedActivityEditorState();
}

class _AdvancedActivityEditorState extends State<_AdvancedActivityEditor> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _link;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.draft.title)
      ..addListener(_pushTitle);
    _description = TextEditingController(text: widget.draft.description)
      ..addListener(_pushDescription);
    _link = TextEditingController(text: widget.draft.link)
      ..addListener(_pushLink);
  }

  // Field-specific listeners (rather than one shared one) so we don't
  // write three values per keystroke — only the field that changed.
  void _pushTitle() {
    widget.draft.title = _title.text;
    widget.onChanged();
  }

  void _pushDescription() {
    widget.draft.description = _description.text;
    widget.onChanged();
  }

  void _pushLink() {
    widget.draft.link = _link.text;
    widget.onChanged();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return SafeArea(
      // Top inset off — the sheet host (bottom-sheet drag handle on
      // mobile, side-panel header on web) already positions content
      // below the system chrome.
      top: false,
      child: Padding(
        // Bottom-edge inset for the keyboard so the focused field
        // never disappears under it on mobile.
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AdaptiveSheetHeader(title: 'Edit activity'),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _title,
                autofocus: widget.draft.title.isEmpty,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Activity Name',
                  helperText: 'Required',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _description,
                maxLines: 4,
                minLines: 2,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'Describe',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _link,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Reference Link',
                  hintText: 'https://…',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
