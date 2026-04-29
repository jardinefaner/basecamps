import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adult_timeline_repository.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/adults/role_blocks_repository.dart';
import 'package:basecamp/features/adults/widgets/adult_timeline_editor_sheet.dart';
import 'package:basecamp/features/adults/widgets/edit_adult_sheet.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/groups/group_summary_repository.dart';
import 'package:basecamp/features/parents/parents_repository.dart';
import 'package:basecamp/features/roles/roles_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/week_days.dart';
import 'package:basecamp/features/schedule/widgets/edit_template_sheet.dart';
import 'package:basecamp/features/schedule/widgets/new_activity_wizard.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Profile + schedule surface for a single adult. Two tabs:
///
///   * **Profile** — avatar, contact info (tap-to-call / tap-to-email),
///     "also a parent" bridge, and the free-form notes field. The
///     "who is this person" half.
///
///   * **Schedule** — data-issue banners, today's blocks, the weekly
///     availability grid, the per-weekday plan + date overrides, and
///     "what they run". The "when do they work and on what" half. The
///     FAB to add a new activity (pre-filled with this adult) lives
///     here too.
///
/// Splitting these used to be one tall scroll — every section stacked
/// in one ListView with a 40/60 column break on wide screens. The
/// page kept growing (data issues, availability grid, day plan +
/// overrides, assignments) until the profile fields at the top were
/// half a screen away from anything actionable. Tabs cap the scroll at
/// "one logical thing" each.
class AdultDetailScreen extends ConsumerStatefulWidget {
  const AdultDetailScreen({required this.adultId, super.key});

  final String adultId;

  @override
  ConsumerState<AdultDetailScreen> createState() =>
      _AdultDetailScreenState();
}

