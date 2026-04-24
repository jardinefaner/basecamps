import 'dart:async';
import 'dart:io';

import 'package:basecamp/features/observations/ai_classifier.dart';
import 'package:basecamp/features/observations/classifier.dart';
import 'package:basecamp/features/observations/observation_media_store.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/features/observations/voice_service.dart';
import 'package:basecamp/features/observations/widgets/multi_capture_camera.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/today/last_expanded_group.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// Minimal, focused capture surface. Text + voice + attachments + send —
/// nothing else on screen while the teacher is writing. Tagging (children,
/// domain, sentiment) happens later by tapping the saved entry in the
/// list above. The classifier still runs at submit time so the saved row
/// has sensible auto-tags the teacher can accept or override later.
///
/// [forActivity] locks the composer to a specific schedule item instead
/// of picking whichever activity happens to be running by the wall
/// clock. Opened from a hero card's Capture button → scoped to the
/// hero's activity; opened from a past-activity card's "log
/// observations" strip → scoped to THAT past occurrence, so the
/// resulting row has the right schedule-source-id + activity-date
/// even though it's no longer "now." Fresh FAB opens leave this null
/// and the composer falls back to current-time + selected-group
/// resolution.
///
/// [prefillChildIds] auto-links the saved observation to one or more
/// children via the `observation_children` join. Used when the
/// composer is opened from a child detail screen's "Log observation"
/// shortcut — the resulting row is already tagged to that child so
/// the teacher doesn't have to re-pick in the edit sheet. Defaults
/// to empty for fresh opens (no pre-tag).
///
/// [prefillGroupId] overrides the current-time + selected-group
/// resolution entirely and pins the observation's groupId to the
/// given value. Used when the composer is opened from a group
/// detail screen — the teacher is explicitly logging "about this
/// group" regardless of what activity is running or which chip is
/// expanded on Today. Null defers to the normal resolution.
class ObservationComposer extends ConsumerStatefulWidget {
  const ObservationComposer({
    this.forActivity,
    this.prefillChildIds = const [],
    this.prefillGroupId,
    super.key,
  });

