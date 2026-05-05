// Prints tab — list of every keepsake card saved from any survey
// kiosk's thank-you screen. Tap to open detail (preview + print +
// delete). Shared across both kiosk styles (marble jar and
// basket) — same list, same actions, polymorphic only on the
// preview content.

import 'dart:io';

import 'package:basecamp/features/prints/prints_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class PrintsScreen extends ConsumerWidget {
  const PrintsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final printsAsync = ref.watch(printsListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Prints')),
      body: printsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (prints) {
          if (prints.isEmpty) return _EmptyState(theme: theme);
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: prints.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, i) => _PrintTile(print: prints[i]),
          );
        },
      ),
    );
  }
}

class _PrintTile extends StatelessWidget {
  const _PrintTile({required this.print});

  final SavedPrint print;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat.MMMd().add_jm();
    final name = print.childName.trim();
    return InkWell(
      borderRadius: AppSpacing.cardBorderRadius,
      onTap: () => context.push('/prints/${print.id}'),
      child: Container(
        padding: AppSpacing.cardPadding,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: AppSpacing.cardBorderRadius,
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
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
