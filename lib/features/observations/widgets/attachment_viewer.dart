import 'dart:async';
import 'dart:io';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/confirm_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Callback the viewer uses to remove an attachment. Implementations
/// should delete both the DB row and the local file — the repo's
/// `deleteAttachment(id)` already does both, so wiring this up is
/// usually `(a) => repo.deleteAttachment(a.id)`.
typedef AttachmentDeleter = Future<void> Function(
  ObservationAttachment attachment,
);

/// Full-screen gallery for an observation's attachments. Pinch-to-zoom
/// for photos, real playback for videos. Swipe left/right between
/// items. When [onDelete] is non-null, a trash icon shows in the top
/// bar and tapping it confirms, removes the item, and either advances
/// to the next page or closes the viewer if the list empties.
class AttachmentViewer extends StatefulWidget {
  const AttachmentViewer({
    required this.attachments,
    this.initialIndex = 0,
    this.onDelete,
    super.key,
  });

  final List<ObservationAttachment> attachments;
  final int initialIndex;
  final AttachmentDeleter? onDelete;

  static Future<void> open(
    BuildContext context,
    List<ObservationAttachment> attachments, {
    int initialIndex = 0,
    AttachmentDeleter? onDelete,
  }) {
    if (attachments.isEmpty) return Future.value();
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AttachmentViewer(
          attachments: attachments,
          initialIndex: initialIndex,
          onDelete: onDelete,
        ),
      ),
    );
  }

  @override
  State<AttachmentViewer> createState() => _AttachmentViewerState();
}

class _AttachmentViewerState extends State<AttachmentViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  // Local mutable copy so the viewer can react to deletes without
  // waiting on parent stream rebuilds.
  late final List<ObservationAttachment> _items =
      List<ObservationAttachment>.from(widget.attachments);

  bool _deleting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDelete() async {
    if (_deleting || widget.onDelete == null || _items.isEmpty) return;
    final current = _items[_index];
    final confirmed = await showConfirmDialog(
      context: context,
      title: current.kind == 'video' ? 'Delete this video?' : 'Delete this photo?',
      message: 'This removes it from the observation. The file '
          'itself stays on the device until the next app launch '
          'in case you change your mind — reopen the observation '
          'to re-attach.',
    );
    if (!confirmed || !mounted) return;

    setState(() => _deleting = true);
    try {
      await widget.onDelete!(current);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
    if (!mounted) return;

    setState(() => _items.removeAt(_index));

    // Empty? close. Otherwise keep index within bounds; the page
    // controller doesn't track removals automatically, so nudge it.
    if (_items.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final nextIndex = _index.clamp(0, _items.length - 1);
    _index = nextIndex;
    unawaited(_controller.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: _items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final att = _items[i];
              if (att.kind == 'video') {
                return _VideoPage(
                  key: ValueKey('video-${att.id}'),
                  path: att.localPath,
                );
              }
              return _PhotoPage(path: att.localPath);
            },
          ),
          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                    ),
                  ),
                  const Spacer(),
                  if (_items.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${_index + 1} / ${_items.length}',
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: Colors.white),
                      ),
                    ),
                  if (widget.onDelete != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    IconButton(
                      tooltip: 'Delete',
                      onPressed: _deleting ? null : _handleDelete,
                      icon: _deleting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.delete_outline,
                              color: Colors.white,
                            ),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoPage extends StatelessWidget {
  const _PhotoPage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: kIsWeb
            ? const _WebUnsupported(icon: Icons.image_outlined)
            : Image.file(
                File(path),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const _ErrorBlock(
                  icon: Icons.broken_image_outlined,
                  message: 'Could not load image',
                ),
              ),
      ),
    );
  }
}

class _VideoPage extends StatefulWidget {
  const _VideoPage({required this.path, super.key});

  final String path;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  VideoPlayerController? _controller;
  Object? _initError;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final controller = kIsWeb
          ? VideoPlayerController.networkUrl(Uri.parse(widget.path))
          : VideoPlayerController.file(File(widget.path));
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onTick);
      setState(() => _controller = controller);
      await controller.play();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _initError = e);
    }
  }

  void _onTick() {
    // Rebuild to update play/pause icon + position.
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      unawaited(c.pause());
    } else {
      unawaited(c.play());
    }
    setState(() => _showControls = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return const _ErrorBlock(
        icon: Icons.videocam_off_outlined,
        message: 'Could not play this video',
      );
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return GestureDetector(
      onTap: () => setState(() => _showControls = !_showControls),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: c.value.aspectRatio,
              child: VideoPlayer(c),
            ),
          ),
          if (_showControls) ...[
            Center(
              child: IconButton(
                iconSize: 64,
                onPressed: _togglePlay,
                icon: Icon(
                  c.value.isPlaying
                      ? Icons.pause_circle
                      : Icons.play_circle,
                  color: Colors.white,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.md,
                ),
                child: VideoProgressIndicator(
                  c,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.white,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white12,
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.sm,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WebUnsupported extends StatelessWidget {
  const _WebUnsupported({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.white70, size: 64),
        const SizedBox(height: AppSpacing.md),
        const Text(
          'Photo viewing is mobile-only for now.',
          style: TextStyle(color: Colors.white70),
        ),
      ],
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 56),
          const SizedBox(height: AppSpacing.md),
          Text(message, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}
