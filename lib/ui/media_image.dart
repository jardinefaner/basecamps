import 'package:basecamp/features/sync/media_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Identity key for [mediaImageProvider]. Combines an optional
/// device-local file path (fast native render) with the cross-
/// device Supabase Storage key + per-upload content tag. Two
/// MediaSources with the same (localPath, storagePath, etag)
/// triple resolve to the same family slot, so multiple widgets
/// watching the same row share one fetch.
///
/// Why etag: the bucket key is stable per logical id (avatars are
/// keyed by row id, form images are keyed by submission+field),
/// so a re-uploaded photo lands at the same path. Without etag in
/// the equality, a row that pulled in a fresh etag from realtime
/// would still hit the same family slot and serve stale bytes.
/// With etag included, any change creates a new family entry and
/// forces re-resolution through the cache (which itself checks
/// etag and re-fetches on mismatch). End-to-end invalidation in
/// one tuple flip.
///
/// Null etag is a wildcard match — observation attachments and
/// other write-once media don't carry one, and the cache
/// gracefully accepts that.
@immutable
class MediaSource {
  const MediaSource({this.localPath, this.storagePath, this.etag});

  /// Filesystem path on the device that captured the file.
  /// Native-only; on web `XFile.path` is a `blob:` URL useless to
  /// `dart:io.File`, so this stays null. Falls through to
  /// [storagePath] when missing.
  final String? localPath;

  /// Bucket-relative key in Supabase Storage. The cross-device
  /// source of truth — every device + platform can resolve to
  /// bytes through it.
  final String? storagePath;

  /// Per-upload content tag. Null on legacy / write-once media.
  final String? etag;

  bool get isEmpty => (localPath == null || localPath!.isEmpty) &&
      (storagePath == null || storagePath!.isEmpty);

  @override
  bool operator ==(Object other) =>
      other is MediaSource &&
      other.localPath == localPath &&
      other.storagePath == storagePath &&
      other.etag == etag;

  @override
  int get hashCode => Object.hash(localPath, storagePath, etag);
}

/// Resolves a [MediaSource] to a renderable [ImageProvider]. One
/// fetch per source across the whole app — the family caches by
/// value, so a hundred SmallAvatars rendering the same child
/// share one resolution.
///
/// Resolution: always through [MediaService.ensureBytes] which
/// hits the drift media-cache table; on miss / etag mismatch,
/// downloads from Supabase Storage, saves to drift with the new
/// etag, and returns the bytes. Subsequent renders read straight
/// from drift, no Supabase round-trip.
///
/// **Why no native local-file fast path:** `avatar_path` is a
/// per-device handle that never crosses devices, so it can lag
/// the canonical `avatar_storage_path` + `avatar_etag` on the
/// row. Symptom: Device A uploads a new photo, Device B receives
/// the row update, but Device B's `avatar_path` still points at
/// a previous photo it took locally — the fast path would render
/// that stale file forever, ignoring the new etag. Going through
/// the cache on every platform means rendering is content-
/// addressed by `(storage_path, etag)` and a fresh upload on any
/// device invalidates correctly everywhere.
///
/// Native still gets persistence: drift_flutter stores the cache
/// blob in SQLite locally, so offline rendering works the same
/// as the FileImage fast path did. The only thing we lose is one
/// SQLite blob read instead of one FS read on warm-cache hits —
/// negligible.
///
/// `autoDispose` — family entries clean up when no listener is
/// watching. The drift cache survives the dispose, so re-mounting
/// is as fast as the initial fetch.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final mediaImageProvider = FutureProvider.autoDispose
    .family<ImageProvider?, MediaSource>((ref, source) async {
  if (source.isEmpty) return null;
  final storagePath = source.storagePath;
  if (storagePath == null || storagePath.isEmpty) return null;
  final bytes = await ref
      .read(mediaServiceProvider)
      .ensureBytes(storagePath, etag: source.etag);
  if (bytes == null) return null;
  return MemoryImage(bytes);
});

/// Generic rectangular image renderer that goes through the same
/// drift-first cache pipeline as `SmallAvatar`. Use it for
/// observation attachment thumbnails, form image fields, and any
/// other non-circular media surface.
///
/// Loading + error states render [placeholder] (or a default
/// "broken image" icon if absent), so callers don't have to
/// branch on `kIsWeb` themselves.
class MediaImage extends ConsumerWidget {
  const MediaImage({
    required this.source,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
    this.cacheWidth,
    this.placeholder,
    this.errorPlaceholder,
    super.key,
  });

  final MediaSource source;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// Optional clip — ergonomic shortcut so callers don't have to
  /// wrap in a ClipRRect for the common rounded-thumbnail case.
  final BorderRadius? borderRadius;

  /// Optional decode-time width clamp, the same lever
  /// `Image.file(cacheWidth: ...)` exposes — saves memory on
  /// thumbnail grids of 12MP photos.
  final int? cacheWidth;

  /// Shown while the resolver is loading bytes (drift cache miss
  /// → Supabase download). Defaults to a neutral placeholder.
  final Widget? placeholder;

  /// Shown when resolution fails or the source is empty. Defaults
  /// to the broken-image icon.
  final Widget? errorPlaceholder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final fallback = errorPlaceholder ??
        _DefaultPlaceholder(
          icon: Icons.broken_image_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        );

    if (source.isEmpty) {
      return _wrap(fallback, theme);
    }

    final asyncImage = ref.watch(mediaImageProvider(source));
    final widget = asyncImage.when(
      loading: () =>
          placeholder ??
          _DefaultPlaceholder(
            icon: Icons.image_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
      error: (_, _) => fallback,
      data: (image) {
        if (image == null) return fallback;
        // ResizeImage caps decode width — mirrors Image.file's
        // cacheWidth knob. Defaults to 2× the layout width when
        // unset and the layout has a width, so retina is happy
        // and a 12MP photo doesn't blow up memory.
        final width = cacheWidth ??
            (this.width != null ? (this.width! * 2).round() : null);
        final provider = width != null
            ? ResizeImage(image, width: width)
            : image;
        return Image(
          image: provider,
          fit: fit,
          // `this.width` because the local `width` above shadows
          // the field. `height` isn't shadowed.
          width: this.width,
          height: height,
          errorBuilder: (_, _, _) => fallback,
        );
      },
    );

    return _wrap(widget, theme);
  }

  Widget _wrap(Widget child, ThemeData theme) {
    Widget out = SizedBox(width: width, height: height, child: child);
    if (borderRadius != null) {
      out = ClipRRect(borderRadius: borderRadius!, child: out);
    }
    return out;
  }
}

class _DefaultPlaceholder extends StatelessWidget {
  const _DefaultPlaceholder({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Center(child: Icon(icon, color: color)),
    );
  }
}
