import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Horizontal, single-select avatar strip of every staff member /
/// specialist on record. Same visual language as the child chip picker
/// so the form feels consistent. Tapping the currently-selected chip
/// deselects it.
class SpecialistChipPicker extends ConsumerWidget {
  const SpecialistChipPicker({
    required this.selectedId,
    required this.onChanged,
    super.key,
  });

  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final specialistsAsync = ref.watch(specialistsProvider);
    return specialistsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: LinearProgressIndicator(),
      ),
      error: (err, _) => Text(
        'Error loading staff: $err',
        style: theme.textTheme.bodySmall,
      ),
      data: (specialists) {
        if (specialists.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              'No adults on file yet. Add them in More → Adults '
              'and they will show up here.',
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
            itemCount: specialists.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, i) {
              final s = specialists[i];
              final selected = s.id == selectedId;
              return _SpecialistChip(
                specialist: s,
                selected: selected,
                onTap: () => onChanged(selected ? null : s.id),
              );
            },
          ),
        );
      },
    );
  }
}

class _SpecialistChip extends StatelessWidget {
  const _SpecialistChip({
    required this.specialist,
    required this.selected,
    required this.onTap,
  });

  final Specialist specialist;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = specialist.name.isNotEmpty
        ? specialist.name.characters.first.toUpperCase()
        : '?';
    return SizedBox(
      width: 68,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                path: specialist.avatarPath,
                fallbackInitial: initial,
                radius: 24,
                backgroundColor: theme.colorScheme.secondaryContainer,
                foregroundColor: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              specialist.name,
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
