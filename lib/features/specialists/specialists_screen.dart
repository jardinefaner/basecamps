import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:basecamp/features/specialists/widgets/new_specialist_wizard.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:basecamp/ui/bulk_selection.dart';
import 'package:basecamp/ui/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SpecialistsScreen extends ConsumerStatefulWidget {
  const SpecialistsScreen({super.key});

  @override
  ConsumerState<SpecialistsScreen> createState() => _SpecialistsScreenState();
}

class _SpecialistsScreenState extends ConsumerState<SpecialistsScreen>
    with BulkSelectionMixin {
  Future<void> _openWizard() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const NewSpecialistWizardScreen(),
      ),
    );
  }

  Future<void> _deleteSelected() async {
    final count = selectedCount;
    if (count == 0) return;
    final confirmed = await showConfirmDialog(
      context: context,
      title: count == 1
          ? 'Remove this specialist?'
          : 'Remove $count specialists?',
      message:
          'Activities they were running keep their times and details — '
          'the specialist slot just becomes empty.',
      confirmLabel: count == 1 ? 'Remove' : 'Remove $count',
    );
    if (!confirmed) return;
    await ref
        .read(specialistsRepositoryProvider)
        .deleteSpecialists(selectedIds.toList());
    if (!mounted) return;
    clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    final specialistsAsync = ref.watch(specialistsProvider);

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
            : AppBar(title: const Text('Specialists')),
        floatingActionButton: isSelecting
            ? null
            : FloatingActionButton.extended(
                onPressed: _openWizard,
                icon: const Icon(Icons.add),
                label: const Text('Specialist'),
              ),
        body: specialistsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Error: $err')),
          data: (specialists) {
            if (specialists.isEmpty) {
              return _EmptyState(onAdd: _openWizard);
            }
            return ListView.separated(
              padding: const EdgeInsets.only(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                top: AppSpacing.md,
                bottom: AppSpacing.xxxl * 2,
              ),
              itemCount: specialists.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (_, i) {
                final s = specialists[i];
                return _SpecialistTile(
                  specialist: s,
                  selected: isSelected(s.id),
                  onTap: isSelecting
                      ? () => toggleSelection(s.id)
                      : () => context.push('/more/specialists/${s.id}'),
                  onLongPress: () => toggleSelection(s.id),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _SpecialistTile extends StatelessWidget {
  const _SpecialistTile({
    required this.specialist,
    required this.onTap,
    required this.onLongPress,
    this.selected = false,
  });

  final Specialist specialist;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = specialist.name.isNotEmpty
        ? specialist.name.characters.first.toUpperCase()
        : '?';

    return AppCard(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,
      child: Row(
        children: [
          SmallAvatar(
            path: specialist.avatarPath,
            fallbackInitial: initial,
            backgroundColor: theme.colorScheme.secondaryContainer,
            foregroundColor: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(specialist.name, style: theme.textTheme.titleMedium),
                if (specialist.role != null && specialist.role!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      specialist.role!,
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
              Icons.badge_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No specialists yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Add staff who run specific activities — art, swim, nature, etc.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add specialist'),
            ),
          ],
        ),
      ),
    );
  }
}
