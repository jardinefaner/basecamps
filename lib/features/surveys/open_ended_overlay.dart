// Open-ended voice-answer overlay (Slice 3.5 + real-time STT).
//
// "WRITE or SAY OUT LOUD! At BASECamp this year, something I
// learned about being healthy is..." — TK-3rd grade kids can't
// reasonably type, so we capture their voice. **Live Deepgram
// streaming**: as the kid speaks, partials appear as faint gray
// text and finals lock in solid black. On stop, the concatenated
// finals are saved as the response's transcription.
//
// Mobile-only — `record`'s streaming bridge isn't available on
// the browser yet (same caveat as observations/voice_service.dart).
// On web we show a graceful "use a tablet" hint.
//
// Cost: live streaming is ~$0.0048/minute (Nova-2). 30-second
// answer ≈ 0.24¢. A 30-child classroom = ~7¢ per survey day.

import 'dart:async';

import 'package:basecamp/features/observations/voice_service.dart';
import 'package:basecamp/features/surveys/survey_audio_service.dart';
import 'package:basecamp/features/surveys/survey_models.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  /// Fires once the kid taps stop with a non-empty transcription.
  /// Caller writes the SurveyResponse and advances. Empty
  /// transcript → caller treats as Skip.
  final void Function(String transcription, int durationMs) onCommit;

  /// Skip the question without recording or transcribing.
  final VoidCallback onSkip;

  @override
  ConsumerState<OpenEndedQuestionOverlay> createState() =>
      _OpenEndedQuestionOverlayState();
}

