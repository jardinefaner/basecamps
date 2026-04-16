import 'dart:async';
import 'dart:io';

import 'package:basecamp/theme/spacing.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// One item captured during a camera session.
class CapturedMedia {
  const CapturedMedia({required this.path, required this.kind});

  final String path;

  /// 'photo' or 'video'.
  final String kind;
}

enum _CaptureMode { photo, video }

/// Full-screen camera that stays open between shots. Teachers tap the
/// shutter, see a thumbnail land in the strip, and keep capturing —
/// tapping Done returns the full batch to the composer. Supports pinch
/// zoom and a Photo/Video mode toggle, so switching media type doesn't
/// require closing and re-opening the picker.
///
/// Call [open] from a screen/sheet — pops with `List<CapturedMedia>`.
/// An empty list means the user backed out with no shots.
class MultiCaptureCamera extends StatefulWidget {
  const MultiCaptureCamera({super.key});

  static Future<List<CapturedMedia>> open(BuildContext context) async {
    final result = await Navigator.of(context).push<List<CapturedMedia>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const MultiCaptureCamera(),
      ),
    );
    return result ?? const [];
  }

  @override
  State<MultiCaptureCamera> createState() => _MultiCaptureCameraState();
}

class _MultiCaptureCameraState extends State<MultiCaptureCamera>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  Object? _initError;

  _CaptureMode _mode = _CaptureMode.photo;
  bool _busy = false;
  bool _recording = false;
  DateTime? _recordingStarted;

  // Zoom state. Pinch gesture scales between [_minZoom, _maxZoom] and
  // we apply it to the camera controller. Kept in state so the overlay
  // label can show "1.2×", etc.
  double _minZoom = 1;
  double _maxZoom = 1;
  double _currentZoom = 1;
  double _zoomBaseline = 1;

  final List<CapturedMedia> _captured = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeCameras());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    // Standard pattern: tear down on background, re-init on resume —
    // otherwise iOS revokes the camera and we come back to a dead
    // preview.
    if (state == AppLifecycleState.inactive) {
      unawaited(controller.dispose());
    } else if (state == AppLifecycleState.resumed) {
      if (_cameras.isNotEmpty) {
        unawaited(_bindCamera(_cameras[_cameraIndex]));
      }
    }
  }

  Future<void> _initializeCameras() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() => _initError = 'No camera available on this device.');
        return;
      }
      // Prefer the back camera — that's what teachers almost always want
      // for capturing kids across the room.
      final backIndex = cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      _cameras = cameras;
      _cameraIndex = backIndex == -1 ? 0 : backIndex;
      await _bindCamera(cameras[_cameraIndex]);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _initError = e);
    }
  }

  Future<void> _bindCamera(CameraDescription description) async {
    // enableAudio defaults to true; we keep it on so video mode records
    // sound without a second switch.
    final controller = CameraController(
      description,
      ResolutionPreset.high,
    );
    try {
      await controller.initialize();
      final minZ = await controller.getMinZoomLevel();
      final maxZ = await controller.getMaxZoomLevel();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _minZoom = minZ;
        _maxZoom = maxZ;
        _currentZoom = minZ;
        _initError = null;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _initError = e);
    }
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || _recording) return;
    final old = _controller;
    setState(() => _controller = null);
    await old?.dispose();
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _bindCamera(_cameras[_cameraIndex]);
  }

  Future<void> _takePhoto() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await c.takePicture();
      if (!mounted) return;
      setState(() {
        _captured.add(CapturedMedia(path: file.path, kind: 'photo'));
      });
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't capture photo: $e")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleVideo() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (_recording) {
      setState(() => _busy = true);
      try {
        final file = await c.stopVideoRecording();
        if (!mounted) return;
        setState(() {
          _captured.add(CapturedMedia(path: file.path, kind: 'video'));
          _recording = false;
          _recordingStarted = null;
        });
      } on Object catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't finish recording: $e")),
        );
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } else {
      try {
        await c.startVideoRecording();
        if (!mounted) return;
        setState(() {
          _recording = true;
          _recordingStarted = DateTime.now();
        });
      } on Object catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't start recording: $e")),
        );
      }
    }
  }

  Future<void> _setZoom(double target) async {
    final c = _controller;
    if (c == null) return;
    final clamped = target.clamp(_minZoom, _maxZoom);
    await c.setZoomLevel(clamped);
    if (!mounted) return;
    setState(() => _currentZoom = clamped);
  }

  void _removeCaptured(int index) {
    setState(() => _captured.removeAt(index));
  }

  Future<void> _done() async {
    // If a recording is still in-flight, end it before returning so the
    // teacher doesn't lose the clip.
    if (_recording) {
      await _toggleVideo();
    }
    if (!mounted) return;
    Navigator.of(context).pop(_captured);
  }

  @override
  Widget build(BuildContext context) {
    final isVideoMode = _mode == _CaptureMode.video;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _PreviewArea(
            controller: _controller,
            initError: _initError,
            onScaleStart: (_) => _zoomBaseline = _currentZoom,
            onScaleUpdate: (details) {
              unawaited(_setZoom(_zoomBaseline * details.scale));
            },
          ),

          // Top row: close, zoom readout, recording indicator, flip
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  _pill(
                    child: IconButton(
                      tooltip: 'Back',
                      onPressed: _done,
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                  const Spacer(),
                  if (_recording)
                    _RecordingIndicator(startedAt: _recordingStarted),
                  if (!_recording && _maxZoom > _minZoom + 0.01) ...[
                    _pill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.xs,
                        ),
                        child: Text(
                          '${_currentZoom.toStringAsFixed(1)}×',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  if (!_recording && _cameras.length > 1)
                    _pill(
                      child: IconButton(
                        tooltip: 'Flip camera',
                        onPressed: _flipCamera,
                        icon: const Icon(
                          Icons.cameraswitch_outlined,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Bottom: captured strip + mode toggle + shutter + done
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_captured.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _CapturedStrip(
                          items: _captured,
                          onRemove: _removeCaptured,
                        ),
                      ),
                    if (!_recording) _modeToggle(),
                    const SizedBox(height: AppSpacing.md),
                    _shutterRow(isVideoMode),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill({required Widget child}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }

  Widget _modeToggle() {
    return SegmentedButton<_CaptureMode>(
      segments: const [
        ButtonSegment(
          value: _CaptureMode.photo,
          label: Text('Photo'),
          icon: Icon(Icons.camera_alt_outlined),
        ),
        ButtonSegment(
          value: _CaptureMode.video,
          label: Text('Video'),
          icon: Icon(Icons.videocam_outlined),
        ),
      ],
      selected: {_mode},
      onSelectionChanged: (s) => setState(() => _mode = s.first),
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        foregroundColor: Colors.white,
        selectedForegroundColor: Colors.black,
        selectedBackgroundColor: Colors.white,
        side: const BorderSide(color: Colors.white54),
      ),
    );
  }

  Widget _shutterRow(bool isVideoMode) {
    final onShutter =
        _mode == _CaptureMode.photo ? _takePhoto : _toggleVideo;
    final ready = _controller?.value.isInitialized ?? false;

    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: _pill(
              child: TextButton.icon(
                onPressed: _captured.isEmpty ? null : _done,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white38,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                ),
                icon: const Icon(Icons.check),
                label: Text(
                  _captured.isEmpty ? 'Done' : 'Done (${_captured.length})',
                ),
              ),
            ),
          ),
        ),
        _ShutterButton(
          onTap: ready && !_busy ? onShutter : null,
          recording: _recording,
          isVideo: isVideoMode,
        ),
        const Expanded(child: SizedBox()),
      ],
    );
  }
}

