import 'package:basecamp/features/schedule/conflicts.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/widgets/activity_detail_sheet.dart';
import 'package:basecamp/features/today/widgets/schedule_item_card.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  Future<void> _openDetail(BuildContext context, ScheduleItem item) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ActivityDetailSheet(item: item),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(todayScheduleProvider);
    final theme = Theme.of(context);
    final now = DateTime.now();
    final dateLabel = DateFormat('EEEE · MMMM d').format(now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_outlined),
            tooltip: 'Schedule',
            onPressed: () => context.push('/today/schedule'),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: scheduleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (items) {
          final nowMinutes = now.hour * 60 + now.minute;
          int? currentIndex;
          for (var i = 0; i < items.length; i++) {
            final start = items[i].startMinutes;
            final endParts = items[i].endTime.split(':');
            final end = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
            if (nowMinutes >= start && nowMinutes < end) {
              currentIndex = i;
              break;
            }
          }
          final conflicts = detectConflictingIds(items);

          return ListView(
            padding: const EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              top: AppSpacing.md,
              bottom: AppSpacing.xxxl * 2,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.xs,
                  bottom: AppSpacing.sm,
                ),
                child: Text(
                  dateLabel.toUpperCase(),
                  style: theme.textTheme.labelMedium,
                ),
              ),
              if (items.isEmpty)
                _EmptyState(onEdit: () => context.push('/today/schedule'))
              else
                for (var i = 0; i < items.length; i++) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: ScheduleItemCard(
                      item: items[i],
                      isNow: i == currentIndex,
                      isPast: currentIndex != null && i < currentIndex,
                      hasConflict: conflicts.contains(items[i].id),
                      onTap: () => _openDetail(context, items[i]),
                    ),
                  ),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onEdit});

  final VoidCallback onEdit;

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
              Icons.schedule_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Nothing scheduled today',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Set up a weekly schedule or add one-off activities.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.tune_outlined),
              label: const Text('Edit schedule'),
            ),
          ],
        ),
      ),
    );
  }
}
