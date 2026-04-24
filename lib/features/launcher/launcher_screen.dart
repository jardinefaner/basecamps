import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/forms/parent_concern/parent_concern_form_screen.dart';
import 'package:basecamp/features/launcher/pinned_actions_repository.dart';
import 'package:basecamp/features/parents/parents_repository.dart';
import 'package:basecamp/features/schedule/widgets/new_activity_wizard.dart';
import 'package:basecamp/features/schedule/widgets/new_full_day_event_wizard.dart';
import 'package:basecamp/features/trips/widgets/new_trip_wizard.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Drawer content for Today. Search at the top, then: quick actions,
/// children, adults, the named sections of the app, and library
/// shortcuts — all filterable live from the search field.
///
/// Renders as a Drawer body (no outer Scaffold). Every navigation tap
/// closes the drawer first via [Navigator.pop] on this context, then
/// pushes the pushed route onto the root navigator — so tapping a
/// destination lands the teacher on the new screen with Today in the
/// back-stack.
///
/// A helper [_navigateTo] funnels every tap path through the same
/// close-then-route sequence; use it anywhere inside this file.
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
    final kidsAsync = ref.watch(childrenProvider);
    final adultsAsync = ref.watch(adultsProvider);
    final parentsAsync = ref.watch(parentsProvider);
    final libraryAsync = ref.watch(activityLibraryProvider);

    final children = kidsAsync.asData?.value ?? const <Child>[];
    final adults =
        adultsAsync.asData?.value ?? const <Adult>[];
    final parents =
        parentsAsync.asData?.value ?? const <Parent>[];
    final library =
        libraryAsync.asData?.value ?? const <ActivityLibraryData>[];

    final filteredKids = [
      for (final k in children)
        if (_matches(_displayName(k.firstName, k.lastName))) k,
    ];
    final filteredAdults = [
      for (final s in adults)
        if (_matches(s.name) || _matches(s.role ?? '')) s,
    ];
    final filteredParents = [
      for (final p in parents)
        if (_matches(_parentDisplayName(p)) ||
            _matches(p.relationship ?? ''))
          p,
    ];
    final filteredLibrary = [
      for (final l in library)
        if (_matches(l.title)) l,
    ];

    final pinnedIds = ref.watch(pinnedItemsProvider);
    // Resolve each pinned id to a live tile. Async entries (child,
    // adult, library) look up their current display name from
    // the providers already watched above; an id that no longer
    // resolves (e.g. child was deleted) is skipped silently.
    Widget? resolvePinnedTile(String storedId) {
      final parsed = parsePinId(storedId);
      if (parsed == null) return null;
      switch (parsed.kind) {
        case PinnedKinds.action:
          final a = _QuickActionData.byId(parsed.id);
          if (a == null || !_matches(a.label)) return null;
          return _PinnableTile(
            pinId: storedId,
            child: _QuickActionTile(action: a, ref: ref),
          );
        case PinnedKinds.destination:
          final d = _DestinationData.all
              .where((x) => x.path == parsed.id)
              .firstOrNull;
          if (d == null || !_matches(d.label)) return null;
          return _PinnableTile(
            pinId: storedId,
            child: _DestinationTile(destination: d),
          );
        case PinnedKinds.child:
          final k = children.where((x) => x.id == parsed.id).firstOrNull;
          if (k == null ||
              !_matches(_displayName(k.firstName, k.lastName))) {
            return null;
          }
          return _PinnableTile(
            pinId: storedId,
            child: _PersonCell(
              name: _displayName(k.firstName, k.lastName),
              avatarPath: k.avatarPath,
              fallbackInitial: k.firstName.isEmpty
                  ? '?'
                  : k.firstName.characters.first.toUpperCase(),
              route: '/children/${k.id}',
            ),
          );
        case PinnedKinds.adult:
          final s =
              adults.where((x) => x.id == parsed.id).firstOrNull;
          if (s == null ||
              !(_matches(s.name) || _matches(s.role ?? ''))) {
            return null;
          }
          return _PinnableTile(
            pinId: storedId,
            child: _PersonCell(
              name: s.name,
              avatarPath: s.avatarPath,
              fallbackInitial: s.name.isEmpty
                  ? '?'
                  : s.name.characters.first.toUpperCase(),
              route: '/more/adults/${s.id}',
            ),
          );
        case PinnedKinds.library:
          final l = library.where((x) => x.id == parsed.id).firstOrNull;
          if (l == null || !_matches(l.title)) return null;
          return _PinnableTile(
            pinId: storedId,
            child: _LibraryPill(item: l),
          );
      }
      return null;
    }

    final pinnedTiles = <Widget>[
      for (final id in pinnedIds) ?resolvePinnedTile(id),
    ];

    // Each source section only shows items not already pinned — so
    // items appear in exactly one place at a time (same semantics as
    // the children tab's group reassignment).
    final unpinnedActions = _QuickActionData.all
        .where((a) =>
            !pinnedIds.contains(pinId(PinnedKinds.action, a.id)))
        .where((a) => _matches(a.label))
        .toList();
    final unpinnedKids = filteredKids
        .where((k) =>
            !pinnedIds.contains(pinId(PinnedKinds.child, k.id)))
        .toList();
    final unpinnedAdults = filteredAdults
        .where((s) =>
            !pinnedIds.contains(pinId(PinnedKinds.adult, s.id)))
        .toList();
    final unpinnedLibrary = filteredLibrary
        .where((l) =>
            !pinnedIds.contains(pinId(PinnedKinds.library, l.id)))
        .toList();
    // Parents aren't pinnable yet — dedicated PinnedKind + repository
    // migration would be the next step. For now the whole filtered
    // list shows in its section.
    final unpinnedParents = filteredParents;
    final destinations = _DestinationData.all
        .where((d) =>
            !pinnedIds.contains(pinId(PinnedKinds.destination, d.path)))
        .where((d) => _matches(d.label))
        .toList();

    final hasAnyResults = _query.isEmpty ||
        pinnedTiles.isNotEmpty ||
        unpinnedActions.isNotEmpty ||
        destinations.isNotEmpty ||
        unpinnedKids.isNotEmpty ||
        unpinnedAdults.isNotEmpty ||
        unpinnedParents.isNotEmpty ||
        unpinnedLibrary.isNotEmpty;

    // No outer Scaffold — LauncherScreen is rendered inside a Drawer
    // which supplies its own Material surface. A ColoredBox matches the
    // pre-drawer look (surfaceContainerLowest background) and costs
    // nothing when the Drawer already draws over it.
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLowest,
      child: SafeArea(
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
                        // Smart Shelf — always visible. Accepts drops
                        // of any pinnable tile (action, destination,
                        // child, adult, library item). Tiles
                        // already pinned appear here and disappear
                        // from their source section.
                        _Section(
                          label: 'Pinned',
                          child: _SmartShelf(
                            tiles: pinnedTiles,
                            isFiltered: _query.isNotEmpty,
                          ),
                        ),
                        if (unpinnedActions.isNotEmpty)
                          _Section(
                            label: 'Quick actions',
                            child: _QuickActionsRow(
                              actions: unpinnedActions,
                            ),
                          ),
                        // Sections (destinations grid) moves ABOVE the
                        // people grids so navigation lives at the top
                        // and the long scrollable people lists don't
                        // push it off-screen.
                        if (destinations.isNotEmpty)
                          _Section(
                            label: 'Sections',
                            child: _DestinationsGrid(
                              destinations: destinations,
                            ),
                          ),
                        if (unpinnedKids.isNotEmpty)
                          _Section(
                            label: 'Children',
                            count: unpinnedKids.length,
                            total: children.length,
                            query: _query,
                            child: _PeopleWrap.fromKids(unpinnedKids),
                          ),
                        if (unpinnedAdults.isNotEmpty)
                          _Section(
                            label: 'Adults',
                            count: unpinnedAdults.length,
                            total: adults.length,
                            query: _query,
                            child: _PeopleWrap.fromAdults(
                              unpinnedAdults,
                            ),
                          ),
                        if (unpinnedParents.isNotEmpty)
                          _Section(
                            label: 'Parents',
                            count: unpinnedParents.length,
                            total: parents.length,
                            query: _query,
                            child: _PeopleWrap.fromParents(
                              unpinnedParents,
                            ),
                          ),
                        if (unpinnedLibrary.isNotEmpty)
                          _Section(
                            label: 'Activity library',
                            count: unpinnedLibrary.length,
                            total: library.length,
                            query: _query,
                            child: _LibraryWrap(items: unpinnedLibrary),
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

/// Launcher's display name for a parent — firstName + last-initial.
/// Matches the Child / Adult conventions so the three people grids
/// read the same at a glance.
String _parentDisplayName(Parent p) =>
    _displayName(p.firstName, p.lastName);

/// Route without closing the drawer. The pushed screen covers Today
/// (and the drawer visually), but the Scaffold preserves the drawer's
/// open state — pressing back pops the pushed screen and the drawer
/// is still there. Teachers jumping between setup screens don't have
/// to re-open the drawer after every trip.
///
/// Default is `push` (stacks onto Today); pass `go: true` for
/// horizontal moves that should clear any lower stack (rarely needed
/// now that /today is the only root).
void _navigateTo(BuildContext context, String path, {bool go = false}) {
  if (go) {
    context.go(path);
  } else {
    unawaited(context.push(path));
  }
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
    required this.id,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  /// Stable identifier — persisted in SharedPreferences via the
  /// pinned-actions repository. Changing an id is equivalent to
  /// removing it from everyone's pinned list, so keep these stable.
  final String id;
  final String label;
  final IconData icon;
  final Future<void> Function(BuildContext context, WidgetRef ref) onTap;

  static final List<_QuickActionData> all = [
    _QuickActionData(
      id: 'new-activity',
      label: 'New activity',
      icon: Icons.add,
      onTap: (ctx, _) async {
        // Push on the root navigator so the wizard sits above the
        // drawer. Drawer stays open in Scaffold state; when the
        // wizard pops, the drawer is still there.
        await Navigator.of(ctx, rootNavigator: true).push<void>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const NewActivityWizardScreen(),
          ),
        );
      },
    ),
    _QuickActionData(
      id: 'new-event',
      label: 'New event',
      icon: Icons.event_outlined,
      onTap: (ctx, _) async {
        await Navigator.of(ctx, rootNavigator: true).push<void>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const NewFullDayEventWizardScreen(),
          ),
        );
      },
    ),
    _QuickActionData(
      id: 'new-trip',
      label: 'New trip',
      icon: Icons.map_outlined,
      onTap: (ctx, _) async {
        await Navigator.of(ctx, rootNavigator: true).push<void>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const NewTripWizardScreen(),
          ),
        );
      },
    ),
    _QuickActionData(
      id: 'new-note',
      label: 'New note',
      icon: Icons.chat_outlined,
      onTap: (ctx, _) async {
        await Navigator.of(ctx, rootNavigator: true).push<void>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const ParentConcernFormScreen(
              presentation: ConcernFormPresentation.wizard,
            ),
          ),
        );
      },
    ),
    // (Dropped the 'observe' quick action — same icon, same label,
    // same target as the Observe Sections tile. Pinning now goes
    // through the Sections tile.)
  ];

  static _QuickActionData? byId(String id) {
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }
}