class _PreviewArea extends StatelessWidget {
  const _PreviewArea({
    required this.controller,
    required this.initError,
    required this.onScaleStart,
    required this.onScaleUpdate,
  });

  final CameraController? controller;
  final Object? initError;
  final ValueChanged<ScaleStartDetails> onScaleStart;
  final ValueChanged<ScaleUpdateDetails> onScaleUpdate;

  @override
  Widget build(BuildContext context) {
    if (initError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.videocam_off_outlined,
                size: 56,
                color: Colors.white70,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Camera unavailable.\n$initError',
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    final c = controller;
    if (c == null || !c.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    // The camera plugin reports `aspectRatio` in the sensor's native
    // landscape orientation (width > height). CameraPreview, meanwhile,
    // is just a Texture — it stretches to fill whatever bounds we give
    // it and doesn't auto-correct for orientation. So in portrait we
    // flip the ratio, then scale the preview up with a cover-fill so
    // the viewfinder fills the whole screen like a native camera app
    // (cropping the overflow edges rather than showing black bars).
    final size = MediaQuery.sizeOf(context);
    final isPortrait = size.height >= size.width;
    final sensorRatio = c.value.aspectRatio;
    final previewRatio = isPortrait ? 1 / sensorRatio : sensorRatio;
    final screenRatio = size.width / size.height;

    final scale = screenRatio > previewRatio
        ? screenRatio / previewRatio
        : previewRatio / screenRatio;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: onScaleStart,
      onScaleUpdate: onScaleUpdate,
      child: ClipRect(
        child: Transform.scale(
          scale: scale,
          child: Center(
            child: AspectRatio(
              aspectRatio: previewRatio,
              child: CameraPreview(c),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({
    required this.onTap,
    required this.recording,
    required this.isVideo,
  });

  final VoidCallback? onTap;
  final bool recording;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 80,
        height: 80,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: enabled ? Colors.white : Colors.white38,
                  width: 4,
                ),
              ),
            ),
            // AnimatedContainer interpolates shape + borderRadius in
            // lockstep, which trips the "circle + borderRadius" assertion
            // mid-tween. Keep the shape as a rectangle and animate the
            // radius instead: half-size = circle, 6px = rounded square.
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: recording ? 30 : 60,
              height: recording ? 30 : 60,
              decoration: BoxDecoration(
                color: isVideo || recording ? Colors.red : Colors.white,
                borderRadius: BorderRadius.circular(recording ? 6 : 30),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingIndicator extends StatefulWidget {
  const _RecordingIndicator({required this.startedAt});

  final DateTime? startedAt;

  @override
  State<_RecordingIndicator> createState() => _RecordingIndicatorState();
}

class _RecordingIndicatorState extends State<_RecordingIndicator> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final started = widget.startedAt;
    final elapsed = started == null
        ? Duration.zero
        : DateTime.now().difference(started);
    final mins = elapsed.inMinutes.toString().padLeft(2, '0');
    final secs = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _PulseDot(),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '$mins:$secs',
              style: const TextStyle(
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1).animate(_ac),
      child: const CircleAvatar(
        radius: 5,
        backgroundColor: Colors.red,
      ),
    );
  }
}

class _CapturedStrip extends StatelessWidget {
  const _CapturedStrip({required this.items, required this.onRemove});

  final List<CapturedMedia> items;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final item = items[i];
          final isPhoto = item.kind == 'photo';
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 64,
                height: 64,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white54),
                ),
                child: isPhoto
                    ? Image.file(
                        File(item.path),
                        fit: BoxFit.cover,
                        cacheWidth: 128,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.image_outlined,
                          color: Colors.white70,
                        ),
                      )
                    : const Icon(
                        Icons.play_circle_outline,
                        color: Colors.white,
                      ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onRemove(i),
                  child: const CircleAvatar(
                    radius: 10,
                    backgroundColor: Colors.black87,
                    child: Icon(
                      Icons.close,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
