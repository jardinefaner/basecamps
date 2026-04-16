import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/features/observations/widgets/observation_card.dart';
import 'package:basecamp/features/observations/widgets/observation_sheet.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ObservationsScreen extends ConsumerWidget {
  const ObservationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final observationsAsync = ref.watch(observationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Observations')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Observe'),
      ),
      body: observationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (items) {
          if (items.isEmpty) {
            return _EmptyState(onAdd: () => _openSheet(context));
          }
          return ListView.separated(
            padding: const EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              top: AppSpacing.lg,
              bottom: AppSpacing.xxxl * 2,
            ),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, i) => ObservationCard(observation: items[i]),
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
      builder: (_) => const ObservationSheet(),
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
              Icons.visibility_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No observations yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Quick, structured notes about what you saw.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add observation'),
            ),
          ],
        ),
      ),
    );
  }
}