  final ScheduleItem? forActivity;
  final List<String> prefillChildIds;
  final String? prefillGroupId;

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
    // Focus drives the Speak → Send flip: the moment the teacher taps
    // into the field the keyboard appears and the primary button should
    // already read "Send".
    _noteFocus.addListener(() => setState(() {}));
  }

  /// Three-way mode for the bottom row. See build() for the layout each
  /// state produces.
  _ComposerMode get _mode {
    if (_voiceActive) return _ComposerMode.recording;
    // Once there's content, or the field has focus, commit to Send mode
    // so "Speak" doesn't flash back in mid-typing.
    if (_hasContent || _noteFocus.hasFocus) return _ComposerMode.send;
    return _ComposerMode.speak;
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
    // Stop voice first so any lingering partials land in the note before
    // we read it. Teachers forget the mic is on — make Send do the
    // obvious right thing.
    if (_voiceActive) {
      await _stopVoice();
    }
    setState(() => _submitting = true);
    final currentActivity = _currentActivity();
    final note = _noteController.text.trim();
    // Save immediately with the local heuristic tags so the card shows up
    // without delay. If OpenAI is configured, we refine the tags in the
    // background once the classification call returns.
    final localSuggestion = suggestTags(note);
    final repo = ref.read(observationsRepositoryProvider);

    // Copy each attachment into the app-owned observation-media dir
    // before saving. That way the orphan-sweeper can recognize them
    // as ours and reap them when the attachment row is deleted. Web
    // short-circuits (no filesystem to own); `mediaDir` is null and
    // the original path is used as-is.
    final mediaDir = await ref.read(observationMediaDirProvider.future);
    final attachmentInputs = <ObservationAttachmentInput>[];
    for (final a in _attachments) {
      final storedPath = mediaDir == null
          ? a.path
          : await copyAttachmentToMediaDir(
              source: File(a.path),
              mediaDir: mediaDir,
            );
      attachmentInputs.add(
        ObservationAttachmentInput(kind: a.kind, localPath: storedPath),
      );
    }

    final observationId = await repo.addObservation(
      note: note,
      domains: localSuggestion.domains,
      sentiment: localSuggestion.sentiment,
      attachments: attachmentInputs,
      childIds: widget.prefillChildIds,
      activityLabel: currentActivity?.title,
      // Group resolution: prefillGroupId (from a group detail
      // capture) wins outright — the teacher said "this group" and
      // we honor that regardless of what's running. Otherwise, for
      // group-scoped activities (one concrete groupId) the link is
      // unambiguous. For program-wide activities (all-groups /
      // no-groups) fall back to the group the teacher most recently
      // looked at on Today — that's "their" group, and the
      // observation they're typing is almost always about that
      // group's instance of the activity. Absence of all three
      // leaves groupId null and the observation reads as
      // program-wide.
      groupId: widget.prefillGroupId ?? _resolveGroupId(currentActivity),
      // v33 structural activity context — pins the observation to
      // this specific occurrence so reports can ask "what happened
      // in Butterflies during Morning Circle on April 23?" by row id
      // instead of grepping activityLabel strings.
      scheduleSourceKind: currentActivity == null
          ? null
          : currentActivity.templateId != null
              ? 'template'
              : currentActivity.entryId != null
                  ? 'entry'
                  : null,
      scheduleSourceId:
          currentActivity?.templateId ?? currentActivity?.entryId,
      activityDate: currentActivity?.date,
      roomId: currentActivity?.roomId,
    );
    unawaited(_refineTagsWithAi(observationId, note));

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

  Future<void> _refineTagsWithAi(String observationId, String note) async {
    final refined = await classifyObservationWithAi(note);
    // Use ref (not the widget's context) — this widget may have been
    // disposed by the time the API call returns. Riverpod's ref stays
    // valid, the observation's row in the DB doesn't care about UI state.
    try {
      await ref.read(observationsRepositoryProvider).updateObservation(
            id: observationId,
            domains: refined.domains,
            sentiment: refined.sentiment,
          );
    } on Object {
      // Silent: the locally-suggested tags are still there, teacher
      // can override in the edit sheet.
    }
  }

  /// Resolves which activity the observation belongs to. Priority:
  ///   1. An explicit `widget.forActivity` passed by the caller (hero
  ///      Capture, past-card "log observations"). Locks the composer
  ///      to that occurrence regardless of wall-clock drift.
  ///   2. An activity currently running AND scoped to the selected
  ///      group chip (when multiple concurrent activities exist, the
  ///      one in the teacher's selected group wins).
  ///   3. Any activity currently running (first match) — legacy
  ///      fallback for fresh FAB opens with no group chip active.
  ///   4. null — composer saves as program-wide, no schedule link.
  ScheduleItem? _currentActivity() {
    if (widget.forActivity != null) return widget.forActivity;
    final schedule = ref.read(todayScheduleProvider).asData?.value;
    if (schedule == null) return null;
    final now = DateTime.now();
    final mins = now.hour * 60 + now.minute;
    final selectedGroup = ref.read(lastExpandedGroupProvider);
    ScheduleItem? firstMatch;
    for (final item in schedule) {
      if (item.isFullDay) continue;
      if (mins < item.startMinutes || mins >= item.endMinutes) continue;
      firstMatch ??= item;
      // Prefer the activity that actually belongs to the selected
      // group — two concurrent running activities (e.g. Butterflies'
      // Art and Sprouts' Music) should not silently cross-tag.
      if (selectedGroup != null &&
          !item.isAllGroups &&
          item.groupIds.contains(selectedGroup)) {
        return item;
      }
    }
    return firstMatch;
  }

  /// Resolves which group the observation belongs to, in priority
  /// order:
  ///   1. If the current activity is scoped to a single group, use it.
  ///   2. If the activity is program-wide (all-groups) OR there's no
  ///      current activity, fall back to the group the teacher last
  ///      expanded on Today. That's effectively "the group I work
  ///      with," self-trained from use.
  ///   3. Otherwise null — reads as program-wide.
  ///
  /// Multi-group-but-not-all activities (a combined Butterflies +
  /// Ladybugs block) fall through to the last-expanded fallback too,
  /// since neither group is more-correct and picking one silently
  /// would mis-tag the observation half the time.
  String? _resolveGroupId(ScheduleItem? activity) {
    if (activity != null && activity.groupIds.length == 1) {
      return activity.groupIds.first;
    }
    return ref.read(lastExpandedGroupProvider);
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
      _finalSub = session.finals.listen((text) {
        // A final replaces whatever was in the preview — clearing
        // `_livePartial` here is what prevents the safety-net append
        // on stop from doubling text Deepgram just flushed.
        _appendFinalTranscript(text);
        if (!mounted) return;
        setState(() => _livePartial = '');
      });
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

  /// Opens the in-app multi-capture camera. Teachers take as many
  /// photos and videos as they want in one session — pinch to zoom,
  /// toggle photo/video mode inline — and the whole batch lands as
  /// pending attachments when they tap Done.
  Future<void> _openCamera() async {
    try {
      final items = await MultiCaptureCamera.open(context);
      if (items.isEmpty || !mounted) return;
      setState(() {
        for (final m in items) {
          _attachments.add(_PendingAttachment(kind: m.kind, path: m.path));
        }
      });
    } on Object catch (e) {
      _snack("Couldn't open camera: $e");
    }
  }

  /// Gallery multi-pick — photos + videos in a single gesture. Each item
  /// is classified by file extension so we store the right `kind`.
  Future<void> _pickFromLibrary() async {
    try {
      final files = await _picker.pickMultipleMedia(
        imageQuality: 85,
        maxWidth: 2400,
      );
      if (files.isEmpty || !mounted) return;
      setState(() {
        for (final f in files) {
          _attachments.add(
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

  /// The bottom-row layout shifts based on [_mode]:
  /// * speak    — idle & empty: big "Speak" primary, no disabled Send.
  /// * recording — mic turned into a prominent red Stop with live caption.
  /// * send     — typing or post-voice: small mic beside camera, Send
  ///              primary (disabled only if there's truly nothing to send).
  Widget _buildActionRow(ThemeData theme) {
    final camera = IconButton(
      onPressed: _showAttachSheet,
      icon: const Icon(Icons.add_photo_alternate_outlined),
      tooltip: 'Attach photo or video',
    );

    switch (_mode) {
      case _ComposerMode.speak:
        return Row(
          key: const ValueKey('speak'),
          children: [
            camera,
            const Spacer(),
            FilledButton.icon(
              onPressed: _onMicPressed,
              icon: const Icon(Icons.mic_none_outlined, size: 18),
              label: const Text('Speak'),
            ),
          ],
        );
      case _ComposerMode.recording:
        return Row(
          key: const ValueKey('recording'),
          children: [
            camera,
            const Spacer(),
            FilledButton.icon(
              onPressed: _onMicPressed,
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.errorContainer,
                foregroundColor: theme.colorScheme.onErrorContainer,
              ),
              icon: const Icon(Icons.stop, size: 18),
              label: const Text('Stop'),
            ),
          ],
        );
      case _ComposerMode.send:
        return Row(
          key: const ValueKey('send'),
          children: [
            camera,
            IconButton(
              onPressed: _onMicPressed,
              icon: const Icon(Icons.mic_none_outlined),
              tooltip: 'Voice input',
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
        );
    }
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
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _buildActionRow(theme),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Which bottom-row layout the composer shows. Picked fresh every build
/// from controller content, focus state, and active voice session.
enum _ComposerMode { speak, recording, send }

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
                        // 68dp thumbnail × 2 for retina.
                        cacheWidth: 136,
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
