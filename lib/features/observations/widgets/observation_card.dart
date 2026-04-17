import 'dart:io';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/features/observations/widgets/attachment_viewer.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class ObservationCard extends ConsumerWidget {
  const ObservationCard({
    required this.observation,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.hideAttachments = false,
    super.key,
  });

  final Observation observation;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// When true, the card paints with the selection tint + primary
  /// outline (via AppCard) and the top-right corner shows a check
  /// badge so the card reads as "picked" in bulk-select mode.
  final bool selected;

  /// Strip the attachment thumbnails off the card — used by the Notes
  /// filter on the Observe tab so teachers can scan text at a glance.
  final bool hideAttachments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sentiment = ObservationSentiment.fromName(observation.sentiment);
    final time = DateFormat.MMMd().add_jm().format(observation.createdAt);

    // Perf: only subscribe to the attachments stream when we actually
    // render them. The Notes filter hides thumbnails, so we save one
    // stream listener per card on large feeds.
    final attachmentsAsync = hideAttachments
        ? null
        : ref.watch(observationAttachmentsProvider(observation.id));

    final domainsAsync = ref.watch(
      observationDomainsProvider(observation.id),
    );

    // Fall back to the legacy single-column value on the initial frame
    // before the stream has resolved — keeps the UI from flashing empty.
    final domains = domainsAsync.maybeWhen(
      data: (list) => list.isEmpty
          ? [ObservationDomain.fromName(observation.domain)]
          : list,
      orElse: () => [ObservationDomain.fromName(observation.domain)],
    );

    return AppCard(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: selected
                    ? _SelectCheck(theme: theme)
                    : _SentimentIcon(sentiment: sentiment),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _TargetLabel(observation: observation),
              ),
              Flexible(
                flex: 0,
                child: _DomainChipList(domains: domains),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(observation.note, style: theme.textTheme.bodyMedium),
          if (!hideAttachments && attachmentsAsync != null)
            attachmentsAsync.maybeWhen(
              data: (atts) => atts.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: _AttachmentStrip(attachments: atts),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
          if (observation.activityLabel != null &&
              observation.activityLabel!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(
                  Icons.schedule_outlined,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'During ${observation.activityLabel!}',
                    style: theme.textTheme.labelSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(time, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _AttachmentStrip extends ConsumerWidget {
  const _AttachmentStrip({required this.attachments});

  final List<ObservationAttachment> attachments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Show up to 4 inline, rest collapse into a "+N" tile. Horizontal
    // scroll handles the rare case where 4 thumbs + the +N tile still
    // don't fit on very narrow phones (SE, etc).
    const visibleLimit = 4;
    final visible = attachments.take(visibleLimit).toList();
    final remaining = attachments.length - visible.length;
    final total = visible.length + (remaining > 0 ? 1 : 0);

    Future<void> onDelete(ObservationAttachment a) =>
        ref.read(observationsRepositoryProvider).deleteAttachment(a.id);

    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // With a full row of 4 + overflow tile most screens don't need
        // scrolling; the physics fire only when width is tight.
        physics: const ClampingScrollPhysics(),
        itemCount: total,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          if (i < visible.length) {
            return _AttachmentThumb(
              attachment: visible[i],
              onTap: () => AttachmentViewer.open(
                context,
                attachments,
                initialIndex: i,
                onDelete: onDelete,
              ),
            );
          }
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => AttachmentViewer.open(
              context,
              attachments,
              initialIndex: visible.length,
              onDelete: onDelete,
            ),
            child: Container(
              width: 64,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant,
                  width: 0.5,
                ),
              ),
              child: Text('+$remaining', style: theme.textTheme.labelMedium),
            ),
          );
        },
      ),
    );
  }
}

