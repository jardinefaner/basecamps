// iPad share-sheet anchor helper.
//
// iPadOS presents UIActivityViewController as a popover, which
// requires `UIPopoverPresentationController.sourceRect`. Without
// it, share_plus throws PlatformException — surfaced to teachers
// as "could not export… platform exception copy fail." Mac
// Catalyst and other Apple platforms inherit the same constraint
// for file shares.
//
// Other platforms (Android, macOS, Windows, Linux, web) ignore
// the rect — `Rect.zero` is a safe default everywhere. The
// helper resolves an anchor from the calling widget's BuildContext
// (usually an IconButton render box), which is what iOS wants
// the popover to point at.

import 'package:flutter/widgets.dart';

/// Best-effort iPad popover anchor derived from [context]. Falls
/// back to `Rect.zero` if the context's RenderBox isn't laid out
/// — share_plus tolerates that on non-iPad platforms and most
/// iPad versions just default to the top-left.
Rect shareOriginFromContext(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return Rect.zero;
  final origin = box.localToGlobal(Offset.zero);
  return origin & box.size;
}
