import 'dart:async';
import 'dart:io';

import 'package:basecamp/features/sync/media_service.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

// ────────────────────────────────────────────────────────────────
// Single source of truth for cross-device avatar resolution
// ────────────────────────────────────────────────────────────────

/// Identity key for [avatarImageProvider]. Combines an optional
/// device-local file path (fast native render) with the cross-
/// device Supabase Storage key. Two AvatarSources with the same
/// (localPath, storagePath) pair resolve to the same family slot,
/// so multiple widgets watching the same row share one fetch.
@immutable
class AvatarSource {
  const AvatarSource({this.localPath, this.storagePath});

  /// Filesystem path on the device that captured the photo.
  /// Native-only; on web `XFile.path` is a `blob:` URL useless to
  /// `dart:io.File`, so this stays null. Falls through to
  /// [storagePath] when missing.
  final String? localPath;

  /// Bucket-relative key in Supabase Storage. The cross-device
  /// source of truth — every device + platform can resolve to
  /// bytes through it.
  final String? storagePath;

  bool get isEmpty => (localPath == null || localPath!.isEmpty) &&
      (storagePath == null || storagePath!.isEmpty);

  @override
  bool operator ==(Object other) =>
      other is AvatarSource &&
      other.localPath == localPath &&
      other.storagePath == storagePath;

  @override
  int get hashCode => Object.hash(localPath, storagePath);
}

/// Resolves an avatar to a renderable [ImageProvider]. One fetch
/// per [AvatarSource] across the whole app — the family caches by
/// value, so a hundred SmallAvatars rendering the same child
/// share one resolution.
///
/// Resolution order:
///   1. **Native + local file present** → [FileImage]. Instant,
///      offline-friendly. Skipped on web (no FS).
///   2. **storagePath set** → [MediaService.ensureBytes] hits the
///      drift media-cache table; on miss, downloads from
///      Supabase Storage, saves to drift, and returns the bytes.
///      Result rendered as [MemoryImage]. Subsequent renders
///      (anywhere in the app, this session or future sessions,
///      even after a web page reload — drift persists to
///      IndexedDB) read straight from drift, no Supabase
///      round-trip.
///   3. **Otherwise** → null. The widget renders the fallback
///      initial.
///
/// `keepAlive: false` — the family entries auto-dispose when no
/// listener is watching them. The drift cache survives the
/// dispose, so re-mounting is as fast as the initial fetch.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final avatarImageProvider = FutureProvider.autoDispose
    .family<ImageProvider?, AvatarSource>((ref, source) async {
  if (source.isEmpty) return null;

  // 1) Native fast path: render the device-local file directly.
  //    No drift hit, no signed URL, no Supabase round-trip.
  if (!kIsWeb && source.localPath != null) {
    final f = File(source.localPath!);
    if (f.existsSync()) {
      return FileImage(f);
    }
  }

  // 2) Cross-device path: drift cache → on miss, Supabase
  //    download → save to drift → render bytes.
  final storagePath = source.storagePath;
  if (storagePath == null || storagePath.isEmpty) return null;
  final bytes = await ref.read(mediaServiceProvider).ensureBytes(storagePath);
  if (bytes == null) return null;
  return MemoryImage(bytes);
});

// ────────────────────────────────────────────────────────────────
// Pickers + tiles
// ────────────────────────────────────────────────────────────────

/// Circular avatar picker used in the child and adult edit sheets.
/// Shows the current photo (cross-device storage path, local path,
/// or freshly-picked XFile) with a small camera badge. Tap to open
/// a bottom sheet that lets the teacher take a photo, pick one
/// from the library, or remove the existing avatar.
///
/// Returns the picked [XFile] to the caller via [onChanged]. Null
/// means "cleared". The caller is responsible for handing the
/// XFile to the repository on save — the picker itself doesn't
/// trigger any cloud upload.
///
/// Web parity:
///   * `image_picker` on web returns an [XFile] whose `path` is a
///     `blob:` URL — useless to `dart:io.File`. Bytes are still
///     readable via `XFile.readAsBytes()`, which the picker calls
///     once and caches in [_AvatarPickerState._pendingBytes] so
///     [MemoryImage] can render the preview.
///   * Existing avatars on web go through the shared
///     [avatarImageProvider] just like read-only [SmallAvatar]s
///     do — drift cache → Supabase download on miss → reuse.
class AvatarPicker extends ConsumerStatefulWidget {
  const AvatarPicker({
    required this.currentLocalPath,
    required this.currentStoragePath,
    required this.pendingFile,
    required this.fallbackInitial,
    required this.onChanged,
    this.radius = 40,
    super.key,
  });

  /// Existing local file on this device. Native-only fast path —
  /// the underlying [avatarImageProvider] checks it before
  /// touching the cache.
  final String? currentLocalPath;

  /// Supabase Storage bucket key. Drives the cross-device cache
  /// fallback when the local file isn't present (web + native).
  final String? currentStoragePath;

  /// Freshly-picked file the teacher hasn't saved yet. Takes
  /// precedence over [currentLocalPath] / [currentStoragePath]
  /// for preview rendering. Pass null when nothing's pending.
  final XFile? pendingFile;

  final String fallbackInitial;

  /// Called with the freshly-picked XFile when the teacher snaps
  /// or chooses a photo, or with `null` when they tap "Remove
  /// photo." The caller persists this on save — the picker is
  /// purely UI.
  final ValueChanged<XFile?> onChanged;

  final double radius;

