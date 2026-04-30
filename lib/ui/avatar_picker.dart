import 'dart:async';
import 'dart:io';

import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/media_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

// MediaSource + mediaImageProvider live in `media_image.dart` —
// shared with the rectangular media renderer (observation
// attachments, form images, etc).

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
///     [mediaImageProvider] just like read-only [SmallAvatar]s
///     do — drift cache → Supabase download on miss → reuse.
class AvatarPicker extends ConsumerStatefulWidget {
  const AvatarPicker({
    required this.currentLocalPath,
    required this.currentStoragePath,
    required this.currentEtag,
    required this.pendingFile,
    required this.fallbackInitial,
    required this.onChanged,
    this.radius = 40,
    super.key,
  });

  /// Existing local file on this device. Native-only fast path —
  /// the underlying [mediaImageProvider] checks it before
  /// touching the cache.
  final String? currentLocalPath;

  /// Supabase Storage bucket key. Drives the cross-device cache
  /// fallback when the local file isn't present (web + native).
  final String? currentStoragePath;

  /// Per-upload content tag from the row's `avatar_etag` column.
  /// When this changes (realtime delivers another device's
  /// upload), the underlying [mediaImageProvider] family creates
  /// a new entry and pulls fresh bytes.
  final String? currentEtag;

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
  /// shared [mediaImageProvider].
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
    final source = MediaSource(
      localPath: widget.currentLocalPath,
      storagePath: widget.currentStoragePath,
      etag: widget.currentEtag,
    );
    if (source.isEmpty) return null;
    final resolved = ref.watch(mediaImageProvider(source)).asData?.value;
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
/// through the shared [mediaImageProvider] so every tile in the
/// app uses the same resolution + caching pipeline (drift first,
/// Supabase on miss, save to drift, reuse forever).
///
/// Resolution order (delegated to [mediaImageProvider]):
///   1. **Native + local file present** → Image.file (instant,
///      offline).
///   2. **storagePath set** → `MediaService.ensureBytes` returns
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
    this.etag,
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

  /// Per-upload content tag (from the row's `avatar_etag` column).
  /// Composed into the cache key so realtime-delivered etag
  /// changes force a fresh fetch instead of serving stale bytes.
  /// Null on legacy rows pre-v51.
  final String? etag;

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

    final source = MediaSource(
      localPath: path,
      storagePath: storagePath,
      etag: etag,
    );
    final resolved = source.isEmpty
        ? null
        : ref.watch(mediaImageProvider(source)).asData?.value;
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
