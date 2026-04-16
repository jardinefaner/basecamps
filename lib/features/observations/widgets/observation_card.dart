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
    this.hideAttachments = false,
    super.key,
  });

  final Observation observation;
  final VoidCallback? onTap;

  /// Strip the attachment thumbnails off the card — used by the Notes
  /// filter on the Observe tab so teachers can scan text at a glance.
  final bool hideAttachments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sentiment = ObservationSentiment.fromName(observation.sentiment);
    final time = DateFormat.MMMd().add_jm().format(observation.createdAt);
    final attachmentsAsync =
        ref.watch(observationAttachmentsProvider(observation.id));
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _SentimentIcon(sentiment: sentiment),
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
          if (!hideAttachments)
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

class _AttachmentStrip extends StatelessWidget {
  const _AttachmentStrip({required this.attachments});

  final List<ObservationAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const visibleLimit = 4;
    final visible = attachments.take(visibleLimit).toList();
    final remaining = attachments.length - visible.length;

    return SizedBox(
      height: 84,
      child: Row(
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            _AttachmentThumb(
              attachment: visible[i],
              onTap: () => AttachmentViewer.open(
                context,
                attachments,
                initialIndex: i,
              ),
            ),
            if (i < visible.length - 1 || remaining > 0)
              const SizedBox(width: AppSpacing.sm),
          ],
          if (remaining > 0)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => AttachmentViewer.open(
                context,
                attachments,
                initialIndex: visible.length,
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
                child: Text(
                  '+$remaining',
                  style: theme.textTheme.labelMedium,
                ),
              ),
            ),
        ],
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

/// Stack of domain chips rendered in the card header. Shows up to two
/// chips inline; any extras collapse into a "+N" pill so the header
/// stays on one line for long kid names.
class _DomainChipList extends StatelessWidget {
  const _DomainChipList({required this.domains});

  final List<ObservationDomain> domains;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const inlineLimit = 2;
    final visible = domains.take(inlineLimit).toList();
    final extra = domains.length - visible.length;

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
        for (final d in visible)
          chip(d == ObservationDomain.other ? d.label : d.code),
        if (extra > 0) chip('+$extra'),
      ],
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

    final kidsAsync = ref.watch(observationKidsProvider(observation.id));
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
        final legacyKidId = observation.kidId;
        if (legacyKidId != null) {
          final kidAsync = ref.watch(kidProvider(legacyKidId));
          return kidAsync.maybeWhen(
            data: (k) => Text(
              k == null ? 'Unknown kid' : _singleKidLabel(k),
              style: theme.textTheme.titleMedium,
            ),
            orElse: () => Text('…', style: theme.textTheme.titleMedium),
          );
        }
        final podId = observation.podId;
        if (podId != null) {
          final podAsync = ref.watch(podProvider(podId));
          return podAsync.maybeWhen(
            data: (p) => Text(
              p?.name ?? 'Unknown pod',
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

  String _singleKidLabel(Kid kid) {
    final last = kid.lastName;
    if (last == null || last.isEmpty) return kid.firstName;
    return '${kid.firstName} ${last[0]}.';
  }

  String _formatKidList(List<Kid> kids) {
    if (kids.length == 1) return _singleKidLabel(kids.first);
    if (kids.length == 2) {
      return '${_singleKidLabel(kids[0])} & ${_singleKidLabel(kids[1])}';
    }
    final firstTwo = kids.take(2).map(_singleKidLabel).join(', ');
    return '$firstTwo + ${kids.length - 2} more';
  }
}
