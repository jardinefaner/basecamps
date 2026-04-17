import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:basecamp/features/forms/parent_concern/parent_concern_form_screen.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/schedule/widgets/new_activity_wizard.dart';
import 'package:basecamp/features/schedule/widgets/new_full_day_event_wizard.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:basecamp/features/trips/widgets/new_trip_wizard.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Hidden "spotlight" surface reached by swiping right from Today.
/// Search at the top, then: quick actions, kids, specialists, the
/// named sections of the app, and library shortcuts — all filterable
/// live from the search field.
class LauncherScreen extends ConsumerStatefulWidget {
  const LauncherScreen({super.key});

  @override
  ConsumerState<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends ConsumerState<LauncherScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matches(String haystack) {
    if (_query.isEmpty) return true;
    return haystack.toLowerCase().contains(_query.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kidsAsync = ref.watch(kidsProvider);
    final specialistsAsync = ref.watch(specialistsProvider);
    final libraryAsync = ref.watch(activityLibraryProvider);

    final kids = kidsAsync.asData?.value ?? const <Kid>[];
    final specialists =
        specialistsAsync.asData?.value ?? const <Specialist>[];
    final library =
        libraryAsync.asData?.value ?? const <ActivityLibraryData>[];

    final filteredKids = [
      for (final k in kids)
        if (_matches(_displayName(k.firstName, k.lastName))) k,
    ];
    final filteredSpecialists = [
      for (final s in specialists)
        if (_matches(s.name) || _matches(s.role ?? '')) s,
    ];
    final filteredLibrary = [
      for (final l in library)
        if (_matches(l.title)) l,
    ];

    final quickActions = _QuickActionData.all
        .where((q) => _matches(q.label))
        .toList();
    final destinations = _DestinationData.all
        .where((d) => _matches(d.label))
        .toList();

    final hasAnyResults = _query.isEmpty ||
        quickActions.isNotEmpty ||
        destinations.isNotEmpty ||
        filteredKids.isNotEmpty ||
        filteredSpecialists.isNotEmpty ||
        filteredLibrary.isNotEmpty;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: Column(
          children: [
            _SearchField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
            Expanded(
              child: !hasAnyResults
                  ? _NoResults(query: _query)
                  : ListView(
                      padding: const EdgeInsets.only(
                        left: AppSpacing.lg,
                        right: AppSpacing.lg,
                        top: AppSpacing.sm,
                        bottom: AppSpacing.xxxl,
                      ),
                      children: [
                        if (quickActions.isNotEmpty)
                          _Section(
                            label: 'Quick actions',
                            child: _QuickActionsRow(actions: quickActions),
                          ),
                        if (filteredKids.isNotEmpty)
                          _Section(
                            label: 'Children',
                            count: filteredKids.length,
                            total: kids.length,
                            query: _query,
                            child: _PeopleWrap.fromKids(filteredKids),
                          ),
                        if (filteredSpecialists.isNotEmpty)
                          _Section(
                            label: 'Specialists',
                            count: filteredSpecialists.length,
                            total: specialists.length,
                            query: _query,
                            child: _PeopleWrap.fromSpecialists(
                              filteredSpecialists,
                            ),
                          ),
                        if (destinations.isNotEmpty)
                          _Section(
                            label: 'Sections',
                            child: _DestinationsGrid(
                              destinations: destinations,
                            ),
                          ),
                        if (filteredLibrary.isNotEmpty)
                          _Section(
                            label: 'Activity library',
                            count: filteredLibrary.length,
                            total: library.length,
                            query: _query,
                            child: _LibraryWrap(items: filteredLibrary),
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

String _displayName(String first, String? last) {
  if (last == null || last.trim().isEmpty) return first;
  return '$first ${last.trim()[0]}.';
}

// ================================================================
// Search field
// ================================================================

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: [
            Icon(
              Icons.search,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.search,
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'Search children, notes, anywhere…',
                  hintStyle: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: AppSpacing.md),
                ),
                onChanged: onChanged,
              ),
            ),
            if (controller.text.isNotEmpty)
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// Section wrapper
// ================================================================

class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.child,
    this.count,
    this.total,
    this.query = '',
  });

  final String label;
  final Widget child;
  final int? count;
  final int? total;
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suffix = _headerSuffix();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xs,
              bottom: AppSpacing.sm,
            ),
            child: Text(
              '${label.toUpperCase()}$suffix',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }

  String _headerSuffix() {
    if (count == null || total == null) return '';
    if (query.isEmpty || count == total) return ' · $count';
    return ' · $count of $total';
  }
}

// ================================================================
// Quick actions
// ================================================================

class _QuickActionData {
  const _QuickActionData({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Future<void> Function(BuildContext context, WidgetRef ref) onTap;

  static final List<_QuickActionData> all = [
    _QuickActionData(
      label: 'New activity',
      icon: Icons.add,
      onTap: (ctx, _) async {
        await Navigator.of(ctx).push<void>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const NewActivityWizardScreen(),
          ),
        );
      },
    ),
    _QuickActionData(
      label: 'New event',
      icon: Icons.event_outlined,
      onTap: (ctx, _) async {
        await Navigator.of(ctx).push<void>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const NewFullDayEventWizardScreen(),
          ),
        );
      },
    ),
    _QuickActionData(
      label: 'New trip',
      icon: Icons.map_outlined,
      onTap: (ctx, _) async {
        await Navigator.of(ctx).push<void>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const NewTripWizardScreen(),
          ),
        );
      },
    ),
    _QuickActionData(
      label: 'New note',
      icon: Icons.chat_outlined,
      onTap: (ctx, _) async {
        await Navigator.of(ctx).push<void>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const ParentConcernFormScreen(
              presentation: ConcernFormPresentation.wizard,
            ),
          ),
        );
      },
    ),
    _QuickActionData(
      label: 'Observe',
      icon: Icons.visibility_outlined,
      onTap: (ctx, _) async {
        ctx.go('/observations');
      },
    ),
  ];
}

