import 'package:basecamp/core/format/text.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/adults/widgets/new_adult_wizard.dart';
import 'package:basecamp/features/children/children_repository.dart'
    show groupsProvider;
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:basecamp/ui/bootstrap_setup_card.dart';
import 'package:basecamp/ui/bulk_selection.dart';
import 'package:basecamp/ui/responsive.dart';
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
            // Build a quick id → Group map for the cards' group
            // labels. groupsProvider streams; if it hasn't resolved
            // yet the cards just render without the group line.
            final groupsAsync = ref.watch(groupsProvider);
            final groupsById = <String, Group>{
              for (final g in groupsAsync.value ?? const <Group>[])
                g.id: g,
            };
            return BreakpointBuilder(
              builder: (context, bp) {
                // Avatar-card grid is denser than the old single-
                // line-row layout. Each card stacks avatar + name +
                // role pill + job title + group label vertically,
                // so we want more cards per row at every breakpoint.
                final columns = switch (bp) {
                  Breakpoint.compact => 2,
                  Breakpoint.medium => 3,
                  Breakpoint.expanded => 4,
                  Breakpoint.large => 5,
                };
                final hSide = bp == Breakpoint.compact
                    ? AppSpacing.lg
                    : AppSpacing.xl;
                final padding = EdgeInsets.only(
                  left: hSide,
                  right: hSide,
                  top: AppSpacing.md,
                  bottom: AppSpacing.xxxl * 2,
                );
                return GridView.builder(
                  padding: padding,
                  gridDelegate:
                      SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    // 220dp gives the avatar (72dp) + name + role pill
                    // + job title + group line room without
                    // overflowing the cardPadding's 16dp.
                    mainAxisExtent: 220,
                  ),
                  itemCount: adults.length,
                  itemBuilder: (_, i) {
                    final a = adults[i];
                    final group = a.anchoredGroupId == null
                        ? null
                        : groupsById[a.anchoredGroupId];
                    return _AdultCard(
                      adult: a,
                      group: group,
                      selected: isSelected(a.id),
                      onTap: isSelecting
                          ? () => toggleSelection(a.id)
                          : () => context.push('/more/adults/${a.id}'),
                      onLongPress: () => toggleSelection(a.id),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Avatar-card variant of the adults tile. Stacks vertically so the
/// teacher sees a face-first roster with name + canonical role pill
/// (Lead / Specialist / Ambient) + their job title (the free-text
/// "role on schedule" — Director, Kitchen, Floater, etc.) + their
/// anchored group. Replaces the previous one-line ListTile shape;
/// reads less like a contact list and more like a staff page.
class _AdultCard extends StatelessWidget {
  const _AdultCard({
    required this.adult,
    required this.group,
    required this.onTap,
    required this.onLongPress,
    this.selected = false,
  });

  final Adult adult;
  final Group? group;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final adultRole = AdultRole.fromDb(adult.adultRole);
    final hasJobTitle = adult.role != null && adult.role!.isNotEmpty;
    return AppCard(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SmallAvatar(
            path: adult.avatarPath,
            storagePath: adult.avatarStoragePath,
            etag: adult.avatarEtag,
            fallbackInitial: adult.name.initial,
            backgroundColor: cs.secondaryContainer,
            foregroundColor: cs.onSecondaryContainer,
            radius: 36,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            adult.name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xs),
          _RoleChip(role: adultRole),
          if (hasJobTitle) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              adult.role!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (group != null) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.group_outlined,
                  size: 12,
                  color: cs.primary,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    group!.name,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
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
          'Specialist',
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
    return Center(
      child: ConstrainedBox(
        // Keep the empty-state message column readable on wide
        // windows — otherwise the bootstrap card stretches across
        // the full 1500dp pane and dwarfs the copy below.
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Shows only when BOTH adults and groups are empty. Once
              // groups exist, this collapses and the familiar "Add adult"
              // CTA below is what the teacher sees.
              const BootstrapSetupCard(),
              const SizedBox(height: AppSpacing.xl),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.badge_outlined,
                      size: 56,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('No adults yet',
                        style: theme.textTheme.titleLarge),
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
            ],
          ),
        ),
      ),
    );
  }
}
