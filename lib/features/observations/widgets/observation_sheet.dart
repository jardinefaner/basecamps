import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/observations/classifier.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fast capture sheet. Type (voice input coming next commit) → tag kids →
/// accept or adjust suggested domain/sentiment → save. Domain and sentiment
/// are suggested automatically from the text via a local classifier and
/// shown as editable chips so the teacher's only required tap is kids.
class ObservationSheet extends ConsumerStatefulWidget {
  const ObservationSheet({super.key, this.initialKidIds});

  final List<String>? initialKidIds;

  @override
  ConsumerState<ObservationSheet> createState() => _ObservationSheetState();
}

class _ObservationSheetState extends ConsumerState<ObservationSheet> {
  final _noteController = TextEditingController();
  final _noteFocus = FocusNode();
  late final Set<String> _selectedKidIds =
      (widget.initialKidIds ?? const <String>[]).toSet();
  ObservationDomain _domain = ObservationDomain.other;
  ObservationSentiment _sentiment = ObservationSentiment.neutral;
  bool _tagsAutoSet = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _noteController.addListener(_onNoteChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _noteFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  void _onNoteChanged() {
    if (!_tagsAutoSet) return;
    final suggestion = suggestTags(_noteController.text);
    if (suggestion.domain != _domain ||
        suggestion.sentiment != _sentiment) {
      setState(() {
        _domain = suggestion.domain;
        _sentiment = suggestion.sentiment;
      });
    } else {
      setState(() {}); // keep the Save button's enabled state current
    }
  }

  bool get _isValid => _noteController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_isValid) return;
    setState(() => _submitting = true);
    final currentActivity = _currentActivity();
    await ref.read(observationsRepositoryProvider).addObservation(
          note: _noteController.text.trim(),
          domain: _domain,
          sentiment: _sentiment,
          kidIds: _selectedKidIds.toList(),
          activityLabel: currentActivity?.title,
          podId: currentActivity != null && currentActivity.podIds.length == 1
              ? currentActivity.podIds.first
              : null,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// Reads the Today schedule and returns the timed activity that contains
  /// "now" — the one the Today card badges as NOW. Returns null if no timed
  /// activity is running right now.
  ScheduleItem? _currentActivity() {
    final schedule = ref.read(todayScheduleProvider).asData?.value;
    if (schedule == null) return null;
    final now = DateTime.now();
    final mins = now.hour * 60 + now.minute;
    for (final item in schedule) {
      if (item.isFullDay) continue;
      if (mins >= item.startMinutes && mins < item.endMinutes) return item;
    }
    return null;
  }

  void _onMicPressed() {
    // Real voice-to-text lands in the next commit (needs native
    // permissions + speech_to_text package). For now, let the teacher
    // know the surface is there.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Voice input coming in the next update'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);
    final kidsAsync = ref.watch(kidsProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.md,
        bottom: AppSpacing.xl + insets,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'New observation',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Voice (coming soon)',
                  icon: const Icon(Icons.mic_none_outlined),
                  onPressed: _onMicPressed,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            _CurrentActivityBanner(
              activity: _currentActivity(),
            ),

            // Primary capture surface.
            TextField(
              controller: _noteController,
              focusNode: _noteFocus,
              minLines: 4,
              maxLines: 10,
              autofocus: true,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [
                LengthLimitingTextInputFormatter(2000),
              ],
              decoration: const InputDecoration(
                hintText:
                    "What happened? Just write it down — we'll help tag it.",
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            _SuggestedTagsRow(
              domain: _domain,
              sentiment: _sentiment,
              isAuto: _tagsAutoSet,
              onPickDomain: _pickDomain,
              onPickSentiment: _pickSentiment,
            ),
            const SizedBox(height: AppSpacing.lg),

            Text('Who was involved', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            kidsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text('Error: $err'),
              data: (kids) => _KidChipPicker(
                kids: kids,
                selectedIds: _selectedKidIds,
                onToggle: (id) => setState(() {
                  if (!_selectedKidIds.add(id)) _selectedKidIds.remove(id);
                }),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            AppButton.primary(
              onPressed: _isValid ? _submit : null,
              label: 'Save observation',
              isLoading: _submitting,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDomain() async {
    final picked = await showModalBottomSheet<ObservationDomain>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _DomainPicker(selected: _domain),
    );
    if (picked != null) {
      setState(() {
        _domain = picked;
        _tagsAutoSet = false;
      });
    }
  }

  Future<void> _pickSentiment() async {
    final picked = await showModalBottomSheet<ObservationSentiment>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _SentimentPicker(selected: _sentiment),
    );
    if (picked != null) {
      setState(() {
        _sentiment = picked;
        _tagsAutoSet = false;
      });
    }
  }
}

class _CurrentActivityBanner extends ConsumerWidget {
  const _CurrentActivityBanner({required this.activity});

  final ScheduleItem? activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (activity == null) return const SizedBox.shrink();
    final a = activity!;
    final parts = <String>[];
    if (a.podIds.isNotEmpty) {
      final names = <String>[];
      for (final podId in a.podIds) {
        final pod = ref.watch(podProvider(podId)).asData?.value;
        if (pod != null) names.add(pod.name);
      }
      if (names.isNotEmpty) parts.add(names.join(' + '));
    }
    if (a.location != null && a.location!.isNotEmpty) parts.add(a.location!);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'NOW',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                if (parts.isNotEmpty)
                  Text(
                    parts.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
              ],
            ),
          ),
          Tooltip(
            message: 'This observation will be linked to this activity',
            child: Icon(
              Icons.link,
              size: 16,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestedTagsRow extends StatelessWidget {
  const _SuggestedTagsRow({
    required this.domain,
    required this.sentiment,
    required this.isAuto,
    required this.onPickDomain,
    required this.onPickSentiment,
  });

  final ObservationDomain domain;
  final ObservationSentiment sentiment;
  final bool isAuto;
  final VoidCallback onPickDomain;
  final VoidCallback onPickSentiment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Tags', style: theme.textTheme.titleSmall),
            const SizedBox(width: AppSpacing.sm),
            if (isAuto)
              Text(
                '(auto)',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _TagPill(
                icon: Icons.category_outlined,
                label: domain.label,
                onTap: onPickDomain,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _TagPill(
                icon: _sentimentIcon(sentiment),
                label: sentiment.label,
                color: _sentimentColor(context, sentiment),
                onTap: onPickSentiment,
              ),
            ),
          ],
        ),
      ],
    );
  }

  IconData _sentimentIcon(ObservationSentiment s) => switch (s) {
        ObservationSentiment.positive => Icons.sentiment_satisfied_outlined,
        ObservationSentiment.neutral => Icons.sentiment_neutral_outlined,
        ObservationSentiment.concern => Icons.flag_outlined,
      };

  Color? _sentimentColor(BuildContext context, ObservationSentiment s) {
    final theme = Theme.of(context);
    return switch (s) {
      ObservationSentiment.positive => theme.colorScheme.primary,
      ObservationSentiment.neutral => null,
      ObservationSentiment.concern => theme.colorScheme.error,
    };
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = color ?? theme.colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outline,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(color: fg),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.expand_more,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _KidChipPicker extends StatelessWidget {
  const _KidChipPicker({
    required this.kids,
    required this.selectedIds,
    required this.onToggle,
  });

  final List<Kid> kids;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    if (kids.isEmpty) {
      return Text(
        'No kids yet — add some in the Kids tab.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final kid in kids)
          FilterChip(
            label: Text(_kidLabel(kid)),
            selected: selectedIds.contains(kid.id),
            onSelected: (_) => onToggle(kid.id),
          ),
      ],
    );
  }

  String _kidLabel(Kid kid) {
    final last = kid.lastName;
    if (last == null || last.isEmpty) return kid.firstName;
    return '${kid.firstName} ${last[0]}.';
  }
}

class _DomainPicker extends StatelessWidget {
  const _DomainPicker({required this.selected});

  final ObservationDomain selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Domain', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final d in ObservationDomain.values)
                ChoiceChip(
                  label: Text(d.label),
                  selected: d == selected,
                  onSelected: (_) => Navigator.of(context).pop(d),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SentimentPicker extends StatelessWidget {
  const _SentimentPicker({required this.selected});

  final ObservationSentiment selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Sentiment', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final s in ObservationSentiment.values)
                ChoiceChip(
                  label: Text(s.label),
                  selected: s == selected,
                  onSelected: (_) => Navigator.of(context).pop(s),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
