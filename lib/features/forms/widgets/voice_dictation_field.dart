import 'dart:async';

import 'package:basecamp/features/observations/voice_service.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A multiline text field with a mic button in the bottom-right that
/// runs live Deepgram dictation into the controller. Final snippets
/// append to whatever's already there; interim text is shown as a
/// faded overlay at the bottom of the field so the teacher can watch
/// the recognition stream without it landing in the note until it's
/// confirmed.
///
/// Uses the same [DeepgramVoiceSession] wired into the observation
/// composer — one shared voice path for the whole app.
class VoiceDictationField extends StatefulWidget {
  const VoiceDictationField({
    required this.controller,
    this.hint,
    this.minLines = 4,
    this.maxLines = 10,
    super.key,
  });

  final TextEditingController controller;
  final String? hint;
  final int minLines;
  final int maxLines;

  @override
  State<VoiceDictationField> createState() => _VoiceDictationFieldState();
}

class _VoiceDictationFieldState extends State<VoiceDictationField> {
  DeepgramVoiceSession? _voice;
  bool _voiceActive = false;
  String _partial = '';
  StreamSubscription<String>? _finalSub;
  StreamSubscription<String>? _partialSub;
  StreamSubscription<Object>? _errorSub;

  @override
  void dispose() {
    unawaited(_finalSub?.cancel());
    unawaited(_partialSub?.cancel());
    unawaited(_errorSub?.cancel());
    unawaited(_voice?.dispose());
    super.dispose();
  }

  Future<void> _toggleVoice() async {
    if (_voiceActive) {
      await _stop();
    } else {
      await _start();
    }
  }

  Future<void> _start() async {
    final messenger = ScaffoldMessenger.of(context);
    final session = DeepgramVoiceSession();
    try {
      _finalSub = session.finals.listen((text) {
        // A final replaces whatever was in the preview — clearing
        // `_partial` here is what prevents the safety-net append on
        // stop from doubling the text Deepgram just flushed. The
        // preview is "what's pending for the NEXT final", not "what
        // Deepgram already committed."
        _appendFinal(text);
        if (!mounted) return;
        setState(() => _partial = '');
      });
      _partialSub = session.partials.listen((p) {
        if (!mounted) return;
        setState(() => _partial = p);
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
        _partial = '';
      });
    } on VoiceUnsupportedError catch (e) {
      await _teardown(session);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on VoicePermissionError catch (e) {
      await _teardown(session);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on VoiceConfigError catch (e) {
      await _teardown(session);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on Object catch (e) {
      await _teardown(session);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't start voice: $e")),
      );
    }
  }

  Future<void> _stop() async {
    final session = _voice;
    await session?.stop();
    if (_partial.isNotEmpty) _appendFinal(_partial);
    if (!mounted) return;
    setState(() {
      _voiceActive = false;
      _partial = '';
    });
  }

  Future<void> _teardown(DeepgramVoiceSession session) async {
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
      _partial = '';
    });
  }

  void _appendFinal(String text) {
    final existing = widget.controller.text;
    final sep =
        existing.isEmpty || existing.endsWith(' ') || existing.endsWith('\n')
            ? ''
            : ' ';
    widget.controller.text = '$existing$sep$text';
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        TextField(
          controller: widget.controller,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: widget.hint,
            // Pad the bottom so text never runs under the mic button —
            // skipped on web since the mic isn't drawn there.
            contentPadding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              kIsWeb ? AppSpacing.md : AppSpacing.xxxl,
            ),
          ),
        ),

        // Live partial transcript — faded, bottom-left.
        if (_voiceActive)
          Positioned(
            left: AppSpacing.md,
            right: 64,
            bottom: AppSpacing.sm,
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
                    _partial.isEmpty ? 'Listening…' : _partial,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Mic button, bottom-right. Skipped on web — Deepgram
        // depends on the native `record` plugin's PCM stream which
        // isn't wired for the web build, so the button would only
        // throw `VoiceUnsupportedError` on tap. Without the gate
        // the field still works as a plain text input on web,
        // just without dictation.
        if (!kIsWeb)
          Positioned(
            right: AppSpacing.xs,
            bottom: AppSpacing.xs,
            child: Material(
              color: _voiceActive
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _toggleVoice,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Icon(
                    _voiceActive ? Icons.stop : Icons.mic,
                    size: 20,
                    color: _voiceActive
                        ? theme.colorScheme.onError
                        : theme.colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
