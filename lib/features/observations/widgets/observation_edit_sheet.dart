import 'dart:io';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full editor for an observation. Opens after a teacher taps a saved
/// observation on the list — this is where tagging, tuning, and cleanup
/// happen. Capture stays minimal; tagging lives here.
class ObservationEditSheet extends ConsumerStatefulWidget {
  const ObservationEditSheet({required this.observation, super.key});

  final Observation observation;

  @override
  ConsumerState<ObservationEditSheet> createState() =>
      _ObservationEditSheetState();
}

class _ObservationEditSheetState extends ConsumerState<ObservationEditSheet> {
  late final _noteController =
      TextEditingController(text: widget.observation.note);
  late ObservationDomain _domain =
      ObservationDomain.fromName(widget.observation.domain);
  late ObservationSentiment _sentiment =
      ObservationSentiment.fromName(widget.observation.sentiment);
  final Set<String> _selectedKidIds = <String>{};
  bool _kidsLoaded = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadKids());
  }

  Future<void> _loadKids() async {
    final kids = await ref
        .read(observationsRepositoryProvider)
        .kidsForObservation(widget.observation.id);
    if (!mounted) return;
    setState(() {
      _selectedKidIds.addAll(kids.map((k) => k.id));
      _kidsLoaded = true;
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _submitting = true);
    await ref.read(observationsRepositoryProvider).updateObservation(
          id: widget.observation.id,
          note: _noteController.text.trim(),
          domain: _domain,
          sentiment: _sentiment,
          kidIds: _selectedKidIds.toList(),
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete observation?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(observationsRepositoryProvider)
        .deleteObservation(widget.observation.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);
    final kidsAsync = ref.watch(kidsProvider);
    final attachmentsAsync =
        ref.watch(observationAttachmentsProvider(widget.observation.id));

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
                    'Edit observation',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  tooltip: 'Delete',
                  onPressed: _delete,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              controller: _noteController,
              label: 'Note',
              maxLines: 6,
            ),
            attachmentsAsync.maybeWhen(
              data: (atts) => atts.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: _AttachmentStrip(attachments: atts),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Domain', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final d in ObservationDomain.values)
                  ChoiceChip(
                    label: Text(d.label),
                    selected: _domain == d,
                    onSelected: (_) => setState(() => _domain = d),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Sentiment', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<ObservationSentiment>(
              segments: const [
                ButtonSegment(
                  value: ObservationSentiment.positive,
                  label: Text('Positive'),
                  icon: Icon(Icons.sentiment_satisfied_outlined),
                ),
                ButtonSegment(
                  value: ObservationSentiment.neutral,
                  label: Text('Neutral'),
                  icon: Icon(Icons.sentiment_neutral_outlined),
                ),
                ButtonSegment(
                  value: ObservationSentiment.concern,
                  label: Text('Concern'),
                  icon: Icon(Icons.flag_outlined),
                ),
              ],
              selected: {_sentiment},
              onSelectionChanged: (s) =>
                  setState(() => _sentiment = s.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Kids tagged', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            kidsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text('Error: $err'),
              data: (kids) {
                if (!_kidsLoaded) return const LinearProgressIndicator();
                if (kids.isEmpty) {
                  return Text(
                    'No kids yet — add some in the Kids tab.',
                    style: theme.textTheme.bodySmall,
                  );
                }
                return Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final kid in kids)
                      FilterChip(
                        label: Text(_kidLabel(kid)),
                        selected: _selectedKidIds.contains(kid.id),
                        onSelected: (_) => setState(() {
                          if (!_selectedKidIds.add(kid.id)) {
                            _selectedKidIds.remove(kid.id);
                          }
                        }),
                      ),
                  ],
                );
              },
            ),
            if (widget.observation.activityLabel != null &&
                widget.observation.activityLabel!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Icon(
                    Icons.link,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Linked to: ${widget.observation.activityLabel}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppButton.primary(
              onPressed: _submitting ? null : _save,
              label: 'Save changes',
              isLoading: _submitting,
            ),
          ],
        ),
      ),
    );
  }

  String _kidLabel(Kid kid) {
    final last = kid.lastName;
    if (last == null || last.isEmpty) return kid.firstName;
    return '${kid.firstName} ${last[0]}.';
  }
}

class _AttachmentStrip extends StatelessWidget {
  const _AttachmentStrip({required this.attachments});

  final List<ObservationAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) {
          final att = attachments[i];
          return Container(
            width: 80,
            height: 80,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: att.kind == 'photo' && !kIsWeb
                ? Image.file(
                    File(att.localPath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Center(
                      child: Icon(
                        Icons.image_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Center(
                    child: Icon(
                      att.kind == 'video'
                          ? Icons.play_circle_outline
                          : Icons.image_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          );
        },
      ),
    );
  }
}
