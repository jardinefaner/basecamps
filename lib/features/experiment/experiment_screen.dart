import 'dart:async';
import 'dart:convert';

import 'package:basecamp/features/activity_library/url_scraper.dart';
import 'package:basecamp/features/ai/openai_client.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/adaptive_sheet.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';

/// Sandbox surface for trying things out before they earn a real home.
/// Current experiment: **WYSIWYG activity cards.**
///
/// **Mental model:** the card is the document. The display state and
/// the edit state are visually identical — same fonts, same line
/// heights, same hit areas, zero input chrome (no borders, no fill,
/// no underlines, no padding inside the input). The only thing that
/// changes between modes is whether a cursor is blinking. So toggling
/// in and out of edit mode never shifts a pixel.
///
/// **Two ways to edit a card:**
///   1. **Inline (default).** Tap a card to enter edit mode in place;
///      tap the FAB Done (`✓`) to commit + cleanup. Empty fields
///      disappear; a card whose every field is empty is removed.
///   2. **Advanced (pencil).** Tap the pencil in the AppBar to arm
///      "pick mode," then tap any card — that card opens in an
///      adaptive sheet (bottom modal on phones, right side panel on
///      web) with full labeled-input chrome for deliberate authoring.
///
/// **FAB lifecycle:**
///   * Idle → `+` opens an action sheet (*New activity* / *AI activity*).
///   * Inline-editing → `✓` Done — unfocus, drop empty cards.
///   * The list reserves enough bottom whitespace that the FAB never
///     covers the last card.
///
/// **AI activity** uses `gpt-4o-mini` (cheap — fractions of a cent
/// per call). When the user pastes a URL we fetch + extract the page
/// text via [scrapeUrl] first and pass that to the model so the
/// description is grounded in real content. The browser-side fetch
/// is subject to CORS — works on native, can fail on web for sites
/// without permissive CORS headers (the message surfaces inline).
///
/// Drafts live in memory only — sandbox.
class ExperimentScreen extends StatefulWidget {
  const ExperimentScreen({super.key});

  @override
  State<ExperimentScreen> createState() => _ExperimentScreenState();
}

class _ExperimentScreenState extends State<ExperimentScreen> {
  final List<_ActivityDraft> _drafts = [];

  // Which draft (if any) is currently inline-editing. Only one card
  // edits at a time — keeps the FAB state unambiguous and means
  // tapping a different card cleanly hands off without race
  // conditions on focus.
  _ActivityDraft? _editingDraft;

  // Pencil-armed state. While true, the next card tap opens the
  // advanced editor in an adaptive sheet (instead of entering inline
  // edit). Mutually exclusive with inline editing — entering pick
  // mode auto-Dones any inline edit first.
  bool _pickForAdvanced = false;

  bool get _isEditing => _editingDraft != null;

  void _addBlank() {
    final draft = _ActivityDraft();
    setState(() {
      _drafts.add(draft);
      _editingDraft = draft;
      // Adding a blank card is decisively an inline edit gesture, so
      // make sure we're not accidentally still in pick mode.
      _pickForAdvanced = false;
    });
  }

  Future<void> _showAddMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New activity'),
              subtitle: const Text('Blank card to fill in'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _addBlank();
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('AI activity'),
              subtitle: const Text('Describe an idea or paste a link'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                unawaited(_openAiComposer());
              },
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  Future<void> _openAiComposer() async {
    final result = await showModalBottomSheet<_ActivityDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AiActivityComposer(),
    );
    if (!mounted || result == null) return;
    setState(() => _drafts.add(result));
  }

  void _enterEditMode(_ActivityDraft draft) {
    if (_editingDraft == draft) return;
    setState(() => _editingDraft = draft);
  }

  void _doneEditing() {
    FocusScope.of(context).unfocus();
    setState(() {
      _drafts.removeWhere(
        (d) => d.title.isEmpty && d.description.isEmpty && d.link.isEmpty,
      );
      _editingDraft = null;
    });
  }

