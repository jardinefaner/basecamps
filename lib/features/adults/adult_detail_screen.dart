import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adult_timeline_repository.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/adults/widgets/edit_adult_sheet.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/groups/group_summary_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/week_days.dart';
import 'package:basecamp/features/schedule/widgets/edit_template_sheet.dart';
import 'package:basecamp/features/schedule/widgets/new_activity_wizard.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Profile + schedule surface for a single adult. Header shows
/// their avatar and contact info; below it sits a weekly list of the
/// blocks they're available plus every activity they currently run.
/// A "+ Add activity" button pre-fills this adult into the
/// activity wizard so teachers can schedule them without leaving the
/// context.
class AdultDetailScreen extends ConsumerWidget {
  const AdultDetailScreen({required this.adultId, super.key});

  final String adultId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final adultAsync = ref.watch(adultProvider(adultId));

    return Scaffold(
      appBar: AppBar(
        actions: [
          adultAsync.maybeWhen(
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
      floatingActionButton: adultAsync.maybeWhen(
        data: (s) => s == null
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _openAddActivity(context, s),
                icon: const Icon(Icons.add),
                label: const Text('Add activity'),
              ),
        orElse: () => null,
      ),
      body: adultAsync.when(
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
              _Header(adult: s, onEdit: () => _openEdit(context, s)),
              const SizedBox(height: AppSpacing.xl),
              _TodayBlocksSection(adultId: adultId),
              const SizedBox(height: AppSpacing.lg),
              _AvailabilitySection(adultId: adultId),
              const SizedBox(height: AppSpacing.lg),
              _AssignedActivitiesSection(
                adultId: adultId,
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

  Future<void> _openEdit(BuildContext context, Adult s) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditAdultSheet(adult: s),
    );
  }

  Future<void> _openAddActivity(BuildContext context, Adult s) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => NewActivityWizardScreen(initialAdultId: s.id),
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

class _Header extends ConsumerWidget {
  const _Header({required this.adult, required this.onEdit});

  final Adult adult;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final initial = adult.name.isNotEmpty
        ? adult.name.characters.first.toUpperCase()
        : '?';
    final role = AdultRole.fromDb(adult.adultRole);
    // Anchor group name is only meaningful for leads. Safe-default
    // to a null watcher when the adult has no anchor so we don't
    // spin up a provider just to get an empty string back.
    final anchorId = adult.anchoredGroupId;
    final anchorName = anchorId == null
        ? null
        : ref.watch(groupProvider(anchorId)).asData?.value?.name;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Row(
          children: [
            SmallAvatar(
              path: adult.avatarPath,
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
                    adult.name,
                    style: theme.textTheme.headlineMedium,
                  ),
                  if ((adult.role ?? '').trim().isNotEmpty)
                    Text(
                      adult.role!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: 4,
                    children: [
                      _RoleChip(role: role),
                      if (role == AdultRole.lead && anchorName != null)
                        _AnchorChip(name: anchorName),
                      if (role == AdultRole.lead && anchorId != null &&
                          anchorName == null)
                        const _AnchorChip(name: '…'),
                    ],
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

/// Small role pill next to the adult's name. Mirrors the one on the
/// Adults list tile so scanning between list + detail stays visually
/// consistent.
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final AdultRole role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg, label) = switch (role) {
      AdultRole.lead => (
          theme.colorScheme.primaryContainer,
          theme.colorScheme.onPrimaryContainer,
          'Lead',
        ),
      AdultRole.specialist => (
          theme.colorScheme.tertiaryContainer,
          theme.colorScheme.onTertiaryContainer,
          'Specialist',
        ),
      AdultRole.ambient => (
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurface,
          'Ambient',
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// "Anchors: Butterflies" chip next to the role. Shown only for
/// leads with an anchor — adults + ambient never anchor a
/// group.
class _AnchorChip extends StatelessWidget {
  const _AnchorChip({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.anchor,
            size: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            name,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailabilitySection extends ConsumerWidget {
  const _AvailabilitySection({required this.adultId});

  final String adultId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final availabilityAsync =
        ref.watch(adultAvailabilityProvider(adultId));
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
              final byDay = <int, List<AdultAvailabilityData>>{};
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
  final List<AdultAvailabilityData> blocks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              scheduleDayShortLabels[day - 1],
              style: theme.textTheme.titleSmall,
            ),
          ),
          Expanded(
            child: blocks.isEmpty
                ? Text(
                    'Off',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final b in blocks) _blockLine(theme, b),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Top line is the shift span; below it, a single muted row lists
  /// break + lunch windows when set. Kept on one row so a teacher
  /// scanning the week sees the shape at a glance.
  Widget _blockLine(ThemeData theme, AdultAvailabilityData b) {
    final extras = <String>[
      if (b.breakStart != null && b.breakEnd != null)
        'break ${_display(b.breakStart!)}–${_display(b.breakEnd!)}',
      if (b.break2Start != null && b.break2End != null)
        'break ${_display(b.break2Start!)}–${_display(b.break2End!)}',
      if (b.lunchStart != null && b.lunchEnd != null)
        'lunch ${_display(b.lunchStart!)}–${_display(b.lunchEnd!)}',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_display(b.startTime)} – ${_display(b.endTime)}',
            style: theme.textTheme.bodyMedium,
          ),
          if (extras.isNotEmpty)
            Text(
              extras.join(' · '),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
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
    required this.adultId,
    required this.onItemTap,
  });

  final String adultId;
  final ValueChanged<ScheduleItem> onItemTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final templatesAsync = ref.watch(templatesByAdultProvider(adultId));
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
                            adultId: t.adultId,
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

/// "Today's blocks" section — renders this adult's day timeline
/// (v30 AdultDayBlocks) for today's weekday, cross-referencing
/// each block's group assignment.
///
/// For LEAD blocks: shows the anchored group's name inline.
/// For SPECIALIST blocks: cross-references scheduled activities
/// with this adult assigned + time overlap, and lists the
/// destination groups (plus each group's own anchor lead name so
/// the teacher sees "rotating into Butterflies (anchor: Sarah)"
/// at a glance).
///
/// Self-hides when the adult has no timeline set for today — the
/// Availability section above already tells the teacher what day
/// shape they're on.
class _TodayBlocksSection extends ConsumerWidget {
  const _TodayBlocksSection({required this.adultId});

  final String adultId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final dayOfWeek = today.weekday;
    // Weekends show Monday's layout — program runs M-F, weekend
    // view on this screen isn't useful and just lands empty.
    final effectiveDay = (dayOfWeek >= 1 && dayOfWeek <= 5)
        ? dayOfWeek
        : 1;

    final blocksAsync = ref.watch(
      StreamProvider.autoDispose<List<AdultDayBlock>>(
        (ref) => ref
            .watch(adultTimelineRepositoryProvider)
            .watchBlocksFor(adultId),
      ),
    );
    final blocks = (blocksAsync.asData?.value ?? const <AdultDayBlock>[])
        .where((b) => b.dayOfWeek == effectiveDay)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    if (blocks.isEmpty) return const SizedBox.shrink();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Today's blocks",
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 2),
          Text(
            'Where they are as the day moves.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final b in blocks)
            _BlockRow(adultId: adultId, block: b),
        ],
      ),
    );
  }
}

class _BlockRow extends ConsumerWidget {
  const _BlockRow({required this.adultId, required this.block});

  final String adultId;
  final AdultDayBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final role = AdultBlockRole.fromDb(block.role);

    // Resolve destination label.
    //
    // Lead block: block.groupId is the anchored group — name it.
    // Adult block: render one row per overlapping scheduled
    // template (rotating into different activities through the
    // day), each resolved to the destination group + that group's
    // anchor-lead name inside a dedicated child widget.
    final summariesByGroupId = {
      for (final g in ref.watch(groupSummariesProvider).asData?.value ??
          const <GroupSummary>[])
        g.id: g,
    };

    Widget destinationContent;
    if (role == AdultBlockRole.lead) {
      final g = block.groupId == null
          ? null
          : summariesByGroupId[block.groupId!];
      destinationContent = Text(
        g?.name ?? 'No group set',
        style: theme.textTheme.bodyMedium,
      );
    } else {
      // Adult — cross-ref scheduled templates that overlap the
      // block window. Each gets its own line with the destination
      // group + anchor-lead name resolved through the
      // templateGroupsProvider join.
      final allTemplates =
          ref.watch(templatesByAdultProvider(adultId))
                  .asData?.value ??
              const <ScheduleTemplate>[];
      final blockStart = _parseHHmm(block.startTime);
      final blockEnd = _parseHHmm(block.endTime);
      final overlapping = [
        for (final t in allTemplates)
          if (t.dayOfWeek == block.dayOfWeek &&
              _parseHHmm(t.startTime) < blockEnd &&
              _parseHHmm(t.endTime) > blockStart)
            t,
      ]..sort((a, b) => a.startTime.compareTo(b.startTime));

      if (overlapping.isEmpty) {
        destinationContent = Text(
          'Rotating · no activity scheduled',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        );
      } else {
        destinationContent = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final t in overlapping)
              _AdultDestinationLine(
                template: t,
                summariesByGroupId: summariesByGroupId,
              ),
          ],
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              '${_display(block.startTime)}–${_display(block.endTime)}',
              style: theme.textTheme.labelMedium,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _MiniRoleChip(role: role),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: destinationContent),
                  ],
                ),
              ],
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

/// One line inside a adult block — describes a single activity
/// they're running during that block, with the destination group(s)
/// and each group's anchor-lead name so the covering lead knows
/// where they're heading and who the "home" lead there is.
///
/// Watches [templateGroupsProvider] for its own template so the
/// parent row doesn't have to thread N async lookups. Loading
/// state shows a muted activity title only; once the join lands,
/// destinations + anchors fill in.
class _AdultDestinationLine extends ConsumerWidget {
  const _AdultDestinationLine({
    required this.template,
    required this.summariesByGroupId,
  });

  final ScheduleTemplate template;
  final Map<String, GroupSummary> summariesByGroupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final groupIdsAsync =
        ref.watch(templateGroupsProvider(template.id));

    // Build the destination phrase based on the template's scope.
    String? destination;
    if (template.allGroups) {
      destination = 'all groups';
    } else {
      final groupIds = groupIdsAsync.asData?.value ?? const <String>[];
      if (groupIds.isEmpty && !groupIdsAsync.isLoading) {
        // No-groups activity (explicit staff-prep etc). Leave
        // destination null so the line renders just the title.
      } else {
        final dests = <String>[];
        for (final gid in groupIds) {
          final summary = summariesByGroupId[gid];
          if (summary == null) continue;
          // Each anchor-lead name surfaces alongside the group so
          // the rotator sees "Butterflies (with Sarah)" at a glance.
          // Groups with multiple anchors list just the first by name
          // order (leadsInPodNow resolution is a Today concern, not
          // a schedule-static one).
          final anchor = summary.anchorLeads.isEmpty
              ? null
              : summary.anchorLeads.first.name;
          dests.add(
            anchor == null
                ? summary.name
                : '${summary.name} (with $anchor)',
          );
        }
        if (dests.isNotEmpty) destination = dests.join(' · ');
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            template.title,
            style: theme.textTheme.bodyMedium,
          ),
          if (destination != null)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_right_alt,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      destination,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

int _parseHHmm(String hhmm) {
  final parts = hhmm.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

/// Compact role chip used inline next to a block row's time range.
class _MiniRoleChip extends StatelessWidget {
  const _MiniRoleChip({required this.role});
  final AdultBlockRole role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg, label) = switch (role) {
      AdultBlockRole.lead => (
          theme.colorScheme.primaryContainer,
          theme.colorScheme.onPrimaryContainer,
          'LEAD',
        ),
      AdultBlockRole.specialist => (
          theme.colorScheme.tertiaryContainer,
          theme.colorScheme.onTertiaryContainer,
          'SPEC',
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
