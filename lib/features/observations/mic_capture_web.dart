// Web mic capture — uses the browser's `MediaRecorder` API via
// `package:web`. Native uses `record` instead (see
// `mic_capture_native.dart`); the conditional export in
// `mic_capture.dart` picks one at compile time.
//
// Audio shape: WebM/Opus. Deepgram's WebSocket Listen API auto-
// detects container formats when no `encoding` query param is
// passed, so the URL on web omits `encoding`, `sample_rate`, and
// `channels` — Deepgram reads the WebM header.
//
// Chunking: MediaRecorder fires `dataavailable` events on a
// configurable timeslice. We use 250ms — small enough that the
// last partial after stop arrives quickly, large enough that we
// don't flood the WebSocket with sub-frame chunks.

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class MicCapture {
  web.MediaStream? _stream;
  web.MediaRecorder? _recorder;
  StreamController<Uint8List>? _controller;

  /// `true` if the browser already has mic permission for this
  /// origin. On web the only way to know is to call
  /// `navigator.permissions.query({name: 'microphone'})` — but
  /// that API is uneven across browsers and `getUserMedia` itself
  /// pops the prompt anyway. We always return true and let
  /// [startStream] surface a `NotAllowedError` if the user
  /// declines; the caller's `try` already handles that.
  Future<bool> hasPermission() async => true;

  Future<Stream<Uint8List>> startStream() async {
    final constraints = web.MediaStreamConstraints(audio: true.toJS);
    final stream = await web.window.navigator.mediaDevices
        .getUserMedia(constraints)
        .toDart;
    _stream = stream;

    // Pick a MIME the browser supports. Chrome / Edge / Firefox
    // all do `audio/webm;codecs=opus`; Safari falls back to
    // `audio/mp4`. We probe in order and let MediaRecorder use
    // its default if neither is supported (older browsers).
    String? mime;
    for (final candidate in const <String>[
      'audio/webm;codecs=opus',
      'audio/webm',
      'audio/mp4',
    ]) {
      if (web.MediaRecorder.isTypeSupported(candidate)) {
        mime = candidate;
        break;
      }
    }
    final recorder = mime == null
        ? web.MediaRecorder(stream)
        : web.MediaRecorder(stream, web.MediaRecorderOptions(mimeType: mime));
    _recorder = recorder;

    final controller = StreamController<Uint8List>.broadcast();
    _controller = controller;

    // package:web exposes MediaRecorder events as settable JS
    // function properties (`ondataavailable`). We pump each
    // BlobEvent through the controller; cleanup nulls the
    // property out in `stop()`.
    recorder.ondataavailable = ((web.Event event) {
      final blob = (event as web.BlobEvent).data;
      if (blob.size == 0) return;
      // Fire-and-forget the arrayBuffer read — we don't need to
      // wait inside this synchronous JS callback. The controller
      // emits when the bytes resolve, in order.
      // ignore: discarded_futures
      blob.arrayBuffer().toDart.then((buf) {
        if (controller.isClosed) return;
        controller.add(buf.toDart.asUint8List());
      });
    }).toJS;

    // 250ms slices — small enough for low-latency partials,
    // large enough that the WebSocket isn't fragmented to death.
    recorder.start(250);
    return controller.stream;
  }

  /// Web sends WebM/Opus (or MP4 on Safari) and lets Deepgram
  /// auto-detect the container — no params needed on the URL.
  /// Native carries `encoding=linear16&sample_rate=16000&channels=1`.
  void applyToSocketParams(Map<String, String> params) {
    // Intentionally empty — Deepgram reads the container header.
  }

  Future<void> stop() async {
    final recorder = _recorder;
    if (recorder != null && recorder.state != 'inactive') {
      try {
        recorder.stop();
      } on Object {
        // best-effort
      }
    }
    // Detach the event handler so the (now inactive) recorder
    // can be GC'd and we don't get a stray dataavailable on
    // teardown. Setting to undefined is the JS way to "remove."
    if (recorder != null) {
      recorder.ondataavailable = null;
    }
    final stream = _stream;
    if (stream != null) {
      // Stop every track so the browser releases the mic + drops
      // the recording indicator in the tab. Without this the
      // user keeps seeing the red dot after the survey advances.
      final tracks = stream.getTracks().toDart;
      for (final t in tracks) {
        try {
          t.stop();
        } on Object {/* best-effort */}
      }
    }
    await _controller?.close();
    _controller = null;
    _recorder = null;
    _stream = null;
  }

  Future<void> dispose() => stop();
}