class _QuickActionsRow extends ConsumerWidget {
  const _QuickActionsRow({required this.actions});

  final List<_QuickActionData> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final a in actions)
          _QuickActionTile(action: a, ref: ref),
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({required this.action, required this.ref});

  final _QuickActionData action;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 88,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => action.onTap(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(
                  action.icon,
                  size: 24,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                action.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================
// People (kids + specialists)
// ================================================================

class _PeopleWrap extends StatelessWidget {
  const _PeopleWrap({required this.cells});

  factory _PeopleWrap.fromKids(List<Kid> kids) {
    return _PeopleWrap(
      cells: [
        for (final k in kids)
          _PersonCell(
            name: _displayName(k.firstName, k.lastName),
            avatarPath: k.avatarPath,
            fallbackInitial: k.firstName.isEmpty
                ? '?'
                : k.firstName.characters.first.toUpperCase(),
            route: '/kids/${k.id}',
          ),
      ],
    );
  }

  factory _PeopleWrap.fromSpecialists(List<Specialist> specialists) {
    return _PeopleWrap(
      cells: [
        for (final s in specialists)
          _PersonCell(
            name: s.name,
            avatarPath: s.avatarPath,
            fallbackInitial: s.name.isEmpty
                ? '?'
                : s.name.characters.first.toUpperCase(),
            route: '/more/specialists/${s.id}',
          ),
      ],
    );
  }

  final List<_PersonCell> cells;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: cells,
    );
  }
}

class _PersonCell extends StatelessWidget {
  const _PersonCell({
    required this.name,
    required this.fallbackInitial,
    required this.route,
    this.avatarPath,
  });

  final String name;
  final String? avatarPath;
  final String fallbackInitial;
  final String route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 68,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(route),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              SmallAvatar(
                path: avatarPath,
                fallbackInitial: fallbackInitial,
                radius: 26,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================
// Destinations — main tabs + sub-surfaces
// ================================================================

class _DestinationData {
  const _DestinationData({
    required this.label,
    required this.icon,
    required this.path,
    this.isMainTab = false,
  });

  final String label;
  final IconData icon;
  final String path;
  final bool isMainTab;

  static const List<_DestinationData> all = [
    _DestinationData(
      label: 'Today',
      icon: Icons.today_outlined,
      path: '/today',
      isMainTab: true,
    ),
    _DestinationData(
      label: 'Observe',
      icon: Icons.visibility_outlined,
      path: '/observations',
      isMainTab: true,
    ),
    _DestinationData(
      label: 'Children',
      icon: Icons.people_outline,
      path: '/kids',
      isMainTab: true,
    ),
    _DestinationData(
      label: 'Trips',
      icon: Icons.map_outlined,
      path: '/trips',
      isMainTab: true,
    ),
    _DestinationData(
      label: 'More',
      icon: Icons.more_horiz,
      path: '/more',
      isMainTab: true,
    ),
    _DestinationData(
      label: 'Schedule',
      icon: Icons.calendar_month_outlined,
      path: '/today/schedule',
    ),
    _DestinationData(
      label: 'Forms',
      icon: Icons.assignment_outlined,
      path: '/more/forms',
    ),
    _DestinationData(
      label: 'Specialists',
      icon: Icons.badge_outlined,
      path: '/more/specialists',
    ),
    _DestinationData(
      label: 'Library',
      icon: Icons.bookmarks_outlined,
      path: '/more/library',
    ),
  ];
}

class _DestinationsGrid extends StatelessWidget {
  const _DestinationsGrid({required this.destinations});

  final List<_DestinationData> destinations;

  @override
  Widget build(BuildContext context) {
    // Fixed 3-col grid — reflows across phones without any
    // max-width gymnastics. Every tile lays out at the same height so
    // the grid reads as a clean strip.
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
        childAspectRatio: 1.15,
      ),
      itemCount: destinations.length,
      itemBuilder: (_, i) => _DestinationTile(destination: destinations[i]),
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({required this.destination});

  final _DestinationData destination;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          // Main tabs jump via `go` so the shell swaps branches; deep
          // sub-routes push on top of the current branch.
          if (destination.isMainTab) {
            context.go(destination.path);
          } else {
            unawaited(context.push(destination.path));
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                destination.icon,
                size: 28,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                destination.label,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================
// Library pills
// ================================================================

class _LibraryWrap extends StatelessWidget {
  const _LibraryWrap({required this.items});

  final List<ActivityLibraryData> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final item in items) _LibraryPill(item: item),
      ],
    );
  }
}

class _LibraryPill extends StatelessWidget {
  const _LibraryPill({required this.item});

  final ActivityLibraryData item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => context.push('/more/library'),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_outlined,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              item.title,
              style: theme.textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// Empty state
// ================================================================

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Nothing matches "$query"',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Try a different name, or tap a quick action to add something new.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
