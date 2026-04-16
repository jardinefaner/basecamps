import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Horizontal, multi-select avatar strip of every kid in the roster.
/// Tapping an avatar toggles selection; the selected ids are reported
/// back via [onChanged] in insertion order so callers can derive
/// display strings like "Jordan, Maya, & Leo".
///
/// An "override" caption lives below the strip — when the concern
/// involves someone not yet in the system, the teacher can still type
/// in a free-form name alongside their selections.
class KidChipPicker extends ConsumerWidget {
  const KidChipPicker({
    required this.selectedIds,
    required this.onChanged,
    super.key,
  });

  final List<String> selectedIds;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final kidsAsync = ref.watch(kidsProvider);
    return kidsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: LinearProgressIndicator(),
      ),
      error: (err, _) => Text(
        'Error loading kids: $err',
        style: theme.textTheme.bodySmall,
      ),
      data: (kids) {
        if (kids.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              'No kids yet. Add kids from the Kids tab and they will '
              'show up here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kids.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, i) {
              final kid = kids[i];
              final selected = selectedIds.contains(kid.id);
              return _KidChip(
                kid: kid,
                selected: selected,
                onTap: () {
                  final next = List<String>.from(selectedIds);
                  if (selected) {
                    next.remove(kid.id);
                  } else {
                    next.add(kid.id);
                  }
                  onChanged(next);
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _KidChip extends StatelessWidget {
  const _KidChip({
    required this.kid,
    required this.selected,
    required this.onTap,
  });

  final Kid kid;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = kid.firstName.isNotEmpty
        ? kid.firstName.characters.first.toUpperCase()
        : '?';
    return SizedBox(
      width: 64,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? theme.colorScheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: SmallAvatar(
                    path: kid.avatarPath,
                    fallbackInitial: initial,
                    radius: 24,
                  ),
                ),
                if (selected)
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.check,
                        size: 12,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              kid.firstName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: selected
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
