import 'dart:async';
import 'dart:io' show Directory, File;

import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/media_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:signature/signature.dart';

/// A draw-on-canvas signature pad that expands inline underneath the
/// "Sign now" row. Callers control when it's visible; tapping Save
/// exports the strokes to a PNG and returns it as an [XFile] +
/// timestamp via [onSigned]. Clear wipes the canvas; Cancel closes
/// without saving.
///
/// Web parity: on native we write the PNG to disk first (so the
/// capture device can fast-render via the local path), then wrap
/// the path as `XFile(path)`. On web there's no filesystem, so we
/// return `XFile.fromData(bytes)` directly — the upstream upload
/// reads bytes the same way either platform delivers them.
class InlineSignaturePad extends StatefulWidget {
  const InlineSignaturePad({
    required this.onSigned,
    required this.onCancel,
    super.key,
  });

  /// Called with the freshly-saved signature as an [XFile] + the
  /// moment the teacher committed it. The XFile carries:
  ///   * native — a real disk path the capture device can render
  ///     directly via `Image.file`. The path is also persisted in
  ///     the form data blob for offline render.
  ///   * web — a `blob:` URL (useless to dart:io.File but readable
  ///     via `XFile.readAsBytes`); upload reads the bytes for
  ///     Storage.
  final void Function(XFile signature, DateTime signedAt) onSigned;

  /// Called when the teacher backs out without saving.
  final VoidCallback onCancel;

  @override
  State<InlineSignaturePad> createState() => _InlineSignaturePadState();
}

class _InlineSignaturePadState extends State<InlineSignaturePad> {
  late final SignatureController _ctrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = SignatureController(
      penStrokeWidth: 2.5,
      exportBackgroundColor: Colors.white,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_ctrl.isEmpty) return;
    setState(() => _saving = true);
    try {
      final bytes = await _ctrl.toPngBytes();
      if (bytes == null) return;
      final filename = 'sig_${DateTime.now().millisecondsSinceEpoch}.png';
      final XFile xfile;
      if (kIsWeb) {
        // Web: no filesystem. Wrap bytes directly — upload reads
        // them via XFile.readAsBytes either way.
        xfile = XFile.fromData(
          bytes,
          name: filename,
          mimeType: 'image/png',
          length: bytes.length,
        );
      } else {
        // Native: write to disk first so the capture device can
        // fast-render via the local path on the next form re-open
        // (offline-friendly), then wrap the path as XFile.
        final dir = await getApplicationDocumentsDirectory();
        final sigDir = Directory(p.join(dir.path, 'signatures'));
        if (!sigDir.existsSync()) {
          await sigDir.create(recursive: true);
        }
        final path = p.join(sigDir.path, filename);
        await File(path).writeAsBytes(bytes);
        xfile = XFile(path, name: filename, mimeType: 'image/png');
      }
      if (!mounted) return;
      widget.onSigned(xfile, DateTime.now());
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't save signature: $e")),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.draw_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Sign below',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 180,
            child: Signature(controller: _ctrl),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => _ctrl.clear(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Clear'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: const Text('Save'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only preview of a saved signature PNG. Routes through the
/// shared [MediaImage] pipeline (drift cache + Supabase fallback)
/// so receive devices and web both render correctly.
class SignaturePreview extends StatelessWidget {
  const SignaturePreview({
    required this.localPath,
    required this.storagePath,
    required this.etag,
    super.key,
  });

  /// On-disk path for the capture device's fast offline render.
  /// Null on web + on receive devices.
  final String? localPath;

  /// Cross-device source of truth — the bucket key the upload
  /// stamped after the pad's bytes hit Storage.
  final String? storagePath;

  /// Per-upload content tag for cache invalidation when a
  /// signature is replaced (rare for signatures, but uniform with
  /// the rest of the media pipeline).
  final String? etag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 3,
        child: MediaImage(
          source: MediaSource(
            localPath: localPath,
            storagePath: storagePath,
            etag: etag,
          ),
          fit: BoxFit.contain,
          // Pen-thin strokes — full resolution isn't needed.
          cacheWidth: 600,
          errorPlaceholder: Center(
            child: Text(
              'Missing signature',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
