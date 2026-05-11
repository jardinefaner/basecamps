// Prints tab — list of every keepsake card saved from any survey
// kiosk's thank-you screen. Tap to open detail (preview + print +
// delete). Long-press or hit "Select" to enter multi-select mode
// and batch-print several cards into a single PDF. Shared across
// both kiosk styles (marble jar and basket) — same list, same
// actions, polymorphic only on the preview content.

import 'dart:io';

import 'package:basecamp/features/prints/prints_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PrintsScreen extends ConsumerStatefulWidget {
  const PrintsScreen({super.key});

  @override
  ConsumerState<PrintsScreen> createState() => _PrintsScreenState();
}

class _PrintsScreenState extends ConsumerState<PrintsScreen> {
  final Set<String> _selected = <String>{};
  bool _selectMode = false;
  bool _printing = false;

  void _toggleSelect(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        if (_selected.isEmpty) _selectMode = false;
      } else {
        _selected.add(id);
      }
    });
  }

  void _enterSelect(String firstId) {
    setState(() {
      _selectMode = true;
      _selected.add(firstId);
    });
  }

  void _exitSelect() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  void _selectAll(List<SavedPrint> prints) {
    setState(() {
      _selected
        ..clear()
        ..addAll(prints.map((p) => p.id));
    });
  }

  Future<void> _printSelected(List<SavedPrint> all) async {
    if (_selected.isEmpty || _printing) return;
    final byId = {for (final p in all) p.id: p};
    final picks = _selected
        .map((id) => byId[id])
        .whereType<SavedPrint>()
        .toList();
    if (picks.isEmpty) return;
    setState(() => _printing = true);
    try {
      await Printing.layoutPdf(
        name: 'BASECamp prints (${picks.length})',
        onLayout: (format) async => _buildBatchPdf(format, picks),
      );
      if (!mounted) return;
      _exitSelect();
    } on Object catch (e, st) {
      debugPrint('[prints] batch print failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not print: $e')),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<Uint8List> _buildBatchPdf(
    PdfPageFormat format,
    List<SavedPrint> picks,
  ) async {
    final doc = pw.Document();
    for (final p in picks) {
      final bytes = await _readSnapshotBytes(p.absoluteSnapshotPath);
      if (bytes.isEmpty) continue;
      final image = pw.MemoryImage(bytes);
      doc.addPage(
        pw.Page(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(28),
          build: (ctx) => pw.Center(child: pw.Image(image)),
        ),
      );
    }
    return doc.save();
  }

  Future<Uint8List> _readSnapshotBytes(String path) async {
    if (path.startsWith('data:')) {
      return Uri.parse(path).data?.contentAsBytes() ?? Uint8List(0);
    }
    if (kIsWeb) return Uint8List(0);
    return File(path).readAsBytes();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final printsAsync = ref.watch(printsListProvider);
    return Scaffold(
      appBar: AppBar(
        leading: _selectMode
            ? IconButton(
                tooltip: 'Cancel',
                icon: const Icon(Icons.close),
                onPressed: _exitSelect,
              )
            : null,
        title: Text(
          _selectMode
              ? '${_selected.length} selected'
              : 'Prints',
        ),
        actions: [
          printsAsync.maybeWhen(
            data: (prints) {
              if (prints.isEmpty) return const SizedBox.shrink();
              if (_selectMode) {
                return TextButton(
                  onPressed: () => _selectAll(prints),
                  child: const Text('Select all'),
                );
              }
              return TextButton.icon(
                onPressed: () => _enterSelect(prints.first.id),
                icon: const Icon(Icons.checklist),
                label: const Text('Select'),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: printsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (prints) {
          if (prints.isEmpty) return _EmptyState(theme: theme);
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              _selectMode ? 96 : AppSpacing.lg,
            ),
            itemCount: prints.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, i) => _PrintTile(
              print: prints[i],
              selectMode: _selectMode,
              selected: _selected.contains(prints[i].id),
              onTap: () {
                if (_selectMode) {
                  _toggleSelect(prints[i].id);
                } else {
                  context.push('/prints/${prints[i].id}');
                }
              },
              onLongPress: () {
                if (!_selectMode) _enterSelect(prints[i].id);
              },
            ),
          );
        },
      ),
      bottomNavigationBar: _selectMode
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: FilledButton.icon(
                  icon: _printing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print_outlined),
                  label: Text(
                    _selected.isEmpty
                        ? 'Print'
                        : 'Print ${_selected.length} '
                            '${_selected.length == 1 ? "card" : "cards"}',
                  ),
                  onPressed: _selected.isEmpty || _printing
                      ? null
                      : () => _printSelected(
                            printsAsync.asData?.value ??
                                const <SavedPrint>[],
                          ),
                ),
              ),
            )
          : null,
    );
  }
}

class _PrintTile extends StatelessWidget {
  const _PrintTile({
    required this.print,
    required this.selectMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final SavedPrint print;
  final bool selectMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat.MMMd().add_jm();
    final name = print.childName.trim();
    return InkWell(
      borderRadius: AppSpacing.cardBorderRadius,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: AppSpacing.cardPadding,
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
              : theme.colorScheme.surface,
          borderRadius: AppSpacing.cardBorderRadius,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (selectMode) ...[
              Icon(
                selected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            // Thumbnail of the saved snapshot.
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 84,
                height: 84,
                child: ColoredBox(
                  color: theme.colorScheme.surfaceContainer,
                  child: _ThumbnailImage(path: print.absoluteSnapshotPath),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name.isEmpty ? '(no name)' : name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: name.isEmpty
                          ? theme.colorScheme.outline
                          : theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    print.kind.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dateFmt.format(print.createdAt.toLocal()),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            if (!selectMode)
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.outline,
              ),
          ],
        ),
      ),
    );
  }
}

/// Loads either a file (mobile/desktop) or a data URL (web). The
/// repo stores absolute paths on mobile/desktop and data URLs on
/// web; we branch on the prefix.
class _ThumbnailImage extends StatelessWidget {
  const _ThumbnailImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    if (path.startsWith('data:')) {
      // base64-encoded inline image (web fallback)
      try {
        final base64Part = path.split(',').last;
        final bytes = Uri.parse(path).data?.contentAsBytes() ??
            // Fallback if the parser doesn't extract bytes (some
            // Flutter web versions): decode by hand.
            _decodeBase64Bytes(base64Part);
        return Image.memory(bytes, fit: BoxFit.cover);
      } on Object {
        return const Icon(Icons.broken_image_outlined);
      }
    }
    if (kIsWeb) {
      // Should not happen — mobile/desktop only branch — but
      // guard with a placeholder anyway.
      return const Icon(Icons.image_outlined);
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
    );
  }

  Uint8List _decodeBase64Bytes(String s) {
    return Uri.parse('data:application/octet-stream;base64,$s')
            .data
            ?.contentAsBytes() ??
        Uint8List(0);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.print_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No saved prints yet',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'When a child finishes a survey and saves their '
              'card, it lands here for batch-printing later.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
