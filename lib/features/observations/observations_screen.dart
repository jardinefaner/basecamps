import 'dart:async';
import 'dart:io';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/features/observations/widgets/attachment_viewer.dart';
import 'package:basecamp/features/observations/widgets/observation_card.dart';
import 'package:basecamp/features/observations/widgets/observation_composer.dart';
import 'package:basecamp/features/observations/widgets/observation_edit_sheet.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/undo_delete.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// How the Observe tab's feed is filtered.
enum _ObserveFilter {
  /// Show everything — notes, attachments, the whole card.
  all,

  /// Only show text notes, attachment thumbs hidden.
  notes,

  /// Only show photos and videos, laid out as a tappable grid.
  media,
}

class ObservationsScreen extends ConsumerStatefulWidget {
  const ObservationsScreen({super.key, this.initialTagFilter});

  /// Raw `?tag=` query param from the route. Resolved to an
  /// [ObservationDomain] once in [State.initState]; unknown values
  /// fall back to "no filter" rather than `.other` so a typo'd URL
  /// doesn't silently scope the archive to Other observations.
  final String? initialTagFilter;

  @override
  ConsumerState<ObservationsScreen> createState() => _ObservationsScreenState();
}

class _ObservationsScreenState extends ConsumerState<ObservationsScreen> {
  _ObserveFilter _filter = _ObserveFilter.all;

  /// Domain the archive is scoped to, if any. Driven initially by the
  /// `?tag=` query param but editable in-widget via the Filtered pill's
  /// clear button. `null` = unfiltered feed.
  ObservationDomain? _activeTagFilter;

  @override
  void initState() {
    super.initState();
    final raw = widget.initialTagFilter;
    if (raw != null && raw.isNotEmpty) {
      // Guard against unknown enum names — fromName returns .other as
      // its fallback, which would silently scope to Other when a URL
      // typo arrives. Verify the match is exact before applying.
      final resolved = ObservationDomain.fromName(raw);
      if (resolved.name == raw) {
        _activeTagFilter = resolved;
      }
    }
  }

  void _clearTagFilter() {
    setState(() => _activeTagFilter = null);
    // Keep the URL honest so a follow-up share / back-stack manoeuvre
    // doesn't resurface the filter. `go` replaces rather than pushes —
    // the teacher is on the Observations page already, no need for an
    // extra history entry.
    context.go('/observations');
  }

  /// Held so child widgets (the list feed) can reach back out and
  /// animate the outer AppBar controller on send — otherwise the
  /// AppBar stays hidden above the newly-scrolled-to-top card and
  /// covers it when it snaps back in.
  final _nestedKey = GlobalKey<NestedScrollViewState>();

  /// Bulk-select state. The observation set drives selection in the
  /// All/Notes feed; the attachment set drives it in the Media grid.
  /// Filter switches clear both so a half-selected feed doesn't bleed
  /// across tabs.
  final Set<String> _selectedObservationIds = <String>{};
  final Set<String> _selectedAttachmentIds = <String>{};

  bool get _selectingObservations => _selectedObservationIds.isNotEmpty;
  bool get _selectingAttachments => _selectedAttachmentIds.isNotEmpty;
  bool get _selecting =>
      _selectingObservations || _selectingAttachments;

