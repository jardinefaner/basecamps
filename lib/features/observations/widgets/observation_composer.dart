import 'dart:async';
import 'dart:io';

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

/// Minimal, focused capture surface. Text + voice + attachments + send —
/// nothing else on screen while the teacher is writing. Tagging (kids,
/// domain, sentiment) happens later by tapping the saved entry in the
/// list above. The classifier still runs at submit time so the saved row
/// has sensible auto-tags the teacher can accept or override later.
class ObservationComposer extends ConsumerStatefulWidget {
  const ObservationComposer({super.key});

  @override
  ConsumerState<ObservationComposer> createState() =>
      _ObservationComposerState();
}

class _ObservationComposerState extends ConsumerState<ObservationComposer> {
  final _noteController = TextEditingController();
  final _noteFocus = FocusNode();
  final _picker = ImagePicker();

  final List<_PendingAttachment> _attachments = [];
  bool _submitting = false;

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
    _noteController.addListener(() => setState(() {}));
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

  Future<void> _submit() async {
    if (!_hasContent) return;
    setState(() => _submitting = true);
    final currentActivity = _currentActivity();
    final note = _noteController.text.trim();
    final suggestion = suggestTags(note);
    await ref.read(observationsRepositoryProvider).addObservation(
          note: note,
          domain: suggestion.domain,
          sentiment: suggestion.sentiment,
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
    _noteController.clear();
    setState(() {
      _attachments.clear();
      _submitting = false;
      _livePartial = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved — tap the entry above to tag or edit.'),
        duration: Duration(seconds: 2),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant,
              width: 0.5,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  0,
                ),
                child: _AttachmentCarousel(
                  attachments: _attachments,
                  onRemove: (i) => setState(() => _attachments.removeAt(i)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                0,
              ),
              child: TextField(
                controller: _noteController,
                focusNode: _noteFocus,
                minLines: 1,
                maxLines: 6,
                textInputAction: TextInputAction.newline,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(4000),
                ],
                decoration: const InputDecoration(
                  hintText: 'Capture a moment…',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (_voiceActive)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  0,
                ),
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
                        _livePartial.isEmpty ? 'Listening…' : _livePartial,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => _showAttachSheet(photo: true),
                    icon: const Icon(Icons.photo_camera_outlined),
                    tooltip: 'Add photo',
                  ),
                  IconButton(
                    onPressed: () => _showAttachSheet(photo: false),
                    icon: const Icon(Icons.videocam_outlined),
                    tooltip: 'Add video',
                  ),
                  IconButton(
                    onPressed: _onMicPressed,
                    style: _voiceActive
                        ? IconButton.styleFrom(
                            backgroundColor: theme.colorScheme.errorContainer,
                            foregroundColor:
                                theme.colorScheme.onErrorContainer,
                          )
                        : null,
                    icon: Icon(
                      _voiceActive ? Icons.stop : Icons.mic_none_outlined,
                    ),
                    tooltip: _voiceActive ? 'Stop' : 'Voice input',
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _hasContent && !_submitting ? _submit : null,
                    icon: _submitting
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
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingAttachment {
  _PendingAttachment({required this.kind, required this.path});
  final String kind;
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
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final att = attachments[i];
          return Stack(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                clipBehavior: Clip.antiAlias,
                child: att.kind == 'photo' && !kIsWeb
                    ? Image.file(
                        File(att.path),
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
                        size: 18,
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