/// Smart Shelf — DragTarget that accepts every pinnable tile id and
/// pins anything not already pinned. Dropping an already-pinned tile
/// back on the shelf is a no-op (treated as "cancel"), which leaves
/// `Draggable.onDragEnd` with wasAccepted=true so the unpin-on-cancel
/// path in [_PinnableTile] doesn't misfire. Always visible;
/// placeholder copy when empty so the drop zone is discoverable.
class _SmartShelf extends ConsumerWidget {
  const _SmartShelf({
    required this.tiles,
    required this.isFiltered,
  });

  final List<Widget> tiles;

  /// True when a search query is active — changes the empty-state copy
  /// so "no pinned matches" doesn't get confused with "no pins yet".
  final bool isFiltered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) {
        final pinned = ref.read(pinnedItemsProvider);
        if (!pinned.contains(d.data)) {
          unawaited(
            ref.read(pinnedItemsProvider.notifier).pin(d.data),
          );
        }
        // Already pinned → dropping back is a "cancel, leave it alone".
      },
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: hovering
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hovering
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: hovering ? 1.5 : 1,
            ),
          ),
          child: tiles.isEmpty
              ? _ShelfEmpty(hovering: hovering, isFiltered: isFiltered)
              : Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: tiles,
                ),
        );
      },
    );
  }
}

