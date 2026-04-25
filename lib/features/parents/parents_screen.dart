import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/parents/parents_repository.dart';
import 'package:basecamp/features/parents/widgets/edit_parent_sheet.dart';
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
              // Default 1 / 1 / 2 / 3 ramp — parent rows are short.
              final columns = Breakpoints.columnsFor(context);
              final hSide = bp == Breakpoint.compact
                  ? AppSpacing.lg
                  : AppSpacing.xl;
              final padding = EdgeInsets.only(
                left: hSide,
                right: hSide,
                top: AppSpacing.md,
                bottom: AppSpacing.xxxl * 2,
              );
              Widget tileFor(int i) => _ParentTile(parent: parents[i]);

              if (columns == 1) {
                return ListView.separated(
                  padding: padding,
                  itemCount: parents.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, i) => tileFor(i),
                );
              }
              return GridView.builder(
                padding: padding,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisExtent: 96,
                ),
                itemCount: parents.length,
                itemBuilder: (_, i) => tileFor(i),
              );
            },
          );
        },
      ),
    );
  }
}

class _ParentTile extends ConsumerWidget {
  const _ParentTile({required this.parent});

  final Parent parent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Subtitle pulls the children the parent is linked to — cheap
    // thanks to the index on parent_children.parent_id (well, on
    // child_id; this is the less-common direction and is still fine
    // for a list of < 200 parents).
    final kidsAsync = ref.watch(childrenForParentProvider(parent.id));
    final kids = kidsAsync.asData?.value ?? const <Child>[];
    final kidLine = kids.isEmpty
        ? null
        : kids.length == 1
            ? kids.first.firstName
            : '${kids.first.firstName} +${kids.length - 1}';

    final name = _formatName(parent);
    final relationship = parent.relationship;

    return AppCard(
      onTap: () => context.push('/more/parents/${parent.id}'),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: theme.colorScheme.secondaryContainer,
            foregroundColor: theme.colorScheme.onSecondaryContainer,
            child: Text(
              _initial(parent),
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  relationship == null || relationship.isEmpty
                      ? name
                      : '$name · $relationship',
                  style: theme.textTheme.titleMedium,
                ),
                if (kidLine != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'For $kidLine',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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

  String _formatName(Parent p) {
    final last = p.lastName;
    return last == null || last.isEmpty
        ? p.firstName
        : '${p.firstName} $last';
  }

  String _initial(Parent p) {
    return p.firstName.isEmpty ? '?' : p.firstName[0].toUpperCase();
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
