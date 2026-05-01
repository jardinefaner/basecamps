import 'dart:async';
import 'dart:convert';

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
/// **AI activity** uses `gpt-4o-mini-search-preview`, which has web
/// browsing built in. We pass the user's freeform input straight to
/// the model — if it contained a URL, the model visits it; otherwise
/// it searches the web for related content. We don't pre-fetch.
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

class _ActivityDraft {
  String title = '';
  String description = '';
  String link = '';
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

class _ActivityDraftCardState extends State<_ActivityDraftCard> {
  late final TextEditingController _title =
      TextEditingController(text: widget.draft.title);
  late final TextEditingController _description =
      TextEditingController(text: widget.draft.description);
  late final TextEditingController _link =
      TextEditingController(text: widget.draft.link);

  final FocusNode _titleFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _title.addListener(() => widget.draft.title = _title.text);
    _description.addListener(
      () => widget.draft.description = _description.text,
    );
    _link.addListener(() => widget.draft.link = _link.text);
    if (widget.isEditing && widget.draft.title.isEmpty) {
      _focusTitleNextFrame();
    }
  }

  void _focusTitleNextFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titleFocus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant _ActivityDraftCard old) {
    super.didUpdateWidget(old);
    // Auto-focus title when this card freshly enters edit mode AND
    // has no title yet (the typical case for FAB-added blanks).
    if (widget.isEditing &&
        !old.isEditing &&
        widget.draft.title.isEmpty) {
      _focusTitleNextFrame();
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
      onTap: widget.isEditing ? null : widget.onTap,
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
    final children = <Widget>[];
    if (widget.draft.title.isNotEmpty) {
      children.add(Text(
        widget.draft.title,
        style: titleStyle,
        strutStyle: _strut(titleStyle),
      ));
    }
    if (widget.draft.description.isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: AppSpacing.sm));
      }
      children.add(Text(
        widget.draft.description,
        style: bodyStyle,
        strutStyle: _strut(bodyStyle),
      ));
    }
    if (widget.draft.link.isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: AppSpacing.sm));
      }
      children.add(Text(
        widget.draft.link,
        style: linkStyle,
        strutStyle: _strut(linkStyle),
      ));
    }
    if (children.isEmpty) {
      // Truly empty card — render a muted title placeholder so the
      // card has a visible footprint to tap. Done cleanup will delete
      // this if the user never types anything.
      children.add(Text(
        'Activity Name',
        style: placeholderTitle,
        strutStyle: _strut(placeholderTitle),
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
  late final TextEditingController _title =
      TextEditingController(text: widget.draft.title)..addListener(_pushTitle);
  late final TextEditingController _description =
      TextEditingController(text: widget.draft.description)
        ..addListener(_pushDescription);
  late final TextEditingController _link =
      TextEditingController(text: widget.draft.link)..addListener(_pushLink);

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
            ],
          ),
        ),
      ),
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
      _status = 'Generating…';
      _error = null;
    });
    try {
      final url = _urlPattern.firstMatch(input)?.group(0);
      final draft = await _generateActivityDraft(input: input, url: url);
      if (!mounted) return;
      Navigator.of(context).pop(draft);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _status = null;
        // Trim the exception's class prefix — users don't need to see
        // "OpenAiClientException(...)" to understand "the model didn't
        // respond, try again."
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

/// Calls `gpt-4o-mini-search-preview` — OpenAI's chat-completions
/// model with built-in web search — and turns the freeform input
/// into a populated draft.
///
/// Why this model: `gpt-4o-mini` (the one we use elsewhere) doesn't
/// browse, so a pasted URL would force us to fetch the page client-
/// side first. The search-preview variant browses for us, which:
///   1. Removes the CORS wall on web (we'd otherwise need a server-
///      side scrape proxy).
///   2. Lets the model decide *whether* to search even when the user
///      gave a freeform description rather than a URL.
///
/// Quirks worth knowing:
///   * Search-preview models don't accept `temperature` or
///     `response_format`. We instruct JSON in the prompt and parse
///     best-effort.
///   * `web_search_options` is a required parameter — empty `{}` is
///     fine and uses default search context size.
///   * The model may include citation markdown in its output; we
///     pull the first `{...}` JSON block out by index rather than
///     trusting the whole content body to parse.
Future<_ActivityDraft> _generateActivityDraft({
  required String input,
  required String? url,
}) async {
  if (!OpenAiClient.isAvailable) {
    throw const _AiUnavailable();
  }
  final body = await OpenAiClient.chat({
    'model': 'gpt-4o-mini-search-preview',
    // Empty options uses default search context. Bump to
    // {"search_context_size": "high"} if we want richer browsing
    // later — costs more tokens.
    'web_search_options': <String, dynamic>{},
    'messages': [
      {
        'role': 'system',
        'content':
            'You generate short activity cards for early-childhood '
            'educators. If the user pastes a URL, visit it and base '
            'the card on real content from the page. If the user '
            'describes an idea instead, expand it directly. '
            'Respond with ONLY a JSON object — no prose, no markdown, '
            'no code fences. Required keys:\n'
            '  "title": short title-cased name, max 8 words\n'
            '  "description": one or two concrete classroom-friendly '
            'sentences\n'
            'Do not include URLs, citations, or any extra keys.',
      },
      {'role': 'user', 'content': input},
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
  final parsed = _parseFirstJsonObject(content);
  return _ActivityDraft()
    ..title = (parsed['title'] as String? ?? '').trim()
    ..description = (parsed['description'] as String? ?? '').trim()
    // Always use the user's verbatim URL — never trust the model to
    // round-trip it (paraphrased hosts would silently break refs).
    ..link = url ?? '';
}

/// Pulls the first `{...}` block out of a freeform model response.
/// The search-preview models sometimes wrap JSON in prose or markdown
/// fences despite our "ONLY JSON" instruction — extracting by first
/// `{` to last `}` survives that without us needing a real JSON-
/// streaming parser.
Map<String, dynamic> _parseFirstJsonObject(String content) {
  final start = content.indexOf('{');
  final end = content.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw const _AiEmptyResponse();
  }
  final json = content.substring(start, end + 1);
  final decoded = jsonDecode(json);
  if (decoded is! Map<String, dynamic>) {
    throw const _AiEmptyResponse();
  }
  return decoded;
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
