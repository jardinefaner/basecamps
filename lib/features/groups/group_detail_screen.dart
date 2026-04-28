import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adult_timeline_repository.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/children/widgets/edit_child_sheet.dart';
import 'package:basecamp/features/children/widgets/edit_group_sheet.dart';
import 'package:basecamp/features/forms/polymorphic/definitions/incident.dart';
import 'package:basecamp/features/forms/polymorphic/definitions/parent_concern.dart';
import 'package:basecamp/features/forms/polymorphic/generic_form_screen.dart';
import 'package:basecamp/features/groups/group_summary_repository.dart';
import 'package:basecamp/features/observations/widgets/observation_composer.dart';
import 'package:basecamp/features/rooms/rooms_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/week_days.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:basecamp/ui/responsive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Single-group dashboard. Opens full-screen when a teacher taps a
/// group on the Children tab (or drills in from anywhere else that
/// has a groupId). Shows — and lets the teacher manage — the four
/// pieces of a group in one place:
///
///   - Identity (name, color, delete)          → EditGroupSheet
///   - Default room                             → inline picker
///   - Anchor leads                             → inline picker
///   - Kids roster (+ expected times)           → child edit sheet
///
/// Nothing here is new data: every action delegates to an existing
/// repository call, so the screen is a view composition plus a few
/// thin write helpers.
class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({required this.groupId, super.key});

  final String groupId;

  /// Convenience launcher so callers don't have to know the route
  /// shape — teachers tap a group on Children / Today / anywhere
  /// else and this pushes the full-screen detail. Returns once the
  /// teacher pops back.
  static Future<void> open(BuildContext context, String groupId) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => GroupDetailScreen(groupId: groupId),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(groupSummaryProvider(groupId));
    return Scaffold(
      appBar: AppBar(
        title: summaryAsync.maybeWhen(
          data: (s) => Text(s?.name ?? 'Group'),
          orElse: () => const Text('Group'),
        ),
        actions: [
          summaryAsync.maybeWhen(
            data: (s) => s == null
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit name & color',
                    onPressed: () => _openNameColorEdit(context, s.group),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: summaryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (summary) {
          if (summary == null) {
            return const _MissingGroup();
          }
          return _Body(summary: summary);
        },
      ),
    );
  }

  Future<void> _openNameColorEdit(BuildContext context, Group group) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditGroupSheet(group: group),
    );
  }
}

/// Shown when the teacher lands on a stale id (group was deleted in
/// another tab or on another device). Gives a clear out rather than
/// a blank screen.
class _MissingGroup extends StatelessWidget {
  const _MissingGroup();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.group_off, size: 48),
            const SizedBox(height: AppSpacing.md),
            const Text('This group no longer exists.'),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.summary});

  final GroupSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kidsAsync = ref.watch(childrenProvider);
    final kids = kidsAsync.asData?.value ?? const <Child>[];
    final kidsInGroup = kids.where((k) => k.groupId == summary.id).toList()
      ..sort((a, b) => a.firstName.compareTo(b.firstName));

    // Identity column — the color-dot hero header. Sparse but anchors
    // the screen. Becomes the left column on wide.
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroHeader(summary: summary),
      ],
    );

    // Body sections — unstaffed warning, capture actions, room,
    // leads, visitors today, kids roster. Stacks vertically in both
    // narrow and wide layouts, just inside different parents.
    final bodySections = <Widget>[
      _UnstaffedWarning(summary: summary),
      _CaptureActionCard(summary: summary),
      const SizedBox(height: AppSpacing.lg),
      _RoomSection(summary: summary),
      const SizedBox(height: AppSpacing.lg),
      _LeadsSection(summary: summary),
      const SizedBox(height: AppSpacing.lg),
      _VisitorsTodaySection(summary: summary),
      const SizedBox(height: AppSpacing.lg),
      _KidsSection(summary: summary, kids: kidsInGroup),
      const SizedBox(height: AppSpacing.xxxl),
    ];

    return BreakpointBuilder(
      builder: (context, breakpoint) {
        if (breakpoint.index < Breakpoint.expanded.index) {
          return ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            children: [
              identity,
              const SizedBox(height: AppSpacing.lg),
              ...bodySections,
            ],
          );
        }
        // Wide: group detail has a lean header (color dot + count
        // summary) and a heavy right column of actionable sections
        // (warnings, captures, kids roster). 35/65 pushes more space
        // to the list-heavy body.
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 35,
                child: SingleChildScrollView(child: identity),
              ),
              const SizedBox(width: AppSpacing.xl),
              Expanded(
                flex: 65,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: bodySections,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Big color-dot + name header at the top — same visual anchor Today
/// uses for the group so teachers recognize they're on the right page.
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.summary});

  final GroupSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _parseHex(summary.group.colorHex) ??
        theme.colorScheme.primary;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary.name,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${summary.childCount} '
                '${summary.childCount == 1 ? "child" : "children"} · '
                '${summary.anchorLeads.length} '
                '${summary.anchorLeads.length == 1 ? "lead" : "leads"}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color? _parseHex(String? hex) {
    if (hex == null) return null;
    final h = hex.startsWith('#') ? hex.substring(1) : hex;
    if (h.length != 6 && h.length != 8) return null;
    final intVal = int.tryParse(h, radix: 16);
    if (intVal == null) return null;
    return Color(h.length == 6 ? 0xFF000000 | intVal : intVal);
  }
}

