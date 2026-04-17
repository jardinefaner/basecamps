import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/children/group_colors.dart';
import 'package:basecamp/features/children/widgets/child_tile.dart';
import 'package:basecamp/features/children/widgets/edit_group_sheet.dart';
import 'package:basecamp/features/children/widgets/new_child_wizard.dart';
import 'package:basecamp/features/children/widgets/new_group_wizard.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ChildrenScreen extends ConsumerWidget {
  const ChildrenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final podsAsync = ref.watch(groupsProvider);
    final kidsAsync = ref.watch(childrenProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Children'),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add_outlined),
            tooltip: 'Add group',
            onPressed: () => _openAddPod(context),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      floatingActionButton: podsAsync.maybeWhen(
        data: (pods) => pods.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _openAddKid(context, pods: pods),
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Add child'),
              ),
        orElse: () => null,
      ),
      body: podsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (pods) => kidsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Error: $err')),
          data: (kids) => _KidsBody(pods: pods, kids: kids),
        ),
      ),
    );
  }

  Future<void> _openAddPod(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const NewGroupWizardScreen(),
      ),
    );
  }

  Future<void> _openAddKid(
    BuildContext context, {
    required List<Group> pods,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => NewChildWizardScreen(pods: pods),
      ),
    );
  }
}

class _KidsBody extends StatelessWidget {
  const _KidsBody({required this.pods, required this.kids});

  final List<Group> pods;
  final List<Child> kids;

  @override
  Widget build(BuildContext context) {
    if (pods.isEmpty) {
      return const _EmptyState();
    }

    final kidsByPod = <String?, List<Child>>{};
    for (final kid in kids) {
      kidsByPod.putIfAbsent(kid.groupId, () => []).add(kid);
    }
    final unassigned = kidsByPod[null] ?? const <Child>[];

    return ListView(
      padding: const EdgeInsets.only(
        top: AppSpacing.sm,
        bottom: AppSpacing.xxxl * 2,
      ),
      children: [
        for (final pod in pods)
          _PodSection(
            pod: pod,
            kids: kidsByPod[pod.id] ?? const [],
          ),
        if (unassigned.isNotEmpty)
          _PodSection(
            pod: null,
            kids: unassigned,
          ),
      ],
    );
  }
}

class _PodSection extends ConsumerWidget {
  const _PodSection({required this.pod, required this.kids});

  final Group? pod;
  final List<Child> kids;

  Future<void> _openEdit(BuildContext context) async {
    final current = pod;
    if (current == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditGroupSheet(pod: current),
    );
  }

  Future<void> _moveKidHere(WidgetRef ref, Child kid) async {
    // Idempotent: dropping a kid back on their own pod does nothing.
    if (kid.groupId == pod?.id) return;
    await ref.read(childrenRepositoryProvider).updateKidPod(
          childId: kid.id,
          groupId: pod?.id,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final title = pod?.name ?? 'Unassigned';
    final swatch = podColorFromHex(pod?.colorHex);

    return DragTarget<Child>(
      // Only accept kids that would actually move — prevents the
      // highlight from turning on when you drag a Redbird onto the
      // Redbirds section.
      onWillAcceptWithDetails: (d) => d.data.groupId != pod?.id,
      onAcceptWithDetails: (d) => _moveKidHere(ref, d.data),
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
                onTap: pod == null ? null : () => _openEdit(context),
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
                        '${kids.length}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (pod != null) ...[
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
              if (kids.isEmpty)
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
                    for (final kid in kids)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppSpacing.sm,
                        ),
                        child: _DraggableKidTile(kid: kid),
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

/// Long-press to pick up, drag onto any pod section to reassign.
/// We don't render a grip handle — the drag affordance is the
/// long-press itself, which keeps the list visually calm.
class _DraggableKidTile extends StatelessWidget {
  const _DraggableKidTile({required this.kid});

  final Child kid;

  @override
  Widget build(BuildContext context) {
    final tile = ChildTile(
      kid: kid,
      onTap: () => context.push('/children/${kid.id}'),
    );
    return LongPressDraggable<Child>(
      data: kid,
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
