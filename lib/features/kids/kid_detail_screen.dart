import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/widgets/activity_detail_sheet.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
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
              _TodayTimeline(kid: kid),
              const SizedBox(height: AppSpacing.md),
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

/// Today's filtered schedule for this specific kid: items where their pod
/// is in the activity's targeted pods (or where the activity is "all pods").
class _TodayTimeline extends ConsumerWidget {
  const _TodayTimeline({required this.kid});

  final Kid kid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheduleAsync = ref.watch(todayScheduleProvider);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Today's schedule", style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          scheduleAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: LinearProgressIndicator(),
            ),
            error: (err, _) => Text(
              'Error loading schedule',
              style: theme.textTheme.bodySmall,
            ),
            data: (items) {
              final mine = items.where((i) {
                if (i.isAllPods) return true;
                return kid.podId != null && i.podIds.contains(kid.podId);
              }).toList();

              if (mine.isEmpty) {
                return Text(
                  'Nothing scheduled for this kid today.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              }

              final now = DateTime.now();
              final nowMinutes = now.hour * 60 + now.minute;

              return Column(
                children: [
                  for (final item in mine)
                    _TimelineRow(
                      item: item,
                      isNow: !item.isFullDay &&
                          nowMinutes >= item.startMinutes &&
                          nowMinutes < item.endMinutes,
                      onTap: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (_) => ActivityDetailSheet(item: item),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends ConsumerWidget {
  const _TimelineRow({
    required this.item,
    required this.isNow,
    required this.onTap,
  });

  final ScheduleItem item;
  final bool isNow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final specialistId = item.specialistId;
    final specialist = specialistId == null
        ? null
        : ref.watch(specialistProvider(specialistId)).asData?.value;
    final subtitleParts = <String>[];
    if (specialist != null) subtitleParts.add(specialist.name);
    if (item.location != null && item.location!.isNotEmpty) {
      subtitleParts.add(item.location!);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 54,
              child: Text(
                item.isFullDay ? 'All day' : _formatTime(item.startTime),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: isNow ? theme.colorScheme.primary : null,
                  fontWeight: isNow ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      if (isNow)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'NOW',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (subtitleParts.isNotEmpty)
                    Text(
                      subtitleParts.join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.parse(parts[0]);
    final m = parts[1];
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final period = h < 12 ? 'a' : 'p';
    return m == '00' ? '$hour12$period' : '$hour12:$m$period';
  }
}
