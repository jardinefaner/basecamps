import 'dart:async';
import 'dart:convert';

import 'package:basecamp/config/env.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// One live transcription pass: open mic → stream PCM to Deepgram →
/// surface partial + final transcripts. Close the session when done.
///
/// Callers listen to [partials] and [finals]:
/// - [partials] emit transient, unstable text snippets that should show in
///   the UI as a preview but not be committed to the note yet.
/// - [finals] emit confirmed chunks that should be appended to the note.
class DeepgramVoiceSession {
  DeepgramVoiceSession() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;
  WebSocketChannel? _channel;
  StreamSubscription<List<int>>? _audioSub;
  StreamSubscription<dynamic>? _socketSub;

  final _partialController = StreamController<String>.broadcast();
  final _finalController = StreamController<String>.broadcast();
  final _errorController = StreamController<Object>.broadcast();

  Stream<String> get partials => _partialController.stream;
  Stream<String> get finals => _finalController.stream;
  Stream<Object> get errors => _errorController.stream;

  bool get isActive => _channel != null;

  /// Starts recording and opens the Deepgram socket. Throws
  /// [VoiceUnsupportedError] if the platform doesn't support streaming
  /// capture (currently: web) or [VoicePermissionError] / [VoiceConfigError]
  /// on setup failures.
  Future<void> start() async {
    if (kIsWeb) {
      throw const VoiceUnsupportedError(
        'Live voice input is mobile-only for now.',
      );
    }
    if (!Env.hasDeepgram) {
      throw const VoiceConfigError(
        'Deepgram API key missing. Add DEEPGRAM_API_KEY to .env.',
      );
    }
    if (!await _recorder.hasPermission()) {
      throw const VoicePermissionError('Microphone permission denied.');
    }

    final uri = Uri.parse(
      'wss://api.deepgram.com/v1/listen'
      '?model=nova-2'
      '&encoding=linear16'
      '&sample_rate=16000'
      '&channels=1'
      '&smart_format=true'
      '&interim_results=true'
      '&endpointing=350'
      '&punctuate=true',
    );

    // Browser-compatible auth path: token passed as a subprotocol. Works in
    // both native WebSocket and browser WebSocket.
    final channel = WebSocketChannel.connect(
      uri,
      protocols: ['token', Env.deepgramApiKey],
    );
    _channel = channel;

    _socketSub = channel.stream.listen(
      _onSocketMessage,
      onError: (Object err, StackTrace st) {
        _errorController.add(err);
      },
      onDone: () {
        _channel = null;
      },
      cancelOnError: false,
    );

    final audio = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    _audioSub = audio.listen(
      (chunk) {
        final ch = _channel;
        if (ch == null) return;
        ch.sink.add(chunk);
      },
      onError: (Object err, StackTrace st) {
        _errorController.add(err);
      },
    );
  }

  void _onSocketMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final type = data['type'];
      if (type != 'Results') return;
      final channel = data['channel'] as Map<String, dynamic>?;
      final alternatives = channel?['alternatives'] as List<dynamic>?;
      if (alternatives == null || alternatives.isEmpty) return;
      final first = alternatives.first as Map<String, dynamic>;
      final transcript = first['transcript'] as String? ?? '';
      if (transcript.isEmpty) return;
      final isFinal = data['is_final'] == true;
      if (isFinal) {
        _finalController.add(transcript);
      } else {
        _partialController.add(transcript);
      }
    } on Object catch (err) {
      _errorController.add(err);
    }
  }

  Future<void> stop() async {
    final ch = _channel;
    _channel = null;
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      await _recorder.stop();
    } on Object {
      // best-effort
    }
    if (ch != null) {
      // Tell Deepgram we're done so it returns any buffered final.
      try {
        ch.sink.add(jsonEncode({'type': 'CloseStream'}));
      } on Object {
        // ignore
      }
      await ch.sink.close();
    }
    await _socketSub?.cancel();
    _socketSub = null;
  }

  Future<void> dispose() async {
    await stop();
    await _partialController.close();
    await _finalController.close();
    await _errorController.close();
    await _recorder.dispose();
  }
}

class VoiceUnsupportedError implements Exception {
  const VoiceUnsupportedError(this.message);
  final String message;
  @override
  String toString() => message;
}

class VoicePermissionError implements Exception {
  const VoicePermissionError(this.message);
  final String message;
  @override
  String toString() => message;
}

class VoiceConfigError implements Exception {
  const VoiceConfigError(this.message);
  final String message;
  @override
  String toString() => message;
}
