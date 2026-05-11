// Non-web stub. Native + desktop never call this — the export
// path branches on kIsWeb and only the web build resolves to
// `web_file_download_web.dart`. The stub exists so the bundler
// can satisfy the import on every platform without pulling
// `package:web` into native builds.

void downloadTextFile({
  required String filename,
  required String mimeType,
  required String content,
}) {
  throw UnsupportedError(
    'downloadTextFile is web-only; native + desktop should use '
    'share_plus / writeAsString instead.',
  );
}
