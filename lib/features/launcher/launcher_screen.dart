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

/// Drawer content for Today. Gmail-style vertical list: a rounded
/// search pill pinned at the top, then sections of labeled rows — each
/// a 24dp icon + text label — grouped under small-caps headers.
///
/// Sections (top → bottom): Pinned → Quick actions → Sections
/// (destinations) → Children → Adults → Parents → Activity library.
/// Every section live-filters off the search pill and hides itself
/// (header included) when it has zero matches.
///
/// Renders as a Drawer body (no outer Scaffold). Every navigation tap
/// funnels through [_navigateTo] which pushes on the root navigator —
/// the drawer stays in its Scaffold state so back pops the new screen
/// and Today's drawer is still open.
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
    final adults = adultsAsync.asData?.value ?? const <Adult>[];
    final parents = parentsAsync.asData?.value ?? const <Parent>[];
    final library =
        libraryAsync.asData?.value ?? const <ActivityLibraryData>[];

    // Alphabetize every list that has a natural sort axis. Pinned
    // keeps storage order (teacher-curated) and Quick actions keep
    // declared order (function-priority).
    final sortedKids = [...children]..sort((a, b) {
        final f = a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
        if (f != 0) return f;
        return (a.lastName ?? '')
            .toLowerCase()
            .compareTo((b.lastName ?? '').toLowerCase());
      });
    final sortedAdults = [...adults]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final sortedParents = [...parents]..sort((a, b) {
        final f = a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
        if (f != 0) return f;
        return (a.lastName ?? '')
            .toLowerCase()
            .compareTo((b.lastName ?? '').toLowerCase());
      });
    final sortedLibrary = [...library]
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final sortedDestinations = [..._DestinationData.all]
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    final filteredKids = [
      for (final k in sortedKids)
        if (_matches(_displayName(k.firstName, k.lastName))) k,
    ];
    final filteredAdults = [
      for (final s in sortedAdults)
        if (_matches(s.name) || _matches(s.role ?? '')) s,
    ];
    final filteredParents = [
      for (final p in sortedParents)
        if (_matches(_parentDisplayName(p)) ||
            _matches(p.relationship ?? ''))
          p,
    ];
    final filteredLibrary = [
      for (final l in sortedLibrary)
        if (_matches(l.title)) l,
    ];

    final pinnedIds = ref.watch(pinnedItemsProvider);
    // Resolve each pinned id to a live row. An id that no longer
    // resolves (e.g. child was deleted) is skipped silently.
    Widget? resolvePinnedRow(String storedId) {
      final parsed = parsePinId(storedId);
      if (parsed == null) return null;
      switch (parsed.kind) {
        case PinnedKinds.action:
          final a = _QuickActionData.byId(parsed.id);
          if (a == null || !_matches(a.label)) return null;
          return _PinnableTile(
            pinId: storedId,
            child: _ActionRow(action: a, ref: ref),
          );
        case PinnedKinds.destination:
          final d = _DestinationData.all
              .where((x) => x.path == parsed.id)
              .firstOrNull;
          if (d == null || !_matches(d.label)) return null;
          return _PinnableTile(
            pinId: storedId,
            child: _DestinationRow(destination: d),
          );
        case PinnedKinds.child:
          final k = children.where((x) => x.id == parsed.id).firstOrNull;
          if (k == null ||
              !_matches(_displayName(k.firstName, k.lastName))) {
            return null;
          }
          return _PinnableTile(
            pinId: storedId,
            child: _PersonRow(
              name: _displayName(k.firstName, k.lastName),
              avatarPath: k.avatarPath,
              fallbackInitial: k.firstName.isEmpty
                  ? '?'
                  : k.firstName.characters.first.toUpperCase(),
              route: '/children/${k.id}',
            ),
          );
        case PinnedKinds.adult:
          final s = adults.where((x) => x.id == parsed.id).firstOrNull;
          if (s == null ||
              !(_matches(s.name) || _matches(s.role ?? ''))) {
            return null;
          }
          return _PinnableTile(
            pinId: storedId,
            child: _PersonRow(
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
            child: _LibraryRow(item: l),
          );
      }
      return null;
    }

    final pinnedRows = <Widget>[
      for (final id in pinnedIds) ?resolvePinnedRow(id),
    ];

    // Each source section only shows items not already pinned — so
    // items appear in exactly one place at a time.
    final unpinnedActions = _QuickActionData.all
        .where((a) => !pinnedIds.contains(pinId(PinnedKinds.action, a.id)))
        .where((a) => _matches(a.label))
        .toList();
    final unpinnedKids = filteredKids
        .where((k) => !pinnedIds.contains(pinId(PinnedKinds.child, k.id)))
        .toList();
    final unpinnedAdults = filteredAdults
        .where((s) => !pinnedIds.contains(pinId(PinnedKinds.adult, s.id)))
        .toList();
    final unpinnedLibrary = filteredLibrary
        .where((l) => !pinnedIds.contains(pinId(PinnedKinds.library, l.id)))
        .toList();
    // Parents aren't pinnable yet — no PinnedKinds.parent entry.
    final unpinnedParents = filteredParents;
    final destinations = sortedDestinations
        .where((d) =>
            !pinnedIds.contains(pinId(PinnedKinds.destination, d.path)))
        .where((d) => _matches(d.label))
        .toList();

    final hasAnyResults = _query.isEmpty ||
        pinnedRows.isNotEmpty ||
        unpinnedActions.isNotEmpty ||
        destinations.isNotEmpty ||
        unpinnedKids.isNotEmpty ||
        unpinnedAdults.isNotEmpty ||
        unpinnedParents.isNotEmpty ||
        unpinnedLibrary.isNotEmpty;

    // Show the Pinned section whenever pinning is useful — either
    // there are pins already, or there's no search filter masking
    // everything. This keeps the drop target discoverable.
    final showPinnedSection =
        pinnedRows.isNotEmpty || _query.isEmpty;

    // No outer Scaffold — LauncherScreen is rendered inside a Drawer
    // which supplies its own Material surface.
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
                        top: AppSpacing.xs,
                        bottom: AppSpacing.xxxl,
                      ),
                      children: [
                        if (showPinnedSection)
                          _PinnedSection(
                            rows: pinnedRows,
                            isFiltered: _query.isNotEmpty,
                          ),
                        if (unpinnedActions.isNotEmpty)
                          const _SectionHeader(label: 'Quick actions'),
                        for (final a in unpinnedActions)
                          _PinnableTile(
                            pinId: pinId(PinnedKinds.action, a.id),
                            child: _ActionRow(action: a, ref: ref),
                          ),
                        if (destinations.isNotEmpty)
                          const _SectionHeader(label: 'Sections'),
                        for (final d in destinations)
                          _PinnableTile(
                            pinId: pinId(PinnedKinds.destination, d.path),
                            child: _DestinationRow(destination: d),
                          ),
                        if (unpinnedKids.isNotEmpty)
                          _SectionHeader(
                            label: 'Children',
                            count: unpinnedKids.length,
                            total: children.length,
                            query: _query,
                          ),
                        for (final k in unpinnedKids)
                          _PinnableTile(
                            pinId: pinId(PinnedKinds.child, k.id),
                            child: _PersonRow(
                              name: _displayName(k.firstName, k.lastName),
                              avatarPath: k.avatarPath,
                              fallbackInitial: k.firstName.isEmpty
                                  ? '?'
                                  : k.firstName.characters.first.toUpperCase(),
                              route: '/children/${k.id}',
                            ),
                          ),
                        if (unpinnedAdults.isNotEmpty)
                          _SectionHeader(
                            label: 'Adults',
                            count: unpinnedAdults.length,
                            total: adults.length,
                            query: _query,
                          ),
                        for (final s in unpinnedAdults)
                          _PinnableTile(
                            pinId: pinId(PinnedKinds.adult, s.id),
                            child: _PersonRow(
                              name: s.name,
                              avatarPath: s.avatarPath,
                              fallbackInitial: s.name.isEmpty
                                  ? '?'
                                  : s.name.characters.first.toUpperCase(),
                              route: '/more/adults/${s.id}',
                            ),
                          ),
                        if (unpinnedParents.isNotEmpty)
                          _SectionHeader(
                            label: 'Parents',
                            count: unpinnedParents.length,
                            total: parents.length,
                            query: _query,
                          ),
                        // Parents aren't pinnable yet, so no
                        // `_PinnableTile` wrapper — they read as plain
                        // rows. Adding a PinnedKinds.parent entry is a
                        // small follow-up if teachers ask for it.
                        for (final p in unpinnedParents)
                          _PersonRow(
                            name: _parentDisplayName(p),
                            fallbackInitial: p.firstName.isEmpty
                                ? '?'
                                : p.firstName.characters.first.toUpperCase(),
                            route: '/more/parents/${p.id}',
                            // Parents don't carry an avatar path yet —
                            // leaving it null triggers the initial-on-
                            // secondaryContainer fallback.
                            useSecondaryFallback: true,
                          ),
                        if (unpinnedLibrary.isNotEmpty)
                          _SectionHeader(
                            label: 'Activity library',
                            count: unpinnedLibrary.length,
                            total: library.length,
                            query: _query,
                          ),
                        for (final l in unpinnedLibrary)
                          _PinnableTile(
                            pinId: pinId(PinnedKinds.library, l.id),
                            child: _LibraryRow(item: l),
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
/// Matches the Child / Adult conventions so the three people lists
/// read the same at a glance.
String _parentDisplayName(Parent p) =>
    _displayName(p.firstName, p.lastName);

/// Route without closing the drawer. The pushed screen covers Today
/// (and the drawer visually), but the Scaffold preserves the drawer's
/// open state — pressing back pops the pushed screen and the drawer
/// is still there.
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
// Search pill
// ================================================================

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Outer margin matches the 8dp drawer-to-pill gap Gmail uses.
    // Inside the pill, the search icon is flush left (4dp + 12dp gap
    // places it at 16dp from the drawer edge — the same column every
    // ListTile's leading icon sits in below). That's what "aligned
    // with the rest of the items" actually means visually; the input
    // field inherits the alignment since it follows the icon.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(28),
        ),
        // Breathable input: ~20dp vertical margin inside the pill
        // (via SizedBox heights + TextField content padding) so the
        // text sits centered with air around it instead of hugging
        // the edges.
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(
          children: [
            Icon(
              Icons.search,
              size: 22,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.md),
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
                  // Symmetric vertical padding gives the input
                  // breathing room without needing to push the pill
                  // taller than 56dp.
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 14,
                  ),
                ),
                onChanged: onChanged,
              ),
            ),
            if (controller.text.isNotEmpty)
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              )
            else
              const SizedBox(width: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// Section header
// ================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    this.count,
    this.total,
    this.query = '',
  });

  final String label;
  final int? count;
  final int? total;
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        '${label.toUpperCase()}${_headerSuffix()}',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
        ),
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
// Pinned section
// ================================================================

