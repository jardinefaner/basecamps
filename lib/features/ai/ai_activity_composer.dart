import 'dart:convert';

import 'package:basecamp/features/activity_library/url_scraper.dart';
import 'package:basecamp/features/ai/openai_client.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

/// Public, mutable container for an AI-generated activity. Lives in
/// the AI layer (not in any feature) because multiple surfaces feed
/// it back into their own data models — the experiment screen wraps
/// it as a draft card, the week plan turns it into a `template` row,
/// future surfaces will do their own thing. Plain class instead of a
/// freezed record because callers often need field-by-field copy
/// into their own models without churning a `copyWith` per copy.
class AiActivity {
  AiActivity({
    this.title = '',
    this.description = '',
    this.objectives = '',
    this.steps = '',
    this.materials = '',
    this.duration = '',
    this.ageRange = '',
    this.link = '',
  });

  String title;
  String description;
  String objectives;
  String steps;
  String materials;
  String duration;
  String ageRange;
  String link;

  /// True if any metadata field has content. Useful when a caller
  /// wants to decide whether to show a "More details" disclosure
  /// already-expanded on its surface.
  bool get hasAnyMetadata =>
      objectives.isNotEmpty ||
      steps.isNotEmpty ||
      materials.isNotEmpty ||
      duration.isNotEmpty ||
      ageRange.isNotEmpty;
}

/// Opens the AI activity composer as a bottom modal. Returns the
/// generated activity on success, or null when the user dismissed
/// without generating.
///
/// Bottom modal everywhere (mobile + web) — the composer's a one-
/// shot input → result handoff, not a side-by-side workspace, so
/// the bottom-sheet idiom fits both shapes. (Compare the *advanced*
/// activity editor, which uses `showAdaptiveSheet` for a side-panel
/// on web because that one IS a workspace.)
Future<AiActivity?> showAiActivityComposer(BuildContext context) async {
  return showModalBottomSheet<AiActivity>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _AiActivityComposerSheet(),
  );
}

/// URL detector — anything that looks like an HTTP(S) link in the
/// user's freeform prompt. We pluck the URL out and assign it to
/// the activity's `link` field directly rather than asking the
/// model to echo it back, because (a) it's already verbatim from
/// the user and (b) it removes a class of "the model paraphrased
/// the URL" failures.
final _urlPattern = RegExp(r'https?://\S+');

class _AiActivityComposerSheet extends StatefulWidget {
  const _AiActivityComposerSheet();

  @override
  State<_AiActivityComposerSheet> createState() =>
      _AiActivityComposerSheetState();
}

class _AiActivityComposerSheetState extends State<_AiActivityComposerSheet> {
  final _ctrl = TextEditingController();
  // Null when idle. While work is in flight, holds a teacher-facing
  // status string ("Reading link…", "Generating…") that becomes the
  // button label.
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
      // first so the cheap chat-completions model has real source
      // material to ground on. Without this step the model would
      // hallucinate from the URL pattern alone.
      ScrapedPage? scraped;
      if (url != null) {
        if (mounted) setState(() => _status = 'Reading link…');
        scraped = await scrapeUrl(url);
      }
      if (mounted) setState(() => _status = 'Generating…');
      final activity = await _generateAiActivity(
        input: input,
        url: url,
        scraped: scraped,
      );
      if (!mounted) return;
      Navigator.of(context).pop(activity);
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
/// into a populated [AiActivity]. Cheap — fractions of a cent per
/// call.
///
/// When [scraped] is non-null (the caller fetched the URL via
/// [scrapeUrl] first), the model gets the page's actual title +
/// extracted body text as source material. When no URL is present
/// the model expands the description directly.
Future<AiActivity> _generateAiActivity({
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
  final parsed = jsonDecode(content) as Map<String, dynamic>;
  String pull(String key) => (parsed[key] as String? ?? '').trim();
  return AiActivity(
    title: pull('title'),
    description: pull('description'),
    objectives: pull('objectives'),
    steps: pull('steps'),
    materials: pull('materials'),
    duration: pull('duration'),
    ageRange: pull('ageRange'),
    // Always use the user's verbatim URL — never trust the model to
    // round-trip it (paraphrased hosts would silently break refs).
    link: url ?? '',
  );
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