/// "Default room" card — shows the current room (if any) with a tap
/// action to change, or an "Assign a room" prompt when unset. Tap
/// opens a bottom sheet of existing rooms.
class _RoomSection extends ConsumerWidget {
  const _RoomSection({required this.summary});

  final GroupSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final room = summary.defaultRoom;
    return _SectionCard(
      title: 'DEFAULT ROOM',
      child: InkWell(
        onTap: () => _pickRoom(context, ref),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              Icon(
                Icons.meeting_room_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  room?.name ?? 'No room set yet',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: room == null
                        ? theme.colorScheme.onSurfaceVariant
                        : null,
                    fontStyle: room == null ? FontStyle.italic : null,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickRoom(BuildContext context, WidgetRef ref) async {
    final roomsAsync = ref.read(roomsProvider);
    final rooms = roomsAsync.asData?.value ?? const <Room>[];
    if (rooms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No rooms yet. Add one on the Rooms screen first.',
          ),
        ),
      );
      return;
    }
    final picked = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (_) => _RoomPickerSheet(
        rooms: rooms,
        currentRoomId: summary.defaultRoom?.id,
      ),
    );
    // Sheet returns:
    //   null        → cancel (no change)
    //   empty str   → explicit "No room" pick
    //   room id     → set that room
    if (picked == null) return;
    final repo = ref.read(roomsRepositoryProvider);

    // Clearing an existing default: point the current room at null.
    if (picked.isEmpty) {
      final current = summary.defaultRoom;
      if (current != null) {
        await repo.updateRoom(
          id: current.id,
          defaultForGroupId: const Value<String?>(null),
        );
      }
      return;
    }

    // Setting a new default. If a different room was previously the
    // default, null its pointer first so we don't end up with two
    // rooms claiming to be "the" default for this group.
    final previous = summary.defaultRoom;
    if (previous != null && previous.id != picked) {
      await repo.updateRoom(
        id: previous.id,
        defaultForGroupId: const Value<String?>(null),
      );
    }
    await repo.updateRoom(
      id: picked,
      defaultForGroupId: Value(summary.id),
    );
  }
}

/// Bottom sheet listing available rooms. Returns the picked room id,
/// the empty string for "no room," or null on cancel.
class _RoomPickerSheet extends StatelessWidget {
  const _RoomPickerSheet({
    required this.rooms,
    required this.currentRoomId,
  });

