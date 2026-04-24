import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/adults/widgets/new_adult_wizard.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:basecamp/ui/bulk_selection.dart';
import 'package:basecamp/ui/undo_delete.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AdultsScreen extends ConsumerStatefulWidget {
  const AdultsScreen({super.key});

  @override
  ConsumerState<AdultsScreen> createState() => _AdultsScreenState();
}

class _AdultsScreenState extends ConsumerState<AdultsScreen>
    with BulkSelectionMixin {
  Future<void> _openWizard() async {
    // Full step-by-step wizard walks a first-timer through every v28
    // field — identity, job title, role, anchor group (when Lead),
    // shift, break/lunch, notes. Editing an existing row still opens
    // the dense [EditAdultSheet]; wizard is creation-only.
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const NewAdultWizardScreen(),
      ),
    );
  }

  Future<void> _deleteSelected() async {
    final count = selectedCount;
    if (count == 0) return;
    // Snapshot the selected rows before delete so undo can restore
    // them — ids alone aren't enough; we need the full Adult
    // objects to re-insert.
    final toDelete = selectedIds.toList();
    final all =
        ref.read(adultsProvider).asData?.value ??
            const <Adult>[];
    final snapshot = [
      for (final s in all)
        if (toDelete.contains(s.id)) s,
    ];
    final confirmed = await confirmDeleteWithUndo(
      context: context,
      title: count == 1 ? 'Remove this adult?' : 'Remove $count adults?',
      message:
          'Activities they were running keep their times and details — '
          'the adult slot just becomes empty.',
      confirmLabel: count == 1 ? 'Remove' : 'Remove $count',
      onDelete: () => ref
          .read(adultsRepositoryProvider)
          .deleteAdults(toDelete),
      undoLabel: count == 1 ? 'Adult removed' : '$count adults removed',
      onUndo: () => ref
          .read(adultsRepositoryProvider)
          .restoreAdults(snapshot),
    );
    if (!confirmed || !mounted) return;
    clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    final adultsAsync = ref.watch(adultsProvider);

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
            : AppBar(
                title: const Text('Adults'),
                actions: [
                  IconButton(
                    tooltip: 'Program timeline',
                    icon: const Icon(Icons.view_timeline_outlined),
                    onPressed: () =>
                        context.push('/more/adults/timeline'),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
              ),
        floatingActionButton: isSelecting
            ? null
            : FloatingActionButton.extended(
                onPressed: _openWizard,
                icon: const Icon(Icons.add),
                label: const Text('Adult'),
              ),
        body: adultsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Error: $err')),
          data: (adults) {
            if (adults.isEmpty) {
              return _EmptyState(onAdd: _openWizard);
            }
            return ListView.separated(
              padding: const EdgeInsets.only(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                top: AppSpacing.md,
                bottom: AppSpacing.xxxl * 2,
              ),
              itemCount: adults.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (_, i) {
                final s = adults[i];
                return _AdultTile(
                  adult: s,
                  selected: isSelected(s.id),
                  onTap: isSelecting
                      ? () => toggleSelection(s.id)
                      : () => context.push('/more/adults/${s.id}'),
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

class _AdultTile extends StatelessWidget {
  const _AdultTile({
    required this.adult,
    required this.onTap,
    required this.onLongPress,
    this.selected = false,
  });

  final Adult adult;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = adult.name.isNotEmpty
        ? adult.name.characters.first.toUpperCase()
        : '?';

    final adultRole = AdultRole.fromDb(adult.adultRole);
    return AppCard(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,
      child: Row(
        children: [
          SmallAvatar(
            path: adult.avatarPath,
            fallbackInitial: initial,
            backgroundColor: theme.colorScheme.secondaryContainer,
            foregroundColor: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        adult.name,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    _RoleChip(role: adultRole),
                  ],
                ),
                if (adult.role != null && adult.role!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      adult.role!,
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

/// Small role pill on each adult tile. Colors picked to stay legible
/// in both light + dark: Lead uses the primary tint, Adult the
/// tertiary, Ambient neutral surface.
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final AdultRole role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg, label) = switch (role) {
      AdultRole.lead => (
          theme.colorScheme.primaryContainer,
          theme.colorScheme.onPrimaryContainer,
          'Lead',
        ),
      AdultRole.specialist => (
          theme.colorScheme.tertiaryContainer,
          theme.colorScheme.onTertiaryContainer,
          'Adult',
        ),
      AdultRole.ambient => (
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurface,
          'Ambient',
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
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
              Icons.badge_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No adults yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Add everyone who works the program — leads, adults, '
              'director, kitchen, nurse.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add adult'),
            ),
          ],
        ),
      ),
    );
  }
}