  Future<void> _openEditSheet(Observation observation) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => ObservationEditSheet(observation: observation),
    );
  }

  void _toggleObservation(String id) {
    setState(() {
      if (!_selectedObservationIds.add(id)) _selectedObservationIds.remove(id);
    });
  }

  void _toggleAttachment(String id) {
    setState(() {
      if (!_selectedAttachmentIds.add(id)) _selectedAttachmentIds.remove(id);
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedObservationIds.clear();
      _selectedAttachmentIds.clear();
    });
  }

  Future<void> _deleteSelectedObservations() async {
    final count = _selectedObservationIds.length;
    if (count == 0) return;
    final repo = ref.read(observationsRepositoryProvider);
    final ids = _selectedObservationIds.toList();
    final snapshot = await repo.snapshotObservations(ids);
    if (!mounted) return;
    final confirmed = await confirmDeleteWithUndo(
      context: context,
      title: count == 1
          ? 'Delete this observation?'
          : 'Delete $count observations?',
      message:
          'Every tagged child, domain, photo and video goes with '
          "them. You'll get a 5-second window to undo.",
      confirmLabel: count == 1 ? 'Delete' : 'Delete $count',
      onDelete: () => repo.deleteObservations(ids),
      undoLabel: count == 1
          ? 'Observation removed'
          : '$count observations removed',
      onUndo: () => repo.restoreObservations(snapshot),
    );
    if (!confirmed || !mounted) return;
    _clearSelection();
  }

  Future<void> _deleteSelectedAttachments() async {
    final count = _selectedAttachmentIds.length;
    if (count == 0) return;
    final repo = ref.read(observationsRepositoryProvider);
    final ids = _selectedAttachmentIds.toList();
    final snapshot = await repo.snapshotAttachments(ids);
    if (!mounted) return;
    final confirmed = await confirmDeleteWithUndo(
      context: context,
      title: count == 1
          ? 'Delete this attachment?'
          : 'Delete $count attachments?',
      message:
          'The observations they belong to stay put. The files '
          "survive on disk until the next app launch. You'll get a "
          '5-second window to undo.',
      confirmLabel: count == 1 ? 'Delete' : 'Delete $count',
      onDelete: () => repo.deleteAttachments(ids),
      undoLabel: count == 1
          ? 'Attachment removed'
          : '$count attachments removed',
      onUndo: () => repo.restoreAttachments(snapshot),
    );
    if (!confirmed || !mounted) return;
    _clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selecting) _clearSelection();
      },
      child: Scaffold(
        // Selection AppBar stays pinned — destructive mode.
        appBar: _selecting ? _buildSelectionAppBar(theme) : null,
        body: Column(
          children: [
            if (_activeTagFilter != null)
              _FilterPill(
                domain: _activeTagFilter!,
                onClear: _clearTagFilter,
              ),
            Expanded(
              child: NestedScrollView(
                key: _nestedKey,
                headerSliverBuilder: (ctx, innerBoxIsScrolled) => [
                  if (!_selecting)
                    SliverAppBar(
                      title: const Text('Observe'),
                      floating: true,
                      snap: true,
                      forceElevated: innerBoxIsScrolled,
                      // Filter strip clamped to the AppBar — hides and
                      // shows with it, so scrolling gets maximum
                      // vertical room for the feed.
                      bottom: PreferredSize(
                        preferredSize: const Size.fromHeight(56),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            0,
                            AppSpacing.lg,
                            AppSpacing.sm,
                          ),
                          child: SegmentedButton<_ObserveFilter>(
                            segments: const [
                              ButtonSegment(
                                value: _ObserveFilter.all,
                                label: Text('All'),
                                icon: Icon(Icons.view_agenda_outlined),
                              ),
                              ButtonSegment(
                                value: _ObserveFilter.notes,
                                label: Text('Notes'),
                                icon: Icon(Icons.notes_outlined),
                              ),
                              ButtonSegment(
                                value: _ObserveFilter.media,
                                label: Text('Media'),
                                icon: Icon(Icons.photo_library_outlined),
                              ),
                            ],
                            selected: {_filter},
                            onSelectionChanged: (s) => setState(() {
                              _filter = s.first;
                              _selectedObservationIds.clear();
                              _selectedAttachmentIds.clear();
                            }),
                            showSelectedIcon: false,
                          ),
                        ),
                      ),
                    ),
                ],
                body: _body(),
              ),
            ),
            // Composer is hidden in Media mode (view-only gallery) AND
            // while bulk-selecting anywhere — no room for it, and
            // sending wouldn't clear the selection anyway.
            if (_filter != _ObserveFilter.media && !_selecting)
              const ObservationComposer(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(ThemeData theme) {
    final count = _selectingObservations
        ? _selectedObservationIds.length
        : _selectedAttachmentIds.length;
    return AppBar(
      backgroundColor: theme.colorScheme.primaryContainer,
      foregroundColor: theme.colorScheme.onPrimaryContainer,
      leading: IconButton(
        tooltip: 'Cancel selection',
        icon: const Icon(Icons.close),
        onPressed: _clearSelection,
      ),
      title: Text('$count selected'),
      actions: [
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline),
          onPressed: _selectingObservations
              ? _deleteSelectedObservations
              : _deleteSelectedAttachments,
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }

  Widget _body() {
    switch (_filter) {
      case _ObserveFilter.all:
        return _ListFeed(
          onTapObservation: _openEditSheet,
          notesOnly: false,
          selectedIds: _selectedObservationIds,
          onToggleSelect: _toggleObservation,
          nestedKey: _nestedKey,
          tagFilter: _activeTagFilter,
        );
      case _ObserveFilter.notes:
        return _ListFeed(
          onTapObservation: _openEditSheet,
          notesOnly: true,
          selectedIds: _selectedObservationIds,
          onToggleSelect: _toggleObservation,
          nestedKey: _nestedKey,
          tagFilter: _activeTagFilter,
        );
      case _ObserveFilter.media:
        return _MediaGallery(
          selectedIds: _selectedAttachmentIds,
          onToggleSelect: _toggleAttachment,
        );
    }
  }
}

/// Pill shown above the feed when the archive is scoped to a single
/// domain. Displays the domain's code + short label; the trailing X
/// drops the filter and restores the unfiltered feed.
class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.domain, required this.onClear});

  final ObservationDomain domain;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // "SSD3 · Empathy" for codes, "Other" for the uncoded bucket.
    final label = domain == ObservationDomain.other
        ? 'Other'
        : '${domain.code} · ${domain.label}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        0,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onClear,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.filter_alt_outlined,
                    size: 16,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Filtered: $label',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    Icons.close,
                    size: 18,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Normal list view. Pass `notesOnly: true` to strip attachment strips
