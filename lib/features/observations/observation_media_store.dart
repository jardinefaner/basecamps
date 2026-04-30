import 'dart:io';

import 'package:basecamp/core/id.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// App-owned directory for observation attachments. Lives under
/// `<app documents>/observation_media/`. Created on first access.
///
/// The orphan sweeper reaps files in this directory that no
/// attachment row points at. Anything OUTSIDE this dir
/// (image_picker temp paths, camera-roll shares) is not ours to
/// delete — we pin that by passing only this dir to the sweeper.
///
/// The web build has no filesystem to own — this provider returns
/// null there, and callers short-circuit.
final observationMediaDirProvider =
    FutureProvider<Directory?>((ref) async {
  if (kIsWeb) return null;
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docs.path, 'observation_media'));
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return dir;
});

/// Copy `source` into the app-owned media dir under a fresh unique
/// filename that preserves the original extension. Returns the new
/// absolute path — store this on `ObservationAttachment.localPath`
/// so the sweeper can recognize it as ours.
///
/// Reads bytes via [XFile.readAsBytes] (works on every platform
/// including web) instead of `dart:io.File.copy` (native-only).
/// Web-only callers should not invoke this — `mediaDir` is null
/// there — but the kIsWeb guard is kept defensively.
Future<String> copyAttachmentToMediaDir({
  required XFile source,
  required Directory mediaDir,
}) async {
  if (kIsWeb) return '';
  // Best-effort extension: name first (carries the real suffix on
  // both platforms), then path (real on native), default `.jpg`.
  final fromName = p.extension(source.name);
  final fromPath = p.extension(source.path);
  final ext = fromName.isNotEmpty
      ? fromName
      : fromPath.isNotEmpty
          ? fromPath
          : '.jpg';
  final filename = '${newId()}$ext';
  final dest = File(p.join(mediaDir.path, filename));
  await dest.writeAsBytes(await source.readAsBytes());
  return dest.path;
}
