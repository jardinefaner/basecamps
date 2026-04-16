import 'package:basecamp/features/trips/trips_repository.dart';
import 'package:basecamp/features/trips/widgets/add_trip_sheet.dart';
import 'package:basecamp/features/trips/widgets/trip_card.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(tripsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Trips')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('New trip'),
      ),
      body: tripsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (trips) {
          if (trips.isEmpty) {
            return _EmptyState(onAdd: () => _openSheet(context));
          }
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final upcoming = trips.where((t) => !t.date.isBefore(today)).toList();
          final past = trips.where((t) => t.date.isBefore(today)).toList()
            ..sort((a, b) => b.date.compareTo(a.date));

          return ListView(
            padding: const EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              top: AppSpacing.md,
              bottom: AppSpacing.xxxl * 2,
            ),
            children: [
              if (upcoming.isNotEmpty) ...[
                _SectionLabel(label: 'UPCOMING · ${upcoming.length}'),
                const SizedBox(height: AppSpacing.sm),
                for (final t in upcoming)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: TripCard(
                      trip: t,
                      onTap: () => context.push('/trips/${t.id}'),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (past.isNotEmpty) ...[
                _SectionLabel(label: 'PAST · ${past.length}'),
                const SizedBox(height: AppSpacing.sm),
                for (final t in past)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: TripCard(
                      trip: t,
                      onTap: () => context.push('/trips/${t.id}'),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const AddTripSheet(),
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
