import 'dart:async';
import 'dart:io';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/observations/classifier.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/features/observations/voice_service.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// Chat-style capture. One editable thought per sheet: attachments up top
/// (thumbnails), a big text surface (auto-focused, grows as you type),
/// live voice-to-text partials underneath, and a fixed action dock at the
/// bottom with attach / voice / send plus auto-filled tag chips.
class ObservationSheet extends ConsumerStatefulWidget {
  const ObservationSheet({super.key, this.initialKidIds});

  final List<String>? initialKidIds;

  @override
  ConsumerState<ObservationSheet> createState() => _ObservationSheetState();
}

class _ObservationSheetState extends ConsumerState<ObservationSheet> {
  final _noteController = TextEditingController();
  final _noteFocus = FocusNode();
  final _picker = ImagePicker();

  late final Set<String> _selectedKidIds =
      (widget.initialKidIds ?? const <String>[]).toSet();
  ObservationDomain _domain = ObservationDomain.other;
  ObservationSentiment _sentiment = ObservationSentiment.neutral;
  bool _tagsAutoSet = true;
  bool _submitting = false;

  final List<_PendingAttachment> _attachments = [];

  DeepgramVoiceSession? _voice;
  bool _voiceActive = false;
  String _livePartial = '';
  StreamSubscription<String>? _finalSub;
  StreamSubscription<String>? _partialSub;
  StreamSubscription<Object>? _errorSub;

  bool get _hasContent =>
      _noteController.text.trim().isNotEmpty || _attachments.isNotEmpty;

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
    unawaited(_finalSub?.cancel());
    unawaited(_partialSub?.cancel());
    unawaited(_errorSub?.cancel());
    unawaited(_voice?.dispose());
    _noteController.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  void _onNoteChanged() {
    if (!_tagsAutoSet) {
      setState(() {}); // refresh Send enabled state
      return;
    }
    final suggestion = suggestTags(_noteController.text);
    if (suggestion.domain != _domain ||
        suggestion.sentiment != _sentiment) {
      setState(() {
        _domain = suggestion.domain;
        _sentiment = suggestion.sentiment;
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _submit() async {
    if (!_hasContent) return;
    setState(() => _submitting = true);
    final currentActivity = _currentActivity();
    await ref.read(observationsRepositoryProvider).addObservation(
          note: _noteController.text.trim(),
          domain: _domain,
          sentiment: _sentiment,
          kidIds: _selectedKidIds.toList(),
          attachments: _attachments
              .map(
                (a) => ObservationAttachmentInput(
                  kind: a.kind,
                  localPath: a.path,
                ),
              )
              .toList(),
          activityLabel: currentActivity?.title,
          podId: currentActivity != null && currentActivity.podIds.length == 1
              ? currentActivity.podIds.first
              : null,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

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

  // -- Voice --

  Future<void> _onMicPressed() async {
    if (_voiceActive) {
      await _stopVoice();
      return;
    }
    await _startVoice();
  }

  Future<void> _startVoice() async {
    final messenger = ScaffoldMessenger.of(context);
    final session = DeepgramVoiceSession();
    try {
      _finalSub = session.finals.listen(_appendFinalTranscript);
      _partialSub = session.partials.listen((p) {
        if (!mounted) return;
        setState(() => _livePartial = p);
      });
      _errorSub = session.errors.listen((err) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Voice error: $err')),
        );
      });
      await session.start();
      if (!mounted) {
        await session.dispose();
        return;
      }
      setState(() {
        _voice = session;
        _voiceActive = true;
        _livePartial = '';
      });
    } on VoiceUnsupportedError catch (e) {
      await _tearDownVoice(session);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on VoicePermissionError catch (e) {
      await _tearDownVoice(session);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on VoiceConfigError catch (e) {
      await _tearDownVoice(session);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on Object catch (e) {
      await _tearDownVoice(session);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't start voice: $e")),
      );
    }
  }

  Future<void> _stopVoice() async {
    final session = _voice;
    await session?.stop();
    if (_livePartial.isNotEmpty) _appendFinalTranscript(_livePartial);
    if (!mounted) return;
    setState(() {
      _voiceActive = false;
      _livePartial = '';
    });
  }

  Future<void> _tearDownVoice(DeepgramVoiceSession session) async {
    await _finalSub?.cancel();
    _finalSub = null;
    await _partialSub?.cancel();
    _partialSub = null;
    await _errorSub?.cancel();
    _errorSub = null;
    await session.dispose();
    if (!mounted) return;
    setState(() {
      _voice = null;
      _voiceActive = false;
      _livePartial = '';
    });
  }

  void _appendFinalTranscript(String text) {
    final existing = _noteController.text;
    final sep = existing.isEmpty || existing.endsWith(' ') ? '' : ' ';
    _noteController.text = '$existing$sep$text';
    _noteController.selection = TextSelection.collapsed(
      offset: _noteController.text.length,
    );
  }

  // -- Attachments --

  Future<void> _pickPhoto({required ImageSource source}) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2400,
      );
      if (file != null && mounted) {
        setState(() {
          _attachments.add(_PendingAttachment(kind: 'photo', path: file.path));
        });
      }
    } on Object catch (e) {
      _snack("Couldn't attach photo: $e");
    }
  }

  Future<void> _pickVideo({required ImageSource source}) async {
    try {
      final file = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 5),
      );
      if (file != null && mounted) {
        setState(() {
          _attachments.add(_PendingAttachment(kind: 'video', path: file.path));
        });
      }
    } on Object catch (e) {
      _snack("Couldn't attach video: $e");
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // -- Tag pickers --

  Future<void> _pickDomain() async {
    final picked = await showModalBottomSheet<ObservationDomain>(
      context: context,
      showDragHandle: true,
      builder: (_) => _DomainPicker(selected: _domain),
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
      builder: (_) => _SentimentPicker(selected: _sentiment),
    );
    if (picked != null) {
      setState(() {
        _sentiment = picked;
        _tagsAutoSet = false;
      });
    }
  }

  Future<void> _pickKids() async {
    final kids = ref.read(kidsProvider).asData?.value ?? const <Kid>[];
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _KidPicker(
        kids: kids,
        initial: _selectedKidIds,
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedKidIds
          ..clear()
          ..addAll(picked);
      });
    }
  }

  // -- Build --

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title row
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'New observation',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),

