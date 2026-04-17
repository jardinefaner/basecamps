import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Bottom sheet showing an activity's details and the kid roster for it.
/// Roster is derived from pod membership: kids whose pod is listed (or
/// all kids if the item targets "all pods").
///
/// Also hosts the "Just for today" override actions — cancel this
/// instance, or shift its start/end times for this date only. The
/// template stays untouched so next week's occurrence is unaffected.
class ActivityDetailSheet extends ConsumerWidget {
  const ActivityDetailSheet({required this.item, super.key});

  final ScheduleItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final kidsAsync = ref.watch(childrenProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.md,
        bottom: AppSpacing.xl + insets,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(item.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              item.isFullDay
                  ? 'All day'
                  : '${_formatTime(item.startTime)} – ${_formatTime(item.endTime)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _SpecialistRow(specialistId: item.specialistId),
            if (item.location != null && item.location!.isNotEmpty)
              _MetaRow(
                icon: Icons.place_outlined,
                text: item.location!,
              ),
            _PodsRow(groupIds: item.groupIds),
            if (item.notes != null && item.notes!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text('Notes', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(item.notes!, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: AppSpacing.xl),
            Text('Roster', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            kidsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text('Error: $err'),
              data: (kids) {
                final attending = kids
                    .where(
                      (k) =>
                          item.isAllGroups ||
                          (k.groupId != null && item.groupIds.contains(k.groupId)),
                    )
                    .toList();
                if (attending.isEmpty) {
                  return Text(
                    item.isNoGroups
                        ? 'No groups selected — this activity has no children.'
                        : 'No children assigned to these groups yet.',
                    style: theme.textTheme.bodySmall,
                  );
                }
                return Column(
                  children: [
                    for (final kid in attending)
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _RosterTile(
                          kid: kid,
                          onTap: () {
                            Navigator.of(context).pop();
                            unawaited(context.push('/children/${kid.id}'));
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
            if (_canOverride)
              _JustForTodaySection(item: item),
          ],
        ),
      ),
    );
  }

  /// Only show override actions on a concrete date — the specialist-
  /// detail preview uses a 1970 sentinel date, and multi-day entries
  /// can't be partially shifted without more UX.
  bool get _canOverride {
    if (item.date.year < 2000) return false;
    if (item.isMultiDay) return false;
    if (item.isFullDay) return false;
    return true;
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

/// Action strip at the bottom of the detail sheet: "just for today"
/// overrides that don't touch the template. Template-sourced items get
/// both a shift and a cancel; one-off entries just get a shift (cancel
/// is the existing delete flow).
class _JustForTodaySection extends ConsumerWidget {
  const _JustForTodaySection({required this.item});

  final ScheduleItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dateLabel = _dateLabel(item.date);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'JUST FOR TODAY · $dateLabel',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Changes apply to this date only — the weekly schedule stays.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => _shift(context, ref),
            icon: const Icon(Icons.schedule_outlined, size: 18),
            label: const Text('Shift time'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => _cancel(context, ref),
            icon: Icon(
              Icons.event_busy_outlined,
              size: 18,
              color: theme.colorScheme.error,
            ),
            label: Text(
              'Cancel today',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: theme.colorScheme.error.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shift(BuildContext context, WidgetRef ref) async {
    final start = item.startTimeOfDay;
    final end = item.endTimeOfDay;
    final durationMinutes =
        (end.hour * 60 + end.minute) - (start.hour * 60 + start.minute);

    final newStart = await showTimePicker(
      context: context,
      initialTime: start,
      helpText: 'Shift starts at',
    );
    if (newStart == null || !context.mounted) return;

    final newEndDefault = _addMinutes(newStart, durationMinutes);
    final newEnd = await showTimePicker(
      context: context,
      initialTime: newEndDefault,
      helpText: 'And ends at',
    );
    if (newEnd == null || !context.mounted) return;

    final startMin = newStart.hour * 60 + newStart.minute;
    final endMin = newEnd.hour * 60 + newEnd.minute;
    if (endMin <= startMin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start.')),
      );
      return;
    }

    final repo = ref.read(scheduleRepositoryProvider);
    final startHhmm = _hhmm(newStart);
    final endHhmm = _hhmm(newEnd);
    if (item.isFromTemplate && item.templateId != null) {
      await repo.shiftTemplateForDate(
        templateId: item.templateId!,
        date: item.date,
        startTime: startHhmm,
        endTime: endHhmm,
      );
    } else if (item.entryId != null) {
      await repo.shiftEntryTimes(
        entryId: item.entryId!,
        startTime: startHhmm,
        endTime: endHhmm,
      );
    }
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Cancel "${item.title}" today?',
      message:
          'This skips the activity on ${_dateLabel(item.date)}. The '
          'weekly schedule is unchanged — it will run next week as '
          'usual.',
      confirmLabel: 'Cancel today',
    );
    if (!confirmed || !context.mounted) return;

    final repo = ref.read(scheduleRepositoryProvider);
    if (item.isFromTemplate && item.templateId != null) {
      await repo.cancelTemplateForDate(
        templateId: item.templateId!,
        date: item.date,
      );
    } else if (item.entryId != null) {
      await repo.deleteEntry(item.entryId!);
    }
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  TimeOfDay _addMinutes(TimeOfDay t, int minutes) {
    final total = t.hour * 60 + t.minute + minutes;
    final wrapped = ((total % (24 * 60)) + 24 * 60) % (24 * 60);
    return TimeOfDay(hour: wrapped ~/ 60, minute: wrapped % 60);
  }

  String _dateLabel(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _SpecialistRow extends ConsumerWidget {
  const _SpecialistRow({required this.specialistId});

  final String? specialistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (specialistId == null) return const SizedBox.shrink();
    final specialist = ref.watch(specialistProvider(specialistId!)).asData?.value;
    if (specialist == null) return const SizedBox.shrink();
    final label = specialist.role == null || specialist.role!.isEmpty
        ? specialist.name
        : '${specialist.name} · ${specialist.role}';
    return _MetaRow(icon: Icons.badge_outlined, text: label);
  }
}

class _PodsRow extends ConsumerWidget {
  const _PodsRow({required this.groupIds});

  final List<String> groupIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (groupIds.isEmpty) {
      return const _MetaRow(
        icon: Icons.groups_outlined,
        text: 'All groups',
      );
    }
    final names = <String>[];
    for (final id in groupIds) {
      final pod = ref.watch(groupProvider(id)).asData?.value;
      if (pod != null) names.add(pod.name);
    }
    if (names.isEmpty) return const SizedBox.shrink();
    return _MetaRow(
      icon: Icons.groups_outlined,
      text: names.join(' + '),
    );
  }
}

class _RosterTile extends ConsumerWidget {
  const _RosterTile({required this.kid, required this.onTap});

  final Child kid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fullName =
        [kid.firstName, kid.lastName].whereType<String>().join(' ');
    final initial = kid.firstName.isNotEmpty
        ? kid.firstName.characters.first.toUpperCase()
        : '?';
    final groupId = kid.groupId;
    final pod =
        groupId == null ? null : ref.watch(groupProvider(groupId)).asData?.value;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              initial,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fullName, style: theme.textTheme.titleMedium),
                if (pod != null)
                  Text(pod.name, style: theme.textTheme.bodySmall),
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
}
