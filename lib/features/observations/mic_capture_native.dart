// Native mic capture — wraps the `record` package's PCM streaming
// API. iOS / macOS / Android all hit this path. Web has its own
// implementation in `mic_capture_web.dart`; the conditional export
// in `mic_capture.dart` picks one at compile time.

import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// One-shot mic stream. Construct, call [hasPermission], then
/// [startStream]; listen to the returned `Stream<Uint8List>` for
/// audio chunks; call [stop] when done. Single-use — start a new
/// instance for the next capture.
class MicCapture {
  MicCapture() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;

  /// True when the OS-level mic permission is already granted.
  /// On native this triggers the system prompt the first time;
  /// the user's choice persists.
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Open the mic and start streaming. Audio shape:
  ///   * 16-bit signed PCM
  ///   * 16 kHz sample rate
  ///   * 1 channel (mono)
  /// Deepgram's `?encoding=linear16&sample_rate=16000&channels=1`
  /// query params match this exactly — the native code path passes
  /// those params on the WebSocket URL.
  Future<Stream<Uint8List>> startStream() async {
    final audio = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    return audio.map(Uint8List.fromList);
  }

  /// Stamp the Deepgram WebSocket URL params for this platform.
  /// Native sends 16 kHz mono linear16 PCM, so the URL carries
  /// `encoding`, `sample_rate`, and `channels` explicitly. Web
  /// sends WebM/Opus and lets Deepgram auto-detect; its impl
  /// of this method is a no-op.
  void applyToSocketParams(Map<String, String> params) {
    params['encoding'] = 'linear16';
    params['sample_rate'] = '16000';
    params['channels'] = '1';
  }

  Future<void> stop() async {
    try {
      await _recorder.stop();
    } on Object {
      // best-effort; the caller is shutting down anyway
    }
  }

  Future<void> dispose() => _recorder.dispose();
}
