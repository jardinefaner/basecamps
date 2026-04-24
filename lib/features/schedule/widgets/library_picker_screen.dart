import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/activity_library/activity_card_ai.dart';
import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:basecamp/features/activity_library/widgets/activity_card_preview.dart';
import 'package:basecamp/features/activity_library/widgets/library_filter_header.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fullscreen picker used by the new-activity wizard when the teacher
/// taps "Pick from library". Reuses the same search pill + age-chip
/// filter header as the Activity library screen (via
/// [LibraryFilterHeader]).
///
/// Pops with the selected [ActivityLibraryData], or `null` when the
/// teacher backs out.
class LibraryPickerScreen extends ConsumerStatefulWidget {
  const LibraryPickerScreen({super.key});

  @override
  ConsumerState<LibraryPickerScreen> createState() =>
      _LibraryPickerScreenState();
}

class _LibraryPickerScreenState extends ConsumerState<LibraryPickerScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  LibraryAgeBand _band = LibraryAgeBand.all;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(activityLibraryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Pick from library')),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (items) {
          if (items.isEmpty) {
            return _PickerEmptyState(
              onBack: () => Navigator.of(context).pop(),
            );
          }
          final filtered = [
            for (final item in items)
              if (matchesLibraryFilter(item, query: _query, band: _band))
                item,
          ];
          return Column(
            children: [
              LibraryFilterHeader(
                searchController: _searchCtrl,
                onSearchChanged: (v) => setState(() => _query = v),
                band: _band,
                onBandChanged: (b) => setState(() => _band = b),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? _PickerNoMatches(query: _query, band: _band)
                    : ListView.separated(
                        padding: const EdgeInsets.only(
                          left: AppSpacing.lg,
                          right: AppSpacing.lg,
                          top: AppSpacing.md,
                          bottom: AppSpacing.xxxl,
                        ),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.md),
                        itemBuilder: (_, i) {
                          final item = filtered[i];
                          return _PickerTile(
                            item: item,
                            onTap: () =>
                                Navigator.of(context).pop(item),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({required this.item, required this.onTap});

  final ActivityLibraryData item;
  final VoidCallback onTap;

  bool get _isRichCard =>
      item.summary != null ||
      item.audienceMinAge != null ||
      item.hook != null;

  @override
  Widget build(BuildContext context) {
    if (_isRichCard) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: ActivityCardPreview(
          title: item.title,
          audienceLabel:
              item.audienceMinAge != null && item.audienceMaxAge != null
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
      );
    }
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

class _PickerEmptyState extends StatelessWidget {
  const _PickerEmptyState({required this.onBack});

  final VoidCallback onBack;

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
            Text('No library items yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Add one from the Activity library section in the launcher.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton(
              onPressed: onBack,
              child: const Text('Back to wizard'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerNoMatches extends StatelessWidget {
  const _PickerNoMatches({required this.query, required this.band});

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
      message =
          'No activities in ${libraryAgeBandLabels[band]!.toLowerCase()}.';
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