class _AdultDetailScreenState extends ConsumerState<AdultDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    // FAB is Schedule-only, so rebuild on tab change to show / hide it.
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String get adultId => widget.adultId;

  @override
  Widget build(BuildContext context) {
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
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Profile'),
            Tab(text: 'Schedule'),
          ],
        ),
      ),
      floatingActionButton: _tabs.index == 1
          ? adultAsync.maybeWhen(
              data: (s) => s == null
                  ? null
                  : FloatingActionButton.extended(
                      onPressed: () => _openAddActivity(context, s),
                      icon: const Icon(Icons.add),
                      label: const Text('Add activity'),
                    ),
              orElse: () => null,
            )
          : null,
      body: adultAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (s) {
          if (s == null) {
            return const Center(child: Text('Adult not found'));
          }
          return TabBarView(
            controller: _tabs,
            children: [
              _ProfileTab(
                adult: s,
                onEdit: () => _openEdit(context, s),
              ),
              _ScheduleTab(
                adultId: adultId,
                onItemTap: (item) => _openTemplate(context, ref, item),
              ),
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

/// Profile tab body — identity + contact + parent bridge + notes.
/// Notes used to live at the bottom of the schedule scroll; pulling
/// them up here means a teacher reading "who is this person" sees the
/// note next to the contact rows where it actually belongs.
class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.adult, required this.onEdit});

  final Adult adult;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notes = (adult.notes ?? '').trim();
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxxl * 2,
      ),
      children: [
        _Header(adult: adult, onEdit: onEdit),
        _ContactSection(adult: adult),
        _AlsoParentBadge(adult: adult),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notes', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(notes, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Schedule tab body — every working / availability section in one
/// scroll. A wide-screen 40/60 split was the old way of getting
/// schedule + identity side-by-side; tabs make the split obsolete
/// (each tab uses the full width on every breakpoint).
class _ScheduleTab extends StatelessWidget {
  const _ScheduleTab({
    required this.adultId,
    required this.onItemTap,
  });

  final String adultId;
  final void Function(ScheduleItem item) onItemTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxxl * 2,
      ),
      children: [
        // _DataIssuesCard renders an empty SizedBox when there are no
        // issues, so it costs nothing in the common case but pops to
        // the top the moment something needs attention.
        Consumer(
          builder: (_, ref, _) {
            final adultAsync = ref.watch(adultProvider(adultId));
            final s = adultAsync.asData?.value;
            if (s == null) return const SizedBox.shrink();
            return _DataIssuesCard(adult: s);
          },
        ),
        _TodayBlocksSection(adultId: adultId),
        const SizedBox(height: AppSpacing.lg),
        _AvailabilitySection(adultId: adultId),
        const SizedBox(height: AppSpacing.lg),
        _DayPlanSection(adultId: adultId),
        const SizedBox(height: AppSpacing.lg),
        _AssignedActivitiesSection(
          adultId: adultId,
          onItemTap: onItemTap,
        ),
      ],
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
                  // v39: resolve the role label by priority —
                  //   1. roleId → Roles entity name
                  //   2. legacy free-text `role` string
                  //   3. nothing
                  Builder(
                    builder: (_) {
                      final roleId = adult.roleId;
                      final resolvedName = roleId == null
                          ? null
                          : ref.watch(roleProvider(roleId)).asData?.value?.name;
                      final legacy = (adult.role ?? '').trim();
                      final label = resolvedName ??
                          (legacy.isEmpty ? null : legacy);
                      if (label == null) return const SizedBox.shrink();
                      return Text(
                        label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      );
                    },
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

/// Day-plan timeline (v48). Lists this adult's role-block
/// pattern grouped by weekday. Tapping a block opens an editor;
/// the FAB at the bottom of the section adds a new block to
/// whichever weekday is currently selected.
///
/// Slice 1 ships read + add + delete. The drag-to-reschedule
/// grid editor is slice 3. Per-date overrides are also slice
/// 3 — for now the section shows the recurring pattern only.
class _DayPlanSection extends ConsumerStatefulWidget {
  const _DayPlanSection({required this.adultId});

  final String adultId;

  @override
  ConsumerState<_DayPlanSection> createState() =>
      _DayPlanSectionState();
}

class _DayPlanSectionState extends ConsumerState<_DayPlanSection> {
  /// Selected weekday (1=Mon … 7=Sun). Defaults to today's
  /// weekday so the most relevant blocks render first.
  int _selectedDay = DateTime.now().weekday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocksAsync = ref.watch(
      adultRoleBlockPatternProvider(widget.adultId),
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Day plan',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _openAddSheet(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Block'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Recurring weekly pattern: anchor / specialist / break / '
            'lunch / admin / sub. Drag-edit comes in a future round.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Day-of-week strip — same convention as the
          // availability section uses elsewhere on this screen.
          _DayChipStrip(
            selectedDay: _selectedDay,
            onSelect: (d) => setState(() => _selectedDay = d),
          ),
          const SizedBox(height: AppSpacing.md),
          blocksAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) =>
                Text('Couldn’t load day plan: $err'),
            data: (all) {
              final today = all
                  .where((b) => b.weekday == _selectedDay)
                  .toList()
                ..sort((a, b) =>
                    a.startMinute.compareTo(b.startMinute));
              if (today.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.md,
                  ),
                  child: Text(
                    'No blocks for ${_dayName(_selectedDay)} yet. '
                    'Tap "Block" to add one.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final b in today)
                    _RoleBlockTile(
                      block: b,
                      onTap: () => _openEditSheet(context, b),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          _OverridesSubsection(adultId: widget.adultId),
        ],
      ),
    );
  }

  Future<void> _openAddSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RoleBlockSheet(
        adultId: widget.adultId,
        defaultWeekday: _selectedDay,
      ),
    );
  }

  Future<void> _openEditSheet(
    BuildContext context,
    AdultRoleBlock block,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RoleBlockSheet(
        adultId: widget.adultId,
        defaultWeekday: block.weekday,
        existing: block,
      ),
    );
  }

  static String _dayName(int weekday) {
    const names = ['', 'Monday', 'Tuesday', 'Wednesday',
                   'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return weekday >= 1 && weekday <= 7 ? names[weekday] : 'Day $weekday';
  }
}

class _DayChipStrip extends StatelessWidget {
  const _DayChipStrip({
    required this.selectedDay,
    required this.onSelect,
  });

  final int selectedDay;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int d = 1; d <= 5; d++) ...[
            ChoiceChip(
              label: Text(_short(d)),
              selected: selectedDay == d,
              onSelected: (_) => onSelect(d),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }

  static String _short(int day) {
    const labels = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
    return day < labels.length ? labels[day] : 'D$day';
  }
}