class _ShelfEmpty extends StatelessWidget {
  const _ShelfEmpty({required this.hovering, required this.isFiltered});

  final bool hovering;
  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(
          hovering
              ? 'Drop here to pin'
              : isFiltered
                  ? 'No pinned items match this search.'
                  : 'Long-press any tile below and drag here to pin.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: hovering
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: hovering ? FontWeight.w700 : null,
          ),
        ),
      ),
    );
  }
}

/// Wraps any launcher tile in a long-press-draggable. [pinId] is the
/// stored-format identifier with kind prefix (e.g. `action:new-activity`,
/// `child:abc123`). Drop on the Smart Shelf to pin; drop anywhere
/// else (into the list body, off the edge, on empty space) to unpin.
/// Dropping a pinned tile back on the shelf is a no-op — the shelf
/// treats that as "cancel".
///
/// Simpler rule than per-section unpin targets: "on shelf = pin, off
/// shelf = unpin" removes silent failures when a teacher released
/// over the wrong section.
class _PinnableTile extends ConsumerWidget {
  const _PinnableTile({required this.pinId, required this.child});

  final String pinId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LongPressDraggable<String>(
      data: pinId,
      feedback: Material(
        color: Colors.transparent,
        child: Transform.scale(
          scale: 1.06,
          child: Opacity(opacity: 0.94, child: child),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      onDragEnd: (details) {
        // Accepted drops always land on the shelf (only DragTarget in
        // play). When not accepted, the teacher released over the
        // list body, so interpret that as "unpin" — but only if the
        // tile is actually pinned right now. Dragging an unpinned
        // tile off into empty space is a no-op.
        if (details.wasAccepted) return;
        if (ref.read(pinnedItemsProvider).contains(pinId)) {
          unawaited(
            ref.read(pinnedItemsProvider.notifier).unpin(pinId),
          );
        }
      },
      child: child,
    );
  }
}

/// Renders the unpinned quick actions. Each tile is individually
/// draggable so teachers can pin them onto the Smart Shelf.
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
          _PinnableTile(
            pinId: pinId(PinnedKinds.action, a.id),
            child: _QuickActionTile(action: a, ref: ref),
          ),
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
// People (children + adults)
// ================================================================

class _PeopleWrap extends StatelessWidget {
  const _PeopleWrap({required this.tiles});

