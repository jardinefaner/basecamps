import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/children/child_recap_share.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/children/widgets/edit_child_sheet.dart';
import 'package:basecamp/features/forms/polymorphic/definitions/incident.dart';
import 'package:basecamp/features/forms/polymorphic/definitions/parent_concern.dart';
import 'package:basecamp/features/forms/polymorphic/generic_form_screen.dart';
import 'package:basecamp/features/observations/widgets/observation_composer.dart';
import 'package:basecamp/features/parents/parents_repository.dart';
import 'package:basecamp/features/parents/widgets/edit_parent_sheet.dart';
import 'package:basecamp/features/people/people_display.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/widgets/activity_detail_sheet.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:basecamp/ui/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class ChildDetailScreen extends ConsumerWidget {
  const ChildDetailScreen({required this.childId, super.key});

  final String childId;

  Future<void> _openEditSheet(
    BuildContext context,
    WidgetRef ref,
    Child child,
  ) async {
    final groups = await ref.read(childrenRepositoryProvider).watchGroups().first;
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => EditChildSheet(groups: groups, child: child),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kidAsync = ref.watch(childProvider(childId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        actions: [
          kidAsync.maybeWhen(
            data: (child) => child == null
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: "Share today's recap",
                    icon: const Icon(Icons.ios_share),
                    onPressed: () =>
                        showChildRecapShareSheet(context, child),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
          kidAsync.maybeWhen(
            data: (child) => child == null
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Edit child',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _openEditSheet(context, ref, child),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: kidAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (child) {
          if (child == null) {
            return const Center(child: Text('Child not found'));
          }
          final fullName = child.fullName;
          final initial = child.displayInitial;

          // Header — avatar + name + group label. Becomes the left
          // column on wide; leads the stack otherwise.
          final header = InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openEditSheet(context, ref, child),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Row(
                children: [
                  SmallAvatar(
                    path: child.avatarPath,
                    storagePath: child.avatarStoragePath,
                    etag: child.avatarEtag,
                    fallbackInitial: initial,
                    radius: 32,
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName,
                          style: theme.textTheme.headlineMedium,
                        ),
                        if (child.groupId != null)
                          _GroupLabel(groupId: child.groupId!)
                        else
                          Text(
                            'Unassigned',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color:
                                  theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );

          // Body sections — today, parents, capture, and the
          // coming-soon cards. Scrolls on the right column when wide,
          // vertical continuation on narrow.
          final bodySections = <Widget>[
            _TodayTimeline(child: child),
            const SizedBox(height: AppSpacing.md),
            _ParentsSection(child: child),
            const SizedBox(height: AppSpacing.md),
            _CaptureActionCard(child: child),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Observations', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Coming soon — structured observations tied to this child.',
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
                    'Coming soon — everything tagged with this child from the Today feed.',
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
                    "Coming soon — send this child's recap to parents via email, SMS, or a read-only link.",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ];

          return BreakpointBuilder(
            builder: (context, breakpoint) {
              if (breakpoint.index < Breakpoint.expanded.index) {
                return ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    header,
                    const SizedBox(height: AppSpacing.xl),
                    ...bodySections,
                  ],
                );
              }
              // Wide: child has rich right-column sections (today
              // timeline + parents + capture actions + three
              // coming-soon cards). 35/65 lets all of that breathe
              // while still keeping the identity card visible.
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 35,
                      child: SingleChildScrollView(child: header),
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
        },
      ),
    );
  }
}

class _GroupLabel extends ConsumerWidget {
  const _GroupLabel({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final group = ref.watch(groupProvider(groupId));
    return group.maybeWhen(
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

/// Today's filtered schedule for this specific child: items where their group
/// is in the activity's targeted groups (or where the activity is "all groups").
class _TodayTimeline extends ConsumerWidget {
  const _TodayTimeline({required this.child});

  final Child child;

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
                if (i.isAllGroups) return true;
                return child.groupId != null && i.groupIds.contains(child.groupId);
              }).toList();

              if (mine.isEmpty) {
                return Text(
                  'Nothing scheduled for this child today.',
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
    final adultId = item.adultId;
    final adult = adultId == null
        ? null
        : ref.watch(adultProvider(adultId)).asData?.value;
    final subtitleParts = <String>[];
    if (adult != null) subtitleParts.add(adult.name);
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

/// Parents / guardians linked to this child. When empty, shows a
/// prompt to add the first one; otherwise a compact list with the
/// relationship chip and a star for the primary pickup contact.
/// "Add parent" pops a picker that offers existing parents plus an
/// "Add new parent" tile that chains into the create sheet and
/// auto-links on create.
class _ParentsSection extends ConsumerWidget {
  const _ParentsSection({required this.child});

  final Child child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final linksAsync = ref.watch(parentsForChildProvider(child.id));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Parents & guardians',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: () => _openAddPicker(context, ref),
                icon: const Icon(Icons.person_add_alt_outlined, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          linksAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: LinearProgressIndicator(),
            ),
            error: (err, _) => Text('Error: $err'),
            data: (links) {
              if (links.isEmpty) {
                // Back-compat: if the legacy parentName field is set,
                // show it as faded context — that way programs that
                // haven't promoted to linked Parent rows still see the
                // info they put in. The "Add" button promotes to the
                // new entity.
                final legacy = child.parentName;
                if (legacy != null && legacy.trim().isNotEmpty) {
                  return Padding(
                    padding:
                        const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      '$legacy (from old text field — tap Add to '
                      'promote to a linked parent row)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'No parents linked yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final link in links)
                    _LinkRow(child: child, link: link),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Split a legacy free-text `parentName` like "Sarah Reed" into
  /// (first, last). No last name → last is null. Multi-word last
  /// names collapse into one (the split-on-first-space is a
  /// reasonable MVP; the teacher can correct before saving if the
  /// guess was off).
  (String?, String?) _splitLegacyName(String? raw) {
    if (raw == null) return (null, null);
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return (null, null);
    final idx = trimmed.indexOf(' ');
    if (idx < 0) return (trimmed, null);
    return (
      trimmed.substring(0, idx),
      trimmed.substring(idx + 1).trim(),
    );
  }

  Future<void> _openAddPicker(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final all = await ref.read(parentsRepositoryProvider).getAll();
    final existingLinks =
        await ref.read(parentsForChildProvider(child.id).future);
    final linkedIds = {for (final l in existingLinks) l.parent.id};
    if (!context.mounted) return;
    final result = await showModalBottomSheet<_ParentPickResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ParentPickerSheet(
        all: all,
        linkedIds: linkedIds,
      ),
    );
    if (result == null) return;
    final repo = ref.read(parentsRepositoryProvider);
    if (result.addNew) {
      if (!context.mounted) return;
      // Promote legacy parent_name into the first/last fields when
      // this is the child's first linked parent and the old free-
      // text is set. Teacher doesn't have to retype the name; they
      // just add relationship / phone / email and save.
      final (pf, pl) = existingLinks.isEmpty
          ? _splitLegacyName(child.parentName)
          : (null, null);
      final newId = await showModalBottomSheet<String?>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => EditParentSheet(
          prefillFirstName: pf,
          prefillLastName: pl,
        ),
      );
      if (newId == null) return;
      await repo.linkParentToChild(
        parentId: newId,
        childId: child.id,
        isPrimary: existingLinks.isEmpty,
      );
    } else if (result.parentId != null) {
      await repo.linkParentToChild(
        parentId: result.parentId!,
        childId: child.id,
        isPrimary: existingLinks.isEmpty,
      );
    }
  }
}

/// One linked parent row on the child detail screen. Tap-through to
/// parent detail; long-press to unlink; star toggle for primary
/// pickup contact. Relationship and phone chip subtitle so the row
/// reads informative at a glance.
class _LinkRow extends ConsumerWidget {
  const _LinkRow({required this.child, required this.link});

  final Child child;
  final ParentLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = link.parent;
    final name = _formatName(p);
    final phone = p.phone?.trim();
    final email = p.email?.trim();
    final hasPhone = phone != null && phone.isNotEmpty;
    final hasEmail = email != null && email.isNotEmpty;
    return InkWell(
      onTap: () => context.push('/more/parents/${p.id}'),
      onLongPress: () => _confirmUnlink(context, ref, p),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            IconButton(
              tooltip: link.isPrimary
                  ? 'Primary pickup contact'
                  : 'Make primary pickup contact',
              icon: Icon(
                link.isPrimary ? Icons.star : Icons.star_border,
                color: link.isPrimary
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              onPressed: link.isPrimary
                  ? null
                  : () => ref.read(parentsRepositoryProvider).setPrimary(
                        parentId: p.id,
                        childId: child.id,
                      ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.titleSmall),
                  if (p.relationship != null && p.relationship!.isNotEmpty)
                    Text(
                      p.relationship!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  // Phone + email as their own tappable chips so a
                  // single tap dials or composes without leaving the
                  // child screen. Sits inside the same InkWell that
                  // otherwise pushes the parent detail — GestureDetector
                  // in a child widget wins the hit test, so the row-
                  // level InkWell still fires everywhere else.
                  if (hasPhone)
                    _ContactLine(
                      icon: Icons.phone_outlined,
                      text: phone,
                      onTap: () => _launchContact(
                        context,
                        Uri(scheme: 'tel', path: phone),
                        fallbackLabel: 'Phone',
                      ),
                    ),
                  if (hasEmail)
                    _ContactLine(
                      icon: Icons.mail_outline,
                      text: email,
                      onTap: () => _launchContact(
                        context,
                        Uri(scheme: 'mailto', path: email),
                        fallbackLabel: 'Email',
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
    );
  }

  /// Launch a `tel:` / `mailto:` uri via url_launcher. On devices
  /// without a handler (simulator, stripped-down OS image) we show a
  /// snackbar instead of failing silently.
  Future<void> _launchContact(
    BuildContext context,
    Uri uri, {
    required String fallbackLabel,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await launchUrl(uri);
      if (!ok && context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              "Couldn't open $fallbackLabel — no app registered for "
              '${uri.scheme}: links.',
            ),
          ),
        );
      }
    } on Object catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't open $fallbackLabel: $e")),
      );
    }
  }

  Future<void> _confirmUnlink(
    BuildContext context,
    WidgetRef ref,
    Parent p,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Unlink ${_formatName(p)}?'),
        content: Text(
          "They'll stay in Parents & guardians, just unlinked from "
          '${child.firstName}. You can re-link anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(parentsRepositoryProvider).unlinkParentFromChild(
          parentId: p.id,
          childId: child.id,
        );
  }

  String _formatName(Parent p) {
    final last = p.lastName;
    return last == null || last.isEmpty
        ? p.firstName
        : '${p.firstName} $last';
  }
}

/// Outcome of the "Add parent" picker. Either an existing parent
/// picked by id, or a request to jump into the add-new-parent sheet.
class _ParentPickResult {
  const _ParentPickResult({this.parentId, this.addNew = false});
  final String? parentId;
  final bool addNew;
}

/// Modal list of every program parent, with an "Add new parent"
/// tile. Parents already linked to this child are disabled so the
/// teacher can see who's already on the list without the option to
/// double-link.
class _ParentPickerSheet extends StatelessWidget {
  const _ParentPickerSheet({
    required this.all,
    required this.linkedIds,
  });

  final List<Parent> all;
  final Set<String> linkedIds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.md,
                top: AppSpacing.xs,
                bottom: AppSpacing.md,
              ),
              child: Text(
                'Link a parent',
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (all.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'No parents in the program yet. Add one below.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final p in all)
              ListTile(
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      theme.colorScheme.secondaryContainer,
                  foregroundColor:
                      theme.colorScheme.onSecondaryContainer,
                  child: Text(p.displayInitial),
                ),
                title: Text(p.fullName),
                subtitle: p.relationship == null ||
                        p.relationship!.isEmpty
                    ? null
                    : Text(p.relationship!),
                enabled: !linkedIds.contains(p.id),
                trailing: linkedIds.contains(p.id)
                    ? Text(
                        'Linked',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : null,
                onTap: () => Navigator.of(context).pop(
                  _ParentPickResult(parentId: p.id),
                ),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add new parent…'),
              onTap: () => Navigator.of(context).pop(
                const _ParentPickResult(addNew: true),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

/// Tappable "icon · text" line used under a parent name to surface
/// phone + email as one-tap launchers. Rendered inside an InkWell so
/// the whole strip shows a ripple on press; the parent row's own
/// InkWell still handles taps on the non-contact area.
class _ContactLine extends StatelessWidget {
  const _ContactLine({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: theme.colorScheme.primary
                      .withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three-button capture card on child detail: observation / incident /
/// concern, each pre-linked to this child. Saves here mean the teacher
/// never has to search for the child in the target form.
///
///   - Observation → bottom-sheet composer with prefillChildIds so
///     the saved row auto-links via observation_children.
///   - Incident → fullscreen form with prefillChildId so the typed
///     child_id FK on form_submissions is set.
///   - Concern → fullscreen wizard with initialChildIds so the child
///     picker is pre-seeded (and the parent auto-fills).
class _CaptureActionCard extends StatelessWidget {
  const _CaptureActionCard({required this.child});

  final Child child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Capture', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Log something about ${child.firstName} from right here — '
            'all pre-linked to this child.',
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
            body: ObservationComposer(prefillChildIds: [child.id]),
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
          prefillChildId: child.id,
        ),
      ),
    );
  }

  Future<void> _openConcern(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => GenericFormScreen(
          definition: parentConcernForm,
          // Multi-child picker isn't covered by `prefillChildId`
          // (that path only seeds single-pick fields). Seed the
          // structured `child_ids` slot directly so the wizard lands
          // on step 1 with this child already chipped.
          prefillData: {
            'child_ids': [child.id],
          },
        ),
      ),
    );
  }
}