  @override
  ConsumerState<AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends ConsumerState<AvatarPicker> {
  /// Decoded bytes of [AvatarPicker.pendingFile]. Only populated
  /// on web (where `File(xfile.path)` throws); on native we render
  /// FileImage(File(xfile.path)) directly.
  Uint8List? _pendingBytes;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPendingBytesIfNeeded());
  }

  @override
  void didUpdateWidget(covariant AvatarPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pendingFile?.path != widget.pendingFile?.path) {
      _pendingBytes = null;
      unawaited(_loadPendingBytesIfNeeded());
    }
  }

  Future<void> _loadPendingBytesIfNeeded() async {
    final pending = widget.pendingFile;
    if (pending == null) return;
    if (!kIsWeb) return; // native renders FileImage directly
    try {
      final bytes = await pending.readAsBytes();
      if (!mounted) return;
      setState(() => _pendingBytes = bytes);
    } on Object catch (e) {
      debugPrint('AvatarPicker pending readAsBytes failed: $e');
    }
  }

  Future<void> _openPickerSheet(BuildContext context) async {
    final picker = ImagePicker();

    Future<void> pick(ImageSource source) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        final file = await picker.pickImage(
          source: source,
          imageQuality: 85,
          // Avatars are small — 1000px max keeps the file tiny.
          maxWidth: 1000,
        );
        if (file != null) widget.onChanged(file);
      } on Object catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text("Couldn't set avatar: $e")),
        );
      }
    }

    final hasExisting = widget.pendingFile != null ||
        widget.currentLocalPath != null ||
        widget.currentStoragePath != null;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  unawaited(pick(ImageSource.camera));
                },
              ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from library'),
              onTap: () {
                Navigator.of(ctx).pop();
                unawaited(pick(ImageSource.gallery));
              },
            ),
            if (hasExisting)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove photo'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  widget.onChanged(null);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Pick the right [ImageProvider] for the preview. Pending
  /// picks win over saved state; saved state goes through the
  /// shared [avatarImageProvider].
  ImageProvider? _resolveImageProvider() {
    final diameter = widget.radius * 2;
    final decodeSize = (diameter * 2).round();

    final pending = widget.pendingFile;
    if (pending != null) {
      if (kIsWeb) {
        final bytes = _pendingBytes;
        if (bytes == null) return null;
        return ResizeImage(MemoryImage(bytes), width: decodeSize);
      }
      return ResizeImage(
        FileImage(File(pending.path)),
        width: decodeSize,
      );
    }

    // No pending pick — fall through to the saved-state resolver.
    final source = AvatarSource(
      localPath: widget.currentLocalPath,
      storagePath: widget.currentStoragePath,
    );
    if (source.isEmpty) return null;
    final resolved =
        ref.watch(avatarImageProvider(source)).asData?.value;
    if (resolved == null) return null;
    return ResizeImage(resolved, width: decodeSize);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = _resolveImageProvider();

    final avatar = CircleAvatar(
      radius: widget.radius,
      backgroundColor: theme.colorScheme.primaryContainer,
      // Cap the decode size (2× display for retina) but don't
      // pin both axes — ResizeImage with both width AND height
      // resizes to that exact box and squishes the source's
      // native aspect ratio. We only clamp the width; the
      // height scales proportionally, then CircleAvatar's
      // BoxFit.cover crops to the circle cleanly.
      backgroundImage: source,
      child: source == null
          ? Text(
              widget.fallbackInitial,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            )
          : null,
    );

    return GestureDetector(
      onTap: () => _openPickerSheet(context),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.surface,
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.camera_alt,
                size: 14,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only round avatar for tiles, chips, list rows. Renders
/// through the shared [avatarImageProvider] so every tile in the
/// app uses the same resolution + caching pipeline (drift first,
/// Supabase on miss, save to drift, reuse forever).
///
/// Resolution order (delegated to [avatarImageProvider]):
///   1. **Native + local file present** → Image.file (instant,
///      offline).
///   2. **storagePath set** → [MediaService.ensureBytes] returns
///      drift-cached bytes, falling through to a Supabase
///      download on miss. The bytes-to-drift store survives app
///      restarts AND web page reloads (drift_flutter persists
///      to IndexedDB), so each storage_path downloads once per
///      device — ever.
///   3. **Anything else** → fallback initial. The CircleAvatar
///      always renders the initial when no image is set, so a
///      failure of any kind still produces something readable
///      instead of a blank circle.
class SmallAvatar extends ConsumerWidget {
  const SmallAvatar({
    required this.path,
    required this.fallbackInitial,
    this.storagePath,
    this.radius = 20,
    this.backgroundColor,
    this.foregroundColor,
    super.key,
  });

  /// Local filesystem path. Valid only on the device that captured
  /// the photo. Falls through to [storagePath] when the file isn't
  /// present locally.
  final String? path;

  /// Supabase Storage bucket key (e.g.
  /// `<programId>/avatars/adults/<id>.jpg`). When set, used as the
  /// cross-device source of truth for the avatar image.
  final String? storagePath;

  final String fallbackInitial;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final decodeSize = (radius * 4).round();
    final bg = backgroundColor ?? theme.colorScheme.primaryContainer;
    final fg = foregroundColor ?? theme.colorScheme.onPrimaryContainer;

    final source = AvatarSource(localPath: path, storagePath: storagePath);
    final resolved = source.isEmpty
        ? null
        : ref.watch(avatarImageProvider(source)).asData?.value;
    final image =
        resolved == null ? null : ResizeImage(resolved, width: decodeSize);

    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      backgroundImage: image,
      // Always show the fallback initial when there's no image
      // source — no blank circles. The initial hides as soon as
      // an ImageProvider lands.
      child: image == null
          ? Text(
              fallbackInitial,
              style: theme.textTheme.titleMedium?.copyWith(color: fg),
            )
          : null,
    );
  }
}