class _RoleBlockTile extends ConsumerWidget {
  const _RoleBlockTile({required this.block, required this.onTap});

  final AdultRoleBlock block;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final kind = RoleBlockKind.fromValue(block.kind);
    final accent = _toneFor(theme, kind);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            kind.label,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (block.subject != null &&
                              block.subject!.isNotEmpty) ...[
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              '· ${block.subject}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_fmtTime(block.startMinute)}–'
                        '${_fmtTime(block.endMinute)}'
                        '${_groupLabel(ref, block.groupId)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _groupLabel(WidgetRef ref, String? groupId) {
    if (groupId == null) return '';
    final groups = ref.read(groupsProvider).asData?.value ?? const [];
    for (final g in groups) {
      if (g.id == groupId) return ' · ${g.name}';
    }
    return ' · (group)';
  }

  Color _toneFor(ThemeData theme, RoleBlockKind kind) {
    switch (kind) {
      case RoleBlockKind.anchor:
        return theme.colorScheme.primary;
      case RoleBlockKind.specialist:
        return theme.colorScheme.tertiary;
      case RoleBlockKind.break_:
      case RoleBlockKind.lunch:
        return theme.colorScheme.outline;
      case RoleBlockKind.admin:
        return theme.colorScheme.secondary;
      case RoleBlockKind.sub:
        return theme.colorScheme.error;
    }
  }
}

/// Modal sheet for creating or editing one role block. Keyboard-
/// aware shape (same canonical Padding(viewInsets) + scrollable
/// pattern as every other sheet in the app).
class _RoleBlockSheet extends ConsumerStatefulWidget {
  const _RoleBlockSheet({
    required this.adultId,
    required this.defaultWeekday,
    this.existing,
  });

  final String adultId;
  final int defaultWeekday;
  final AdultRoleBlock? existing;

  @override
  ConsumerState<_RoleBlockSheet> createState() => _RoleBlockSheetState();
}

