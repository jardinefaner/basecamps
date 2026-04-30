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
/// Round avatar widget with cross-device-aware loading.
///
/// Avatars store TWO paths:
///   * `avatar_path` — local filesystem path on the device that
///     captured the photo. Only valid on that device.
///   * `avatar_storage_path` — Supabase Storage bucket key.
///     Deterministic per row id, valid on every device.
///
/// SmallAvatar resolves them in order:
///   1. If `path` exists on disk → render Image.file (fast, offline).
///   2. Else if `storagePath` is set → ensureLocalFile downloads
///      to a persistent cache dir, render from there. First render
///      shows the fallback initial; subsequent renders hit the
///      cache instantly.
///   3. Else → fallback initial.
///
/// Without this fallback, syncing a row from another device
/// brought down the `avatar_path` text but the file didn't exist
/// on the receiving filesystem; FileImage failed silently and the
/// avatar appeared blank.
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
  /// Resolved local path to render — either widget.path when
  /// it exists on disk, or the cache path returned by
  /// `ensureLocalFile(widget.storagePath)`. Null until we've
  /// either confirmed a local file or downloaded one.
  String? _resolvedPath;

  @override
  void initState() {
    super.initState();
    unawaited(_resolvePath());
  }

  @override
  void didUpdateWidget(covariant SmallAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.storagePath != widget.storagePath) {
      _resolvedPath = null;
      unawaited(_resolvePath());
    }
  }

  Future<void> _resolvePath() async {
    if (kIsWeb) return; // Web has no local FS; would need a different render path.
    final localPath = widget.path;
    final storagePath = widget.storagePath;

    // Fast path: the local-captured file is right here on disk.
    // existsSync is fine here — initState/didUpdateWidget can
    // afford the synchronous stat (microsecond-level), and the
    // alternative (await File.exists()) trips the lint about
    // slow async IO without a real benefit.
    if (localPath != null && File(localPath).existsSync()) {
      if (!mounted) return;
      setState(() => _resolvedPath = localPath);
      return;
    }

    // Cross-device path: download from cloud storage to a
    // persistent cache dir. ensureLocalFile is idempotent — the
    // cache survives app restarts, so a re-render hits it
    // instantly. First render on a fresh device shows the
    // fallback initial during the download.
    if (storagePath != null && storagePath.isNotEmpty) {
      try {
        final cached = await ref
            .read(mediaServiceProvider)
            .ensureLocalFile(storagePath);
        if (!mounted) return;
        setState(() => _resolvedPath = cached);
      } on Object catch (e) {
        debugPrint('SmallAvatar download failed for $storagePath: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decodeSize = (widget.radius * 4).round();
    final bg = widget.backgroundColor ?? theme.colorScheme.primaryContainer;
    final fg = widget.foregroundColor ?? theme.colorScheme.onPrimaryContainer;
    final resolved = _resolvedPath;

    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: bg,
      backgroundImage: (resolved != null && !kIsWeb)
          ? ResizeImage(
              FileImage(File(resolved)),
              // Clamp width only — see note in AvatarPicker for why.
              width: decodeSize,
            )
          : null,
      // Show the fallback initial when no image source resolved
      // (no local path, no storage path, or download still
      // pending). Hides automatically once `_resolvedPath` is set.
      child: resolved == null
          ? Text(
              widget.fallbackInitial,
              style: theme.textTheme.titleMedium?.copyWith(color: fg),
            )
          : null,
    );
  }
}
