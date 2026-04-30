import 'dart:async';
import 'dart:io';

import 'package:basecamp/features/sync/media_service.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// Circular avatar picker used in the child and adult edit sheets.
/// Shows the current photo (local file or initial fallback) with a
/// small camera badge. Tap to open a bottom sheet that lets the
/// teacher take a photo, pick one from the library, or remove the
/// existing avatar.
///
/// Returns a local file path to the caller via [onChanged]. Null means
/// "cleared".
class AvatarPicker extends StatelessWidget {
  const AvatarPicker({
    required this.currentPath,
    required this.fallbackInitial,
    required this.onChanged,
    this.radius = 40,
    super.key,
  });

  final String? currentPath;
  final String fallbackInitial;
  final ValueChanged<String?> onChanged;
  final double radius;

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
        if (file != null) onChanged(file.path);
      } on Object catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text("Couldn't set avatar: $e")),
        );
      }
    }

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
            if (currentPath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove photo'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onChanged(null);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diameter = radius * 2;
    final decodeSize = (diameter * 2).round();

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primaryContainer,
      backgroundImage: (currentPath != null && !kIsWeb)
          ? ResizeImage(
              FileImage(File(currentPath!)),
              // Cap the decode size (2× display for retina) but don't
              // pin both axes — ResizeImage with both width AND height
              // resizes to that exact box and squishes the source's
              // native aspect ratio. We only clamp the width; the
              // height scales proportionally, then CircleAvatar's
              // BoxFit.cover crops to the circle cleanly.
              width: decodeSize,
            )
          : null,
      child: currentPath == null
          ? Text(
              fallbackInitial,
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

/// Small read-only round avatar for tiles. Uses the same decode-size
/// discipline as [AvatarPicker].
/// Round avatar widget with cross-device + cross-platform-aware
/// loading. Always shows the fallback initial when no image
/// source is available — never a blank circle.
///
/// Avatars store TWO paths:
///   * `avatar_path` — local filesystem path on the device that
///     captured the photo. Only valid on that device + only when
///     the file actually exists (cache eviction on iOS / Android
///     can wipe it).
///   * `avatar_storage_path` — Supabase Storage bucket key.
///     Deterministic per row id, valid on every device + platform.
///
/// Resolution order:
///   1. **Native + local file present** → Image.file (instant,
///      offline-friendly). Falls through if the file is gone.
///   2. **Native + storagePath** → ensureLocalFile downloads to
///      a persistent cache dir; render from there. First render
///      shows the fallback initial during download; cache hits
///      are instant after.
///   3. **Web + storagePath** → signed URL via Supabase Storage,
///      render NetworkImage. URL is cached in memory; rotating
///      hourly transparently. First render shows the fallback
///      initial during URL fetch.
///   4. **Anything else** → fallback initial. The CircleAvatar
///      always renders the initial when no image is set, so a
///      failure of any kind still produces something readable
///      instead of a blank circle.
class SmallAvatar extends ConsumerStatefulWidget {
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
  ConsumerState<SmallAvatar> createState() => _SmallAvatarState();
}

class _SmallAvatarState extends ConsumerState<SmallAvatar> {
  /// Local file path on native — set when widget.path exists or
  /// ensureLocalFile completes. Null on web (no FS) and when
  /// nothing's resolved yet.
  String? _resolvedFilePath;

  /// Signed HTTPS URL on web — set when signedUrlFor completes.
  /// Null on native (we use _resolvedFilePath there) and when
  /// nothing's resolved yet.
  String? _resolvedNetworkUrl;

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  @override
  void didUpdateWidget(covariant SmallAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.storagePath != widget.storagePath) {
      _resolvedFilePath = null;
      _resolvedNetworkUrl = null;
      unawaited(_resolve());
    }
  }

  Future<void> _resolve() async {
    final localPath = widget.path;
    final storagePath = widget.storagePath;

    // Native: prefer the local-captured file when it exists. Fast,
    // offline, no network round-trip. existsSync is fine here —
    // a microsecond-level stat in init/didUpdate is cheaper than
    // tripping the slow-async-io lint for await File.exists().
    if (!kIsWeb && localPath != null && File(localPath).existsSync()) {
      if (!mounted) return;
      setState(() => _resolvedFilePath = localPath);
      return;
    }

    // No usable local file — fall back to cloud storage. Two
    // paths depending on platform:
    if (storagePath == null || storagePath.isEmpty) return;

    if (kIsWeb) {
      // Web: signed URL → NetworkImage. Browser caches bytes.
      // Memory cache on the URL itself (TTL ~55min) keeps re-
      // render cheap.
      try {
        final url = await ref
            .read(mediaServiceProvider)
            .signedUrlFor(storagePath);
        if (!mounted) return;
        if (url != null) setState(() => _resolvedNetworkUrl = url);
      } on Object catch (e) {
        debugPrint('SmallAvatar signed URL failed for $storagePath: $e');
      }
      return;
    }

    // Native: download to persistent file cache. Cache survives
    // app restarts so a re-render hits it instantly. First
    // render on a fresh device shows the fallback initial during
    // the download.
    try {
      final cached = await ref
          .read(mediaServiceProvider)
          .ensureLocalFile(storagePath);
      if (!mounted) return;
      setState(() => _resolvedFilePath = cached);
    } on Object catch (e) {
      debugPrint('SmallAvatar download failed for $storagePath: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decodeSize = (widget.radius * 4).round();
    final bg = widget.backgroundColor ?? theme.colorScheme.primaryContainer;
    final fg = widget.foregroundColor ?? theme.colorScheme.onPrimaryContainer;
    // Pick the right ImageProvider based on what resolved. Both
    // start null; only one ends up set per platform. ResizeImage
    // wraps either to clamp decode width.
    ImageProvider? source;
    if (_resolvedFilePath != null && !kIsWeb) {
      source = ResizeImage(
        FileImage(File(_resolvedFilePath!)),
        width: decodeSize,
      );
    } else if (_resolvedNetworkUrl != null) {
      source = ResizeImage(
        NetworkImage(_resolvedNetworkUrl!),
        width: decodeSize,
      );
    }

    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: bg,
      backgroundImage: source,
      // Always show the fallback initial when there's no image
      // source — no blank circles. The initial hides as soon as
      // an ImageProvider lands.
      child: source == null
          ? Text(
              widget.fallbackInitial,
              style: theme.textTheme.titleMedium?.copyWith(color: fg),
            )
          : null,
    );
  }
}
