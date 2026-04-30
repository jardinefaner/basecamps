import 'package:web/web.dart' as web;

/// Web implementation. `window.history.replaceState` swaps the URL
/// without a reload — the in-flight Flutter boot continues, just
/// with a clean address bar (no `?code=<dead>` left over to retrigger
/// the same auth failure on every refresh).
void replaceUrl(String cleanedUrl) {
  web.window.history.replaceState(null, '', cleanedUrl);
}