class _RoleBlockSheetState extends ConsumerState<_RoleBlockSheet> {
  late int _weekday;
  late RoleBlockKind _kind;
  late int _startMinute;
  late int _endMinute;
  String? _subject;
  String? _groupId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _weekday = e?.weekday ?? widget.defaultWeekday;
    _kind = e == null
        ? RoleBlockKind.anchor
        : RoleBlockKind.fromValue(e.kind);
    _startMinute = e?.startMinute ?? 9 * 60;
    _endMinute = e?.endMinute ?? 10 * 60;
    _subject = e?.subject;
    _groupId = e?.groupId;
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _startMinute ~/ 60,
        minute: _startMinute % 60,
      ),
    );
    if (picked != null) {
      setState(() => _startMinute = picked.hour * 60 + picked.minute);
    }
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _endMinute ~/ 60,
        minute: _endMinute % 60,
      ),
    );
    if (picked != null) {
      setState(() => _endMinute = picked.hour * 60 + picked.minute);
    }
  }

  Future<void> _save() async {
    if (_endMinute <= _startMinute) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End time must be after start time.'),
        ),
      );
      return;
    }
    if (_kind.isInRoom && _groupId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_kind.label} blocks need a classroom selected.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(roleBlocksRepositoryProvider);
      if (widget.existing == null) {
        await repo.addPatternBlock(
          adultId: widget.adultId,
          weekday: _weekday,
          startMinute: _startMinute,
          endMinute: _endMinute,
          kind: _kind,
          subject: _subject,
          groupId: _kind.isInRoom ? _groupId : null,
        );
      } else {
        await repo.updatePatternBlock(
          id: widget.existing!.id,
          weekday: _weekday,
          startMinute: _startMinute,
          endMinute: _endMinute,
          kind: _kind,
          subject: Value(_subject),
          groupId: Value(_kind.isInRoom ? _groupId : null),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (widget.existing == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(roleBlocksRepositoryProvider)
          .deletePatternBlock(widget.existing!.id);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups =
        ref.watch(groupsProvider).asData?.value ?? const <Group>[];
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existing == null
                    ? 'New role block'
                    : 'Edit role block',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              // Weekday
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  for (int d = 1; d <= 5; d++)
                    ChoiceChip(
                      label: Text(_dayShort(d)),
                      selected: _weekday == d,
                      onSelected: (_) => setState(() => _weekday = d),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              // Kind
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  for (final k in RoleBlockKind.values)
                    ChoiceChip(
                      label: Text(k.label),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickStart,
                      icon: const Icon(Icons.access_time, size: 16),
                      label: Text('Start ${_fmtTime(_startMinute)}'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickEnd,
                      icon: const Icon(Icons.access_time, size: 16),
                      label: Text('End ${_fmtTime(_endMinute)}'),
                    ),
                  ),
                ],
              ),
              if (_kind == RoleBlockKind.specialist) ...[
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  initialValue: _subject,
                  decoration: const InputDecoration(
                    labelText: 'Subject (e.g. Art, Music)',
                  ),
                  onChanged: (v) =>
                      setState(() => _subject = v.trim().isEmpty ? null : v.trim()),
                ),
              ],
              if (_kind.isInRoom) ...[
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _groupId,
                  decoration: const InputDecoration(
                    labelText: 'Classroom',
                  ),
                  items: [
                    for (final g in groups)
                      DropdownMenuItem(value: g.id, child: Text(g.name)),
                  ],
                  onChanged: (v) => setState(() => _groupId = v),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  if (widget.existing != null)
                    TextButton(
                      onPressed: _saving ? null : _delete,
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      child: const Text('Delete'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _dayShort(int d) {
    const labels = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
    return d < labels.length ? labels[d] : 'D$d';
  }
}

String _fmtTime(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  final ampm = h >= 12 ? 'pm' : 'am';
  if (m == 0) return '$h12 $ampm';
  return '$h12:${m.toString().padLeft(2, '0')} $ampm';
}

/// One-off / per-date overrides on top of the recurring pattern.
/// Use cases:
///   * "Marcus is subbing in Bears 9-12 today only"
///     → add an override with `replaces=false` (additive).
///   * "Sarah is out, replace her 9-12 anchor block today"
///     → add an override with `replaces=true` covering that span.
///
/// Lists all overrides for the chosen date with a "+ Today only"
/// button. Tap an existing override to edit/delete; the date can
/// be changed via the date chip at the top.
class _OverridesSubsection extends ConsumerStatefulWidget {
  const _OverridesSubsection({required this.adultId});

  final String adultId;

  @override
  ConsumerState<_OverridesSubsection> createState() =>
      _OverridesSubsectionState();
}

class _OverridesSubsectionState
    extends ConsumerState<_OverridesSubsection> {
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _date = DateTime(
            picked.year,
            picked.month,
            picked.day,
          ));
    }
  }

  Future<void> _addOverride() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OverrideSheet(
        adultId: widget.adultId,
        date: _date,
      ),
    );
  }

  Future<void> _editOverride(AdultRoleBlockOverride o) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OverrideSheet(
        adultId: widget.adultId,
        date: _date,
        existing: o,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overridesAsync = ref.watch(
      _adultOverridesProvider((
        adultId: widget.adultId,
        date: _date,
      )),
    );
    final dateLabel = DateFormat.yMMMEd().format(_date);
    final isToday = _isSameDay(_date, DateTime.now());
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.event_repeat_outlined,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  isToday ? 'Today only' : 'Date-only changes',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.calendar_today_outlined,
                    size: 14),
                label: Text(dateLabel),
                onPressed: _pickDate,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'One-off blocks just for this date — substitutes, '
            "special events, anything that won't repeat.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          overridesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => Text('Error: $err'),
            data: (list) {
              if (list.isEmpty) {
                return Text(
                  'No overrides for this date.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                );
              }
              return Column(
                children: [
                  for (final o in list)
                    _OverrideTile(
                      row: o,
                      onTap: () => _editOverride(o),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addOverride,
              icon: const Icon(Icons.add, size: 16),
              label: Text(isToday
                  ? 'Add for today only'
                  : 'Add for $dateLabel'),
            ),
          ),
        ],
      ),
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _OverrideTile extends ConsumerWidget {
  const _OverrideTile({
    required this.row,
    required this.onTap,
  });

  final AdultRoleBlockOverride row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final kind = RoleBlockKind.fromValue(row.kind);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                _OverrideKindBadge(replaces: row.replaces),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${kind.label}'
                        '${row.subject != null ? ' · ${row.subject}' : ''}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${_fmtTime(row.startMinute)}–'
                        '${_fmtTime(row.endMinute)}'
                        '${_groupLabel(ref, row.groupId)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _groupLabel(WidgetRef ref, String? groupId) {
    if (groupId == null) return '';
    final groups = ref.read(groupsProvider).asData?.value ?? const [];
    for (final g in groups) {
      if (g.id == groupId) return ' · ${g.name}';
    }
    return ' · (group)';
  }
}

