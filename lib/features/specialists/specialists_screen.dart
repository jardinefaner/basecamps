import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:basecamp/features/specialists/widgets/edit_specialist_sheet.dart';
import 'package:basecamp/features/specialists/widgets/new_specialist_wizard.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SpecialistsScreen extends ConsumerWidget {
  const SpecialistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final specialistsAsync = ref.watch(specialistsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Specialists')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Specialist'),
      ),
      body: specialistsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (specialists) {
          if (specialists.isEmpty) {
            return _EmptyState(onAdd: () => _openSheet(context));
          }
          return ListView.separated(
            padding: const EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              top: AppSpacing.md,
              bottom: AppSpacing.xxxl * 2,
            ),
            itemCount: specialists.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, i) => _SpecialistTile(
              specialist: specialists[i],
              onTap: () => _openSheet(context, specialist: specialists[i]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openSheet(BuildContext context, {Specialist? specialist}) async {
    // Create flow goes through the page-by-page wizard; editing an
    // existing specialist keeps the dense sheet for fast tweaks.
    if (specialist == null) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const NewSpecialistWizardScreen(),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditSpecialistSheet(specialist: specialist),
    );
  }
}

class _SpecialistTile extends StatelessWidget {
  const _SpecialistTile({required this.specialist, required this.onTap});

  final Specialist specialist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = specialist.name.isNotEmpty
        ? specialist.name.characters.first.toUpperCase()
        : '?';

    return AppCard(
      onTap: onTap,
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