          // Scrollable content area
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CurrentActivityBanner(activity: _currentActivity()),
                  if (_attachments.isNotEmpty) ...[
                    _AttachmentCarousel(
                      attachments: _attachments,
                      onRemove: (i) =>
                          setState(() => _attachments.removeAt(i)),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  TextField(
                    controller: _noteController,
                    focusNode: _noteFocus,
                    minLines: 4,
                    maxLines: 12,
                    autofocus: true,
                    textInputAction: TextInputAction.newline,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(4000),
                    ],
                    decoration: const InputDecoration(
                      hintText: 'What happened? Tap the mic to dictate, or '
                          'add a photo/video.',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (_voiceActive)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Row(
                        children: [
                          Icon(
                            Icons.graphic_eq,
                            size: 14,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              _livePartial.isEmpty
                                  ? 'Listening…'
                                  : _livePartial,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),

          // Fixed bottom dock: tag chips + action row
          _BottomDock(
            domain: _domain,
            sentiment: _sentiment,
            isAuto: _tagsAutoSet,
            selectedKidIds: _selectedKidIds,
            onPickDomain: _pickDomain,
            onPickSentiment: _pickSentiment,
            onPickKids: _pickKids,
            onAttachPhoto: () => _showAttachSheet(photo: true),
            onAttachVideo: () => _showAttachSheet(photo: false),
            onMic: _onMicPressed,
            onSend: _hasContent && !_submitting ? _submit : null,
            voiceActive: _voiceActive,
            submitting: _submitting,
          ),
        ],
      ),
    );
  }

  Future<void> _showAttachSheet({required bool photo}) async {
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
                title: Text(photo ? 'Take a photo' : 'Record a video'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  if (photo) {
                    unawaited(_pickPhoto(source: ImageSource.camera));
                  } else {
                    unawaited(_pickVideo(source: ImageSource.camera));
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(photo ? 'Pick from library' : 'Pick a video'),
              onTap: () {
                Navigator.of(ctx).pop();
                if (photo) {
                  unawaited(_pickPhoto(source: ImageSource.gallery));
                } else {
                  unawaited(_pickVideo(source: ImageSource.gallery));
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingAttachment {
  _PendingAttachment({required this.kind, required this.path});
  final String kind; // 'photo' | 'video'
  final String path;
}

class _AttachmentCarousel extends StatelessWidget {
  const _AttachmentCarousel({
    required this.attachments,
    required this.onRemove,
  });

  final List<_PendingAttachment> attachments;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final att = attachments[i];
          return Stack(
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                clipBehavior: Clip.antiAlias,
                child: att.kind == 'photo' && !kIsWeb
                    ? Image.file(
                        File(att.path),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _AttachmentPlaceholder(
                          icon: Icons.image_outlined,
                        ),
                      )
                    : _AttachmentPlaceholder(
                        icon: att.kind == 'video'
                            ? Icons.play_circle_outline
                            : Icons.image_outlined,
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
                    onTap: () => onRemove(i),
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

class _AttachmentPlaceholder extends StatelessWidget {
  const _AttachmentPlaceholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

class _BottomDock extends ConsumerWidget {
  const _BottomDock({
    required this.domain,
    required this.sentiment,
    required this.isAuto,
    required this.selectedKidIds,
    required this.onPickDomain,
    required this.onPickSentiment,
    required this.onPickKids,
    required this.onAttachPhoto,
    required this.onAttachVideo,
    required this.onMic,
    required this.onSend,
    required this.voiceActive,
    required this.submitting,
  });

  final ObservationDomain domain;
  final ObservationSentiment sentiment;
  final bool isAuto;
  final Set<String> selectedKidIds;
  final VoidCallback onPickDomain;
  final VoidCallback onPickSentiment;
  final VoidCallback onPickKids;
  final Future<void> Function() onAttachPhoto;
  final Future<void> Function() onAttachVideo;
  final Future<void> Function() onMic;
  final VoidCallback? onSend;
  final bool voiceActive;
  final bool submitting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tag chips row (domain + sentiment + kids)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _TagPill(
                  icon: Icons.category_outlined,
                  label: isAuto ? '${domain.label} ·' : domain.label,
                  trailingLabel: isAuto ? 'auto' : null,
                  onTap: onPickDomain,
                ),
                const SizedBox(width: AppSpacing.sm),
                _TagPill(
                  icon: _sentimentIcon(sentiment),
                  label: sentiment.label,
                  color: _sentimentColor(context, sentiment),
                  onTap: onPickSentiment,
                ),
                const SizedBox(width: AppSpacing.sm),
                _KidsPill(
                  count: selectedKidIds.length,
                  onTap: onPickKids,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Action row
          Row(
            children: [
              IconButton(
                onPressed: onAttachPhoto,
                icon: const Icon(Icons.photo_camera_outlined),
                tooltip: 'Add photo',
              ),
              IconButton(
                onPressed: onAttachVideo,
                icon: const Icon(Icons.videocam_outlined),
                tooltip: 'Add video',
              ),
              IconButton(
                onPressed: onMic,
                style: voiceActive
                    ? IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.errorContainer,
                        foregroundColor: theme.colorScheme.onErrorContainer,
                      )
                    : null,
                icon: Icon(
                  voiceActive ? Icons.stop_circle : Icons.mic_none_outlined,
                ),
                tooltip: voiceActive ? 'Stop' : 'Voice input',
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: onSend,
                icon: submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_upward, size: 18),
                label: const Text('Send'),
              ),
            ],
          ),
        ],
      ),
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
    this.trailingLabel,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final String? trailingLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = color ?? theme.colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.outline,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: fg),
            ),
            if (trailingLabel != null) ...[
              const SizedBox(width: 4),
              Text(
                trailingLabel!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KidsPill extends StatelessWidget {
  const _KidsPill({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final empty = count == 0;
    final bg = empty
        ? theme.colorScheme.surfaceContainer
        : theme.colorScheme.primaryContainer;
    final fg = empty
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onPrimaryContainer;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: empty
                ? theme.colorScheme.outline
                : theme.colorScheme.primary,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_alt_outlined, size: 14, color: fg),
            const SizedBox(width: 4),
            Text(
              count == 0
                  ? 'Tag kids'
                  : count == 1
                      ? '1 kid'
                      : '$count kids',
              style: theme.textTheme.labelMedium?.copyWith(color: fg),
            ),
          ],
        ),
      ),
    );
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

class _KidPicker extends StatefulWidget {
  const _KidPicker({required this.kids, required this.initial});

  final List<Kid> kids;
  final Set<String> initial;

  @override
  State<_KidPicker> createState() => _KidPickerState();
}

class _KidPickerState extends State<_KidPicker> {
  late final Set<String> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.md,
        bottom: AppSpacing.xl + insets,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Tag kids', style: theme.textTheme.titleLarge),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(_selected),
                child: const Text('Done'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (widget.kids.isEmpty)
            Text(
              'No kids yet — add some in the Kids tab.',
              style: theme.textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final kid in widget.kids)
                  FilterChip(
                    label: Text(_kidLabel(kid)),
                    selected: _selected.contains(kid.id),
                    onSelected: (_) => setState(() {
                      if (!_selected.add(kid.id)) _selected.remove(kid.id);
                    }),
                  ),
              ],
            ),
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