/// off the cards so teachers can scan pure-text observations.
///
/// Stateful so we can keep a [ScrollController] for the auto-scroll that
/// runs after every send. In reverse-mode the newest row lives at offset
/// 0, so "scroll to top" = animate back to 0.
class _ListFeed extends ConsumerStatefulWidget {
  const _ListFeed({
    required this.onTapObservation,
    required this.notesOnly,
    required this.selectedIds,
    required this.onToggleSelect,
    required this.nestedKey,
    this.tagFilter,
  });

  final Future<void> Function(Observation) onTapObservation;
  final bool notesOnly;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggleSelect;

  /// Handle on the screen's NestedScrollView so we can also animate
  /// the outer AppBar controller on send — otherwise the inner list
  /// animates to 0 while the AppBar stays hidden, and snaps back in
  /// on top of the just-sent card.
  final GlobalKey<NestedScrollViewState> nestedKey;

  /// When non-null the feed pulls from the domain-scoped stream
  /// instead of the full archive — only observations tagged with this
  /// domain show up, and the empty state names the tag.
  final ObservationDomain? tagFilter;

  @override
  ConsumerState<_ListFeed> createState() => _ListFeedState();
}

class _ListFeedState extends ConsumerState<_ListFeed> {
  int _lastCount = 0;

  /// The just-added observation id, if any — the card briefly glows
  /// with the same primaryContainer tint + primary border that the
  /// Children tab uses when a child lands in a new group. Cleared
  /// after the animation window so the list settles back to neutral.
  String? _justAddedId;
  Timer? _highlightTimer;

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }

  void _flashHighlight(String id) {
    setState(() => _justAddedId = id);
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() => _justAddedId = null);
    });
  }

  void _scrollToNewest(BuildContext context) {
    // Two controllers in play under a NestedScrollView:
    //   * outerController — drives the SliverAppBar visibility
    //   * innerController (exposed via PrimaryScrollController) —
    //     scrolls the list below the AppBar
    //
    // Animating only the inner to 0 leaves the AppBar wherever it was
    // hiding, and when it snaps back in it covers the freshly-sent
    // card. We run both: the outer returns to 0 so the AppBar is
    // fully visible, and the inner returns to 0 so the new row sits
    // right below it.
    const duration = Duration(milliseconds: 260);
    const curve = Curves.easeOut;
    final nested = widget.nestedKey.currentState;
    if (nested != null && nested.outerController.hasClients) {
      unawaited(
        nested.outerController.animateTo(
          0,
          duration: duration,
          curve: curve,
        ),
      );
    }
    final inner = PrimaryScrollController.maybeOf(context);
    if (inner != null && inner.hasClients) {
      unawaited(
        inner.animateTo(0, duration: duration, curve: curve),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pick the feed source — scoped to a domain when the archive was
    // entered via a tag chip, otherwise the full stream. `ref.listen`
    // / `ref.watch` are called twice with the same branching so the
    // inferred provider type stays sharp (the exported Listenable
    // type isn't stable enough to hoist into a shared local).
    final tag = widget.tagFilter;
    void onFeed(
      AsyncValue<List<Observation>>? prev,
      AsyncValue<List<Observation>> next,
    ) {
      final list = next.asData?.value ?? const <Observation>[];
      final count = list.length;
      if (count > _lastCount && _lastCount != 0) {
        // An observation was added (not the initial hydration). Snap
        // the feed back to the newest so the teacher sees what just
        // landed, and flash the drag-target highlight so the new
        // row is impossible to miss.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToNewest(context),
        );
        if (list.isNotEmpty) {
          _flashHighlight(list.first.id);
        }
      }
      _lastCount = count;
    }

    if (tag == null) {
      ref.listen<AsyncValue<List<Observation>>>(observationsProvider, onFeed);
    } else {
      ref.listen<AsyncValue<List<Observation>>>(
        observationsWithDomainProvider(tag),
        onFeed,
      );
    }

    final observationsAsync = tag == null
        ? ref.watch(observationsProvider)
        : ref.watch(observationsWithDomainProvider(tag));
    final selecting = widget.selectedIds.isNotEmpty;

    return observationsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error: $err')),
      data: (items) {
        if (items.isEmpty) {
          return _EmptyState(filteredDomain: tag);
        }
        return ListView.separated(
          // No custom controller — the PrimaryScrollController injected
          // by the parent NestedScrollView drives both this list AND
          // the collapsing SliverAppBar. Keeping our own controller
          // severs that link and the AppBar stops hiding on scroll.
          //
          // Forward scroll (newest at top, natural drag direction).
          // After send we animate back to offset 0 so the new row is
          // visible.
          padding: const EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.md,
            bottom: AppSpacing.lg,
          ),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (_, i) {
            final obs = items[i];
            final selected = widget.selectedIds.contains(obs.id);
            final highlighted = obs.id == _justAddedId;
            final theme = Theme.of(context);
            return AnimatedContainer(
              // Same tween the Children tab's _GroupSection uses for
              // drag-target highlight — intentionally copied so "just
              // landed" and "dropping into a new group" read as the
              // same visual language.
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                color: highlighted
                    ? theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.4)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: highlighted
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: ObservationCard(
                observation: obs,
                hideAttachments: widget.notesOnly,
                selected: selected,
                // In selection mode a tap toggles; otherwise it edits.
                // Long-press always toggles so the first pick can kick
                // off the mode.
                onTap: selecting
                    ? () => widget.onToggleSelect(obs.id)
                    : () => widget.onTapObservation(obs),
                onLongPress: () => widget.onToggleSelect(obs.id),
              ),
            );
          },
        );
      },
    );
  }
}

