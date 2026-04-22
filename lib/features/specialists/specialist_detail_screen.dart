import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/week_days.dart';
import 'package:basecamp/features/schedule/widgets/edit_template_sheet.dart';
import 'package:basecamp/features/schedule/widgets/new_activity_wizard.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:basecamp/features/specialists/widgets/edit_specialist_sheet.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Profile + schedule surface for a single specialist. Header shows
/// their avatar and contact info; below it sits a weekly list of the
/// blocks they're available plus every activity they currently run.
/// A "+ Add activity" button pre-fills this specialist into the
/// activity wizard so teachers can schedule them without leaving the
/// context.
class SpecialistDetailScreen extends ConsumerWidget {
  const SpecialistDetailScreen({required this.specialistId, super.key});

  final String specialistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final specialistAsync = ref.watch(specialistProvider(specialistId));

    return Scaffold(
      appBar: AppBar(
        actions: [
          specialistAsync.maybeWhen(
            data: (s) => s == null
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _openEdit(context, s),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      floatingActionButton: specialistAsync.maybeWhen(
        data: (s) => s == null
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _openAddActivity(context, s),
                icon: const Icon(Icons.add),
                label: const Text('Add activity'),
              ),
        orElse: () => null,
      ),
      body: specialistAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (s) {
          if (s == null) {
            return const Center(child: Text('Adult not found'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xxxl * 2,
            ),
            children: [
              _Header(specialist: s, onEdit: () => _openEdit(context, s)),
              const SizedBox(height: AppSpacing.xl),
              _AvailabilitySection(specialistId: specialistId),
              const SizedBox(height: AppSpacing.lg),
              _AssignedActivitiesSection(
                specialistId: specialistId,
                onItemTap: (item) => _openTemplate(context, ref, item),
              ),
              if ((s.notes ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Notes', style: theme.textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.sm),
                      Text(s.notes!, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _openEdit(BuildContext context, Specialist s) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditSpecialistSheet(specialist: s),
    );
  }

  Future<void> _openAddActivity(BuildContext context, Specialist s) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => NewActivityWizardScreen(initialSpecialistId: s.id),
      ),
    );
  }

  Future<void> _openTemplate(
    BuildContext context,
    WidgetRef ref,
    ScheduleItem item,
  ) async {
    final templateId = item.templateId;
    if (templateId == null) return;
    final template =
        await ref.read(scheduleRepositoryProvider).getTemplate(templateId);
    if (template == null || !context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      isDismissible: false,
      builder: (_) => EditTemplateSheet(template: template),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.specialist, required this.onEdit});

  final Specialist specialist;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = specialist.name.isNotEmpty
        ? specialist.name.characters.first.toUpperCase()
        : '?';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Row(
          children: [
            SmallAvatar(
              path: specialist.avatarPath,
              fallbackInitial: initial,
              radius: 32,
              backgroundColor: theme.colorScheme.secondaryContainer,
              foregroundColor: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    specialist.name,
                    style: theme.textTheme.headlineMedium,
                  ),
                  if ((specialist.role ?? '').trim().isNotEmpty)
                    Text(
                      specialist.role!,
                      style: theme.textTheme.bodyMedium?.copyWith(
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
}

class _AvailabilitySection extends ConsumerWidget {
  const _AvailabilitySection({required this.specialistId});

  final String specialistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final availabilityAsync =
        ref.watch(specialistAvailabilityProvider(specialistId));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Availability', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          availabilityAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (err, _) => Text('Error: $err'),
            data: (blocks) {
              if (blocks.isEmpty) {
                return Text(
                  'No availability set. Tap edit to add working hours.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              }
              final byDay = <int, List<SpecialistAvailabilityData>>{};
              for (final b in blocks) {
                byDay.putIfAbsent(b.dayOfWeek, () => []).add(b);
              }
              return Column(
                children: [
                  for (final d in scheduleDayValues)
                    _AvailabilityRow(
                      day: d,
                      blocks: byDay[d] ?? const [],
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

class _AvailabilityRow extends StatelessWidget {
  const _AvailabilityRow({required this.day, required this.blocks});

  final int day;
  final List<SpecialistAvailabilityData> blocks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              scheduleDayShortLabels[day - 1],
              style: theme.textTheme.titleSmall,
            ),
          ),
          Expanded(
            child: Text(
              blocks.isEmpty
                  ? 'Off'
                  : blocks
                      .map((b) => '${_display(b.startTime)}'
                          ' – ${_display(b.endTime)}')
                      .join(' · '),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: blocks.isEmpty
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _display(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.parse(parts[0]);
    final m = parts[1];
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final period = h < 12 ? 'a' : 'p';
    return m == '00' ? '$hour12$period' : '$hour12:$m$period';
  }
}

class _AssignedActivitiesSection extends ConsumerWidget {
  const _AssignedActivitiesSection({
    required this.specialistId,
    required this.onItemTap,
  });

  final String specialistId;
  final ValueChanged<ScheduleItem> onItemTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final templatesAsync = ref.watch(templatesBySpecialistProvider(specialistId));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What they run', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          templatesAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (err, _) => Text('Error: $err'),
            data: (templates) {
              if (templates.isEmpty) {
                return Text(
                  'No activities yet. Tap "Add activity" below to '
                  'schedule one.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              }
              final byDay = <int, List<ScheduleTemplate>>{};
              for (final t in templates) {
                byDay.putIfAbsent(t.dayOfWeek, () => []).add(t);
              }
              return Column(
                children: [
                  for (final d in scheduleDayValues)
                    if ((byDay[d] ?? const []).isNotEmpty)
                      _DayGroup(
                        day: d,
                        templates: byDay[d]!,
                        onTap: (t) => onItemTap(
                          ScheduleItem(
                            id: t.id,
                            date: DateTime(1970),
                            startTime: t.startTime,
                            endTime: t.endTime,
                            isFullDay: t.isFullDay,
                            title: t.title,
                            groupIds: const [],
                            allGroups: t.allGroups,
                            specialistId: t.specialistId,
                            location: t.location,
                            notes: t.notes,
                            isFromTemplate: true,
                            templateId: t.id,
                          ),
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

class _DayGroup extends StatelessWidget {
  const _DayGroup({
    required this.day,
    required this.templates,
    required this.onTap,
  });

  final int day;
  final List<ScheduleTemplate> templates;
  final ValueChanged<ScheduleTemplate> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            scheduleDayShortLabels[day - 1].toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          for (final t in templates)
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => onTap(t),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.xs,
                  horizontal: 2,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        _display(t.startTime),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        t.title,
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _display(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.parse(parts[0]);
    final m = parts[1];
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final period = h < 12 ? 'a' : 'p';
    return m == '00' ? '$hour12$period' : '$hour12:$m$period';
  }
}
