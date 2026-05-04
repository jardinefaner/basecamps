// Open-ended voice-answer overlay (Slice 3.5).
//
// "WRITE or SAY OUT LOUD! At BASECamp this year, something I
// learned about being healthy is..." — TK-3rd grade kids can't
// reasonably type, so we capture their voice. Tap mic to start,
// tap again (or hit auto-stop) to commit. The recorded WAV is
// saved with the response so the teacher can always re-listen
// from the results sheet, and a Deepgram transcription drops
// into the row in the background once it lands.
//
// Mobile-only for the recording side — the `record` package's
// browser bridge isn't there yet (same caveat as
// observations/voice_service.dart). On web we show a graceful
// "use a tablet" hint with a Skip button.
//
// Audio cost: 30s @ Nova-2 prerecorded = ~0.2¢ per child.

import 'dart:async';
import 'dart:io';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/features/surveys/survey_audio_service.dart';
import 'package:basecamp/features/surveys/survey_models.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class OpenEndedQuestionOverlay extends ConsumerStatefulWidget {
  const OpenEndedQuestionOverlay({
    required this.question,
    required this.voice,
    required this.audioMode,
    required this.onCommit,
    required this.onSkip,
    super.key,
  });

  final SurveyQuestion question;
  final SurveyVoice voice;
  final SurveyAudioMode audioMode;

  /// Fires once the WAV is on disk. The caller writes the
  /// SurveyResponse and (optionally) kicks off background STT.
  /// `relativePath` is the path within the app docs folder so it
  /// stays portable across iOS app reinstalls.
  final void Function(String relativePath, int durationMs) onCommit;

  /// Skip the question without recording anything.
  final VoidCallback onSkip;

  @override
  ConsumerState<OpenEndedQuestionOverlay> createState() =>
      _OpenEndedQuestionOverlayState();
}

class _OpenEndedQuestionOverlayState
    extends ConsumerState<OpenEndedQuestionOverlay> {
  static const _maxRecordingSec = 30;

  late final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  // Nullable on purpose — these are unset before the kid taps
  // record. `late` would force a setter-before-getter contract
  // we don't want.
  // ignore: use_late_for_private_fields_and_variables
  DateTime? _startedAt;
  String? _activeFilePath;

  @override
  void initState() {
    super.initState();
    if (widget.audioMode != SurveyAudioMode.silent) {
      final audio = ref.read(surveyAudioServiceProvider);
      unawaited(audio.playQuestion(widget.voice, widget.question.prompt));
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (_recording) {
      // Best-effort: stop + drop the partial recording on
      // teardown (e.g. teacher exits while a kid is mid-record).
      unawaited(_recorder.stop());
    }
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stop();
    } else {
      await _start();
    }
  }

  Future<void> _start() async {
    if (kIsWeb) return; // platform-gate; Skip is the path
    if (!await _recorder.hasPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mic permission needed to record an answer.'),
        ),
      );
      return;
    }
    final docsDir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(docsDir.path, 'survey_audio'));
    if (!folder.existsSync()) {
      await folder.create(recursive: true);
    }
    final filename = '${newId()}.m4a';
    final fullPath = p.join(folder.path, filename);
    await _recorder.start(
      const RecordConfig(sampleRate: 16000),
      path: fullPath,
    );
    _startedAt = DateTime.now();
    setState(() {
      _recording = true;
      _activeFilePath = fullPath;
      _elapsed = Duration.zero;
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || !_recording) return;
      final newElapsed = DateTime.now().difference(_startedAt!);
      setState(() => _elapsed = newElapsed);
      if (newElapsed.inSeconds >= _maxRecordingSec) {
        // Auto-stop at 30s.
        unawaited(_stop());
      }
    });
  }

  Future<void> _stop() async {
    final stoppedAtPath = await _recorder.stop();
    _ticker?.cancel();
    if (!mounted) return;
    final filePath = stoppedAtPath ?? _activeFilePath;
    final durationMs = _elapsed.inMilliseconds;
    setState(() {
      _recording = false;
      _ticker = null;
    });
    if (filePath == null) return;
    // Save the path RELATIVE to the docs folder so the response
    // row stays meaningful across iOS app reinstalls (where the
    // docs folder is at a different absolute path each install).
    final docsDir = await getApplicationDocumentsDirectory();
    final relative = p.relative(filePath, from: docsDir.path);
    if (!mounted) return;
    widget.onCommit(relative, durationMs);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (kIsWeb) {
      return _WebUnsupported(
        prompt: widget.question.prompt,
        onSkip: widget.onSkip,
        theme: theme,
      );
    }
    return ColoredBox(
      color: theme.colorScheme.surface.withValues(alpha: 0.97),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox.shrink(),
              Column(
                children: [
                  Icon(
                    Icons.mic,
                    size: 48,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    widget.question.prompt,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _recording
                        ? 'Listening… tap the mic when you are done.'
                        : 'Tap the mic and say it out loud.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              _MicButton(
                recording: _recording,
                elapsed: _elapsed,
                maxSeconds: _maxRecordingSec,
                onTap: _toggleRecording,
                theme: theme,
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _recording ? null : widget.onSkip,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: const Text('Skip'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.recording,
    required this.elapsed,
    required this.maxSeconds,
    required this.onTap,
    required this.theme,
  });

  final bool recording;
  final Duration elapsed;
  final int maxSeconds;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final progress = (elapsed.inMilliseconds / (maxSeconds * 1000))
        .clamp(0.0, 1.0);
    final secs = elapsed.inSeconds;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(120),
      child: SizedBox(
        width: 200,
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (recording)
              SizedBox(
                width: 200,
                height: 200,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 4,
                  color: theme.colorScheme.primary,
                  backgroundColor:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: recording ? 168 : 144,
              height: recording ? 168 : 144,
              decoration: BoxDecoration(
                color: recording
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (recording
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary)
                        .withValues(alpha: 0.30),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  recording ? Icons.stop_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: recording ? 56 : 64,
                ),
              ),
            ),
            if (recording)
              Positioned(
                bottom: 0,
                child: Text(
                  '${secs}s / ${maxSeconds}s',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WebUnsupported extends StatelessWidget {
  const _WebUnsupported({
    required this.prompt,
    required this.onSkip,
    required this.theme,
  });

  final String prompt;
  final VoidCallback onSkip;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: theme.colorScheme.surface.withValues(alpha: 0.97),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.mic_off_outlined,
                  size: 56,
                  color: theme.colorScheme.outlineVariant,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  prompt,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  "Voice answers aren't supported in the web build yet. "
                  'Use the iPad app to record this one.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: onSkip,
                  child: const Text('Skip for now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
