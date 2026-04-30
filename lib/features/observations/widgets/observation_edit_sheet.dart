import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/observations/observation_media_store.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/features/observations/widgets/attachment_viewer.dart';
import 'package:basecamp/features/observations/widgets/multi_capture_camera.dart';
import 'package:basecamp/features/observations/widgets/refineable_note_editor.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/media_image.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:basecamp/ui/undo_delete.dart';
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

  /// Domains selected by the teacher, order preserved (first = primary).
  /// Populated from the DB after [_loadDomains] — seeded with the legacy
  /// single-domain column so the UI isn't empty for one frame.
  late final List<ObservationDomain> _domains = [
    ObservationDomain.fromName(widget.observation.domain),
  ];
  bool _domainsLoaded = false;

  late ObservationSentiment _sentiment =
      ObservationSentiment.fromName(widget.observation.sentiment);
  final Set<String> _selectedChildIds = <String>{};
  bool _childrenLoaded = false;
  bool _submitting = false;

  final _picker = ImagePicker();

  /// Ids of existing attachments the teacher removed in this edit session.
  /// Deleted when Save is tapped.
  final Set<String> _removedAttachmentIds = <String>{};

  /// New attachments added in this edit session. Inserted on Save.
  final List<_PendingAttachment> _newAttachments = [];

  /// Snapshot of the child set that loaded with the observation —
  /// lets us distinguish a pristine edit from a real change.
  Set<String> _childrenBaseline = const <String>{};

  /// Same for the domain list (order preserved).
  List<ObservationDomain> _domainsBaseline = const [];

  /// Latest value the refineable editor told us to persist as
  /// `note_original`. Seeded from the observation so a pristine open
  /// matches what's already stored. `null` means "drop it" (teacher went
  /// back to Original or never refined); a string means the refined
  /// version is active and we should preserve this pre-refine text on
  /// save.
  late String? _preservedOriginal = widget.observation.noteOriginal;

  bool get _hasChanges {
    if (_noteController.text.trim() != widget.observation.note) return true;
    if (_preservedOriginal != widget.observation.noteOriginal) return true;
    if (_sentiment !=
        ObservationSentiment.fromName(widget.observation.sentiment)) {
      return true;
    }
    if (_removedAttachmentIds.isNotEmpty) return true;
    if (_newAttachments.isNotEmpty) return true;
    if (_childrenLoaded) {
      if (_selectedChildIds.length != _childrenBaseline.length) return true;
      if (!_selectedChildIds.containsAll(_childrenBaseline)) return true;
    }
    if (_domainsLoaded) {
      if (_domains.length != _domainsBaseline.length) return true;
      for (var i = 0; i < _domains.length; i++) {
        if (_domains[i] != _domainsBaseline[i]) return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadKids());
      unawaited(_loadDomains());
    });
  }

  Future<void> _loadKids() async {
    final children = await ref
        .read(observationsRepositoryProvider)
        .childrenForObservation(widget.observation.id);
    if (!mounted) return;
    setState(() {
      final ids = children.map((k) => k.id).toSet();
      _selectedChildIds.addAll(ids);
      _childrenBaseline = Set<String>.from(ids);
      _childrenLoaded = true;
    });
  }

  Future<void> _loadDomains() async {
    final fromDb = await ref
        .read(observationsRepositoryProvider)
        .domainsForObservation(widget.observation.id);
    if (!mounted) return;
    setState(() {
      if (fromDb.isNotEmpty) {
        _domains
          ..clear()
          ..addAll(fromDb);
      }
      _domainsBaseline = List<ObservationDomain>.from(_domains);
      _domainsLoaded = true;
    });
  }

  void _toggleDomain(ObservationDomain d) {
    setState(() {
      if (_domains.contains(d)) {
        // Guard against clearing to empty — at least one domain is
        // required; just keep the last one.
        if (_domains.length > 1) _domains.remove(d);
      } else {
        _domains.add(d);
      }
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
    // Non-destructive refine: persist the Original snapshot whenever
    // there's one to preserve. We only drop it when the teacher truly
    // reverted — the final in-use note equals the Original text, so
    // there's no refined version left to preserve.
    final preserved = _preservedOriginal;
    final finalNote = _noteController.text.trim();
    final reverted =
        preserved != null && preserved.trim() == finalNote;
    final shouldClear = preserved == null || reverted;
    await repo.updateObservation(
      id: widget.observation.id,
      note: finalNote,
      noteOriginal: shouldClear ? null : preserved,
      clearNoteOriginal: shouldClear,
      domains: _domains.toList(),
      sentiment: _sentiment,
      childIds: _selectedChildIds.toList(),
    );
    for (final id in _removedAttachmentIds) {
      await repo.deleteAttachment(id);
    }
    // Copy new attachments into the app-owned media dir first so
    // the orphan sweeper recognizes them as ours when their row is
    // eventually deleted. Web skips the copy (no filesystem to
    // own) — the picker's XFile rides through to the upload step
    // for cloud storage.
    final mediaDir = await ref.read(observationMediaDirProvider.future);
    for (final a in _newAttachments) {
      final storedPath = mediaDir == null
          ? '' // web: no on-device path; render goes through storage_path
          : await copyAttachmentToMediaDir(
              source: a.source,
              mediaDir: mediaDir,
            );
      await repo.addAttachment(
        observationId: widget.observation.id,
        input: ObservationAttachmentInput(
          kind: a.kind,
          localPath: storedPath,
          source: a.source,
        ),
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final repo = ref.read(observationsRepositoryProvider);
    final id = widget.observation.id;
    final snapshot = await repo.snapshotObservation(id);
    if (snapshot.isEmpty || !mounted) return;
    final navigator = Navigator.of(context);
    final confirmed = await confirmDeleteWithUndo(
      context: context,
      title: 'Delete observation?',
      message: "You'll get a 5-second window to undo.",
      onDelete: () => repo.deleteObservation(id),
      undoLabel: 'Observation removed',
      onUndo: () => repo.restoreObservations(snapshot),
    );
    if (!confirmed) return;
    navigator.pop();
  }

  /// Opens the in-app multi-capture camera. Same flow as the composer:
  /// stay open between shots, Photo/Video toggle, pinch to zoom.
  Future<void> _openCamera() async {
    try {
      final items = await MultiCaptureCamera.open(context);
      if (items.isEmpty || !mounted) return;
      setState(() {
        for (final m in items) {
          _newAttachments.add(
            _PendingAttachment(kind: m.kind, source: XFile(m.path)),
          );
        }
      });
    } on Object catch (e) {
      _snack("Couldn't open camera: $e");
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
              kind: _isVideoXFile(f) ? 'video' : 'photo',
              source: f,
            ),
          );
        }
      });
    } on Object catch (e) {
      _snack("Couldn't attach media: $e");
    }
  }

  bool _isVideoXFile(XFile f) {
    final mime = f.mimeType?.toLowerCase();
    if (mime != null && mime.startsWith('video/')) return true;
    final candidates = [f.name.toLowerCase(), f.path.toLowerCase()];
    const videoExt = [
      '.mp4',
      '.mov',
      '.webm',
      '.m4v',
      '.avi',
      '.mkv',
      '.3gp',
    ];
    for (final c in candidates) {
      if (videoExt.any(c.endsWith)) return true;
    }
    return false;
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
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Open camera'),
                subtitle: const Text(
                  'Stay in — snap multiple photos, record video, pinch to zoom',
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  unawaited(_openCamera());
                },
              ),
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
    final kidsAsync = ref.watch(childrenProvider);
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
        onPressed: _submitting || !_hasChanges ? null : _save,
        label: 'Save changes',
        isLoading: _submitting,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RefineableNoteEditor(
            controller: _noteController,
            label: 'Note',
            initialOriginal: widget.observation.noteOriginal,
            onChanged: (_) => setState(() {}),
            onPreservedOriginalChanged: (value) => setState(() {
              _preservedOriginal = value;
            }),
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
          Row(
            children: [
              Expanded(
                child: Text('Domains', style: theme.textTheme.titleSmall),
              ),
              if (_domainsLoaded)
                Text(
                  '${_domains.length} selected',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _DomainSelector(
            selected: _domains.toSet(),
            onToggle: _toggleDomain,
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
          Text('Children tagged', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          kidsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (err, _) => Text('Error: $err'),
            data: (children) {
              if (!_childrenLoaded) return const LinearProgressIndicator();
              if (children.isEmpty) {
                return Text(
                  'No children yet — add some in the Children tab.',
                  style: theme.textTheme.bodySmall,
                );
              }
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final child in children)
                    FilterChip(
                      label: Text(_kidLabel(child)),
                      selected: _selectedChildIds.contains(child.id),
                      onSelected: (_) => setState(() {
                        if (!_selectedChildIds.add(child.id)) {
                          _selectedChildIds.remove(child.id);
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

  String _kidLabel(Child child) {
    final last = child.lastName;
    if (last == null || last.isEmpty) return child.firstName;
    return '${child.firstName} ${last[0]}.';
  }
}

class _PendingAttachment {
  _PendingAttachment({required this.kind, required this.source});
  final String kind;

  /// The picker's [XFile]. Held so the preview can read bytes via
  /// [XFile.readAsBytes] (works on every platform, including web
  /// where the underlying path is a `blob:` URL) and so the upload
  /// step has the same handle to stream into Storage.
  final XFile source;
}

class _DomainSelector extends StatelessWidget {
  const _DomainSelector({required this.selected, required this.onToggle});

  final Set<ObservationDomain> selected;
  final ValueChanged<ObservationDomain> onToggle;

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
                  FilterChip(
                    label: Text(
                      d == ObservationDomain.other
                          ? d.label
                          : '${d.code} · ${d.label}',
                    ),
                    selected: selected.contains(d),
                    onSelected: (_) => onToggle(d),
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
          final isPhoto = kind == 'photo';
          // For SAVED attachments (isExisting), route through the
          // shared MediaImage pipeline so cross-device sync works
          // — the same pattern every other observation surface
          // uses. PENDING (unsaved) attachments render directly
          // from the picker's [XFile] via [_PendingPhotoThumb] so
          // web previews work too (Image.file can't open a `blob:`
          // URL).
          final pendingSource =
              isExisting ? null : pending[i - existing.length].source;

          final thumb = Container(
            width: 80,
            height: 80,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: !isPhoto
                ? Center(
                    child: Icon(
                      Icons.play_circle_outline,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : isExisting
                    ? MediaImage(
                        source: MediaSource(
                          localPath: existing[i].localPath,
                          storagePath: existing[i].storagePath,
                        ),
                        cacheWidth: 160, // 80dp × 2 retina
                        errorPlaceholder: Center(
                          child: Icon(
                            Icons.image_outlined,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : _PendingPhotoThumb(source: pendingSource!),
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
                    // The edit sheet stages removals and commits them
                    // on Save so the teacher can still cancel — mirror
                    // that here by routing through the same remove
                    // callback instead of calling the repo directly.
                    onDelete: (a) async => onRemoveExisting(a.id),
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

/// Renders a freshly-picked photo via `Image.memory`. Reads bytes
/// from the [XFile] once on first build; the result is cached in
/// state so a rebuild (e.g. removing a sibling) doesn't re-decode.
/// Works on every platform — `XFile.readAsBytes()` abstracts the
/// file-vs-blob distinction that breaks `Image.file` on web.
class _PendingPhotoThumb extends StatefulWidget {
  const _PendingPhotoThumb({required this.source});

  final XFile source;

  @override
  State<_PendingPhotoThumb> createState() => _PendingPhotoThumbState();
}

class _PendingPhotoThumbState extends State<_PendingPhotoThumb> {
  late final Future<Uint8List> _bytes = widget.source.readAsBytes();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty || snap.hasError) {
          return Center(
            child: Icon(
              Icons.image_outlined,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          cacheWidth: 160, // 80dp × 2 retina
          errorBuilder: (_, _, _) => Center(
            child: Icon(
              Icons.image_outlined,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }
}