/// Pinned section combines the Gmail-style header with the drop-target
/// semantics of the old Smart Shelf. Rows render as plain rows; the
/// whole section area is the drop target — so teachers can drag onto
/// the header, any row, or the empty-state hint and it all lands as
/// "pin here".
class _PinnedSection extends ConsumerWidget {
  const _PinnedSection({required this.rows, required this.isFiltered});

  final List<Widget> rows;

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
          color: hovering
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
              : Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionHeader(label: 'Pinned'),
              if (rows.isEmpty)
                _PinnedEmpty(hovering: hovering, isFiltered: isFiltered)
              else
                ...rows,
            ],
          ),
        );
      },
    );
  }
}

class _PinnedEmpty extends StatelessWidget {
  const _PinnedEmpty({required this.hovering, required this.isFiltered});

  final bool hovering;
  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Text(
        hovering
            ? 'Drop here to pin'
            : isFiltered
                ? 'No pinned items match this search.'
                : 'Long-press any row below and drag here to pin.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: hovering
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
          fontWeight: hovering ? FontWeight.w700 : null,
        ),
      ),
    );
  }
}

/// Wraps any launcher row in a long-press-draggable. [pinId] is the
/// stored-format identifier with kind prefix (e.g. `action:new-activity`,
/// `child:abc123`). Drop on the Pinned section to pin; drop anywhere
/// else (into the list body, off the edge, on empty space) to unpin.
/// Dropping a pinned row back on the Pinned section is a no-op — the
/// section treats that as "cancel".
class _PinnableTile extends ConsumerWidget {
  const _PinnableTile({required this.pinId, required this.child});

