import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Fresh-program nudge card. Self-hides unless BOTH adults and groups
/// are empty — once either has a row, the teacher has a direction to
/// go and doesn't need the training-wheels card.
///
/// Two CTAs so the teacher can start from whichever side feels
/// natural: "Add first group" (goes to /children) or "Add first
/// adult" (goes to /more/adults). The flows themselves have inline-
/// create for the other side (see new_group_wizard + new_adult_wizard),
/// so the chicken-and-egg doesn't bite past the first tap.
class BootstrapSetupCard extends ConsumerWidget {
  const BootstrapSetupCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adultsAsync = ref.watch(adultsProvider);
    final groupsAsync = ref.watch(groupsProvider);
    final hasAnyAdult = adultsAsync.asData?.value.isNotEmpty ?? false;
    final hasAnyGroup = groupsAsync.asData?.value.isNotEmpty ?? false;
    if (hasAnyAdult || hasAnyGroup) return const SizedBox.shrink();

    final theme = Theme.of(context);
    // AppCard doesn't expose a color override, so use a plain Card
    // tuned to the primaryContainer surface — Material 3's convention
    // for a prominent-but-not-alarming nudge.
    return Card(
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.rocket_launch_outlined,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    "Let's set up your program",
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Basecamp needs at least one group and one adult. Either '
              "side is fine to start with — you'll be able to link "
              'them as you go.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  onPressed: () => context.push('/children'),
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Add first group'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.push('/more/adults'),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Add first adult'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