  final List<Room> rooms;
  final String? currentRoomId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Default room',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('No room'),
              trailing: currentRoomId == null
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.of(context).pop(''),
            ),
            for (final r in rooms)
              ListTile(
                leading: const Icon(Icons.meeting_room_outlined),
                title: Text(r.name),
                trailing: currentRoomId == r.id
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(context).pop(r.id),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Anchor leads" section — shows avatar + name for each lead anchored
/// here, plus a "+ Add lead" button. Tapping an existing lead
/// navigates to the adult detail (via GoRouter); tapping the add
/// button opens a picker sheet of non-anchored adults.
class _LeadsSection extends ConsumerWidget {
  const _LeadsSection({required this.summary});

  final GroupSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return _SectionCard(
      title: 'ANCHOR LEADS',
      actions: [
        TextButton.icon(
          onPressed: () => _addLead(context, ref),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add lead'),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
      child: summary.anchorLeads.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                'No leads yet. Tap "Add lead" to anchor an adult here.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Column(
              children: [
                for (final s in summary.anchorLeads)
                  _LeadTile(
                    adult: s,
                    onTap: () =>
                        context.push('/more/adults/${s.id}'),
                    onRemove: () =>
                        _removeLead(context, ref, s),
                  ),
              ],
            ),
    );
  }

  Future<void> _addLead(BuildContext context, WidgetRef ref) async {
    final adults =
        ref.read(adultsProvider).asData?.value ??
            const <Adult>[];
    // Offer every adult; the row's current-role hint tells the teacher
    // whether picking them would re-anchor them. Skip adults already
    // anchored HERE (no-op pick).
    final candidates = adults
        .where((s) => !(AdultRole.fromDb(s.adultRole) == AdultRole.lead &&
            s.anchoredGroupId == summary.id))
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No adults available. Add one from the Adults screen.',
          ),
        ),
      );
      return;
    }
    final pickedId = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _LeadPickerSheet(candidates: candidates),
    );
    if (pickedId == null) return;
    final s = adults.firstWhere((x) => x.id == pickedId);
    await ref.read(adultsRepositoryProvider).updateAdult(
          id: s.id,
          name: s.name,
          role: s.role,
          notes: s.notes,
          avatarPath: s.avatarPath,
          adultRole: const Value('lead'),
          anchoredGroupId: Value(summary.id),
        );
  }

  Future<void> _removeLead(
    BuildContext context,
    WidgetRef ref,
    Adult s,
  ) async {
    // Remove = clear the anchor. Don't demote role; the teacher may
    // want them to stay a Lead and re-anchor to another group next.
    // Unanchored lead shows as "Lead (no group)" in adult detail.
    await ref.read(adultsRepositoryProvider).updateAdult(
          id: s.id,
          name: s.name,
          role: s.role,
          notes: s.notes,
          avatarPath: s.avatarPath,
          anchoredGroupId: const Value<String?>(null),
        );
  }
}

class _LeadTile extends StatelessWidget {
  const _LeadTile({
    required this.adult,
    required this.onTap,
    required this.onRemove,
  });

