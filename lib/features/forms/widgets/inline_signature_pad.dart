import 'dart:async';
import 'dart:io';

import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:signature/signature.dart';

/// A draw-on-canvas signature pad that expands inline underneath the
/// "Sign now" row. Callers control when it's visible; tapping Save
/// exports the strokes to a PNG on local disk and returns the path +
/// a timestamp via [onSigned]. Clear wipes the canvas; Cancel closes
/// without saving.
///
/// No reliance on a persistent SignatureController in the parent — the
/// controller lives inside the widget so open/close fully resets the
/// drawing state.
class InlineSignaturePad extends StatefulWidget {
  const InlineSignaturePad({
    required this.onSigned,
    required this.onCancel,
    super.key,
  });

  /// Called with the PNG path on disk + the moment the teacher
  /// committed the signature.
  final void Function(String path, DateTime signedAt) onSigned;

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
      final dir = await getApplicationDocumentsDirectory();
      final sigDir = Directory(p.join(dir.path, 'signatures'));
      if (!sigDir.existsSync()) {
        await sigDir.create(recursive: true);
      }
      final path = p.join(
        sigDir.path,
        'sig_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await File(path).writeAsBytes(bytes);
      if (!mounted) return;
      widget.onSigned(path, DateTime.now());
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

/// Read-only preview of a saved signature PNG.
class SignaturePreview extends StatelessWidget {
  const SignaturePreview({required this.path, super.key});

  final String path;

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
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          // Decode the strokes at a reasonable width — signatures are
          // pen-thin so we don't need full resolution.
          cacheWidth: 600,
          errorBuilder: (_, _, _) => Center(
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