  final String pinId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LongPressDraggable<String>(
      data: pinId,
      // Constrain the feedback width so the row doesn't stretch to
      // its natural "fill the drawer" width while being dragged.
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Opacity(
            opacity: 0.94,
            child: Transform.scale(scale: 1.02, child: child),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      onDragEnd: (details) {
        // Accepted drops always land on the Pinned section (only
        // DragTarget in play). When not accepted, the teacher
        // released over the list body, so interpret that as "unpin" —
        // but only if the row is actually pinned right now.
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
  ];

  static _QuickActionData? byId(String id) {
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }
}

// ================================================================
// Row widgets — Gmail-style ListTile rows (24dp icon + label)
// ================================================================

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action, required this.ref});

  final _QuickActionData action;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
      ),
      leading: Icon(
        action.icon,
        size: 24,
        color: theme.colorScheme.primary,
      ),
      title: Text(action.label),
      onTap: () => action.onTap(context, ref),
    );
  }
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({required this.destination});

  final _DestinationData destination;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
      ),
      leading: Icon(
        destination.icon,
        size: 24,
        color: theme.colorScheme.primary,
      ),
      title: Text(destination.label),
      onTap: () => _navigateTo(context, destination.path),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.name,
    required this.fallbackInitial,
    required this.route,
    this.avatarPath,
    this.useSecondaryFallback = false,
  });

  final String name;
  final String? avatarPath;
  final String fallbackInitial;
  final String route;

  /// Parents don't carry avatar images yet; when true, the fallback
  /// initial renders on `secondaryContainer` to match the older
  /// launcher's parent styling.
  final bool useSecondaryFallback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
      ),
      leading: SmallAvatar(
        path: avatarPath,
        fallbackInitial: fallbackInitial,
        // 24dp icon → 12dp radius circle fits a ListTile leading slot.
        radius: 12,
        backgroundColor: useSecondaryFallback
            ? theme.colorScheme.secondaryContainer
            : null,
        foregroundColor: useSecondaryFallback
            ? theme.colorScheme.onSecondaryContainer
            : null,
      ),
      title: Text(name),
      onTap: () => _navigateTo(context, route),
    );
  }
}

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({required this.item});

  final ActivityLibraryData item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
      ),
      leading: Icon(
        Icons.bookmark_outlined,
        size: 24,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(item.title),
      onTap: () => _navigateTo(context, '/more/library'),
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
