// Print detail — full-screen preview of a saved keepsake card,
// with actions: Print (pops the system print sheet), Delete
// (soft-delete + back).

import 'dart:io';
import 'dart:typed_data';

import 'package:basecamp/features/prints/prints_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PrintDetailScreen extends ConsumerWidget {
  const PrintDetailScreen({required this.printId, super.key});

  final String printId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncPrint = ref.watch(printByIdProvider(printId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Print'),
        actions: [
          asyncPrint.maybeWhen(
            data: (saved) => saved == null
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmDelete(
                      context: context,
                      ref: ref,
                      printId: saved.id,
                    ),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: asyncPrint.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text('Could not load print: $e')),
        data: (saved) {
          if (saved == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'This print has been deleted.',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            );
          }
          return Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Center(
                    child: _SnapshotPreview(saved: saved),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('Print'),
                          onPressed: () => _print(context, saved),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _print(BuildContext context, SavedPrint saved) async {
    try {
      final bytes = await _readSnapshotBytes(saved.absoluteSnapshotPath);
      await Printing.layoutPdf(
        name: 'BASECamp ${saved.kind.label} — '
            '${saved.childName.isEmpty ? "card" : saved.childName}',
        onLayout: (format) async => _buildPdf(format, bytes),
      );
    } on Object catch (e, st) {
      debugPrint('[print-detail] print failed: $e\n$st');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not print: $e')),
      );
    }
  }

  Future<Uint8List> _readSnapshotBytes(String path) async {
    if (path.startsWith('data:')) {
      final data = Uri.parse(path).data;
      return data?.contentAsBytes() ?? Uint8List(0);
    }
    return File(path).readAsBytes();
  }

  Future<Uint8List> _buildPdf(
    PdfPageFormat format,
    Uint8List png,
  ) async {
    final doc = pw.Document();
    final image = pw.MemoryImage(png);
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => pw.Center(child: pw.Image(image)),
      ),
    );
    return doc.save();
  }

  Future<void> _confirmDelete({
    required BuildContext context,
    required WidgetRef ref,
    required String printId,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this print?'),
        content: const Text(
          "This card won't be printable any more. The kid's "
          'recorded answers stay safe in the survey results.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(printsRepositoryProvider).softDelete(printId);
    if (!context.mounted) return;
    context.pop();
  }
}

class _SnapshotPreview extends StatelessWidget {
  const _SnapshotPreview({required this.saved});

  final SavedPrint saved;

  @override
  Widget build(BuildContext context) {
    if (saved.absoluteSnapshotPath.startsWith('data:')) {
      try {
        final bytes =
            Uri.parse(saved.absoluteSnapshotPath).data?.contentAsBytes();
        if (bytes != null) {
          return Image.memory(bytes, fit: BoxFit.contain);
        }
      } on Object {/* fall through */}
      return const Icon(Icons.broken_image_outlined, size: 56);
    }
    if (kIsWeb) {
      return const Icon(Icons.image_outlined, size: 56);
    }
    return Image.file(
      File(saved.absoluteSnapshotPath),
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) =>
          const Icon(Icons.broken_image_outlined, size: 56),
    );
  }
}
