import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/children/group_colors.dart';
import 'package:basecamp/features/children/widgets/child_tile.dart';
import 'package:basecamp/features/children/widgets/new_child_wizard.dart';
import 'package:basecamp/features/children/widgets/new_group_wizard.dart';
import 'package:basecamp/features/groups/group_detail_screen.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ChildrenScreen extends ConsumerWidget {
  const ChildrenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(groupsProvider);
    final childrenAsync = ref.watch(childrenProvider);

    return Scaffold(
      floatingActionButton: groupsAsync.maybeWhen(
        data: (groups) => groups.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _openAddChild(context, groups: groups),
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Add child'),
              ),
        orElse: () => null,
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('Children'),
            floating: true,
            snap: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.group_add_outlined),
                tooltip: 'Add group',
                onPressed: () => _openAddGroup(context),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
          ),
          groupsAsync.when(
            loading: () => const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('Error: $err')),
            ),
            data: (groups) => childrenAsync.when(
              loading: () => const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('Error: $err')),
              ),
              data: (children) => _ChildrenBody(
                groups: groups,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddGroup(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const NewGroupWizardScreen(),
      ),
    );
  }

  Future<void> _openAddChild(
    BuildContext context, {
    required List<Group> groups,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => NewChildWizardScreen(groups: groups),
      ),
    );
  }
}

class _ChildrenBody extends StatelessWidget {
  const _ChildrenBody({required this.groups, required this.children});

  final List<Group> groups;
  final List<Child> children;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyState(),
      );
    }

    final childrenByGroup = <String?, List<Child>>{};
    for (final child in children) {
      childrenByGroup.putIfAbsent(child.groupId, () => []).add(child);
    }
    final unassigned = childrenByGroup[null] ?? const <Child>[];

    return SliverPadding(
      padding: const EdgeInsets.only(
        top: AppSpacing.sm,
        bottom: AppSpacing.xxxl * 2,
      ),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          for (final group in groups)
            _GroupSection(
              group: group,
              children: childrenByGroup[group.id] ?? const [],
            ),
          if (unassigned.isNotEmpty)
            _GroupSection(group: null, children: unassigned),
        ]),
      ),
    );
  }
}

class _GroupSection extends ConsumerWidget {
  const _GroupSection({required this.group, required this.children});

  final Group? group;
  final List<Child> children;

  Future<void> _openDetail(BuildContext context) async {
    final current = group;
    if (current == null) return;
    await GroupDetailScreen.open(context, current.id);
  }

  Future<void> _moveChildHere(WidgetRef ref, Child child) async {
    // Idempotent: dropping a child back on their own group does nothing.
    if (child.groupId == group?.id) return;
    await ref.read(childrenRepositoryProvider).updateChildGroup(
          childId: child.id,
          groupId: group?.id,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final title = group?.name ?? 'Unassigned';
    final swatch = groupColorFromHex(group?.colorHex);

    return DragTarget<Child>(
      // Only accept children that would actually move — prevents the
      // highlight from turning on when you drag a Redbird onto the
      // Redbirds section.
      onWillAcceptWithDetails: (d) => d.data.groupId != group?.id,
      onAcceptWithDetails: (d) => _moveChildHere(ref, d.data),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: hovering
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hovering
                  ? theme.colorScheme.primary
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: group == null ? null : () => _openDetail(context),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      if (swatch != null) ...[
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: swatch,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                      ],
                      Text(
                        title.toUpperCase(),
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '${children.length}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (group != null) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Icon(
                          Icons.edit_outlined,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                      if (hovering) ...[
                        const Spacer(),
                        Text(
                          'Drop here',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              if (children.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.sm,
                  ),
                  child: Text(
                    hovering
                        ? 'Add them to this group'
                        : 'No children yet',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hovering
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                Column(
                  children: [
                    for (final child in children)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppSpacing.sm,
                        ),
                        child: _DraggableChildTile(child: child),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Long-press to pick up, drag onto any group section to reassign.
/// We don't render a grip handle — the drag affordance is the
/// long-press itself, which keeps the list visually calm.
class _DraggableChildTile extends StatelessWidget {
  const _DraggableChildTile({required this.child});

  final Child child;

  @override
  Widget build(BuildContext context) {
    final tile = ChildTile(
      child: child,
      onTap: () => context.push('/children/${child.id}'),
    );
    return LongPressDraggable<Child>(
      data: child,
      // Grab one full card's width for the floating feedback; keeps it
      // legible when the finger obscures the original spot.
      feedback: Material(
        color: Colors.transparent,
        child: Transform.scale(
          scale: 1.04,
          child: Opacity(
            opacity: 0.94,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width - 48,
              ),
              child: tile,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: tile),
      child: tile,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
              Icons.groups_2_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No groups yet',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Create your first group to start adding children.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => const NewGroupWizardScreen(),
                ),
              ),
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Create group'),
            ),
          ],
        ),
      ),
    );
  }
}
