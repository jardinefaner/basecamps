import 'package:basecamp/database/database.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

/// The library has no `category` column. Instead, we facet on the
/// existing audience-age range — most teachers think about activities
/// per age band anyway. This enum + [libraryAgeBandLabels] is the
/// single source of truth shared by the library screen and the
/// wizard's library picker.
enum LibraryAgeBand {
  all,
  infant, // 0–2
  toddler, // 2–3
  preschool, // 3–5
  schoolAge, // 5+
  unset, // no age data on the card
}

const Map<LibraryAgeBand, String> libraryAgeBandLabels = {
  LibraryAgeBand.all: 'All ages',
  LibraryAgeBand.infant: 'Infant (0–2)',
  LibraryAgeBand.toddler: 'Toddler (2–3)',
  LibraryAgeBand.preschool: 'Preschool (3–5)',
  LibraryAgeBand.schoolAge: 'School age (5+)',
  LibraryAgeBand.unset: 'No age set',
};

/// Pure predicate used by both screens and the unit tests. Kept free
/// of Flutter imports (the data type is fine — Drift generates it as
/// plain Dart) so the test stays snappy.
bool matchesLibraryFilter(
  ActivityLibraryData item, {
  required String query,
  required LibraryAgeBand band,
}) {
  final q = query.trim().toLowerCase();
  if (q.isNotEmpty) {
    final haystack = <String?>[
      item.title,
      item.summary,
      item.hook,
      item.keyPoints,
    ];
    final hit = haystack.any(
      (s) => s != null && s.toLowerCase().contains(q),
    );
    if (!hit) return false;
  }
  return _matchesBand(item, band);
}

bool _matchesBand(ActivityLibraryData item, LibraryAgeBand band) {
  final min = item.audienceMinAge;
  final max = item.audienceMaxAge;
  final hasAny = min != null || max != null;
  switch (band) {
    case LibraryAgeBand.all:
      return true;
    case LibraryAgeBand.unset:
      return !hasAny;
    case LibraryAgeBand.infant:
      // "Infant (0–2)" — cards whose audienceMinAge <= 2.
      if (!hasAny) return false;
      return (min ?? 0) <= 2;
    case LibraryAgeBand.toddler:
      // Overlap [2, 3].
      if (!hasAny) return false;
      return _overlaps(min, max, 2, 3);
    case LibraryAgeBand.preschool:
      // Overlap [3, 5].
      if (!hasAny) return false;
      return _overlaps(min, max, 3, 5);
    case LibraryAgeBand.schoolAge:
      // audienceMaxAge is null OR >= 5. Null-age cards excluded
      // (handled by the hasAny check above) — a card with no age data
      // only shows under "All ages" or "No age set".
      if (!hasAny) return false;
      return max == null || max >= 5;
  }
}

/// Returns true when [aMin..aMax] overlaps [bMin..bMax]. Treats a null
/// bound as open on that side.
bool _overlaps(int? aMin, int? aMax, int bMin, int bMax) {
  final lo = aMin ?? 0;
  final hi = aMax ?? 999;
  return lo <= bMax && hi >= bMin;
}

/// Search pill + age-band chip row. Pin this above a list of library
/// cards. Both pieces of UI are shared between the library screen and
/// the new-activity wizard's library picker.
class LibraryFilterHeader extends StatelessWidget {
  const LibraryFilterHeader({
    required this.searchController,
    required this.onSearchChanged,
    required this.band,
    required this.onBandChanged,
    super.key,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final LibraryAgeBand band;
  final ValueChanged<LibraryAgeBand> onBandChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SearchPill(
          controller: searchController,
          onChanged: onSearchChanged,
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            children: [
              for (final b in LibraryAgeBand.values)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: FilterChip(
                    label: Text(libraryAgeBandLabels[b]!),
                    selected: band == b,
                    onSelected: (_) => onBandChanged(b),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Matches the launcher's search pill: 56dp, surfaceContainerHighest,
/// rounded 28, leading search icon, trailing clear-X.
class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(28),
        ),
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(
          children: [
            Icon(
              Icons.search,
              size: 22,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.search,
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'Search activities…',
                  hintStyle: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onChanged: onChanged,
              ),
            ),
            if (controller.text.isNotEmpty)
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              )
            else
              const SizedBox(width: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}
