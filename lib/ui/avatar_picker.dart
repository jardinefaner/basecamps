import 'dart:async';
import 'dart:io';

import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
class SmallAvatar extends StatelessWidget {
  const SmallAvatar({
    required this.path,
    required this.fallbackInitial,
    this.radius = 20,
    this.backgroundColor,
    this.foregroundColor,
    super.key,
  });

  final String? path;
  final String fallbackInitial;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decodeSize = (radius * 4).round();
    final bg = backgroundColor ?? theme.colorScheme.primaryContainer;
    final fg = foregroundColor ?? theme.colorScheme.onPrimaryContainer;

    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      backgroundImage: (path != null && !kIsWeb)
          ? ResizeImage(
              FileImage(File(path!)),
              // Clamp width only — see note in AvatarPicker for why.
              width: decodeSize,
            )
          : null,
      child: path == null
          ? Text(
              fallbackInitial,
              style: theme.textTheme.titleMedium?.copyWith(color: fg),
            )
          : null,
    );
  }
}
