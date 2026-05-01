import 'dart:async';
import 'dart:convert';

import 'package:basecamp/features/activity_library/url_scraper.dart';
import 'package:basecamp/features/ai/openai_client.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';

/// Sandbox surface for trying things out before they earn a real
/// home. The current experiment: **WYSIWYG activity cards.**
///
/// **Mental model:** the card *is* the document. There's no input
/// chrome — no borders, no underlines, no field labels — so the
/// edit state is visually identical to the display state. The only
/// transition between "writing" and "reading" a card is the cursor
/// blinking. No jumpiness because the TextField and the Text use
/// the same [TextStyle], same line height, same hit area.
///
/// **Edit lifecycle:**
///   1. FAB `+` opens an action menu — *New activity* (blank card)
///      or *AI activity* (describe / paste a link, model fills it in).
///   2. While any card is being edited, the FAB morphs into `✓` Done.
///      Tapping Done unfocuses + cleans up: empty fields disappear
///      from the card, and a card with every field empty is removed
///      entirely.
///   3. Tapping a card in display mode re-enters edit mode (with
///      placeholders for empty fields), so the user can append a
///      description or link any time.
///
/// **Display rule:** in display mode each field renders only if it
/// has content. A title-only card shows just the title. The
/// "Activity Name" / "Describe" / "Reference Link" placeholders
/// appear only inside edit mode — display mode stays clean.
///
/// Drafts live in memory only. When the pattern graduates we'll
/// back it with the activity-library repo; until then this is
/// disposable.
class ExperimentScreen extends StatefulWidget {
  const ExperimentScreen({super.key});

  @override
  State<ExperimentScreen> createState() => _ExperimentScreenState();
}

class _ExperimentScreenState extends State<ExperimentScreen> {
  // In-memory only — sandbox.
  final List<_ActivityDraft> _drafts = [];

  // Which draft (if any) is currently being edited. Only one card
  // edits at a time — keeps the FAB state unambiguous (any non-null
  // value here flips the FAB into Done) and means tapping a different
  // card cleanly hands off edit mode without worrying about how to
  // close the previous one.
  _ActivityDraft? _editingDraft;

  bool get _isEditing => _editingDraft != null;