/// Read-only grid of every attachment. Long-press to enter bulk-select
/// mode, which the parent screen translates into a delete action.
class _MediaGallery extends ConsumerWidget {
  const _MediaGallery({
    required this.selectedIds,
    required this.onToggleSelect,
  });

  final Set<String> selectedIds;
  final ValueChanged<String> onToggleSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachmentsAsync = ref.watch(allAttachmentsProvider);
    final selecting = selectedIds.isNotEmpty;

    return attachmentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error: $err')),
      data: (atts) {
        if (atts.isEmpty) {
          return const _EmptyMedia();
        }
        return GridView.builder(
          padding: const EdgeInsets.all(AppSpacing.sm),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemCount: atts.length,
          itemBuilder: (context, i) {
            final att = atts[i];
            final selected = selectedIds.contains(att.id);
            return _GalleryTile(
              attachment: att,
              selected: selected,
              onTap: selecting
                  ? () => onToggleSelect(att.id)
                  : () => AttachmentViewer.open(
                        context,
                        atts,
                        initialIndex: i,
                        onDelete: (a) => ref
                            .read(observationsRepositoryProvider)
                            .deleteAttachment(a.id),
                      ),
              onLongPress: () => onToggleSelect(att.id),
            );
          },
        );
      },
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    required this.attachment,
    required this.onTap,
    required this.onLongPress,
    this.selected = false,
  });

  final ObservationAttachment attachment;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPhoto = attachment.kind == 'photo';
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isPhoto && !kIsWeb)
              Image.file(
                File(attachment.localPath),
                fit: BoxFit.cover,
                // 3-col grid tiles render around ~130dp on phones; 2x
                // for retina. Decodes at thumbnail size so a hundred
                // photos don't blow up memory.
                cacheWidth: 260,
                errorBuilder: (_, _, _) => Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Center(
                child: Icon(
                  isPhoto ? Icons.image_outlined : Icons.play_circle_outline,
                  size: 40,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (!isPhoto)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.videocam,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            // Selection veil + top-left check badge. Drawn last so
            // it sits on top of the thumbnail and the video indicator.
            if (selected) ...[
              Container(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
              ),
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.check,
                    size: 12,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.filteredDomain});

  /// When non-null the feed is scoped to this domain and the
  /// empty-state copy names the tag so the teacher knows why
  /// the list looks bare.
  final ObservationDomain? filteredDomain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = filteredDomain;
    final title = filtered == null ? 'Start capturing' : 'Nothing tagged yet';
    final body = filtered == null
        ? 'Type, dictate, or attach a photo below — your observations '
            'show up here.'
        : filtered == ObservationDomain.other
            ? 'No observations tagged Other yet.'
            : 'No observations tagged ${filtered.code} · ${filtered.label} yet.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.edit_note_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              body,
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

class _EmptyMedia extends StatelessWidget {
  const _EmptyMedia();

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
              Icons.photo_library_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No photos or videos yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Switch to All or Notes, then attach media from the composer.',
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
