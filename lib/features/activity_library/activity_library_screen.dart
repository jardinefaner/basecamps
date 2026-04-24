import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/activity_library/activity_card_ai.dart';
import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:basecamp/features/activity_library/library_usages_repository.dart';
import 'package:basecamp/features/activity_library/widgets/activity_card_preview.dart';
import 'package:basecamp/features/activity_library/widgets/edit_library_item_sheet.dart';
import 'package:basecamp/features/activity_library/widgets/library_card_detail_sheet.dart';
import 'package:basecamp/features/activity_library/widgets/library_filter_header.dart';
import 'package:basecamp/features/activity_library/widgets/new_library_item_wizard.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/features/schedule/widgets/new_activity_wizard.dart';
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
  final _searchCtrl = TextEditingController();
  String _query = '';
  LibraryAgeBand _band = LibraryAgeBand.all;
  ObservationDomain? _domain;
  bool _requireMaterials = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

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

  Future<void> _scheduleFromLibrary(ActivityLibraryData item) async {
    await Navigator.of(context).push<CreatedActivity>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => NewActivityWizardScreen(initialLibraryItem: item),
      ),
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
            final domainsMap =
                ref.watch(allLibraryDomainTagsProvider).asData?.value ??
                    const <String, Set<String>>{};
            // "Recently used" is the default sort — teacher's last
            // week of picks are the ones most likely to be wanted
            // again. Never-used cards slide to the bottom but keep
            // their newest-first ordering so freshly-generated cards
            // still surface. No user-visible toggle for now: list
            // screen's job is to surface the right cards, not offer
            // preferences.
            final recentUsages =
                ref.watch(recentLibraryUsagesProvider(500)).asData?.value ??
                    const [];
            final lastUsed = <String, DateTime>{};
            for (final u in recentUsages) {
              final existing = lastUsed[u.libraryItemId];
              if (existing == null || u.createdAt.isAfter(existing)) {
                lastUsed[u.libraryItemId] = u.createdAt;
              }
            }
            final sortedItems = [...items]..sort((a, b) {
                final au = lastUsed[a.id];
                final bu = lastUsed[b.id];
                if (au == null && bu == null) {
                  return b.createdAt.compareTo(a.createdAt);
                }
                if (au == null) return 1;
                if (bu == null) return -1;
                return bu.compareTo(au);
              });
            final filtered = [
              for (final item in sortedItems)
                if (matchesLibraryFilter(
                  item,
                  query: _query,
                  band: _band,
                  domain: _domain,
                  itemDomains: domainsMap,
                  requireMaterials: _requireMaterials,
                ))
                  item,
            ];
            return Column(
              children: [
                LibraryFilterHeader(
                  searchController: _searchCtrl,
                  onSearchChanged: (v) => setState(() => _query = v),
                  band: _band,
                  onBandChanged: (b) => setState(() => _band = b),
                  domain: _domain,
                  onDomainChanged: (d) => setState(() => _domain = d),
                  requireMaterials: _requireMaterials,
                  onRequireMaterialsChanged: (v) =>
                      setState(() => _requireMaterials = v),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? _NoMatchesState(query: _query, band: _band)
                      : ListView.separated(
                          padding: const EdgeInsets.only(
                            left: AppSpacing.lg,
                            right: AppSpacing.lg,
                            top: AppSpacing.md,
                            bottom: AppSpacing.xxxl * 2,
                          ),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.md),
                          itemBuilder: (_, i) {
                            final item = filtered[i];
                            return _LibraryTile(
                              item: item,
                              selected: isSelected(item.id),
                              onTap: isSelecting
                                  ? () => toggleSelection(item.id)
                                  : () => _openSheet(item: item),
                              onLongPress: () => toggleSelection(item.id),
                              onSchedule: isSelecting
                                  ? null
                                  : () => _scheduleFromLibrary(item),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LibraryTile extends ConsumerWidget {
  const _LibraryTile({
    required this.item,
    required this.onTap,
    required this.onLongPress,
    this.onSchedule,
    this.selected = false,
  });

  final ActivityLibraryData item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onSchedule;
  final bool selected;

  /// True for rows populated by the new AI-card flow — they have at
  /// minimum a summary and an audience. Legacy preset rows (title +
  /// duration only) fall back to the tight tile layout.
  bool get _isRichCard =>
      item.summary != null ||
      item.audienceMinAge != null ||
      item.hook != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastUsedAsync = ref.watch(lastUsedAtProvider(item.id));
    final lastUsed = lastUsedAsync.asData?.value;
    if (_isRichCard) {
      return InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                _TileFooter(
                  lastUsed: lastUsed,
                  onSchedule: onSchedule,
                ),
              ],
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
      onSchedule: onSchedule,
      selected: selected,
      lastUsed: lastUsed,
    );
  }
}

/// Small strip under each card showing "used 3d ago" plus a compact
/// Schedule action. Kept as a plain row rather than a trailing icon
/// on the card so the schedule tap doesn't compete with the main
/// card tap.
class _TileFooter extends StatelessWidget {
  const _TileFooter({required this.lastUsed, required this.onSchedule});

  final DateTime? lastUsed;
  final VoidCallback? onSchedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.xs,
        bottom: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(
            Icons.history,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              lastUsed == null
                  ? 'Never used'
                  : 'Used ${relativePast(lastUsed!)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (onSchedule != null)
            TextButton.icon(
              onPressed: onSchedule,
              icon: const Icon(Icons.event_available_outlined, size: 16),
              label: const Text('Schedule'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tiny relative-time formatter. Public so the card detail sheet can
/// reuse it without pulling in a full i18n layer. Handles the
/// "yesterday / N days / N weeks / N months" ladder we actually care
/// about for library cards; anything older collapses to "months ago".
String relativePast(DateTime then) {
  final now = DateTime.now();
  final diff = now.difference(then);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 2) return 'yesterday';
  if (diff.inDays < 14) return '${diff.inDays}d ago';
  if (diff.inDays < 60) return '${(diff.inDays / 7).floor()}w ago';
  return '${(diff.inDays / 30).floor()}mo ago';
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
    required this.lastUsed,
    this.onSchedule,
  });

  final ActivityLibraryData item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selected;
  final DateTime? lastUsed;
  final VoidCallback? onSchedule;

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
    sub.add(lastUsed == null ? 'Never used' : 'Used ${relativePast(lastUsed!)}');
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
          if (onSchedule != null)
            IconButton(
              tooltip: 'Schedule',
              icon: const Icon(Icons.event_available_outlined),
              onPressed: onSchedule,
            )
          else
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }
}

class _NoMatchesState extends StatelessWidget {
  const _NoMatchesState({required this.query, required this.band});

  final String query;
  final LibraryAgeBand band;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = query.trim();
    final String message;
    if (trimmed.isNotEmpty) {
      message = "No activities match '$trimmed'.";
    } else if (band != LibraryAgeBand.all) {
      message = 'No activities in ${libraryAgeBandLabels[band]!.toLowerCase()}.';
    } else {
      message = 'No activities match.';
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
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
