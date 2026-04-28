import 'dart:async';
import 'dart:convert';

import 'package:basecamp/config/env.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
      // The `record` package's audio capture isn't supported on web
      // yet (no MediaRecorder bridge). Voice stays mobile-only until
      // we wire a web-specific recorder. The Deepgram side is now
      // fine on web — temp tokens come from the edge function — but
      // recording the mic from a browser is the missing piece.
      throw const VoiceUnsupportedError(
        'Live voice input is mobile-only for now.',
      );
    }
    if (Supabase.instance.client.auth.currentSession == null) {
      throw const VoiceConfigError(
        'Sign in to use live voice input.',
      );
    }
    if (!await _recorder.hasPermission()) {
      throw const VoicePermissionError('Microphone permission denied.');
    }

    // Fetch a 30-second Deepgram temp token from our edge function.
    // This avoids ever having the long-lived Deepgram project key
    // on the client. The function verifies the user's Supabase
    // session before granting.
    final tempToken = await _fetchDeepgramTempToken();

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

    // Deepgram's grant endpoint returns a JWT; the realtime
    // socket accepts it via the same `Bearer` subprotocol the
    // long-lived key used. (Bearer + JWT is the documented
    // path; "token" + raw key was the old way.)
    final channel = WebSocketChannel.connect(
      uri,
      protocols: ['bearer', tempToken],
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

  /// POSTs to our `deepgram-token` Edge Function with the user's
  /// Supabase session JWT and returns the short-lived (30-second)
  /// Deepgram access token. The function authenticates the caller
  /// via Supabase's verify_jwt before exchanging the long-lived
  /// project key for a temp JWT — so the project key never reaches
  /// the client.
  ///
  /// Throws [VoiceConfigError] when the function is missing,
  /// unreachable, or returns a non-2xx (e.g. DEEPGRAM_API_KEY
  /// secret not set).
  Future<String> _fetchDeepgramTempToken() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      throw const VoiceConfigError('Sign in to use live voice input.');
    }
    final url = Uri.parse(
      '${Env.supabaseUrl}/functions/v1/deepgram-token',
    );
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer ${session.accessToken}',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VoiceConfigError(
        'Deepgram token grant failed (${response.statusCode}): '
        '${response.body}',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['access_token'] as String?;
    if (token == null || token.isEmpty) {
      throw const VoiceConfigError(
        'Deepgram grant returned no access_token.',
      );
    }
    return token;
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