  void _addBlank() {
    final draft = _ActivityDraft();
    setState(() {
      _drafts.add(draft);
      _editingDraft = draft;
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
                // Fire-and-forget — the composer manages its own
                // lifecycle and we don't need to await here (the
                // ListTile's onTap is sync).
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
    // AI-generated cards land in display mode (already populated) —
    // the user can tap to refine, but nothing's auto-edit so we don't
    // shove the keyboard up unsolicited.
    setState(() => _drafts.add(result));
  }

  void _enterEditMode(_ActivityDraft draft) {
    if (_editingDraft == draft) return;
    setState(() => _editingDraft = draft);
  }

  void _doneEditing() {
    // Drop focus first so any pending controller writes have settled
    // before we run cleanup on the underlying values.
    FocusScope.of(context).unfocus();
    setState(() {
      // Cleanup: a card with no content at all (user tapped + then
      // tapped Done without typing) shouldn't linger as a ghost.
      _drafts.removeWhere(
        (d) => d.title.isEmpty && d.description.isEmpty && d.link.isEmpty,
      );
      _editingDraft = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Experiment')),
      body: _drafts.isEmpty
          // Blank canvas — the FAB is the only affordance until the
          // first card lands.
          ? const SizedBox.expand()
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: _drafts.length,
              itemBuilder: (_, i) {
                final draft = _drafts[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _ActivityDraftCard(
                    // ValueKey on the draft instance so reordering or
                    // deletion can't recycle one card's controllers
                    // into another card's slot.
                    key: ValueKey(draft),
                    draft: draft,
                    isEditing: _editingDraft == draft,
                    onEnterEdit: () => _enterEditMode(draft),
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
            // Key by the bool so AnimatedSwitcher actually swaps; the
            // icons would otherwise be considered "the same widget."
            key: ValueKey(_isEditing),
          ),
        ),
      ),
    );
  }
}

/// Mutable draft model. Plain class (not freezed) — the inline-edit
/// loop mutates field-by-field and per-keystroke `copyWith` would
/// just be churn for an in-memory sandbox.
class _ActivityDraft {
  String title = '';
  String description = '';
  String link = '';
}

/// One activity card. WYSIWYG: in **display mode** it renders only
/// the fields the user has filled in (a title-only card is just a
/// bold title). In **edit mode** it renders all three slots as
/// borderless [TextField]s using the exact same [TextStyle]s as the
/// display [Text]s, so toggling between modes never shifts a pixel.
///
/// Single-tap a display-mode card → enter edit mode. While in edit
/// mode the parent's FAB shows Done; tapping it clears `_editingDraft`
/// at the screen level, which kicks this card back into display mode
/// (and runs the screen's empty-card cleanup pass).
class _ActivityDraftCard extends StatefulWidget {
  const _ActivityDraftCard({
    required this.draft,
    required this.isEditing,
    required this.onEnterEdit,
    super.key,
  });

  final _ActivityDraft draft;
  final bool isEditing;
  final VoidCallback onEnterEdit;

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

  // Title focus is the one we actively grab on first edit-mode entry
  // (so a freshly-added blank card has the keyboard up on the title
  // line). Description/link don't need their own focus nodes since
  // the user explicitly taps them when ready.
  final FocusNode _titleFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _title.addListener(_pushTitle);
    _description.addListener(_pushDescription);
    _link.addListener(_pushLink);
    if (widget.isEditing && widget.draft.title.isEmpty) {
      _focusTitleNextFrame();
    }
  }

  // Listeners write back to the draft on every keystroke. They don't
  // call setState — the parent screen doesn't need to rebuild on
  // every character (only on edit/display transitions, which it
  // controls itself via _editingDraft).
  void _pushTitle() => widget.draft.title = _title.text;
  void _pushDescription() => widget.draft.description = _description.text;
  void _pushLink() => widget.draft.link = _link.text;

  void _focusTitleNextFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titleFocus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant _ActivityDraftCard old) {
    super.didUpdateWidget(old);
    // Card just transitioned into edit mode AND has no title yet →
    // grab focus so the user can start typing immediately. We don't
    // grab focus on every entry into edit mode — only the empty case
    // where there's no ambiguity about which field is "next."
    if (widget.isEditing &&
        !old.isEditing &&
        widget.draft.title.isEmpty) {
      _focusTitleNextFrame();
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

    // Placeholders share the field's exact style but with the muted
    // `onSurfaceVariant` color so they read as "scaffolding" rather
    // than committed text. Important for WYSIWYG: same fontSize, same
    // weight, same decoration — only the color differs.
    final placeholderColor = cs.onSurfaceVariant.withValues(alpha: 0.55);
    final placeholderTitle = titleStyle.copyWith(color: placeholderColor);
    final placeholderBody = bodyStyle.copyWith(color: placeholderColor);
    final placeholderLink = linkStyle.copyWith(
      color: placeholderColor,
      decorationColor: placeholderColor,
    );

    return GestureDetector(
      // Display-mode tap → enter edit. Edit mode lets the inner
      // TextFields handle their own taps (don't intercept or focus
      // toggling won't work).
      onTap: widget.isEditing ? null : widget.onEnterEdit,
      // Opaque so taps on empty padding between fields still register
      // (otherwise the AppCard's gaps would swallow them).
      behavior: HitTestBehavior.opaque,
      child: AppCard(
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
    );
  }

  /// Display-mode column: only fields with content. A card with just
  /// a title is just a bold line. If everything is empty (transient
  /// state right before edit mode kicks in), we render a muted
  /// "Activity Name" so the card has a visible footprint to tap.
  Widget _buildDisplayMode({
    required TextStyle titleStyle,
    required TextStyle bodyStyle,
    required TextStyle linkStyle,
    required TextStyle placeholderTitle,
  }) {
    final children = <Widget>[];
    if (widget.draft.title.isNotEmpty) {
      children.add(Text(widget.draft.title, style: titleStyle));
    }
    if (widget.draft.description.isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: AppSpacing.sm));
      }
      children.add(Text(widget.draft.description, style: bodyStyle));
    }
    if (widget.draft.link.isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: AppSpacing.sm));
      }
      children.add(Text(widget.draft.link, style: linkStyle));
    }
    if (children.isEmpty) {
      // Truly empty card — render a muted title placeholder so the
      // card is at least tappable. The screen's Done cleanup will
      // delete this if the user never enters anything.
      children.add(Text('Activity Name', style: placeholderTitle));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  /// Edit-mode column: all three fields as borderless TextFields.
  /// Each TextField uses [InputDecoration.collapsed] so it renders
  /// with zero chrome — no border, no underline, no padding beyond
  /// the text glyphs themselves. Result: a TextField that occupies
  /// the same vertical space as a Text with the same style, which is
  /// what kills the toggle jumpiness.
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
          textInputAction: TextInputAction.next,
          // cursorHeight matched to fontSize so the cursor doesn't
          // tower over the glyphs (default cursor extends past line
          // height a bit, which would shift the visual baseline).
          cursorHeight: titleStyle.fontSize,
          decoration: InputDecoration.collapsed(
            hintText: 'Activity Name',
            hintStyle: placeholderTitle,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _description,
          style: bodyStyle,
          maxLines: null,
          textInputAction: TextInputAction.newline,
          cursorHeight: bodyStyle.fontSize,
          decoration: InputDecoration.collapsed(
            hintText: 'Describe',
            hintStyle: placeholderBody,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _link,
          style: linkStyle,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          cursorHeight: linkStyle.fontSize,
          decoration: InputDecoration.collapsed(
            hintText: 'Reference Link',
            hintStyle: placeholderLink,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------
// AI activity composer
// ---------------------------------------------------------------

/// URL detector — anything that looks like an HTTP(S) link in the
/// user's freeform prompt. We pluck the URL out and assign it to
/// the draft's `link` field directly rather than asking the model
/// to echo it back, because (a) it's already verbatim from the user
/// and (b) it removes a class of "the model paraphrased the URL"
/// failures.
final _urlPattern = RegExp(r'https?://\S+');

/// Bottom-sheet composer. User types a description or pastes a link,
/// taps Generate, the OpenAI proxy returns `{title, description}`,
/// and we hand a populated [_ActivityDraft] back via Navigator.pop.
class _AiActivityComposer extends StatefulWidget {
  const _AiActivityComposer();

  @override
  State<_AiActivityComposer> createState() => _AiActivityComposerState();
}

class _AiActivityComposerState extends State<_AiActivityComposer> {
  final _ctrl = TextEditingController();
  // Null when idle. While work is in flight, holds a teacher-facing
  // status string ("Reading link…", "Generating…") that becomes the
  // button label so the user sees which phase we're in. A single
  // string handles "is something happening" + "what is happening"
  // together, so we don't need a parallel bool.
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
      // If the user pasted a link, fetch it and pass the page's
      // actual title + extracted text to the model — otherwise we'd
      // be asking gpt-4o-mini to riff on a URL pattern, which is
      // hallucination-prone. Body fetched and HTML→text-extracted
      // by `scrapeUrl` (same helper the activity-library wizard uses).
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
        // Trim the exception's class prefix — users don't need to
        // see "ScrapeFailure: …" or "OpenAiClientException(...): …"
        // to understand "the link didn't load, try again."
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
        // Lift above the keyboard so the input + button never get
        // covered on mobile.
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
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_outlined),
                // Label tracks the phase ("Reading link…" then
                // "Generating…") so a long network hop has visible
                // progress instead of a generic spinner.
                label: Text(_status ?? 'Generate'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Calls the OpenAI proxy with a JSON-mode prompt and turns the
/// freeform `input` into a populated draft.
///
/// When [scraped] is non-null (the caller fetched the URL via
/// [scrapeUrl] first), the model gets the page's actual title +
/// extracted text — so the description is grounded in real content
/// rather than the model's prior on whatever the URL pattern looked
/// like. When no URL is present the model riffs on the description
/// directly.
///
/// The link field on the returned draft is always the user's
/// verbatim URL (or empty) — we never trust the model to round-trip
/// it, since paraphrased hosts ("medium.com" → "medium.example.com")
/// would silently break the reference.
Future<_ActivityDraft> _generateActivityDraft({
  required String input,
  required String? url,
  required ScrapedPage? scraped,
}) async {
  if (!OpenAiClient.isAvailable) {
    throw const _AiUnavailable();
  }

  // Two prompt shapes — one for "we read the page, here's its
  // content," one for "the user described an idea, expand it." We
  // could collapse these into one parameterised prompt, but keeping
  // them split makes each one easier to tune independently when the
  // outputs drift.
  final userMessage = scraped != null
      ? 'Source page title: ${scraped.title}\n\n'
          'Source page text:\n${scraped.text}\n\n'
          'Write an activity card based on what the page describes. '
          'Use concrete details from the source text — do not invent '
          'materials or steps that the source does not mention.'
      : 'Generate an activity card based on this description: $input';

  final body = await OpenAiClient.chat({
    // gpt-4o-mini matches the rest of the AI features in the app —
    // cheap, fast, and good enough for a one-paragraph generation.
    'model': 'gpt-4o-mini',
    'temperature': 0.4,
    'response_format': {'type': 'json_object'},
    'messages': [
      {
        'role': 'system',
        'content':
            'You generate short activity cards for early-childhood '
            'educators. Return JSON with exactly two keys: '
            '"title" (a short, title-cased name, max 8 words), '
            '"description" (one or two concrete classroom-friendly '
            'sentences). Do not include URLs, markdown, or extra keys.',
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
  final parsed = jsonDecode(content) as Map<String, dynamic>;
  return _ActivityDraft()
    ..title = (parsed['title'] as String? ?? '').trim()
    ..description = (parsed['description'] as String? ?? '').trim()
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