  final Adult adult;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            SmallAvatar(
              path: adult.avatarPath,
              fallbackInitial: adult.name.isNotEmpty
                  ? adult.name.characters.first.toUpperCase()
                  : '?',
              radius: 18,
              backgroundColor: theme.colorScheme.secondaryContainer,
              foregroundColor: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    adult.name,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (adult.role != null &&
                      adult.role!.isNotEmpty)
                    Text(
                      adult.role!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove from group',
              icon: const Icon(Icons.link_off, size: 18),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _LeadPickerSheet extends StatelessWidget {
  const _LeadPickerSheet({required this.candidates});

  final List<Adult> candidates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add lead',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Anchors this adult here as a Lead. If they were leading '
              'another group they switch over.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final s in candidates)
                    ListTile(
                      leading: SmallAvatar(
                        path: s.avatarPath,
                        fallbackInitial: s.name.isNotEmpty
                            ? s.name.characters.first.toUpperCase()
                            : '?',
                        radius: 16,
                      ),
                      title: Text(s.name),
                      subtitle: Text(_currentRoleLabel(s)),
                      onTap: () => Navigator.of(context).pop(s.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _currentRoleLabel(Adult s) {
    switch (AdultRole.fromDb(s.adultRole)) {
      case AdultRole.lead:
        return s.anchoredGroupId == null
            ? 'Currently: Lead (no group)'
            : 'Currently: Lead (another group)';
      case AdultRole.specialist:
        return 'Currently: Specialist';
      case AdultRole.ambient:
        return 'Currently: Ambient';
    }
  }
}

/// Kids roster — name + expected arrival/pickup per row. Tap opens
/// the child edit sheet so expected times can be set inline without
/// leaving the group view.
class _KidsSection extends ConsumerWidget {
  const _KidsSection({required this.summary, required this.kids});

  final GroupSummary summary;
  final List<Child> kids;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final groups =
        ref.read(groupsProvider).asData?.value ?? const <Group>[];
    return _SectionCard(
      title: 'KIDS (${kids.length})',
      actions: [
        TextButton.icon(
          onPressed: () => _addKid(context, ref, groups),
          icon: const Icon(Icons.person_add_alt, size: 16),
          label: const Text('Add kid'),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
      child: kids.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                'No kids in this group yet.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Column(
              children: [
                for (final k in kids)
                  _KidTile(
                    kid: k,
                    onTap: () => _openKidEdit(context, k, groups),
                  ),
              ],
            ),
    );
  }

  Future<void> _openKidEdit(
    BuildContext context,
    Child k,
    List<Group> groups,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => EditChildSheet(groups: groups, child: k),
    );
  }

  Future<void> _addKid(
    BuildContext context,
    WidgetRef ref,
    List<Group> groups,
  ) async {
    // "Add kid" from here opens the child create sheet with this
    // group pre-selected, so teachers seeding a group go straight
    // into the right bucket instead of having to remember to pick.
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => EditChildSheet(
        groups: groups,
        initialGroupId: summary.id,
      ),
    );
  }
}

class _KidTile extends StatelessWidget {
  const _KidTile({required this.kid, required this.onTap});

  final Child kid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = _fullName(kid);
    final times = _timesLabel(kid);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            SmallAvatar(
              path: kid.avatarPath,
              fallbackInitial: kid.firstName.isNotEmpty
                  ? kid.firstName.characters.first.toUpperCase()
                  : '?',
              radius: 16,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.titleSmall),
                  if (times != null)
                    Text(
                      times,
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
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  String _fullName(Child k) {
    final last = k.lastName;
    if (last == null || last.trim().isEmpty) return k.firstName;
    return '${k.firstName} ${last.trim()}';
  }

  /// Returns a "Drop-off 8:30 · Pickup 5:00" string, or null when the
  /// child has no expected times — in which case the row stays quiet
  /// instead of rendering a single dash.
  String? _timesLabel(Child k) {
    final arrival = k.expectedArrival;
    final pickup = k.expectedPickup;
    if (arrival == null && pickup == null) return null;
    final parts = <String>[];
    if (arrival != null) parts.add('Drop-off ${_fmt12h(arrival)}');
    if (pickup != null) parts.add('Pickup ${_fmt12h(pickup)}');
    return parts.join(' · ');
  }

  String _fmt12h(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final period = h >= 12 ? 'PM' : 'AM';
    return '$hour12:${m.toString().padLeft(2, '0')} $period';
  }
}

/// Section card — titled chunk on the detail screen. Shared by Room,
/// Leads, and Kids sections so spacing and typography stay consistent
/// without each section reinventing the container.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...actions,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

/// "Visitors today" section — lists adults who are rotating into
/// this group today as adults. Two data sources merge here:
///
///   1. Scheduled activities (weekly templates) where this group is
///      in the activity's group list AND the activity has a
///      adultId set. These are the "Sarah is running Art for
///      Butterflies at 11" scheduled rotations.
///   2. Adult day-timeline blocks marking someone as adult —
///      filtered to blocks whose scheduled activity overlaps this
///      group. Redundant with (1) when the schedule already pins
///      the adult, but covers the "day-timeline says Sarah is
///      the floating rotator 11-12, scheduled activity slot has no
///      adultId yet" case.
///
/// Self-hides when no visitors today. Mostly a list viewer —
/// edits happen on the adult's timeline sheet or in the schedule
/// editor.
class _VisitorsTodaySection extends ConsumerWidget {
  const _VisitorsTodaySection({required this.summary});

  final GroupSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    final dayOfWeek = today.weekday;
    // Weekends read from Monday so an idle weekend glance at a
    // group isn't empty-by-accident.
    final effectiveDay =
        (dayOfWeek >= 1 && dayOfWeek <= 5) ? dayOfWeek : 1;

    // Adults by scheduled activity this group is in.
    final visitors = _resolveVisitors(ref, effectiveDay);
    if (visitors.isEmpty) return const SizedBox.shrink();

    return _SectionCard(
      title: 'VISITING TODAY',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final v in visitors)
            _VisitorRow(visitor: v),
        ],
      ),
    );
  }

