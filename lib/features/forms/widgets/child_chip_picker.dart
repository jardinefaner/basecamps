import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Horizontal, multi-select avatar strip of every child in the roster.
/// Tapping an avatar toggles selection; the selected ids are reported
/// back via [onChanged] in insertion order so callers can derive
/// display strings like "Jordan, Maya, & Leo".
///
/// An "override" caption lives below the strip — when the concern
/// involves someone not yet in the system, the teacher can still type
/// in a free-form name alongside their selections.
class ChildChipPicker extends ConsumerWidget {
  const ChildChipPicker({
    required this.selectedIds,
    required this.onChanged,
    super.key,
  });

  final List<String> selectedIds;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final kidsAsync = ref.watch(childrenProvider);
    return kidsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: LinearProgressIndicator(),
      ),
      error: (err, _) => Text(
        'Error loading children: $err',
        style: theme.textTheme.bodySmall,
      ),
      data: (children) {
        if (children.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              'No children yet. Add children from the Children tab and '
              'they will show up here.',
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
            itemCount: children.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, i) {
              final child = children[i];
              final selected = selectedIds.contains(child.id);
              return _ChildChip(
                child: child,
                selected: selected,
                onTap: () {
                  final next = List<String>.from(selectedIds);
                  if (selected) {
                    next.remove(child.id);
                  } else {
                    next.add(child.id);
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

class _ChildChip extends StatelessWidget {
  const _ChildChip({
    required this.child,
    required this.selected,
    required this.onTap,
  });

  final Child child;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = child.firstName.isNotEmpty
        ? child.firstName.characters.first.toUpperCase()
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
                    path: child.avatarPath,
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
              child.firstName,
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
