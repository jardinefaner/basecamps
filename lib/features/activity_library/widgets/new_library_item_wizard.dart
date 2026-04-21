import 'dart:async';

import 'package:basecamp/features/activity_library/activity_card_ai.dart';
import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:basecamp/features/activity_library/url_scraper.dart';
import 'package:basecamp/features/activity_library/widgets/activity_card_preview.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Six-step full-screen flow for populating the activity library with
/// AI-generated, audience-scoped cards sourced from a URL the teacher
/// pastes in. Steps:
///   1. Audience — pick an age or age range (single chips + ranges,
///      tap auto-advances)
///   2. Source — paste a URL
///   3. Generating — scrape + AI
///   4. Preview — show the card, Save / Discard
///   5. Saved — confirm + dismiss back to the library
///
/// (Step 0 — the FAB tap — is owned by the library screen.)
///
/// Failure paths are explicit: bad URL / unreachable page / empty text
/// drop the teacher back to the URL step with an inline error. No dead
/// ends.
class NewLibraryItemWizardScreen extends ConsumerStatefulWidget {
  const NewLibraryItemWizardScreen({super.key});

  @override
  ConsumerState<NewLibraryItemWizardScreen> createState() =>
      _NewLibraryItemWizardScreenState();
}

enum _WizardStep { audience, source, generating, preview }

