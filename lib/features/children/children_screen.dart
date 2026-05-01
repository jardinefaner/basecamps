import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/children/group_colors.dart';
import 'package:basecamp/features/children/widgets/new_child_wizard.dart';
import 'package:basecamp/features/children/widgets/new_group_wizard.dart';
import 'package:basecamp/features/groups/group_detail_screen.dart';
import 'package:basecamp/features/people/people_display.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:basecamp/ui/bootstrap_setup_card.dart';
import 'package:basecamp/ui/responsive.dart';
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
                BreakpointBuilder(
                  // Avatar-card grid per section — matches the
                  // parents/adults layout so all three people surfaces
                  // read the same. Denser than the previous one-line
                  // tile column; face-first so a Lead scanning their
                  // group sees who's there at a glance.
                  builder: (context, bp) {
                    final columns = switch (bp) {
                      Breakpoint.compact => 3,
                      Breakpoint.medium => 4,
                      Breakpoint.expanded => 5,
                      Breakpoint.large => 6,
                    };
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: AppSpacing.sm,
                        crossAxisSpacing: AppSpacing.sm,
                        // 150dp fits avatar + name; tighter than
                        // adults/parents because there's no role
                        // chip or group label per child.
                        mainAxisExtent: 150,
                      ),
                      itemCount: children.length,
                      itemBuilder: (_, i) =>
                          _DraggableChildCard(child: children[i]),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Avatar-card child tile inside the group grid. Stacks avatar /
/// short name vertically — same shape as `_AdultCard` and
/// `_ParentCard` so the three people surfaces share one visual
/// language. Wrapped in [LongPressDraggable] so a teacher can pick
/// the child up and drop them on another group's drop zone.
class _DraggableChildCard extends StatelessWidget {
  const _DraggableChildCard({required this.child});

  final Child child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final card = AppCard(
      onTap: () => context.push('/children/${child.id}'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SmallAvatar(
            path: child.avatarPath,
            storagePath: child.avatarStoragePath,
            etag: child.avatarEtag,
            fallbackInitial: child.displayInitial,
            backgroundColor: cs.secondaryContainer,
            foregroundColor: cs.onSecondaryContainer,
            radius: 28,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            // shortName ("Sarah J.") fits in dense grids; fullName
            // would force ellipsis at 3-column compact layout.
            child.shortName,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    // Drag feedback shows the card itself, scaled slightly so the
    // dragged item is visually distinct from the source spot.
    return LongPressDraggable<Child>(
      data: child,
      feedback: Material(
        color: Colors.transparent,
        child: Transform.scale(
          scale: 1.04,
          child: Opacity(
            opacity: 0.94,
            // Cap width so the floating card doesn't balloon to fill
            // the screen on phones (the source card is grid-sized,
            // ~120dp wide on compact).
            child: SizedBox(
              width: 140,
              height: 150,
              child: card,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      child: card,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Shows only on a fresh install (both adults and groups
          // empty). Once adults exist, the bootstrap card is done
          // and the familiar "Create group" CTA below takes over.
          const BootstrapSetupCard(),
          const SizedBox(height: AppSpacing.xl),
          Center(
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
        ],
      ),
    );
  }
}