  /// Resolves the visitor list by scanning scheduled templates that
  /// both (a) target this group and (b) declare a adult. Sorted
  /// by activity start time so the list reads chronologically.
  List<_VisitorInfo> _resolveVisitors(WidgetRef ref, int dayOfWeek) {
    final adults =
        ref.watch(adultsProvider).asData?.value ??
            const <Adult>[];
    if (adults.isEmpty) return const [];
    final byId = {for (final s in adults) s.id: s};

    // templatesForGroupProvider isn't a thing yet; scan each
    // adult's templates and filter to this group + this day.
    // N is small (program has ~10 adults); even linear is fine.
    final out = <_VisitorInfo>[];
    for (final s in adults) {
      final tplAsync =
          ref.watch(templatesByAdultProvider(s.id));
      final templates = tplAsync.asData?.value ??
          const <ScheduleTemplate>[];
      for (final t in templates) {
        if (t.dayOfWeek != dayOfWeek) continue;
        // Watch the template's group list to know whether this
        // group is a target. A null from the future means "still
        // loading" — skip for now, the row re-renders when it
        // lands.
        final groupsAsync = ref.watch(templateGroupsProvider(t.id));
        final groupIds = groupsAsync.asData?.value;
        if (groupIds == null) continue;
        final targetsThisGroup = groupIds.contains(summary.id) ||
            (groupIds.isEmpty && t.allGroups);
        if (!targetsThisGroup) continue;
        out.add(
          _VisitorInfo(
            adult: byId[s.id]!,
            template: t,
          ),
        );
      }
    }
    out.sort((a, b) => a.template.startTime.compareTo(b.template.startTime));
    return out;
  }
}

/// One visitor row — avatar + name + activity they're running + time.
/// Taps through to that adult's detail screen.
class _VisitorRow extends ConsumerWidget {
  const _VisitorRow({required this.visitor});

