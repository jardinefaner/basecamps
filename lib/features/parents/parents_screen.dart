import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/parents/parents_repository.dart';
import 'package:basecamp/features/parents/widgets/edit_parent_sheet.dart';
import 'package:basecamp/features/people/people_display.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// `/more/parents` — list + add + edit parents/guardians. Tapping a
/// row drills into the parent detail screen (linked children,
/// contact info). The FAB adds a new parent; linking to children
/// happens from the child detail screen.
class ParentsScreen extends ConsumerStatefulWidget {
  const ParentsScreen({super.key});

  @override
  ConsumerState<ParentsScreen> createState() => _ParentsScreenState();
}

class _ParentsScreenState extends ConsumerState<ParentsScreen> {
  Future<void> _openAdd() async {
    await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const EditParentSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parentsAsync = ref.watch(parentsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Parents & guardians')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAdd,
        icon: const Icon(Icons.add),
        label: const Text('Parent'),
      ),
      body: parentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (parents) {
          if (parents.isEmpty) {
            return _EmptyState(onAdd: _openAdd);
          }
          return BreakpointBuilder(
            builder: (context, bp) {
              // Avatar-card grid (matches adults). Denser than the
              // old default 1/1/2/3 ramp — face-first reading.
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
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisExtent: 220,
                ),
                itemCount: parents.length,
                itemBuilder: (_, i) => _ParentCard(parent: parents[i]),
              );
            },
          );
        },
      ),
    );
  }
}

/// Avatar-card variant — same shape as `_AdultCard` so the people
/// surfaces (Adults, Parents, Children) read as one consistent
/// visual language. Stacks: avatar / name (+ relationship) / kids
/// summary line.
class _ParentCard extends ConsumerWidget {
  const _ParentCard({required this.parent});

  final Parent parent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final kidsAsync = ref.watch(childrenForParentProvider(parent.id));
    final kids = kidsAsync.asData?.value ?? const <Child>[];
    final kidLine = kids.isEmpty
        ? null
        : kids.length == 1
            ? kids.first.firstName
            : '${kids.first.firstName} +${kids.length - 1} more';

    final relationship = parent.relationship;

    return AppCard(
      onTap: () => context.push('/more/parents/${parent.id}'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: cs.secondaryContainer,
            foregroundColor: cs.onSecondaryContainer,
            child: Text(
              parent.displayInitial,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: cs.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            parent.fullName,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (relationship != null && relationship.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              relationship,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (kidLine != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.child_care_outlined,
                  size: 12,
                  color: cs.primary,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    kidLine,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            Icon(
              Icons.family_restroom_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No parents yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Add parents and guardians so siblings share a contact, '
              'pickup authorization is one row to edit, and the '
              'parent-concern form can one-tap the right person.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add parent'),
            ),
          ],
        ),
          ),
        ),
    );
  }
}
