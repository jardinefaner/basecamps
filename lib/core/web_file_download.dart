// Conditional-import entry for the web-only file download helper.
// Native + desktop pull in the stub (which throws if invoked);
// the web build pulls in the real `package:web` implementation.
// Callers must gate with `if (kIsWeb)` before invoking.

export 'web_file_download_stub.dart'
    if (dart.library.js_interop) 'web_file_download_web.dart';
