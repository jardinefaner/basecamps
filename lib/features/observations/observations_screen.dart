import 'dart:async';
import 'dart:io';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/features/observations/widgets/attachment_viewer.dart';
import 'package:basecamp/features/observations/widgets/observation_card.dart';
import 'package:basecamp/features/observations/widgets/observation_composer.dart';
import 'package:basecamp/features/observations/widgets/observation_edit_sheet.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  const ObservationsScreen({super.key});

  @override
  ConsumerState<ObservationsScreen> createState() => _ObservationsScreenState();
}

class _ObservationsScreenState extends ConsumerState<ObservationsScreen> {
  _ObserveFilter _filter = _ObserveFilter.all;

  Future<void> _openEditSheet(Observation observation) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => ObservationEditSheet(observation: observation),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Observe')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
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
              onSelectionChanged: (s) => setState(() => _filter = s.first),
              showSelectedIcon: false,
            ),
          ),
          Expanded(child: _body()),
          // The composer is a capture surface. Media mode is a
          // view-oriented gallery — hide the composer there so the
          // screen really is "just the pictures".
          if (_filter != _ObserveFilter.media) const ObservationComposer(),
        ],
      ),
    );
  }

  Widget _body() {
    switch (_filter) {
      case _ObserveFilter.all:
        return _ListFeed(
          onTapObservation: _openEditSheet,
          notesOnly: false,
        );
      case _ObserveFilter.notes:
        return _ListFeed(
          onTapObservation: _openEditSheet,
          notesOnly: true,
        );
      case _ObserveFilter.media:
        return const _MediaGallery();
    }
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
  });

  final Future<void> Function(Observation) onTapObservation;
  final bool notesOnly;

  @override
  ConsumerState<_ListFeed> createState() => _ListFeedState();
}

class _ListFeedState extends ConsumerState<_ListFeed> {
  final _controller = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollToNewest() {
    if (!_controller.hasClients) return;
    // Reverse-mode list: offset 0 renders at the bottom of the viewport,
    // which is where items[0] (newest) lives. Jumping short distances
    // feels cheap — use a quick animate.
    unawaited(
      _controller.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<Observation>>>(
      observationsProvider,
      (prev, next) {
        final count = next.asData?.value.length ?? 0;
        if (count > _lastCount && _lastCount != 0) {
          // An observation was added (not the initial hydration). Snap
          // the feed back to the newest so the teacher sees what just
          // landed.
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _scrollToNewest(),
          );
        }
        _lastCount = count;
      },
    );

    final observationsAsync = ref.watch(observationsProvider);

    return observationsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error: $err')),
      data: (items) {
        if (items.isEmpty) {
          return const _EmptyState();
        }
        return ListView.separated(
          controller: _controller,
          reverse: true,
          padding: const EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.xl,
            bottom: AppSpacing.lg,
          ),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (_, i) => ObservationCard(
            observation: items[i],
            hideAttachments: widget.notesOnly,
            onTap: () => widget.onTapObservation(items[i]),
          ),
        );
      },
    );
  }
}

/// Read-only grid of every attachment. The whole point: teachers scan
/// what they shot. Tap = full-screen viewer. No card chrome, no editing.
class _MediaGallery extends ConsumerWidget {
  const _MediaGallery();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachmentsAsync = ref.watch(allAttachmentsProvider);

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
          itemBuilder: (context, i) => _GalleryTile(
            attachment: atts[i],
            onTap: () =>
                AttachmentViewer.open(context, atts, initialIndex: i),
          ),
        );
      },
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({required this.attachment, required this.onTap});

  final ObservationAttachment attachment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPhoto = attachment.kind == 'photo';
    return GestureDetector(
      onTap: onTap,
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
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
              Icons.edit_note_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Start capturing',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Type, dictate, or attach a photo below — your observations '
              'show up here.',
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