class _OpenEndedQuestionOverlayState
    extends ConsumerState<OpenEndedQuestionOverlay> {
  static const _maxRecordingSec = 30;

  DeepgramVoiceSession? _session;
  StreamSubscription<String>? _partialSub;
  StreamSubscription<String>? _finalSub;
  StreamSubscription<Object>? _errorSub;

  /// Concatenated finalized transcripts. Each `final` event from
  /// Deepgram is a stable chunk — append in order, joined by a
  /// single space.
  final List<String> _finals = <String>[];

  /// Current in-flight partial. Replaced on each partial event,
  /// cleared when a final lands.
  String _partial = '';

  bool _recording = false;
  bool _busy = false; // true while starting / stopping
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  // Nullable on purpose — unset until the kid taps record.
  // ignore: use_late_for_private_fields_and_variables
  DateTime? _startedAt;
  String? _errorText;

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
    unawaited(_partialSub?.cancel());
    unawaited(_finalSub?.cancel());
    unawaited(_errorSub?.cancel());
    final s = _session;
    if (s != null) {
      unawaited(s.stop().then((_) => s.dispose()));
    }
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_busy) return;
    if (_recording) {
      await _stop();
    } else {
      await _start();
    }
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _errorText = null;
      _finals.clear();
      _partial = '';
    });
    final session = DeepgramVoiceSession();
    _partialSub = session.partials.listen((p) {
      if (!mounted) return;
      setState(() => _partial = p);
    });
    _finalSub = session.finals.listen((f) {
      if (!mounted) return;
      setState(() {
        _finals.add(f.trim());
        _partial = '';
      });
    });
    _errorSub = session.errors.listen((e) {
      if (!mounted) return;
      setState(() => _errorText = '$e');
    });
    try {
      await session.start();
    } on VoiceUnsupportedError catch (e) {
      _showError(e.message);
      await session.dispose();
      return;
    } on VoicePermissionError catch (e) {
      _showError(e.message);
      await session.dispose();
      return;
    } on VoiceConfigError catch (e) {
      _showError(e.message);
      await session.dispose();
      return;
    } on Object catch (e) {
      _showError("Couldn't start voice input: $e");
      await session.dispose();
      return;
    }
    if (!mounted) {
      await session.stop();
      await session.dispose();
      return;
    }
    _session = session;
    _startedAt = DateTime.now();
    setState(() {
      _busy = false;
      _recording = true;
      _elapsed = Duration.zero;
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || !_recording) return;
      final now = DateTime.now().difference(_startedAt!);
      setState(() => _elapsed = now);
      if (now.inSeconds >= _maxRecordingSec) {
        unawaited(_stop());
      }
    });
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    _ticker?.cancel();
    final session = _session;
    if (session != null) {
      try {
        await session.stop();
      } on Object {
        // Best-effort; we still surface whatever finals already
        // arrived.
      }
      await session.dispose();
      _session = null;
    }
    await _partialSub?.cancel();
    await _finalSub?.cancel();
    await _errorSub?.cancel();
    _partialSub = null;
    _finalSub = null;
    _errorSub = null;
    if (!mounted) return;
    final transcript = _composeTranscript();
    final duration = _elapsed.inMilliseconds;
    setState(() {
      _busy = false;
      _recording = false;
      _ticker = null;
    });
    if (transcript.isEmpty) {
      // Nothing transcribed — treat as a skip rather than
      // saving an empty row.
      widget.onSkip();
    } else {
      widget.onCommit(transcript, duration);
    }
  }

  String _composeTranscript() {
    final parts = <String>[..._finals];
    final p = _partial.trim();
    if (p.isNotEmpty) parts.add(p);
    return parts.join(' ').trim();
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _errorText = message;
      _busy = false;
      _recording = false;
    });
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
              _Prompt(
                prompt: widget.question.prompt,
                hint: _hintText(),
                error: _errorText,
                theme: theme,
              ),
              _TranscriptPreview(
                finals: _finals,
                partial: _partial,
                theme: theme,
              ),
              _MicButton(
                recording: _recording,
                busy: _busy,
                elapsed: _elapsed,
                maxSeconds: _maxRecordingSec,
                onTap: _toggle,
                theme: theme,
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _recording || _busy ? null : widget.onSkip,
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

  String _hintText() {
    if (_busy && !_recording) return 'Connecting...';
    if (_recording) return 'Listening — say it out loud, tap to finish.';
    return 'Tap the mic and say it out loud.';
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({
    required this.prompt,
    required this.hint,
    required this.error,
    required this.theme,
  });

  final String prompt;
  final String hint;
  final String? error;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          Icons.mic,
          size: 48,
          color: theme.colorScheme.outline,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          prompt,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          error ?? hint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: error != null
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Live transcript preview. Finals render in solid color (these
/// are what we save); the in-flight partial trails them in
/// faded gray (will become solid once Deepgram finalizes it).
class _TranscriptPreview extends StatelessWidget {
  const _TranscriptPreview({
    required this.finals,
    required this.partial,
    required this.theme,
  });

  final List<String> finals;
  final String partial;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final hasFinals = finals.isNotEmpty;
    final hasPartial = partial.trim().isNotEmpty;
    if (!hasFinals && !hasPartial) {
      return const SizedBox(height: 80);
    }
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 160),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        reverse: true,
        child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: theme.textTheme.titleMedium?.copyWith(height: 1.4),
            children: <InlineSpan>[
              if (hasFinals)
                TextSpan(
                  text: '${finals.join(' ')} ',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              if (hasPartial)
                TextSpan(
                  text: partial,
                  style: TextStyle(
                    color: theme.colorScheme.outline,
                    fontStyle: FontStyle.italic,
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
    required this.busy,
    required this.elapsed,
    required this.maxSeconds,
    required this.onTap,
    required this.theme,
  });

  final bool recording;
  final bool busy;
  final Duration elapsed;
  final int maxSeconds;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final progress =
        (elapsed.inMilliseconds / (maxSeconds * 1000)).clamp(0.0, 1.0);
    final secs = elapsed.inSeconds;
    final color = recording
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return Opacity(
      opacity: busy ? 0.6 : 1.0,
      child: InkWell(
        onTap: busy ? null : onTap,
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
                    backgroundColor: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.4),
                  ),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: recording ? 168 : 144,
                height: recording ? 168 : 144,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.30),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: busy
                      ? const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
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
