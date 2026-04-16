import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class KidDetailScreen extends ConsumerWidget {
  const KidDetailScreen({required this.kidId, super.key});

  final String kidId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kidAsync = ref.watch(kidProvider(kidId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(),
      body: kidAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (kid) {
          if (kid == null) {
            return const Center(child: Text('Kid not found'));
          }
          final fullName =
              [kid.firstName, kid.lastName].whereType<String>().join(' ');

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      kid.firstName.characters.first.toUpperCase(),
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fullName, style: theme.textTheme.headlineMedium),
                        if (kid.podId != null)
                          _PodLabel(podId: kid.podId!)
                        else
                          Text(
                            'Unassigned',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Observations', style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Coming soon — structured observations tied to this kid.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Photos & moments', style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Coming soon — everything tagged with this kid from the Today feed.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Share', style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      "Coming soon — send this kid's recap to parents via email, SMS, or a read-only link.",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PodLabel extends ConsumerWidget {
  const _PodLabel({required this.podId});

  final String podId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pod = ref.watch(podProvider(podId));
    return pod.maybeWhen(
      data: (p) => Text(
        p?.name ?? '',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}