  void _togglePickMode() {
    setState(() {
      if (!_pickForAdvanced) {
        // Entering pick mode also drops any inline-edit state — the
        // two modes are mutually exclusive and a tap-on-card needs to
        // be unambiguous about which one fires.
        FocusScope.of(context).unfocus();
        _drafts.removeWhere(
          (d) => d.title.isEmpty && d.description.isEmpty && d.link.isEmpty,
        );
        _editingDraft = null;
        _pickForAdvanced = true;
      } else {
        _pickForAdvanced = false;
      }
    });
  }

  Future<void> _openAdvancedEditor(_ActivityDraft draft) async {
    // Pop pick mode the moment a card fires — pencil is one-shot
    // armed; user has to tap pencil again to edit another card.
    setState(() => _pickForAdvanced = false);
    await showAdaptiveSheet<void>(
      context: context,
      builder: (_) => _AdvancedActivityEditor(
        draft: draft,
        onChanged: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }

  void _onCardTap(_ActivityDraft draft) {
    if (_pickForAdvanced) {
      unawaited(_openAdvancedEditor(draft));
    } else {
      _enterEditMode(draft);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Title morphs while pick mode is armed so the user has a
        // clear cue that the next card tap will do something
        // different from the default inline-edit.
        title: Text(
          _pickForAdvanced ? 'Pick a card to edit' : 'Experiment',
        ),
        actions: [
          IconButton(
            icon: Icon(
              _pickForAdvanced ? Icons.close : Icons.edit_outlined,
            ),
            tooltip: _pickForAdvanced ? 'Cancel' : 'Edit',
            onPressed: _togglePickMode,
          ),
        ],
      ),
      body: _drafts.isEmpty
          ? const SizedBox.expand()
          : ListView.builder(
              // Bottom inset clears the FAB (56 dp) + its 16 dp margin
              // + a comfortable 24 dp breathing room. Without this the
              // last card sits behind the FAB on a full list.
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                96,
              ),
              itemCount: _drafts.length,
              itemBuilder: (_, i) {
                final draft = _drafts[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _ActivityDraftCard(
                    key: ValueKey(draft),
                    draft: draft,
                    isEditing: _editingDraft == draft,
                    onTap: () => _onCardTap(draft),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isEditing ? _doneEditing : _showAddMenu,
        tooltip: _isEditing ? 'Done' : 'Add activity',
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: Icon(
            _isEditing ? Icons.check : Icons.add,
            key: ValueKey(_isEditing),
          ),
        ),
      ),
    );
  }
}

/// In-memory draft. The first three fields are the doc-facing ones —
/// they render inline on the card. The rest are **metadata**: the
/// inline card never shows them; they're surfaced only in the
/// advanced editor's "More details" disclosure. Free-text strings
/// across the board because this is a sandbox — when the activity
/// model graduates we'll pick proper structured types (Duration,
/// AgeRange, `List<String>` for steps, etc.) but for now leaving them
/// loose means we can iterate on which fields matter without churn.
class _ActivityDraft {
  String title = '';
  String description = '';
  String link = '';

  // --- Metadata (advanced editor only) ---
  String objectives = '';
  String steps = '';
  String materials = '';
  String duration = '';
  String ageRange = '';

  /// True if any metadata field has content. Drives the "More
  /// details" disclosure's initial state — if the user previously
  /// filled in metadata, the disclosure opens already-expanded so
  /// they don't have to hunt for what they wrote.
  bool get hasAnyMetadata =>
      objectives.isNotEmpty ||
      steps.isNotEmpty ||
      materials.isNotEmpty ||
      duration.isNotEmpty ||
      ageRange.isNotEmpty;
}

// =====================================================================
// Activity card — display + inline edit
// =====================================================================

/// Standard "no chrome" decoration for the inline TextFields. The app's
/// global [InputDecorationTheme] sets `filled: true`, an outlined border
/// and a 14 dp content padding so every form field across the app
/// shares the same look — but here we want the *opposite*: zero chrome
/// so the TextField is visually indistinguishable from the [Text] it
/// replaces. Every state-specific border is set to [InputBorder.none]
/// individually because the theme overrides each of those by name; a
/// generic `border: InputBorder.none` alone wouldn't be enough.
InputDecoration _noChrome({String? hintText, TextStyle? hintStyle}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: hintStyle,
    isDense: true,
    isCollapsed: true,
    filled: false,
    fillColor: Colors.transparent,
    contentPadding: EdgeInsets.zero,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
  );
}

/// Strut style derived from a TextStyle, with `forceStrutHeight` set
/// so Text and TextField laid out with the same TextStyle compute
/// pixel-identical line heights. Without forcing this, TextField uses
/// the font's intrinsic ascender/descender and Text uses the style's
/// line height — they're usually close but not exact, which leaks as
/// a 1–2 px shimmer when toggling between them.
StrutStyle _strut(TextStyle style) {
  return StrutStyle.fromTextStyle(style, forceStrutHeight: true);
}

class _ActivityDraftCard extends StatefulWidget {
  const _ActivityDraftCard({
    required this.draft,
    required this.isEditing,
    required this.onTap,
    super.key,
  });

