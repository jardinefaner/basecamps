import 'dart:async';
import 'dart:io';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/features/observations/widgets/attachment_viewer.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

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

  final _picker = ImagePicker();

  /// Ids of existing attachments the teacher removed in this edit session.
  /// Deleted when Save is tapped.
  final Set<String> _removedAttachmentIds = <String>{};

  /// New attachments added in this edit session. Inserted on Save.
  final List<_PendingAttachment> _newAttachments = [];

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
    final repo = ref.read(observationsRepositoryProvider);
    await repo.updateObservation(
      id: widget.observation.id,
      note: _noteController.text.trim(),
      domain: _domain,
      sentiment: _sentiment,
      kidIds: _selectedKidIds.toList(),
    );
    for (final id in _removedAttachmentIds) {
      await repo.deleteAttachment(id);
    }
    for (final a in _newAttachments) {
      await repo.addAttachment(
        observationId: widget.observation.id,
        input: ObservationAttachmentInput(kind: a.kind, localPath: a.path),
      );
    }
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

  Future<void> _takePhotoWithCamera() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2400,
      );
      if (file != null && mounted) {
        setState(() {
          _newAttachments.add(
            _PendingAttachment(kind: 'photo', path: file.path),
          );
        });
      }
    } on Object catch (e) {
      _snack("Couldn't attach photo: $e");
    }
  }

  Future<void> _recordVideoWithCamera() async {
    try {
      final file = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 5),
      );
      if (file != null && mounted) {
        setState(() {
          _newAttachments.add(
            _PendingAttachment(kind: 'video', path: file.path),
          );
        });
      }
    } on Object catch (e) {
      _snack("Couldn't attach video: $e");
    }
  }

  /// Gallery multi-pick — photos + videos in one pass. File extension
  /// decides which `kind` we save.
  Future<void> _pickFromLibrary() async {
    try {
      final files = await _picker.pickMultipleMedia(
        imageQuality: 85,
        maxWidth: 2400,
      );
      if (files.isEmpty || !mounted) return;
      setState(() {
        for (final f in files) {
          _newAttachments.add(
            _PendingAttachment(
              kind: _isVideoPath(f.path) ? 'video' : 'photo',
              path: f.path,
            ),
          );
        }
      });
    } on Object catch (e) {
      _snack("Couldn't attach media: $e");
    }
  }

  bool _isVideoPath(String p) {
    final l = p.toLowerCase();
    return const ['.mp4', '.mov', '.webm', '.m4v', '.avi', '.mkv', '.3gp']
        .any(l.endsWith);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showAttachSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!kIsWeb) ...[
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  unawaited(_takePhotoWithCamera());
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Record a video'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  unawaited(_recordVideoWithCamera());
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Pick from library'),
              subtitle: const Text('Select multiple photos and videos'),
              onTap: () {
                Navigator.of(ctx).pop();
                unawaited(_pickFromLibrary());
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kidsAsync = ref.watch(kidsProvider);
    final attachmentsAsync =
        ref.watch(observationAttachmentsProvider(widget.observation.id));

    return StickyActionSheet(
      title: 'Edit observation',
      titleTrailing: IconButton(
        icon: Icon(
          Icons.delete_outline,
          color: theme.colorScheme.error,
        ),
        tooltip: 'Delete',
        onPressed: _delete,
      ),
      actionBar: AppButton.primary(
        onPressed: _submitting ? null : _save,
        label: 'Save changes',
        isLoading: _submitting,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _noteController,
            label: 'Note',
            maxLines: 6,
          ),

          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Text('Attachments', style: theme.textTheme.titleSmall),
              ),
              IconButton(
                tooltip: 'Attach photo or video',
                icon: const Icon(Icons.add_photo_alternate_outlined),
                onPressed: _showAttachSheet,
              ),
            ],
          ),
          attachmentsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (err, _) => Text('Error: $err'),
            data: (existing) {
              final visibleExisting = existing
                  .where((a) => !_removedAttachmentIds.contains(a.id))
                  .toList();
              if (visibleExisting.isEmpty && _newAttachments.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'No attachments.',
                    style: theme.textTheme.bodySmall,
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: _EditableAttachmentStrip(
                  existing: visibleExisting,
                  pending: _newAttachments,
                  onRemoveExisting: (id) => setState(() {
                    _removedAttachmentIds.add(id);
                  }),
                  onRemovePending: (i) => setState(() {
                    _newAttachments.removeAt(i);
                  }),
                ),
              );
            },
          ),

          const SizedBox(height: AppSpacing.lg),
          Text('Domain', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          _DomainSelector(
            selected: _domain,
            onSelected: (d) => setState(() => _domain = d),
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
            onSelectionChanged: (s) => setState(() => _sentiment = s.first),
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
        ],
      ),
    );
  }

  String _kidLabel(Kid kid) {
    final last = kid.lastName;
    if (last == null || last.isEmpty) return kid.firstName;
    return '${kid.firstName} ${last[0]}.';
  }
}

class _PendingAttachment {
  _PendingAttachment({required this.kind, required this.path});
  final String kind;
  final String path;
}

class _DomainSelector extends StatelessWidget {
  const _DomainSelector({required this.selected, required this.onSelected});

  final ObservationDomain selected;
  final ValueChanged<ObservationDomain> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byCategory = <ObservationDomainCategory, List<ObservationDomain>>{};
    for (final d in ObservationDomain.values) {
      byCategory.putIfAbsent(d.category, () => []).add(d);
    }

    Widget section(ObservationDomainCategory cat) {
      final domains = byCategory[cat] ?? const [];
      if (domains.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cat.label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final d in domains)
                  ChoiceChip(
                    label: Text(
                      d == ObservationDomain.other
                          ? d.label
                          : '${d.code} · ${d.label}',
                    ),
                    selected: selected == d,
                    onSelected: (_) => onSelected(d),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        section(ObservationDomainCategory.socialSelfDev),
        section(ObservationDomainCategory.health),
        section(ObservationDomainCategory.other),
      ],
    );
  }
}

class _EditableAttachmentStrip extends StatelessWidget {
  const _EditableAttachmentStrip({
    required this.existing,
    required this.pending,
    required this.onRemoveExisting,
    required this.onRemovePending,
  });

  final List<ObservationAttachment> existing;
  final List<_PendingAttachment> pending;
  final ValueChanged<String> onRemoveExisting;
  final ValueChanged<int> onRemovePending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = existing.length + pending.length;
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: total,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final isExisting = i < existing.length;
          final kind = isExisting
              ? existing[i].kind
              : pending[i - existing.length].kind;
          final path = isExisting
              ? existing[i].localPath
              : pending[i - existing.length].path;
          final isPhoto = kind == 'photo';

          final thumb = Container(
            width: 80,
            height: 80,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: isPhoto && !kIsWeb
                ? Image.file(
                    File(path),
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
                      isPhoto
                          ? Icons.image_outlined
                          : Icons.play_circle_outline,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          );

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Only existing (saved) attachments open the full-screen
              // viewer on tap — pending ones live only in the edit sheet
              // until Save.
              if (isExisting)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => AttachmentViewer.open(
                    context,
                    existing,
                    initialIndex: i,
                  ),
                  child: thumb,
                )
              else
                thumb,
              if (!isExisting)
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'NEW',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: -4,
                right: -4,
                child: Material(
                  color: theme.colorScheme.surface,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: isExisting
                        ? () => onRemoveExisting(existing[i].id)
                        : () => onRemovePending(i - existing.length),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.cancel,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