class _NewLibraryItemWizardScreenState
    extends ConsumerState<NewLibraryItemWizardScreen> {
  _WizardStep _step = _WizardStep.audience;

  // Audience.
  int? _minAge;
  int? _maxAge;

  // Source URL / pasted text.
  final _urlController = TextEditingController();
  String? _urlError;

  // Generated card state.
  GeneratedCard? _generated;
  String? _sourceUrl;
  String? _sourceAttribution;
  String _generateStatus = 'Reading your link…';
  String? _generateError;

  bool _saving = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<bool> _confirmExit() async {
    final dirty = _minAge != null ||
        _urlController.text.trim().isNotEmpty ||
        _generated != null;
    if (!dirty) return true;
    return showConfirmDialog(
      context: context,
      title: 'Discard this?',
      message: "You'll lose whatever you've started. Continue?",
      cancelLabel: 'Keep going',
      confirmLabel: 'Discard',
    );
  }

  void _setAudience(int min, int max) {
    setState(() {
      _minAge = min;
      _maxAge = max;
      _step = _WizardStep.source;
    });
  }

  Future<void> _submitUrl() async {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) {
      setState(() => _urlError = 'Paste a link to a web page, article, or video.');
      return;
    }
    setState(() {
      _urlError = null;
      _step = _WizardStep.generating;
      _generated = null;
      _generateError = null;
      _generateStatus = 'Reading your link…';
    });
    unawaited(_runGeneration(raw));
  }

  Future<void> _runGeneration(String raw) async {
    // Staged status so the teacher sees movement — 10–30 s feels long
    // without any signal the machine is doing something.
    try {
      // Try client-side scraping first.
      ScrapedPage? scraped;
      try {
        scraped = await scrapeUrl(raw);
        if (!mounted) return;
        setState(() => _generateStatus =
            'Pulling out the key ideas from ${scraped!.host}…');
      } on ScrapeFailure catch (e) {
        // Fall through — we'll ask OpenAI to handle retrieval itself.
        if (!mounted) return;
        setState(() => _generateStatus =
            "Page wasn't readable — asking the AI to take a look (${e.reason})…");
      }

      setState(() => _generateStatus =
          'Tailoring it for ${_describeAudience()}…');

      GeneratedCard card;
      var effectiveUrl = raw;
      String? effectiveHost;
      if (scraped != null) {
        card = await generateActivityCard(
          sourceTitle: scraped.title,
          sourceText: scraped.text,
          sourceUrl: scraped.url,
          audienceMinAge: _minAge!,
          audienceMaxAge: _maxAge!,
          sourceHost: scraped.host,
        );
        effectiveUrl = scraped.url;
        effectiveHost = scraped.host;
      } else {
        // On-demand retrieval fallback: let OpenAI do its thing with
        // just the URL. This is the "don't dead-end the teacher" path
        // from the spec — a bad scrape shouldn't be a hard stop.
        final uri = Uri.tryParse(
          raw.startsWith(RegExp('https?://')) ? raw : 'https://$raw',
        );
        effectiveHost = uri?.host;
        card = await generateActivityCardFromUrlOnly(
          url: raw,
          audienceMinAge: _minAge!,
          audienceMaxAge: _maxAge!,
          sourceHost: effectiveHost,
        );
      }

      if (!mounted) return;
      if (card.isEmpty) {
        setState(() {
          _generateError =
              "The generator didn't return enough to build a card — try a different link.";
          _step = _WizardStep.source;
        });
        return;
      }
      setState(() {
        _generated = card;
        _sourceUrl = effectiveUrl;
        _sourceAttribution = card.sourceAttribution ??
            (effectiveHost == null || effectiveHost.isEmpty
                ? null
                : 'via $effectiveHost');
        _step = _WizardStep.preview;
      });
    } on GenerateFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _generateError = e.reason;
        _step = _WizardStep.source;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _generateError = 'Something went wrong: $e';
        _step = _WizardStep.source;
      });
    }
  }

  String _describeAudience() {
    if (_minAge == null || _maxAge == null) return 'the audience';
    return audienceLabelFor(_minAge!, _maxAge!).toLowerCase();
  }

  Future<void> _save() async {
    final card = _generated;
    if (card == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(activityLibraryRepositoryProvider).addItem(
            title: card.title,
            hook: card.hook.isEmpty ? null : card.hook,
            summary: card.summary.isEmpty ? null : card.summary,
            keyPoints:
                card.keyPoints.isEmpty ? null : card.keyPoints.join('\n'),
            learningGoals: card.learningGoals.isEmpty
                ? null
                : card.learningGoals.join('\n'),
            engagementTimeMin: card.engagementTimeMin,
            audienceMinAge: _minAge,
            audienceMaxAge: _maxAge,
            sourceUrl: _sourceUrl,
            sourceAttribution: _sourceAttribution,
          );
      if (!mounted) return;
      Navigator.of(context).pop<bool>(true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't save: $e")),
      );
    }
  }

  void _discard() {
    setState(() {
      _generated = null;
      _sourceUrl = null;
      _sourceAttribution = null;
      _step = _WizardStep.source;
    });
  }

  Future<void> _regenerate() async {
    final raw = _sourceUrl ?? _urlController.text.trim();
    if (raw.isEmpty) return;
    setState(() {
      _generated = null;
      _generateError = null;
      _generateStatus = 'Re-reading your link…';
      _step = _WizardStep.generating;
    });
    unawaited(_runGeneration(raw));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final navigator = Navigator.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmExit();
        if (!ok || !mounted) return;
        navigator.pop();
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surfaceContainerLowest,
        appBar: AppBar(
          backgroundColor: theme.colorScheme.surfaceContainerLowest,
          elevation: 0,
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () async {
              final ok = await _confirmExit();
              if (!ok || !mounted) return;
              navigator.pop();
            },
          ),
          title: Text(_titleFor(_step)),
          centerTitle: false,
        ),
        body: SafeArea(
          child: switch (_step) {
            _WizardStep.audience => _AudienceStep(onPick: _setAudience),
            _WizardStep.source => _SourceStep(
                audienceLabel:
                    audienceLabelFor(_minAge ?? 0, _maxAge ?? 0),
                controller: _urlController,
                error: _urlError ?? _generateError,
                onEditAudience: () => setState(() {
                  _step = _WizardStep.audience;
                  _generateError = null;
                }),
                onSubmit: _submitUrl,
                onPasteSupport: true,
              ),
            _WizardStep.generating => _GeneratingStep(
                status: _generateStatus,
                sourceUrl: _urlController.text.trim(),
                audienceLabel:
                    audienceLabelFor(_minAge ?? 0, _maxAge ?? 0),
              ),
            _WizardStep.preview => _PreviewStep(
                card: _generated!,
                audienceLabel:
                    audienceLabelFor(_minAge!, _maxAge!),
                sourceUrl: _sourceUrl,
                sourceAttribution: _sourceAttribution,
                saving: _saving,
                onSave: _save,
                onDiscard: _discard,
                onRegenerate: _regenerate,
              ),
          },
        ),
      ),
    );
  }

  String _titleFor(_WizardStep step) {
    switch (step) {
      case _WizardStep.audience:
        return 'Who is this for?';
      case _WizardStep.source:
        return 'Drop a link';
      case _WizardStep.generating:
        return 'Generating…';
      case _WizardStep.preview:
        return 'Preview';
    }
  }
}

// ---------- Step 1: Audience ----------

class _AudienceStep extends StatelessWidget {
  const _AudienceStep({required this.onPick});

  final void Function(int min, int max) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Who is this activity for?',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Tap an age or range to continue.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'AGE RANGES',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final r in _ranges)
                _AudienceChip(
                  label: 'Ages ${r.$1}–${r.$2}',
                  onTap: () => onPick(r.$1, r.$2),
                ),
              _CustomRangeChip(onPick: onPick),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'SINGLE AGE',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (var age = 3; age <= 12; age++)
                _AudienceChip(
                  label: 'Age $age',
                  onTap: () => onPick(age, age),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // Common early-years / elementary buckets. Easy to expand.
  static const _ranges = <(int, int)>[
    (3, 5),
    (5, 7),
    (6, 8),
    (7, 9),
    (8, 10),
    (10, 12),
  ];
}

class _AudienceChip extends StatelessWidget {
  const _AudienceChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
    );
  }
}

class _CustomRangeChip extends StatefulWidget {
  const _CustomRangeChip({required this.onPick});
  final void Function(int min, int max) onPick;

