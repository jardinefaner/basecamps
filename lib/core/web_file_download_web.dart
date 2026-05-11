// Web implementation: trigger a real file download via an
// anchor element with a Blob URL. The user gets a saved file
// that opens in Sheets / Excel, which is what they expect from
// a "Download CSV" button.
//
// Why not `Clipboard.setData`? Safari rejects clipboard writes
// that don't happen in a synchronous user-gesture context, and
// our export flow has multiple awaits (stream pull, CSV build)
// before the write — by the time we'd call `setData`, the
// user-activation flag has been cleared and the call throws
// `PlatformException: clipboard setdata failed`.
//
// Anchor-click downloads are a passive operation that doesn't
// need user-activation, so they work after any async gap.

import 'dart:convert';

import 'package:web/web.dart' as web;

void downloadTextFile({
  required String filename,
  required String mimeType,
  required String content,
}) {
  // Build a data URL — works in every browser, avoids the
  // permissions/origin complications of Blob URLs and skips
  // the need to revokeObjectURL. CSV payloads are typically
  // small enough (< 1 MB) that base64 inlining is fine.
  final encoded = base64Encode(utf8.encode(content));
  final dataUrl = 'data:$mimeType;base64,$encoded';

  // Create a transient anchor, click it, then remove. The
  // `download` attribute tells the browser to save rather than
  // navigate. Some Safari versions need the anchor in the DOM
  // to honor the download attr, so we append + click + remove.
  final anchor = web.HTMLAnchorElement()
    ..href = dataUrl
    ..download = filename
    ..style.display = 'none';
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
}