  final _ActivityDraft draft;
  final bool isEditing;
  final VoidCallback onTap;

  @override
  State<_ActivityDraftCard> createState() => _ActivityDraftCardState();
}

// Field index constants — used to identify which field a tap
// targets and which TextField to focus when transitioning into
// edit mode. Plain ints rather than an enum because the indices
// also pick into a 3-slot list of controllers / focus nodes.
const int _kTitleField = 0;
const int _kDescriptionField = 1;
const int _kLinkField = 2;

class _ActivityDraftCardState extends State<_ActivityDraftCard> {
  late final TextEditingController _title =
      TextEditingController(text: widget.draft.title);
  late final TextEditingController _description =
      TextEditingController(text: widget.draft.description);
  late final TextEditingController _link =
      TextEditingController(text: widget.draft.link);

  // Per-field focus nodes. Each visible field in display mode has
  // its own tap target that, on tap, requests focus on its
  // corresponding node so the cursor lands in the field the user
  // actually clicked — instead of always defaulting to the title.
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _descriptionFocus = FocusNode();
  final FocusNode _linkFocus = FocusNode();

  // Field index to focus on the next build *after* a display→edit
  // transition. Captured during the tap (when we're still in display
  // mode) and consumed in didUpdateWidget once the TextFields exist.
  int? _focusOnNextBuild;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => widget.draft.title = _title.text);
    _description.addListener(
      () => widget.draft.description = _description.text,
    );
    _link.addListener(() => widget.draft.link = _link.text);
    if (widget.isEditing && widget.draft.title.isEmpty) {
      _focusOnNextBuild = _kTitleField;
      _consumeFocusRequest();
    }
  }

  /// Returns the controller + focus node for a field index.
  (TextEditingController, FocusNode) _slotFor(int field) {
    switch (field) {
      case _kDescriptionField:
        return (_description, _descriptionFocus);
      case _kLinkField:
        return (_link, _linkFocus);
      case _kTitleField:
      default:
        return (_title, _titleFocus);
    }
  }

  /// Called by display-mode tap targets. Records which field was
  /// tapped, then asks the parent to flip into edit mode. The actual
  /// focus + cursor placement happens in didUpdateWidget once the
  /// TextField for that field has been built.
  void _enterEditOnField(int field) {
    if (widget.isEditing) {
      // Already editing — no parent state flip needed; just shift
      // focus to the tapped field directly.
      _focusField(field);
      return;
    }
    _focusOnNextBuild = field;
    widget.onTap();
  }

  /// Focuses [field]'s TextField AND collapses its selection to the
  /// end of its current text. Two reasons for the explicit selection:
  ///   1. Some web browsers select-all when an HTML input first
  ///      receives focus with content — that reads as random
  ///      highlighting instead of a cursor.
  ///   2. Default Flutter behavior places the cursor at offset 0
  ///      on first focus of a fresh TextField, which is rarely what
  ///      a tap-to-edit user wants.
  /// Cursor-at-end is the predictable middle ground; tap-position-
  /// preserving cursor would require text-painter math against the
  /// tap's local coordinates, which we can layer on later if needed.
  void _focusField(int field) {
    final (ctrl, fn) = _slotFor(field);
    fn.requestFocus();
    ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
  }

  void _consumeFocusRequest() {
    final target = _focusOnNextBuild;
    if (target == null) return;
    _focusOnNextBuild = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusField(target);
    });
  }

  @override
  void didUpdateWidget(covariant _ActivityDraftCard old) {
    super.didUpdateWidget(old);
    // Card just transitioned into edit mode — focus the field the
    // user tapped (or default to title for taps on the empty card
    // body).
    if (widget.isEditing && !old.isEditing) {
      _focusOnNextBuild ??= _kTitleField;
      _consumeFocusRequest();
    }
    // External writes (e.g. the advanced editor sheet) sync into the
    // controllers on the next display-mode rebuild. Skip while we're
    // editing to avoid trampling an in-progress keystroke.
    if (!widget.isEditing) {
      if (_title.text != widget.draft.title) {
        _title.text = widget.draft.title;
      }
      if (_description.text != widget.draft.description) {
        _description.text = widget.draft.description;
      }
      if (_link.text != widget.draft.link) {
        _link.text = widget.draft.link;
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _link.dispose();
    _descriptionFocus.dispose();
    _linkFocus.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

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

    final placeholderColor = cs.onSurfaceVariant.withValues(alpha: 0.55);
    final placeholderTitle = titleStyle.copyWith(color: placeholderColor);
    final placeholderBody = bodyStyle.copyWith(color: placeholderColor);
    final placeholderLink = linkStyle.copyWith(
      color: placeholderColor,
      decorationColor: placeholderColor,
    );

    return GestureDetector(
      // Outer tap target catches taps on the card body that aren't
      // on a field (e.g. the gap below a title-only card). Routes
      // through _enterEditOnField so the focus pipeline is the same
      // as a field tap — defaults to title since that's the only
      // field that's always present.
      onTap: widget.isEditing
          ? null
          : () => _enterEditOnField(_kTitleField),
      behavior: HitTestBehavior.opaque,
      child: AppCard(
        // AnimatedSize wraps the body so the layout transition between
        // display mode (only filled fields) and edit mode (all three
        // fields) is a smooth grow/shrink rather than a hard jump.
        // Short duration — long enough to feel intentional, short
        // enough to not slow down a deliberate user.
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: widget.isEditing
              ? _buildEditMode(
                  titleStyle: titleStyle,
                  bodyStyle: bodyStyle,
                  linkStyle: linkStyle,
                  placeholderTitle: placeholderTitle,
                  placeholderBody: placeholderBody,
                  placeholderLink: placeholderLink,
                )
              : _buildDisplayMode(
                  titleStyle: titleStyle,
                  bodyStyle: bodyStyle,
                  linkStyle: linkStyle,
                  placeholderTitle: placeholderTitle,
                ),
        ),
      ),
    );
  }

  Widget _buildDisplayMode({
    required TextStyle titleStyle,
    required TextStyle bodyStyle,
    required TextStyle linkStyle,
    required TextStyle placeholderTitle,
  }) {
    // Each visible field is its own GestureDetector — tapping the
    // title focuses the title's TextField, tapping the description
    // focuses the description's, etc. The outer card-level
    // GestureDetector still catches taps on the empty card body
    // (e.g. the small gap below a title-only card) and defaults to
    // focusing the title. Behavior = opaque on the inner ones so a
    // tap inside a Text doesn't bubble out and defeat the targeted
    // focus.
    Widget tappable({required int field, required Widget child}) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _enterEditOnField(field),
        child: child,
      );
    }

    final children = <Widget>[];
    if (widget.draft.title.isNotEmpty) {
      children.add(tappable(
        field: _kTitleField,
        child: Text(
          widget.draft.title,
          style: titleStyle,
          strutStyle: _strut(titleStyle),
        ),
      ));
    }
    if (widget.draft.description.isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: AppSpacing.sm));
      }
      children.add(tappable(
        field: _kDescriptionField,
        child: Text(
          widget.draft.description,
          style: bodyStyle,
          strutStyle: _strut(bodyStyle),
        ),
      ));
    }
    if (widget.draft.link.isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: AppSpacing.sm));
      }
      children.add(tappable(
        field: _kLinkField,
        child: Text(
          widget.draft.link,
          style: linkStyle,
          strutStyle: _strut(linkStyle),
        ),
      ));
    }
    if (children.isEmpty) {
      // Truly empty card — render a muted title placeholder so the
      // card has a visible footprint to tap. Done cleanup will delete
      // this if the user never types anything.
      children.add(tappable(
        field: _kTitleField,
        child: Text(
          'Activity Name',
          style: placeholderTitle,
          strutStyle: _strut(placeholderTitle),
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _buildEditMode({
    required TextStyle titleStyle,
    required TextStyle bodyStyle,
    required TextStyle linkStyle,
    required TextStyle placeholderTitle,
    required TextStyle placeholderBody,
    required TextStyle placeholderLink,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _title,
          focusNode: _titleFocus,
          style: titleStyle,
          strutStyle: _strut(titleStyle),
          textInputAction: TextInputAction.next,
          // cursorHeight matched to font size so the cursor doesn't
          // tower over the glyphs (default cursor extends past line
          // height a touch, which subtly shifts the visual baseline).
          cursorHeight: titleStyle.fontSize,
          decoration: _noChrome(
            hintText: 'Activity Name',
            hintStyle: placeholderTitle,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _description,
          focusNode: _descriptionFocus,
          style: bodyStyle,
          strutStyle: _strut(bodyStyle),
          maxLines: null,
          textInputAction: TextInputAction.newline,
          cursorHeight: bodyStyle.fontSize,
          decoration: _noChrome(
            hintText: 'Describe',
            hintStyle: placeholderBody,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _link,
          focusNode: _linkFocus,
          style: linkStyle,
          strutStyle: _strut(linkStyle),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          cursorHeight: linkStyle.fontSize,
          decoration: _noChrome(
            hintText: 'Reference Link',
            hintStyle: placeholderLink,
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// Advanced editor — adaptive sheet, full chrome
// =====================================================================

/// "Deliberate authoring" surface for a card. Bottom modal on phones,
/// right side panel on web (via [showAdaptiveSheet]). Uses the app's
/// standard labeled-input chrome — different surface, different rules.
/// Mirrors writes back to the underlying [_ActivityDraft] on every
/// keystroke so the inline card stays in sync as the sheet edits.
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
  // Doc-facing fields (also rendered on the inline card).
  late final TextEditingController _title =
      TextEditingController(text: widget.draft.title)..addListener(_pushTitle);
  late final TextEditingController _description =
      TextEditingController(text: widget.draft.description)
        ..addListener(_pushDescription);
  late final TextEditingController _link =
      TextEditingController(text: widget.draft.link)..addListener(_pushLink);

  // Metadata fields — only surfaced here, never on the inline card.
  late final TextEditingController _objectives =
      TextEditingController(text: widget.draft.objectives)
        ..addListener(_pushObjectives);
  late final TextEditingController _steps =
      TextEditingController(text: widget.draft.steps)
        ..addListener(_pushSteps);
  late final TextEditingController _materials =
      TextEditingController(text: widget.draft.materials)
        ..addListener(_pushMaterials);
  late final TextEditingController _duration =
      TextEditingController(text: widget.draft.duration)
        ..addListener(_pushDuration);
  late final TextEditingController _ageRange =
      TextEditingController(text: widget.draft.ageRange)
        ..addListener(_pushAgeRange);

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

  void _pushObjectives() {
    widget.draft.objectives = _objectives.text;
    widget.onChanged();
  }

  void _pushSteps() {
    widget.draft.steps = _steps.text;
    widget.onChanged();
  }

  void _pushMaterials() {
    widget.draft.materials = _materials.text;
    widget.onChanged();
  }

  void _pushDuration() {
    widget.draft.duration = _duration.text;
    widget.onChanged();
  }

  void _pushAgeRange() {
    widget.draft.ageRange = _ageRange.text;
    widget.onChanged();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _link.dispose();
    _objectives.dispose();
    _steps.dispose();
    _materials.dispose();
    _duration.dispose();
    _ageRange.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      // The sheet host (drag handle on bottom modal, header on side
      // panel) already positions content under the system chrome.
      top: false,
      child: Padding(
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
              const SizedBox(height: AppSpacing.lg),
              // Hairline divider visually separates the doc-facing
              // fields above from the metadata disclosure below, so
              // the user reads them as two tiers.
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant,
              ),
              // "More details" disclosure. Open by default if the
              // draft already has metadata so the user doesn't have
              // to hunt for what they previously wrote.
              _DetailsDisclosure(
                initiallyExpanded: widget.draft.hasAnyMetadata,
                children: [
                  TextField(
                    controller: _objectives,
                    maxLines: null,
                    minLines: 2,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      labelText: 'Objectives',
                      helperText: 'What children will learn or practice',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _steps,
                    maxLines: null,
                    minLines: 3,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      labelText: 'Steps',
                      helperText: 'Step-by-step how to run it',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _materials,
                    maxLines: null,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      labelText: 'Materials',
                      helperText: 'What you need on hand',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // Duration + age range share a row on wide layouts
                  // because they're both compact single-value fields;
                  // pairing them saves vertical space without crowding.
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _duration,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Duration',
                            hintText: '15 min',
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: TextField(
                          controller: _ageRange,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Age range',
                            hintText: '3–5 years',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tappable "More details" disclosure used inside the advanced
/// editor for the metadata block. Why a hand-rolled widget instead
/// of [ExpansionTile]: ExpansionTile insists on top/bottom dividers
/// and tile padding that fight the sheet's existing layout. This
/// version is just an InkWell row that flips a chevron + animates
/// the children's height into view via [AnimatedSize].
class _DetailsDisclosure extends StatefulWidget {
  const _DetailsDisclosure({
    required this.children,
    this.initiallyExpanded = false,
  });

  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  State<_DetailsDisclosure> createState() => _DetailsDisclosureState();
}

class _DetailsDisclosureState extends State<_DetailsDisclosure> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                AnimatedRotation(
                  duration: const Duration(milliseconds: 180),
                  // 0 → chevron points right (collapsed)
                  // 0.25 → chevron points down (expanded)
                  turns: _expanded ? 0.25 : 0,
                  child: Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'More details',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.children,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// =====================================================================
// AI activity composer
// =====================================================================

final _urlPattern = RegExp(r'https?://\S+');

class _AiActivityComposer extends StatefulWidget {
  const _AiActivityComposer();

  @override
  State<_AiActivityComposer> createState() => _AiActivityComposerState();
}

class _AiActivityComposerState extends State<_AiActivityComposer> {
  final _ctrl = TextEditingController();
  // Null when idle. While work is in flight, holds a teacher-facing
  // status string that becomes the button label.
  String? _status;
  String? _error;

  bool get _busy => _status != null;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final input = _ctrl.text.trim();
    if (input.isEmpty || _busy) return;
    setState(() {
      _status = 'Working…';
      _error = null;
    });
    try {
      final url = _urlPattern.firstMatch(input)?.group(0);
      // If the user pasted a link, fetch + extract the page text
      // first. Cheap-model generation alone has no browsing, so
      // without this step it'd just hallucinate from the URL pattern.
      ScrapedPage? scraped;
      if (url != null) {
        if (mounted) setState(() => _status = 'Reading link…');
        scraped = await scrapeUrl(url);
      }
      if (mounted) setState(() => _status = 'Generating…');
      final draft = await _generateActivityDraft(
        input: input,
        url: url,
        scraped: scraped,
      );
      if (!mounted) return;
      Navigator.of(context).pop(draft);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _status = null;
        // Trim the exception's class prefix — users don't need to see
        // "ScrapeFailure: …" or "OpenAiClientException(...): …" to
        // understand "the link didn't load, try again."
        _error = e.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('AI activity', style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _ctrl,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Describe an activity, or paste a link',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: _busy ? null : _generate,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_outlined),
                label: Text(_status ?? 'Generate'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Calls `gpt-4o-mini` with JSON mode and turns the freeform input
/// into a populated draft. Cheap — fractions of a cent per call.
///
/// When [scraped] is non-null (the caller fetched the URL via
/// [scrapeUrl] first), the model gets the page's actual title +
/// extracted body text as source material. When no URL is present
/// the model expands the description directly. The model itself
/// doesn't browse — that's the trade-off for the 140× lower cost
/// versus the search-preview variant.
Future<_ActivityDraft> _generateActivityDraft({
  required String input,
  required String? url,
  required ScrapedPage? scraped,
}) async {
  if (!OpenAiClient.isAvailable) {
    throw const _AiUnavailable();
  }

  final userMessage = scraped != null
      ? 'Source page title: ${scraped.title}\n\n'
          'Source page text:\n${scraped.text}\n\n'
          'Write an activity card based on what the page describes. '
          'Use concrete details from the source text — do not invent '
          'materials or steps that the source does not mention.'
      : 'Generate an activity card based on this description: $input';

  final body = await OpenAiClient.chat({
    'model': 'gpt-4o-mini',
    'temperature': 0.4,
    'response_format': {'type': 'json_object'},
    'messages': [
      {
        'role': 'system',
        'content':
            'You generate activity cards for early-childhood '
            'educators. Return JSON with these keys (title and '
            'description are required; the rest are optional and '
            'should be left as empty strings if you cannot infer '
            'them confidently):\n'
            '  "title": short, title-cased, max 8 words\n'
            '  "description": one or two concrete classroom-friendly '
            'sentences for the card preview\n'
            '  "objectives": one to three sentences on what children '
            'will practice or learn\n'
            '  "steps": numbered, newline-separated steps for how to '
            'run it (e.g. "1. Gather materials\\n2. Show example…")\n'
            '  "materials": comma-separated list of common materials '
            '(e.g. "paper, crayons, scissors")\n'
            '  "duration": estimated time as a short label '
            '(e.g. "15 min")\n'
            '  "ageRange": target age range as a short label '
            '(e.g. "3–5 years")\n'
            'Do not include URLs, markdown formatting, or any extra '
            'keys. Use empty strings, never null, for unknown fields.',
      },
      {'role': 'user', 'content': userMessage},
    ],
  });
  final choices = body['choices'] as List<dynamic>?;
  if (choices == null || choices.isEmpty) {
    throw const _AiEmptyResponse();
  }
  final message = (choices.first as Map<String, dynamic>)['message']
      as Map<String, dynamic>?;
  final content = message?['content'] as String?;
  if (content == null || content.trim().isEmpty) {
    throw const _AiEmptyResponse();
  }
  // JSON mode guarantees parseable JSON — no extraction games needed.
  final parsed = jsonDecode(content) as Map<String, dynamic>;
  String pull(String key) => (parsed[key] as String? ?? '').trim();
  return _ActivityDraft()
    ..title = pull('title')
    ..description = pull('description')
    ..objectives = pull('objectives')
    ..steps = pull('steps')
    ..materials = pull('materials')
    ..duration = pull('duration')
    ..ageRange = pull('ageRange')
    // Always use the user's verbatim URL — never trust the model to
    // round-trip it (paraphrased hosts would silently break refs).
    ..link = url ?? '';
}

class _AiUnavailable implements Exception {
  const _AiUnavailable();
  @override
  String toString() => 'AI: Sign in to use AI generation.';
}

class _AiEmptyResponse implements Exception {
  const _AiEmptyResponse();
  @override
  String toString() => 'AI: The model returned no content.';
}
