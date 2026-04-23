import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/activity_library/activity_card_ai.dart';
import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:basecamp/features/activity_library/widgets/activity_card_preview.dart';
import 'package:basecamp/features/activity_library/widgets/edit_library_item_sheet.dart';
import 'package:basecamp/features/activity_library/widgets/library_card_detail_sheet.dart';
import 'package:basecamp/features/activity_library/widgets/new_library_item_wizard.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/bulk_selection.dart';
import 'package:basecamp/ui/undo_delete.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ActivityLibraryScreen extends ConsumerStatefulWidget {
  const ActivityLibraryScreen({super.key});

  @override
  ConsumerState<ActivityLibraryScreen> createState() =>
      _ActivityLibraryScreenState();
}

class _ActivityLibraryScreenState extends ConsumerState<ActivityLibraryScreen>
    with BulkSelectionMixin {
  Future<void> _openSheet({ActivityLibraryData? item}) async {
    // Create flow uses the wizard; existing rows open a surface that
    // matches their shape.
    if (item == null) {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const NewLibraryItemWizardScreen(),
        ),
      );
      if (saved == true && mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
              content: Text('Added to your activity bucket'),
              duration: Duration(seconds: 2),
            ),
          );
      }
      return;
    }
    // Rich AI cards → full detail view so the teacher can actually
    // *see* what they saved (hook, summary, key points, goals, source).
    // Previously this jumped straight to the dense preset-edit sheet,
    // which hid every AI field — saving a card felt one-way.
    // Legacy preset-only rows still use the edit sheet directly.
    final isRichCard = item.summary != null ||
        item.audienceMinAge != null ||
        item.hook != null;
    if (isRichCard) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (_) => LibraryCardDetailSheet(item: item),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditLibraryItemSheet(item: item),
    );
  }

  Future<void> _deleteSelected() async {
    final count = selectedCount;
    if (count == 0) return;
    final toDelete = selectedIds.toList();
    final all =
        ref.read(activityLibraryProvider).asData?.value ??
            const <ActivityLibraryData>[];
    final snapshot = [
      for (final row in all)
        if (toDelete.contains(row.id)) row,
    ];
    final confirmed = await confirmDeleteWithUndo(
      context: context,
      title: count == 1
          ? 'Delete this library item?'
          : 'Delete $count library items?',
      message:
          'Schedule rows pulled from these presets keep their current '
          "values — only the reusable template goes away. You'll "
          'get a 5-second window to undo.',
      confirmLabel: count == 1 ? 'Delete' : 'Delete $count',
      onDelete: () => ref
          .read(activityLibraryRepositoryProvider)
          .deleteItems(toDelete),
      undoLabel: count == 1
          ? 'Library item removed'
          : '$count library items removed',
      onUndo: () => ref
          .read(activityLibraryRepositoryProvider)
          .restoreItems(snapshot),
    );
    if (!confirmed || !mounted) return;
    clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(activityLibraryProvider);

    return PopScope(
      canPop: !isSelecting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (isSelecting) clearSelection();
      },
      child: Scaffold(
        appBar: isSelecting
            ? buildSelectionAppBar(
                context: context,
                count: selectedCount,
                onCancel: clearSelection,
                onDelete: _deleteSelected,
              )
            : AppBar(title: const Text('Activity library')),
        floatingActionButton: isSelecting
            ? null
            : FloatingActionButton.extended(
                onPressed: _openSheet,
                icon: const Icon(Icons.add),
                label: const Text('Activity'),
              ),
        body: itemsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Error: $err')),
          data: (items) {
            if (items.isEmpty) {
              return _EmptyState(onAdd: _openSheet);
            }
            return ListView.separated(
              padding: const EdgeInsets.only(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                top: AppSpacing.md,
                bottom: AppSpacing.xxxl * 2,
              ),
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (_, i) {
                final item = items[i];
                return _LibraryTile(
                  item: item,
                  selected: isSelected(item.id),
                  onTap: isSelecting
                      ? () => toggleSelection(item.id)
                      : () => _openSheet(item: item),
                  onLongPress: () => toggleSelection(item.id),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.item,
    required this.onTap,
    required this.onLongPress,
    this.selected = false,
  });

  final ActivityLibraryData item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selected;

  /// True for rows populated by the new AI-card flow — they have at
  /// minimum a summary and an audience. Legacy preset rows (title +
  /// duration only) fall back to the tight tile layout.
  bool get _isRichCard =>
      item.summary != null ||
      item.audienceMinAge != null ||
      item.hook != null;

  @override
  Widget build(BuildContext context) {
    if (_isRichCard) {
      return InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            ActivityCardPreview(
              title: item.title,
              audienceLabel: item.audienceMinAge != null &&
                      item.audienceMaxAge != null
                  ? audienceLabelFor(
                      item.audienceMinAge!,
                      item.audienceMaxAge!,
                    )
                  : null,
              hook: item.hook,
              summary: item.summary,
              engagementTimeMin: item.engagementTimeMin,
              sourceAttribution: item.sourceAttribution,
              compact: true,
            ),
            if (selected)
              Positioned(
                top: 8,
                right: 8,
                child: _SelectBadge(),
              ),
          ],
        ),
      );
    }
    return _LegacyTile(
      item: item,
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,
    );
  }
}

class _SelectBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.check,
        size: 14,
        color: theme.colorScheme.onPrimary,
      ),
    );
  }
}

class _LegacyTile extends StatelessWidget {
  const _LegacyTile({
    required this.item,
    required this.onTap,
    required this.onLongPress,
    required this.selected,
  });

  final ActivityLibraryData item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sub = <String>[];
    if (item.defaultDurationMin != null) {
      sub.add('${item.defaultDurationMin} min');
    }
    if (item.location != null && item.location!.isNotEmpty) {
      sub.add(item.location!);
    }
    return AppCard(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.bookmark_outline,
              color: theme.colorScheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: theme.textTheme.titleMedium),
                if (sub.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      sub.join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmarks_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No saved activities', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Save common activities like "Morning Circle" or "Snack" '
              'to reuse them without re-typing every field.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add activity'),
            ),
          ],
        ),
      ),
    );
  }
}
