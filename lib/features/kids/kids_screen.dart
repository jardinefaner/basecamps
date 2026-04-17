import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/kids/widgets/kid_tile.dart';
import 'package:basecamp/features/kids/widgets/new_kid_wizard.dart';
import 'package:basecamp/features/kids/widgets/new_pod_wizard.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class KidsScreen extends ConsumerWidget {
  const KidsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final podsAsync = ref.watch(podsProvider);
    final kidsAsync = ref.watch(kidsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kids'),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add_outlined),
            tooltip: 'Add pod',
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
                label: const Text('Add kid'),
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
        builder: (_) => const NewPodWizardScreen(),
      ),
    );
  }

  Future<void> _openAddKid(
    BuildContext context, {
    required List<Pod> pods,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => NewKidWizardScreen(pods: pods),
      ),
    );
  }
}

class _KidsBody extends StatelessWidget {
  const _KidsBody({required this.pods, required this.kids});

  final List<Pod> pods;
  final List<Kid> kids;

  @override
  Widget build(BuildContext context) {
    if (pods.isEmpty) {
      return const _EmptyState();
    }

    final kidsByPod = <String?, List<Kid>>{};
    for (final kid in kids) {
      kidsByPod.putIfAbsent(kid.podId, () => []).add(kid);
    }
    final unassigned = kidsByPod[null] ?? const <Kid>[];

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

class _PodSection extends StatelessWidget {
  const _PodSection({required this.pod, required this.kids});

  final Pod? pod;
  final List<Kid> kids;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = pod?.name ?? 'Unassigned';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xs,
              bottom: AppSpacing.sm,
            ),
            child: Row(
              children: [
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
              ],
            ),
          ),
          if (kids.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                'No kids yet',
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            Column(
              children: [
                for (final kid in kids)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: KidTile(
                      kid: kid,
                      onTap: () => context.push('/kids/${kid.id}'),
                    ),
                  ),
              ],
            ),
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
              'No pods yet',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Create your first pod to start adding kids.',
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
                  builder: (_) => const NewPodWizardScreen(),
                ),
              ),
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Create pod'),
            ),
          ],
        ),
      ),
    );
  }
}
