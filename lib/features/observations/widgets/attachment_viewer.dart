import 'dart:async';
import 'dart:io';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Full-screen gallery for an observation's attachments. Pinch-to-zoom
/// for photos, real playback for videos. Swipe left/right between items.
class AttachmentViewer extends StatefulWidget {
  const AttachmentViewer({
    required this.attachments,
    this.initialIndex = 0,
    super.key,
  });

  final List<ObservationAttachment> attachments;
  final int initialIndex;

  static Future<void> open(
    BuildContext context,
    List<ObservationAttachment> attachments, {
    int initialIndex = 0,
  }) {
    if (attachments.isEmpty) return Future.value();
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AttachmentViewer(
          attachments: attachments,
          initialIndex: initialIndex,
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.attachments.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final att = widget.attachments[i];
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
                  if (widget.attachments.length > 1)
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
                        '${_index + 1} / ${widget.attachments.length}',
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: Colors.white),
                      ),
                    ),
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
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _showControls = !_showControls),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: c.value.aspectRatio,
              child: VideoPlayer(c),
            ),
          ),
          if (_showControls)
            IconButton(
              iconSize: 80,
              onPressed: _togglePlay,
              icon: Icon(
                c.value.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _VideoProgressBar(controller: c),
          ),
        ],
      ),
    );
  }
}

class _VideoProgressBar extends StatelessWidget {
  const _VideoProgressBar({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.md,
        ),
        child: VideoProgressIndicator(
          controller,
          allowScrubbing: true,
          colors: const VideoProgressColors(
            playedColor: Colors.white,
            bufferedColor: Colors.white24,
            backgroundColor: Colors.white12,
          ),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        ),
      ),
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
          Icon(icon, size: 56, color: Colors.white70),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            style: const TextStyle(color: Colors.white70),
          ),
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
    return _ErrorBlock(
      icon: icon,
      message: 'Preview not supported on web',
    );
  }
}
