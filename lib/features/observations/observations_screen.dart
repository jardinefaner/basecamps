import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/features/observations/widgets/observation_card.dart';
import 'package:basecamp/features/observations/widgets/observation_composer.dart';
import 'package:basecamp/features/observations/widgets/observation_edit_sheet.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ObservationsScreen extends ConsumerWidget {
  const ObservationsScreen({super.key});

  Future<void> _openEditSheet(
    BuildContext context,
    Observation observation,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => ObservationEditSheet(observation: observation),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final observationsAsync = ref.watch(observationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Observe')),
      body: Column(
        children: [
          Expanded(
            child: observationsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error: $err')),
              data: (items) {
                if (items.isEmpty) {
                  return const _EmptyState();
                }
                return ListView.separated(
                  reverse: true,
                  padding: const EdgeInsets.only(
                    left: AppSpacing.lg,
                    right: AppSpacing.lg,
                    top: AppSpacing.xl,
                    bottom: AppSpacing.lg,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, i) => ObservationCard(
                    observation: items[i],
                    onTap: () => _openEditSheet(context, items[i]),
                  ),
                );
              },
            ),
          ),
          const ObservationComposer(),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.edit_note_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Start capturing',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Type, dictate, or attach a photo below — your observations '
              'show up here.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