class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({required this.attachment, this.onTap});

  final ObservationAttachment attachment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPhoto = attachment.kind == 'photo';
    final thumb = Container(
      width: 84,
      height: 84,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isPhoto && !kIsWeb)
            Image.file(
              File(attachment.localPath),
              fit: BoxFit.cover,
              // Decode at ~thumbnail resolution (card thumb is 84px;
              // 2x for retina). Saves hundreds of MB per feed when a
              // teacher has been snapping 12MP photos.
              cacheWidth: 168,
              errorBuilder: (_, _, _) =>
                  _placeholder(theme, Icons.image_outlined),
            )
          else
            _placeholder(
              theme,
              isPhoto ? Icons.image_outlined : Icons.play_circle_outline,
            ),
          if (!isPhoto)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.videocam,
                  color: Colors.white,
                  size: 12,
                ),
              ),
            ),
        ],
      ),
    );

    if (onTap == null) return thumb;
    return GestureDetector(
      onTap: onTap,
      // Swallow other gesture signals so the card's onTap doesn't fire
      // when the user is specifically tapping a thumbnail.
      behavior: HitTestBehavior.opaque,
      child: thumb,
    );
  }

  Widget _placeholder(ThemeData theme, IconData icon) {
    return Center(
      child: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

/// Primary domain chip + an optional "+N" collapsing the rest. Keep
/// the header to a single inline pill so the kid-name column keeps as
/// much space as possible — tapping the card opens the editor where
/// every tagged domain is visible.
class _DomainChipList extends StatelessWidget {
  const _DomainChipList({required this.domains});

  final List<ObservationDomain> domains;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = domains.first;
    final extra = domains.length - 1;

    Widget chip(String text) => Container(
          margin: const EdgeInsets.only(left: AppSpacing.xs),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(text, style: theme.textTheme.labelMedium),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip(primary == ObservationDomain.other ? primary.label : primary.code),
        if (extra > 0) chip('+$extra'),
      ],
    );
  }
}

/// Replaces the sentiment glyph in the card header while the card is
/// selected in multi-pick mode. Small filled primary circle with a
/// white check — mirrors the indicator colour on the grid media tile.
class _SelectCheck extends StatelessWidget {
  const _SelectCheck({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.check,
        size: 12,
        color: theme.colorScheme.onPrimary,
      ),
    );
  }
}

class _SentimentIcon extends StatelessWidget {
  const _SentimentIcon({required this.sentiment});

  final ObservationSentiment sentiment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = switch (sentiment) {
      ObservationSentiment.positive => (
          Icons.sentiment_satisfied,
          theme.colorScheme.primary,
        ),
      ObservationSentiment.neutral => (
          Icons.sentiment_neutral,
          theme.colorScheme.onSurfaceVariant,
        ),
      ObservationSentiment.concern => (
          Icons.flag,
          theme.colorScheme.error,
        ),
    };
    return Icon(icon, size: 18, color: color);
  }
}

class _TargetLabel extends ConsumerWidget {
  const _TargetLabel({required this.observation});

  final Observation observation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final kidsAsync = ref.watch(observationChildrenProvider(observation.id));
    return kidsAsync.when(
      loading: () => Text('…', style: theme.textTheme.titleMedium),
      error: (err, _) =>
          Text('Error', style: theme.textTheme.titleMedium),
      data: (kids) {
        if (kids.isNotEmpty) {
          return Text(
            _formatKidList(kids),
            style: theme.textTheme.titleMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          );
        }
        // Fallbacks for legacy single-kid or pod/activity-scoped observations.
        final legacyKidId = observation.childId;
        if (legacyKidId != null) {
          final kidAsync = ref.watch(childProvider(legacyKidId));
          return kidAsync.maybeWhen(
            data: (k) => Text(
              k == null ? 'Unknown child' : _singleKidLabel(k),
              style: theme.textTheme.titleMedium,
            ),
            orElse: () => Text('…', style: theme.textTheme.titleMedium),
          );
        }
        final groupId = observation.groupId;
        if (groupId != null) {
          final podAsync = ref.watch(groupProvider(groupId));
          return podAsync.maybeWhen(
            data: (p) => Text(
              p?.name ?? 'Unknown group',
              style: theme.textTheme.titleMedium,
            ),
            orElse: () => Text('…', style: theme.textTheme.titleMedium),
          );
        }
        return Text(
          observation.activityLabel ?? 'General note',
          style: theme.textTheme.titleMedium,
        );
      },
    );
  }

  String _singleKidLabel(Child kid) {
    final last = kid.lastName;
    if (last == null || last.isEmpty) return kid.firstName;
    return '${kid.firstName} ${last[0]}.';
  }

  String _formatKidList(List<Child> kids) {
    if (kids.length == 1) return _singleKidLabel(kids.first);
    if (kids.length == 2) {
      return '${_singleKidLabel(kids[0])} & ${_singleKidLabel(kids[1])}';
    }
    final firstTwo = kids.take(2).map(_singleKidLabel).join(', ');
    return '$firstTwo + ${kids.length - 2} more';
  }
}