  @override
  State<_CustomRangeChip> createState() => _CustomRangeChipState();
}

class _CustomRangeChipState extends State<_CustomRangeChip> {
  Future<void> _pick(BuildContext context) async {
    final result = await showModalBottomSheet<(int, int)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _RangePickerSheet(),
    );
    if (result != null && mounted) {
      widget.onPick(result.$1, result.$2);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.tune, size: 16),
      label: const Text('Custom range'),
      onPressed: () => _pick(context),
    );
  }
}

class _RangePickerSheet extends StatefulWidget {
  const _RangePickerSheet();

  @override
  State<_RangePickerSheet> createState() => _RangePickerSheetState();
}

class _RangePickerSheetState extends State<_RangePickerSheet> {
  int _min = 5;
  int _max = 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.md,
        bottom: AppSpacing.xl + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Custom age range', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Pick the youngest and oldest age this card is for.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _NumberStepper(
                  label: 'From',
                  value: _min,
                  min: 2,
                  max: _max,
                  onChanged: (v) => setState(() => _min = v),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _NumberStepper(
                  label: 'To',
                  value: _max,
                  min: _min,
                  max: 18,
                  onChanged: (v) => setState(() => _max = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: () => Navigator.of(context).pop((_min, _max)),
            child: Text(audienceLabelFor(_min, _max)),
          ),
        ],
      ),
    );
  }
}

class _NumberStepper extends StatelessWidget {
  const _NumberStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              IconButton(
                onPressed: value > min ? () => onChanged(value - 1) : null,
                icon: const Icon(Icons.remove),
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: value < max ? () => onChanged(value + 1) : null,
                icon: const Icon(Icons.add),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------- Step 2: Source URL ----------

class _SourceStep extends StatelessWidget {
  const _SourceStep({
    required this.audienceLabel,
    required this.controller,
    required this.onEditAudience,
    required this.onSubmit,
    required this.error,
    required this.onPasteSupport,
  });

  final String audienceLabel;
  final TextEditingController controller;
  final VoidCallback onEditAudience;
  final VoidCallback onSubmit;
  final String? error;
  final bool onPasteSupport;

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) return;
    controller.text = text.trim();
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Audience chip with tap-to-edit.
          Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
              avatar: const Icon(Icons.edit_outlined, size: 16),
              label: Text('For: $audienceLabel'),
              onPressed: onEditAudience,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Paste a link',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            "Article, video, or web page you'd like to turn into an "
            'activity card.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: controller,
            label: 'Link',
            hint: 'https://example.com/cool-article',
            keyboardType: TextInputType.url,
            onChanged: (_) {},
          ),
          if (onPasteSupport) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _paste,
                icon: const Icon(Icons.content_paste, size: 16),
                label: const Text('Paste from clipboard'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          FilledButton.icon(
            onPressed: onSubmit,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Create activity'),
          ),
        ],
      ),
    );
  }
}

// ---------- Step 3: Generating ----------

class _GeneratingStep extends StatelessWidget {
  const _GeneratingStep({
    required this.status,
    required this.sourceUrl,
    required this.audienceLabel,
  });

  final String status;
  final String sourceUrl;
  final String audienceLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              status,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            if (sourceUrl.isNotEmpty)
              Text(
                sourceUrl,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'For $audienceLabel',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Step 4: Preview ----------

class _PreviewStep extends StatelessWidget {
  const _PreviewStep({
    required this.card,
    required this.audienceLabel,
    required this.sourceUrl,
    required this.sourceAttribution,
    required this.saving,
    required this.onSave,
    required this.onDiscard,
    required this.onRegenerate,
  });

  final GeneratedCard card;
  final String audienceLabel;
  final String? sourceUrl;
  final String? sourceAttribution;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onDiscard;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: ActivityCardPreview(
              title: card.title,
              audienceLabel: audienceLabel,
              hook: card.hook,
              summary: card.summary,
              keyPoints: card.keyPoints,
              learningGoals: card.learningGoals,
              engagementTimeMin: card.engagementTimeMin,
              sourceUrl: sourceUrl,
              sourceAttribution: sourceAttribution,
            ),
          ),
        ),
        _PreviewActionBar(
          saving: saving,
          onSave: onSave,
          onDiscard: onDiscard,
          onRegenerate: onRegenerate,
        ),
      ],
    );
  }
}

class _PreviewActionBar extends StatelessWidget {
  const _PreviewActionBar({
    required this.saving,
    required this.onSave,
    required this.onDiscard,
    required this.onRegenerate,
  });

  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onDiscard;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Regenerate',
                onPressed: saving ? null : onRegenerate,
                icon: const Icon(Icons.refresh),
              ),
              TextButton(
                onPressed: saving ? null : onDiscard,
                child: const Text('Discard'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: saving ? null : onSave,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bookmark_add_outlined, size: 18),
                label: const Text('Save to bucket'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