  factory _PeopleWrap.fromKids(List<Child> children) {
    return _PeopleWrap(
      tiles: [
        for (final k in children)
          _PinnableTile(
            pinId: pinId(PinnedKinds.child, k.id),
            child: _PersonCell(
              name: _displayName(k.firstName, k.lastName),
              avatarPath: k.avatarPath,
              fallbackInitial: k.firstName.isEmpty
                  ? '?'
                  : k.firstName.characters.first.toUpperCase(),
              route: '/children/${k.id}',
            ),
          ),
      ],
    );
  }

  factory _PeopleWrap.fromAdults(List<Adult> adults) {
    return _PeopleWrap(
      tiles: [
        for (final s in adults)
          _PinnableTile(
            pinId: pinId(PinnedKinds.adult, s.id),
            child: _PersonCell(
              name: s.name,
              avatarPath: s.avatarPath,
              fallbackInitial: s.name.isEmpty
                  ? '?'
                  : s.name.characters.first.toUpperCase(),
              route: '/more/adults/${s.id}',
            ),
          ),
      ],
    );
  }

  /// Parents aren't pinnable yet (no PinnedKinds.parent), so the
  /// tiles are plain cells without the `_PinnableTile` wrap. Adding
  /// pin support is a small follow-up if teachers ask for it.
  factory _PeopleWrap.fromParents(List<Parent> parents) {
    return _PeopleWrap(
      tiles: [
        for (final p in parents)
          _PersonCell(
            name: _parentDisplayName(p),
            fallbackInitial: p.firstName.isEmpty
                ? '?'
                : p.firstName.characters.first.toUpperCase(),
            route: '/more/parents/${p.id}',
          ),
      ],
    );
  }

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: tiles,
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
        onTap: () => _navigateTo(context, route),
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
  });

  final String label;
  final IconData icon;
  final String path;

  static const List<_DestinationData> all = [
    _DestinationData(
      label: 'Observe',
      icon: Icons.visibility_outlined,
      path: '/observations',
    ),
    _DestinationData(
      label: 'Children & groups',
      icon: Icons.people_outline,
      path: '/children',
    ),
    _DestinationData(
      label: 'Trips',
      icon: Icons.map_outlined,
      path: '/trips',
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
      label: 'Adults',
      icon: Icons.badge_outlined,
      path: '/more/adults',
    ),
    _DestinationData(
      label: 'Activity library',
      icon: Icons.bookmarks_outlined,
      path: '/more/library',
    ),
    _DestinationData(
      label: 'Rooms',
      icon: Icons.meeting_room_outlined,
      path: '/more/rooms',
    ),
    _DestinationData(
      label: 'Vehicles',
      icon: Icons.directions_bus_outlined,
      path: '/more/vehicles',
    ),
    _DestinationData(
      label: 'Parents',
      icon: Icons.family_restroom_outlined,
      path: '/more/parents',
    ),
    _DestinationData(
      label: 'Program settings',
      icon: Icons.settings_outlined,
      path: '/more/settings',
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
      itemBuilder: (_, i) {
        final d = destinations[i];
        return _PinnableTile(
          pinId: pinId(PinnedKinds.destination, d.path),
          child: _DestinationTile(destination: d),
        );
      },
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
        // Every destination pushes on top of Today (the drawer host),
        // so the back gesture returns here rather than exiting the app.
        onTap: () => _navigateTo(context, destination.path),
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
        for (final item in items)
          _PinnableTile(
            pinId: pinId(PinnedKinds.library, item.id),
            child: _LibraryPill(item: item),
          ),
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
      onTap: () => _navigateTo(context, '/more/library'),
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
