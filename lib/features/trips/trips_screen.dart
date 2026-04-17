import 'package:basecamp/features/trips/trips_repository.dart';
import 'package:basecamp/features/trips/widgets/new_trip_wizard.dart';
import 'package:basecamp/features/trips/widgets/trip_card.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/bulk_selection.dart';
import 'package:basecamp/ui/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class TripsScreen extends ConsumerStatefulWidget {
  const TripsScreen({super.key});

  @override
  ConsumerState<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends ConsumerState<TripsScreen>
    with BulkSelectionMixin {
  Future<void> _openWizard() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const NewTripWizardScreen(),
      ),
    );
  }

  Future<void> _deleteSelected() async {
    final count = selectedCount;
    if (count == 0) return;
    final confirmed = await showConfirmDialog(
      context: context,
      title: count == 1 ? 'Delete this trip?' : 'Delete $count trips?',
      message:
          'Linked schedule entries go with them. Observations and photos '
          'tagged to these trips are kept.',
      confirmLabel: count == 1 ? 'Delete' : 'Delete $count',
    );
    if (!confirmed) return;
    await ref
        .read(tripsRepositoryProvider)
        .deleteTrips(selectedIds.toList());
    if (!mounted) return;
    clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    final tripsAsync = ref.watch(tripsProvider);

    return PopScope(
      canPop: !isSelecting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (isSelecting) clearSelection();
      },
      child: Scaffold(
        // Selection AppBar stays pinned — it's destructive mode, hiding
        // the delete affordance on scroll would be a foot-gun.
        appBar: isSelecting
            ? buildSelectionAppBar(
                context: context,
                count: selectedCount,
                onCancel: clearSelection,
                onDelete: _deleteSelected,
              )
            : null,
        floatingActionButton: isSelecting
            ? null
            : FloatingActionButton.extended(
                onPressed: _openWizard,
                icon: const Icon(Icons.add),
                label: const Text('New trip'),
              ),
        body: CustomScrollView(
          slivers: [
            if (!isSelecting)
              const SliverAppBar(
                title: Text('Trips'),
                floating: true,
                snap: true,
              ),
            tripsAsync.when(
              loading: () => const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('Error: $err')),
              ),
              data: (trips) {
                if (trips.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(onAdd: _openWizard),
                  );
                }
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                final upcoming =
                    trips.where((t) => !t.date.isBefore(today)).toList();
                final past = trips
                    .where((t) => t.date.isBefore(today))
                    .toList()
                  ..sort((a, b) => b.date.compareTo(a.date));

                return SliverPadding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.lg,
                    right: AppSpacing.lg,
                    top: AppSpacing.md,
                    bottom: AppSpacing.xxxl * 2,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (upcoming.isNotEmpty) ...[
                        _SectionLabel(
                          label: 'UPCOMING · ${upcoming.length}',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        for (final t in upcoming)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.md,
                            ),
                            child: TripCard(
                              trip: t,
                              selected: isSelected(t.id),
                              onTap: isSelecting
                                  ? () => toggleSelection(t.id)
                                  : () =>
                                      context.push('/trips/${t.id}'),
                              onLongPress: () => toggleSelection(t.id),
                            ),
                          ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      if (past.isNotEmpty) ...[
                        _SectionLabel(label: 'PAST · ${past.length}'),
                        const SizedBox(height: AppSpacing.sm),
                        for (final t in past)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.md,
                            ),
                            child: TripCard(
                              trip: t,
                              selected: isSelected(t.id),
                              onTap: isSelecting
                                  ? () => toggleSelection(t.id)
                                  : () =>
                                      context.push('/trips/${t.id}'),
                              onLongPress: () => toggleSelection(t.id),
                            ),
                          ),
                      ],
                    ]),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
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
              Icons.map_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No trips yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Create a field trip to group captures and observations by day.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Create trip'),
            ),
          ],
        ),
      ),
    );
  }
}
