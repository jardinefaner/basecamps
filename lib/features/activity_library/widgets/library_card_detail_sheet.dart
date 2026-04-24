import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/activity_library/activity_card_ai.dart';
import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:basecamp/features/activity_library/library_usages_repository.dart';
import 'package:basecamp/features/activity_library/widgets/activity_card_preview.dart';
import 'package:basecamp/features/activity_library/widgets/edit_library_item_sheet.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/features/schedule/widgets/new_activity_wizard.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/undo_delete.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full-view bottom sheet for a saved activity-library card. Opens
/// when the teacher taps a rich card in the library list — previously
/// a tap jumped straight to the dense preset-edit sheet, which hid
/// every AI-generated field and made saved cards feel one-way.
///
/// Actions at the bottom:
///   - Edit (preset fields only — title/duration/adult/location
///     /notes via the existing EditLibraryItemSheet)
///   - Delete (with confirm)
///   - Copy link (when a sourceUrl is set)
class LibraryCardDetailSheet extends ConsumerWidget {
  const LibraryCardDetailSheet({required this.item, super.key});

  final ActivityLibraryData item;

  Future<void> _openEdit(BuildContext context) async {
    final navigator = Navigator.of(context)..pop();
    await showModalBottomSheet<void>(
      context: navigator.context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditLibraryItemSheet(item: item),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final confirmed = await confirmDeleteWithUndo(
      context: context,
      title: 'Delete this activity?',
      message: "It'll be removed from your bucket. You'll get a "
          '5-second window to undo.',
      onDelete: () => ref
          .read(activityLibraryRepositoryProvider)
          .deleteItem(item.id),
      undoLabel: '"${item.title}" removed',
      onUndo: () => ref
          .read(activityLibraryRepositoryProvider)
          .restoreItem(item),
    );
    if (!confirmed) return;
    navigator.pop();
  }

  Future<void> _copyLink(BuildContext context) async {
    final url = item.sourceUrl;
    if (url == null || url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('Link copied'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  Future<void> _duplicate(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(activityLibraryRepositoryProvider);
    final newIdValue = await repo.duplicate(item.id);
    final copy = await repo.getItem(newIdValue);
    if (copy == null) return;
    // Pop this sheet, then push the edit sheet on the returned copy
    // so the teacher lands on it ready to tweak. Matches the "just
    // save and refine" loop the rest of the library uses.
    navigator.pop();
    if (!navigator.mounted) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('Duplicated — open in edit'),
          duration: Duration(seconds: 2),
        ),
      );
    await showModalBottomSheet<void>(
      context: navigator.context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditLibraryItemSheet(item: copy),
    );
  }

  Future<void> _schedule(BuildContext context) async {
    final navigator = Navigator.of(context)..pop();
    await navigator.push<CreatedActivity>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => NewActivityWizardScreen(initialLibraryItem: item),
      ),
    );
  }

  String? _audienceLabel() {
    final min = item.audienceMinAge;
    final max = item.audienceMaxAge;
    if (min == null || max == null) return null;
    return audienceLabelFor(min, max);
  }

  List<String> _splitLines(String? s) {
    if (s == null || s.trim().isEmpty) return const <String>[];
    return s
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final hasSourceUrl =
        item.sourceUrl != null && item.sourceUrl!.isNotEmpty;
    final lastUsed = ref.watch(lastUsedAtProvider(item.id)).asData?.value;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.md,
        bottom: AppSpacing.md + insets,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The card itself — full layout, same widget used by
                  // the wizard preview step so there's no rendering
                  // drift.
                  ActivityCardPreview(
                    title: item.title,
                    audienceLabel: _audienceLabel(),
                    hook: item.hook,
                    summary: item.summary,
                    keyPoints: _splitLines(item.keyPoints),
                    learningGoals: _splitLines(item.learningGoals),
                    engagementTimeMin: item.engagementTimeMin,
                    sourceUrl: item.sourceUrl,
                    sourceAttribution: item.sourceAttribution,
                  ),
                  if (lastUsed != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Icon(
                          Icons.history,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Last used ${_relativePast(lastUsed)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (item.materials != null &&
                      item.materials!.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    const _SectionHeader(
                      icon: Icons.inventory_2_outlined,
                      label: 'Materials',
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      item.materials!.trim(),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                  _DomainTagsSection(libraryItemId: item.id),
                  _SimilarActivitiesSection(sourceId: item.id),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Action row: Schedule (primary) / Edit / Duplicate / Delete.
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _schedule(context),
                  icon: const Icon(Icons.event_available_outlined, size: 16),
                  label: const Text('Schedule'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openEdit(context),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _duplicate(context, ref),
                  icon: const Icon(Icons.copy_all_outlined, size: 16),
                  label: const Text('Duplicate'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _delete(context, ref),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  label: Text(
                    'Delete',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: theme.colorScheme.error.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (hasSourceUrl) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: () => _copyLink(context),
              icon: const Icon(Icons.link, size: 16),
              label: const Text('Copy link'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Mirror of the screen's relative-time helper — pulled inline here
// to avoid a public dep on activity_library_screen.dart. Short "N
// ago" format; older than ~2 months collapses to months-ago.
String _relativePast(DateTime then) {
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _DomainTagsSection extends ConsumerWidget {
  const _DomainTagsSection({required this.libraryItemId});

  final String libraryItemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tags = ref
            .watch(libraryDomainsForItemProvider(libraryItemId))
            .asData
            ?.value ??
        const [];
    if (tags.isEmpty) return const SizedBox.shrink();
    final parsed = [for (final t in tags) ObservationDomain.fromName(t)];
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeader(
            icon: Icons.psychology_outlined,
            label: 'Developmental domains',
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final d in parsed)
                Chip(
                  label: Text(
                    d == ObservationDomain.other
                        ? d.label
                        : '${d.code} · ${d.label}',
                    style: theme.textTheme.labelSmall,
                  ),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SimilarActivitiesSection extends ConsumerWidget {
  const _SimilarActivitiesSection({required this.sourceId});

  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(similarLibraryItemsProvider(sourceId));
    final items = async.asData?.value ?? const <ActivityLibraryData>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeader(
            icon: Icons.auto_awesome_outlined,
            label: 'Similar activities',
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: AppSpacing.sm),
              itemBuilder: (_, i) {
                final it = items[i];
                final audience =
                    it.audienceMinAge != null && it.audienceMaxAge != null
                        ? audienceLabelFor(
                            it.audienceMinAge!,
                            it.audienceMaxAge!,
                          )
                        : null;
                return _SimilarCard(
                  title: it.title,
                  audience: audience,
                  onTap: () async {
                    final navigator = Navigator.of(context)..pop();
                    await showModalBottomSheet<void>(
                      context: navigator.context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      useSafeArea: true,
                      builder: (_) => LibraryCardDetailSheet(item: it),
                    );
                  },
                  theme: theme,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SimilarCard extends StatelessWidget {
  const _SimilarCard({
    required this.title,
    required this.audience,
    required this.onTap,
    required this.theme,
  });

  final String title;
  final String? audience;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge,
            ),
            const Spacer(),
            if (audience != null)
              Text(
                audience!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
