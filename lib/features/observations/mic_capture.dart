// Mic-capture facade — abstracts the platform difference between
// `record` (native: iOS / macOS / Android) and the browser's
// MediaRecorder (web). The facade is a tiny interface; each
// platform ships its own implementation alongside, picked at
// compile time via `dart.library.js_interop`.
//
// Why this exists: the `record` package's `startStream` doesn't
// have a web implementation. Voice transcription used to throw
// `VoiceUnsupportedError` on web because of this single gap;
// everything else (Deepgram WebSocket, edge function token
// exchange) already works cross-platform.
//
// Why a facade vs. an `if (kIsWeb)` branch in voice_service:
// keeping the platform-specific imports off the native build
// (native shouldn't reference `package:web` at all) and off the
// web build (web shouldn't reference `package:record` at all).
// Conditional exports give us that for free; the consumer just
// imports `mic_capture.dart` and calls it.

export 'mic_capture_native.dart'
    if (dart.library.js_interop) 'mic_capture_web.dart';