  final _VisitorInfo visitor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = visitor.adult;
    final t = visitor.template;
    // Distinguish lead rotators (someone whose day-timeline says
    // they're adult here) from static adults. Useful
    // context: "your lead-now-visiting-us" reads differently than
    // "the house adult."
    final staticRole = AdultRole.fromDb(s.adultRole);
    final tag = switch (staticRole) {
      AdultRole.lead => 'Lead · visiting',
      AdultRole.specialist => 'Specialist',
      AdultRole.ambient => 'Ambient',
    };
    return InkWell(
      onTap: () => context.push('/more/adults/${s.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            SmallAvatar(
              path: s.avatarPath,
              fallbackInitial: s.name.isNotEmpty
                  ? s.name.characters.first.toUpperCase()
                  : '?',
              radius: 18,
              backgroundColor: theme.colorScheme.tertiaryContainer,
              foregroundColor: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name, style: theme.textTheme.titleSmall),
                  Text(
                    '${t.title} · ${_fmt12h(t.startTime)}–${_fmt12h(t.endTime)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    tag,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.75),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  String _fmt12h(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final period = h >= 12 ? 'p' : 'a';
    return '$hour12${m == 0 ? "" : ":${m.toString().padLeft(2, "0")}"}$period';
  }
}

/// Bundle of "which adult + which activity" for the visitors list.
class _VisitorInfo {
  const _VisitorInfo({required this.adult, required this.template});
  final Adult adult;
  final ScheduleTemplate template;
}

/// Data-quality warning: group has kids but nobody is on the clock as
/// lead today. Self-hides on empty groups (nobody to lead yet) and on
/// staffed groups (nothing to warn about). Renders inline above the
/// content sections so a teacher opening the detail sees the problem
/// before scanning the kid list.
class _UnstaffedWarning extends ConsumerWidget {
  const _UnstaffedWarning({required this.summary});

  final GroupSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // An empty group has nothing to be understaffed relative to —
    // bail before we pull the other streams.
    if (summary.childCount == 0) return const SizedBox.shrink();

    final weekday = clampToScheduleDay(DateTime.now().weekday);
    final adults = ref.watch(adultsProvider).asData?.value;
    final blocks = ref.watch(todayAdultBlocksProvider).asData?.value;
    final availability = ref.watch(allAvailabilityProvider).asData?.value;

    // Wait for every upstream before deciding — flashing the warning
    // while data is still streaming in would be worse than silence.
    if (adults == null || blocks == null || availability == null) {
      return const SizedBox.shrink();
    }

    final staffed = isGroupStaffedToday(
      groupId: summary.id,
      weekday: weekday,
      adults: adults,
      todayDayBlocks: blocks,
      availability: availability,
    );
    if (staffed) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final dayName = scheduleDayLabels[weekday - 1];
    final n = summary.childCount;
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
                    Icons.warning_amber_rounded,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'No lead on shift today',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'This group has $n ${n == 1 ? "child" : "children"} '
                'but no adult is scheduled to lead them on $dayName. '
                'Either anchor a lead from the Adults screen, or check '
                'that their availability is set up.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: () => context.push('/more/adults'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.onErrorContainer,
                    side: BorderSide(
                      color: theme.colorScheme.onErrorContainer
                          .withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Text('Assign a lead'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three-button capture card on group detail: observation / incident /
/// concern, pre-linked to this group where it makes sense.
///
///   - Observation → bottom-sheet composer with prefillGroupId. Saves
///     ignore the current-time/last-expanded resolution and pin the
///     observation to THIS group.
///   - Incident → fullscreen form with prefillGroupId so the typed
///     group_id FK on form_submissions is set.
///   - Concern → fullscreen wizard. Concerns are parent-raised about
///     a specific child, not a group — no group-level prefill; the
///     button is here for consistency with the other detail screens.
class _CaptureActionCard extends StatelessWidget {
  const _CaptureActionCard({required this.summary});

  final GroupSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      title: 'CAPTURE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Log something about ${summary.name} — observations and '
            'incidents land here pre-tagged to this group.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openObservation(context),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Observation'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openIncident(context),
                icon: Icon(
                  Icons.report_problem_outlined,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                label: Text(
                  'Incident',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: theme.colorScheme.error.withValues(alpha: 0.4),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _openConcern(context),
                icon: const Icon(Icons.chat_outlined, size: 18),
                label: const Text('Concern'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openObservation(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: ObservationComposer(prefillGroupId: summary.id),
          ),
        );
      },
    );
  }

  Future<void> _openIncident(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => GenericFormScreen(
          definition: incidentForm,
          prefillGroupId: summary.id,
        ),
      ),
    );
  }

  Future<void> _openConcern(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const GenericFormScreen(
          definition: parentConcernForm,
        ),
      ),
    );
  }
}