class _OverrideKindBadge extends StatelessWidget {
  const _OverrideKindBadge({required this.replaces});
  final bool replaces;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = replaces
        ? theme.colorScheme.error
        : theme.colorScheme.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        replaces ? 'replaces' : 'extra',
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Modal sheet for one date-specific override. Same shape as the
/// pattern-block sheet but writes to `adult_role_block_overrides`
/// and surfaces the `replaces` toggle (default off → "extra
/// block on top of the pattern" — the safer interpretation when
/// the user just wants to add something).
class _OverrideSheet extends ConsumerStatefulWidget {
  const _OverrideSheet({
    required this.adultId,
    required this.date,
    this.existing,
  });

  final String adultId;
  final DateTime date;
  final AdultRoleBlockOverride? existing;

  @override
  ConsumerState<_OverrideSheet> createState() => _OverrideSheetState();
}

class _OverrideSheetState extends ConsumerState<_OverrideSheet> {
  late RoleBlockKind _kind;
  late int _startMinute;
  late int _endMinute;
  String? _subject;
  String? _groupId;
  late bool _replaces;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _kind = e == null
        ? RoleBlockKind.sub
        : RoleBlockKind.fromValue(e.kind);
    _startMinute = e?.startMinute ?? 9 * 60;
    _endMinute = e?.endMinute ?? 12 * 60;
    _subject = e?.subject;
    _groupId = e?.groupId;
    _replaces = e?.replaces ?? false;
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _startMinute ~/ 60,
        minute: _startMinute % 60,
      ),
    );
    if (picked != null) {
      setState(() => _startMinute = picked.hour * 60 + picked.minute);
    }
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _endMinute ~/ 60,
        minute: _endMinute % 60,
      ),
    );
    if (picked != null) {
      setState(() => _endMinute = picked.hour * 60 + picked.minute);
    }
  }

  Future<void> _save() async {
    if (_endMinute <= _startMinute) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End time must be after start time.'),
        ),
      );
      return;
    }
    if (_kind.isInRoom && _groupId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_kind.label} blocks need a classroom selected.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(roleBlocksRepositoryProvider);
      if (widget.existing == null) {
        await repo.addOverride(
          adultId: widget.adultId,
          date: widget.date,
          startMinute: _startMinute,
          endMinute: _endMinute,
          kind: _kind,
          subject: _subject,
          groupId: _kind.isInRoom ? _groupId : null,
          replaces: _replaces,
        );
      } else {
        // Drift doesn't have an updateOverride helper yet; emulate
        // by deleting + adding so the row keeps a single source
        // of truth. The realtime apply on other devices sees one
        // delete + one insert which renders correctly.
        await repo.deleteOverride(widget.existing!.id);
        await repo.addOverride(
          adultId: widget.adultId,
          date: widget.date,
          startMinute: _startMinute,
          endMinute: _endMinute,
          kind: _kind,
          subject: _subject,
          groupId: _kind.isInRoom ? _groupId : null,
          replaces: _replaces,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (widget.existing == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(roleBlocksRepositoryProvider)
          .deleteOverride(widget.existing!.id);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups =
        ref.watch(groupsProvider).asData?.value ?? const <Group>[];
    final dateLabel = DateFormat.yMMMEd().format(widget.date);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existing == null
                    ? 'New override · $dateLabel'
                    : 'Edit override · $dateLabel',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                "Just for this date — won't affect the recurring "
                'pattern.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  for (final k in RoleBlockKind.values)
                    ChoiceChip(
                      label: Text(k.label),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickStart,
                      icon: const Icon(Icons.access_time, size: 16),
                      label: Text('Start ${_fmtTime(_startMinute)}'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickEnd,
                      icon: const Icon(Icons.access_time, size: 16),
                      label: Text('End ${_fmtTime(_endMinute)}'),
                    ),
                  ),
                ],
              ),
              if (_kind == RoleBlockKind.specialist) ...[
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  initialValue: _subject,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                  ),
                  onChanged: (v) =>
                      setState(() => _subject = v.trim().isEmpty ? null : v.trim()),
                ),
              ],
              if (_kind.isInRoom) ...[
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _groupId,
                  decoration: const InputDecoration(
                    labelText: 'Classroom',
                  ),
                  items: [
                    for (final g in groups)
                      DropdownMenuItem(value: g.id, child: Text(g.name)),
                  ],
                  onChanged: (v) => setState(() => _groupId = v),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Replaces pattern'),
                subtitle: Text(
                  _replaces
                      ? 'Cancels overlapping pattern blocks for this date'
                      : 'Adds on top of the pattern (extra block)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                value: _replaces,
                onChanged: (v) => setState(() => _replaces = v),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  if (widget.existing != null)
                    TextButton(
                      onPressed: _saving ? null : _delete,
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      child: const Text('Delete'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stream of overrides for one (adult, date) pair. Family key
/// is a record so two overrides for the same adult on different
/// dates each have their own stream.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final _adultOverridesProvider = StreamProvider.family<
    List<AdultRoleBlockOverride>,
    ({String adultId, DateTime date})>(
  (ref, key) => ref
      .watch(roleBlocksRepositoryProvider)
      .watchOverridesFor(adultId: key.adultId, date: key.date),
);

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

/// Pure check: does [adult]'s static role point somewhere? A lead with
/// no anchor group is a data-entry bug — flagged as lead but the
/// schedule has nowhere to put them.
bool leadWithoutAnchor(Adult adult) {
  return AdultRole.fromDb(adult.adultRole) == AdultRole.lead &&
      adult.anchoredGroupId == null;
}

/// Pure check: returns the weekdays (ISO 1..7) for which this adult
/// has a `lead` day-block with no groupId set. Sorted ascending and
/// de-duplicated so the UI can render "Monday's and Wednesday's" even
/// when the adult has two bad blocks on the same day.
List<int> leadBlocksMissingGroup(List<AdultDayBlock> blocks) {
  final days = <int>{
    for (final b in blocks)
      if (b.role == AdultBlockRole.lead.dbValue && b.groupId == null)
        b.dayOfWeek,
  };
  final list = days.toList()..sort();
  return list;
}

/// "Data issues" card — surfaces quiet validity warnings about the
/// adult's configuration. Self-hides entirely when neither check
/// fires, so a healthy profile renders unchanged.
class _DataIssuesCard extends ConsumerWidget {
  const _DataIssuesCard({required this.adult});

  final Adult adult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final missingAnchor = leadWithoutAnchor(adult);

    // Re-use the already-registered stream (same one _TodayBlocksSection
    // watches) so we don't spin up a second subscription for this
    // adult's blocks just to count bad ones.
    final blocksAsync = ref.watch(
      StreamProvider.autoDispose<List<AdultDayBlock>>(
        (ref) => ref
            .watch(adultTimelineRepositoryProvider)
            .watchBlocksFor(adult.id),
      ),
    );
    final blocks = blocksAsync.asData?.value ?? const <AdultDayBlock>[];
    final badDays = leadBlocksMissingGroup(blocks);

    if (!missingAnchor && badDays.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Card(
        color: theme.colorScheme.errorContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: AppSpacing.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.report_problem_outlined,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Data issues',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (missingAnchor) ...[
                const SizedBox(height: AppSpacing.sm),
                const _IssueRow(
                  title: 'Lead without anchor group',
                  body:
                      "This adult is flagged as a Lead but isn't anchored "
                      'to any group. Pick one on the role page — the '
                      "schedule won't know where to put them.",
                ),
              ],
              if (badDays.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _IssueRow(
                  title: 'Lead block missing group',
                  body: _blockMissingGroupBody(badDays),
                  // Tappable row: re-open the timeline editor so the
                  // teacher can fix it where the bad data lives.
                  onTap: () => _openTimelineEditor(context, ref),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openTimelineEditor(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final repo = ref.read(adultTimelineRepositoryProvider);
    final blocks = await repo.watchBlocksFor(adult.id).first;
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => AdultTimelineEditorSheet(
        adultId: adult.id,
        adultName: adult.name,
        initialBlocks: [
          for (final b in blocks) AdultTimelineBlock.fromRow(b),
        ],
      ),
    );
  }
}

/// Builds the user-facing sentence for "lead block missing group"
/// given the list of offending weekdays. Singular vs. plural phrasing
/// keeps the copy readable — "Monday's 'lead' block doesn't…" for one
/// day, "Monday's and Wednesday's 'lead' blocks don't…" for many.
String _blockMissingGroupBody(List<int> days) {
  final names = [for (final d in days) scheduleDayLabels[d - 1]];
  final String joined;
  if (names.length == 1) {
    joined = names.single;
  } else if (names.length == 2) {
    joined = '${names.first} and ${names.last}';
  } else {
    final head = names.sublist(0, names.length - 1).join(', ');
    joined = '$head, and ${names.last}';
  }
  final possessive = "$joined'${joined.endsWith('s') ? '' : 's'}";
  if (days.length == 1) {
    return "$possessive 'lead' block doesn't say which group to lead. "
        'Fix it in the timeline editor so the schedule can route '
        'activities correctly.';
  }
  return "$possessive 'lead' blocks don't say which group to lead. "
      'Fix it in the timeline editor so the schedule can route '
      'activities correctly.';
}

/// Phone / email rows that mirror the pattern on parent_detail_screen.
/// Tap launches `tel:` / `mailto:` via url_launcher; when the OS has
/// no handler we surface a brief snackbar. Self-hides when neither
/// field is set, so adults without contact info render unchanged.
class _ContactSection extends StatelessWidget {
  const _ContactSection({required this.adult});

  final Adult adult;

  @override
  Widget build(BuildContext context) {
    final phone = adult.phone;
    final email = adult.email;
    if ((phone == null || phone.isEmpty) &&
        (email == null || email.isEmpty)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (phone != null && phone.isNotEmpty)
            _AdultContactRow(
              icon: Icons.call_outlined,
              label: phone,
              uri: Uri(scheme: 'tel', path: phone),
              failMessage: "Couldn't start a call.",
            ),
          if (email != null && email.isNotEmpty)
            _AdultContactRow(
              icon: Icons.mail_outlined,
              label: email,
              uri: Uri(scheme: 'mailto', path: email),
              failMessage: "Couldn't open your email app.",
            ),
        ],
      ),
    );
  }
}

class _AdultContactRow extends StatelessWidget {
  const _AdultContactRow({
    required this.icon,
    required this.label,
    required this.uri,
    required this.failMessage,
  });

  final IconData icon;
  final String label;
  final Uri uri;
  final String failMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _launch(context),
      borderRadius: BorderRadius.circular(AppSpacing.xs),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xs,
          horizontal: 2,
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(label, style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launch(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await launchUrl(uri);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(failMessage)));
    }
  }
}

/// "Also a parent in this program" pill. Shown only when the adult's
/// `parentId` is set — taps through to `/more/parents/<id>` so the
/// teacher can jump to the paired row.
class _AlsoParentBadge extends ConsumerWidget {
  const _AlsoParentBadge({required this.adult});

  final Adult adult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final parentId = adult.parentId;
    if (parentId == null) return const SizedBox.shrink();
    final parent = ref.watch(parentProvider(parentId)).asData?.value;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: () => context.push('/more/parents/$parentId'),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.family_restroom_outlined,
                  size: 14,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  parent == null
                      ? 'Also a parent in this program'
                      : 'Also a parent — ${_displayName(parent)}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  Icons.chevron_right,
                  size: 14,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _displayName(Parent p) {
    final last = p.lastName;
    return last == null || last.isEmpty
        ? p.firstName
        : '${p.firstName} $last';
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.title, required this.body, this.onTap});

  final String title;
  final String body;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onErrorContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          body,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onErrorContainer,
          ),
        ),
      ],
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: content),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onErrorContainer,
            ),
          ],
        ),
      ),
    );
  }
}
