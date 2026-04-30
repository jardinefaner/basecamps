import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/groups/group_summary_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/today/ratio_check.dart';
import 'package:basecamp/features/today/widgets/schedule_item_card.dart'
    show AttendanceSummary;
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:flutter/material.dart';

/// Threshold at which the ratio chip flips from "muted / OK" to
/// "red / UNDER RATIO". Hardcoded for now — programs tune their
/// own ratio rules, so this is the single knob we'd expect to
/// promote next. Exported so the Today screen and any future caller
/// can pass the same value into [computeGroupRatioNow].
// TODO: source this from `ProgramSettings` once the settings feature
// grows per-program ratio rules.
const int kGroupRatioFloor = 8;

/// Today view of a single [GroupSummary] — collapsed it's a one-line
/// "at-a-glance" scannable row; expanded it unfolds into a NOW tile,
/// up-next preview, and an avatar row of the anchor leads.
///
/// One card per group in the group stack. The parent screen owns the
/// "which group is expanded" state (via `lastExpandedGroupProvider`),
/// so only one card is expanded at a time — the accordion semantics
/// keep the vertical footprint constant regardless of group count.
///
/// Data is pushed down, not pulled: the parent already filters the
/// day's schedule items to this group's id and computes the roll
/// summary against today's attendance map. This widget stays dumb.
class GroupTodayCard extends StatelessWidget {
  const GroupTodayCard({
    required this.group,
    required this.now,
    required this.current,
    required this.next,
    required this.attendance,
    required this.leadsNow,
    required this.expanded,
    required this.onToggle,
    required this.onOpenDetail,
    required this.onOpenAttendance,
    required this.onOpenGroupDetail,
    this.ratio,
    super.key,
  });

  /// Pre-computed ratio for this group at `now`. Null hides the chip
  /// (either the caller doesn't have the data yet or intentionally
  /// opted out). Never pulls providers internally — the caller owns
  /// ratio-check inputs so this stays a dumb renderer.
  final GroupRatioNow? ratio;

  final GroupSummary group;
  final DateTime now;

  /// Adults currently leading this group. Derived from the v30 day-
  /// timeline when present, falling back to the static anchor when
  /// an adult has no timeline set. The parent computes this so the
  /// card stays a dumb renderer.
  final List<Adult> leadsNow;

  /// Activity for this group that's in progress right now, if any.
  /// First entry wins when multiple overlap (earliest-started — same
  /// rule the Today bucketer uses for the hero slot).
  final ScheduleItem? current;

  /// Next-up activity for this group, if any.
  final ScheduleItem? next;

  /// Roll summary for the kids assigned to this group. Null when no
  /// kids are assigned yet (brand-new group).
  final AttendanceSummary? attendance;

  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<ScheduleItem> onOpenDetail;
  final ValueChanged<ScheduleItem> onOpenAttendance;

  /// Drill into the group's detail screen. Shown as a footer action
  /// on the expanded card — header tap keeps its expand/collapse
  /// semantics, so this is the explicit "open" affordance.
  final VoidCallback onOpenGroupDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            group: group,
            current: current,
            now: now,
            attendance: attendance,
            ratio: ratio,
            expanded: expanded,
            onToggle: onToggle,
          ),
          if (expanded) ...[
            Divider(
              height: 1,
              thickness: 0.5,
              color: theme.colorScheme.outlineVariant,
            ),
            _ExpandedBody(
              group: group,
              now: now,
              current: current,
              next: next,
              attendance: attendance,
              leadsNow: leadsNow,
              onOpenDetail: onOpenDetail,
              onOpenAttendance: onOpenAttendance,
              onOpenGroupDetail: onOpenGroupDetail,
            ),
          ],
        ],
      ),
    );
  }
}

/// Collapsed tappable row. Tap anywhere on it → toggle expand/collapse.
/// Shows just enough to scan group status in ~1s from the group stack:
/// color dot, name, roll summary, current activity subtitle.
class _Header extends StatelessWidget {
  const _Header({
    required this.group,
    required this.current,
    required this.now,
    required this.attendance,
    required this.ratio,
    required this.expanded,
    required this.onToggle,
  });

  final GroupSummary group;
  final ScheduleItem? current;
  final DateTime now;
  final AttendanceSummary? attendance;
  final GroupRatioNow? ratio;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = _subtitle();
    // Collapsed row — deliberately single-line dense. The hero row
    // dominates the fold when one's earned its spot; each collapsed
    // group card is a scan-in-1s summary, not a mini-card. Expanding
    // fans out the full NOW + NEXT + leads detail.
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            _GroupDot(colorHex: group.group.colorHex),
            const SizedBox(width: AppSpacing.sm),
            Text(
              group.name,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: AppSpacing.sm),
            _RollPill(group: group, attendance: attendance),
            if (ratio != null) ...[
              const SizedBox(width: AppSpacing.xs),
              _RatioChip(ratio: ratio!),
            ],
            if (subtitle.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  '· $subtitle',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const Spacer(),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              color: theme.colorScheme.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  /// Collapsed subtitle — what's happening in this group right now.
  /// "Art Rotation · ends 10:45" / "Free block · Outdoor Play @ 11:00".
  /// Empty string when nothing interesting is happening (no current,
  /// no imminent next-up); header falls back to just the group name.
  String _subtitle() {
    final c = current;
    if (c == null) return '';
    final nowMinutes = now.hour * 60 + now.minute;
    final minsLeft = c.endMinutes - nowMinutes;
    final ends = minsLeft <= 1
        ? 'ending now'
        : minsLeft <= 30
            ? 'ends in $minsLeft min'
            : 'ends ${_short(c.endTime)}';
    return '${c.title} · $ends';
  }

  String _short(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final period = h >= 12 ? 'PM' : 'AM';
    return '$hour12:${m.toString().padLeft(2, '0')} $period';
  }
}

/// Color dot pulled from the group's optional `colorHex`. Falls back
/// to the theme primary when the group hasn't been tinted yet — keeps
/// the row balanced instead of missing the leading visual anchor.
class _GroupDot extends StatelessWidget {
  const _GroupDot({required this.colorHex});

  final String? colorHex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _parseHex(colorHex) ?? theme.colorScheme.primary;
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
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

/// Compact "12/14" pill with color based on attendance completeness.
/// Quiet neutral when all settled, amber hint when kids are still
/// pending (haven't been checked in yet and it's past opening). Total
/// child count alone is shown for groups with no attendance yet.
class _RollPill extends StatelessWidget {
  const _RollPill({required this.group, required this.attendance});

  final GroupSummary group;
  final AttendanceSummary? attendance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = attendance;
    final (label, bg, fg) = a == null
        ? (
            '${group.childCount} kids',
            theme.colorScheme.surfaceContainerHighest,
            theme.colorScheme.onSurfaceVariant,
          )
        : (
            '${a.present}/${a.total}',
            a.allSettled
                ? theme.colorScheme.secondaryContainer
                : theme.colorScheme.tertiaryContainer,
            a.allSettled
                ? theme.colorScheme.onSecondaryContainer
                : theme.colorScheme.onTertiaryContainer,
          );
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

/// Compact chip showing the current kids:adults ratio for this
/// group. Quiet `secondaryContainer` tint when we're inside the
/// threshold; flips to `errorContainer` with a warning icon and
/// "UNDER RATIO" suffix when we're over. Computation lives in
/// `ratio_check.dart` — this widget just paints the result.
class _RatioChip extends StatelessWidget {
  const _RatioChip({required this.ratio});

  final GroupRatioNow ratio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final underRatio = ratio.isUnderRatio;
    final bg = underRatio
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.secondaryContainer;
    final fg = underRatio
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSecondaryContainer;
    final label =
        underRatio ? '${ratio.display} · UNDER RATIO' : ratio.display;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (underRatio) ...[
            Icon(
              Icons.warning_amber_rounded,
              size: 12,
              color: fg,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The unfolded content under an expanded group card. Holds the NOW
/// slot, the up-next line, and the staffing row.
class _ExpandedBody extends StatelessWidget {
  const _ExpandedBody({
    required this.group,
    required this.now,
    required this.current,
    required this.next,
    required this.attendance,
    required this.leadsNow,
    required this.onOpenDetail,
    required this.onOpenAttendance,
    required this.onOpenGroupDetail,
  });

  final GroupSummary group;
  final DateTime now;
  final ScheduleItem? current;
  final ScheduleItem? next;
  final AttendanceSummary? attendance;
  final List<Adult> leadsNow;
  final ValueChanged<ScheduleItem> onOpenDetail;
  final ValueChanged<ScheduleItem> onOpenAttendance;
  final VoidCallback onOpenGroupDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (current != null)
            _NowSlot(
              item: current!,
              now: now,
              attendance: attendance,
              onTap: () => onOpenDetail(current!),
              onOpenAttendance: () => onOpenAttendance(current!),
            )
          else
            _IdleSlot(group: group),
          if (next != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _NextUpLine(
              item: next!,
              now: now,
              onTap: () => onOpenDetail(next!),
            ),
          ],
          if (leadsNow.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'LEADS NOW',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            _LeadsRow(leads: leadsNow),
          ],
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onOpenGroupDetail,
              icon: const Icon(Icons.open_in_new, size: 14),
              label: const Text('Open group'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "NOW" tile inside an expanded group — title + time + room + tap-to-
/// open-detail. Shrinks the hero NOW card down to something that fits
/// multiple times on a mobile screen.
class _NowSlot extends StatelessWidget {
  const _NowSlot({
    required this.item,
    required this.now,
    required this.attendance,
    required this.onTap,
    required this.onOpenAttendance,
  });

  final ScheduleItem item;
  final DateTime now;
  final AttendanceSummary? attendance;
  final VoidCallback onTap;
  final VoidCallback onOpenAttendance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nowMinutes = now.hour * 60 + now.minute;
    final minsLeft = item.endMinutes - nowMinutes;
    final endLabel = minsLeft <= 1
        ? 'ending now'
        : minsLeft <= 30
            ? 'ends in $minsLeft min'
            : '${_fmt12h(item.endTime)} end';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'NOW',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    endLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer
                          .withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              item.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            if (item.location != null && item.location!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  item.location!.trim(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer
                        .withValues(alpha: 0.8),
                  ),
                ),
              ),
            if (attendance != null) ...[
              const SizedBox(height: AppSpacing.sm),
              InkWell(
                onTap: onOpenAttendance,
                child: Row(
                  children: [
                    Icon(
                      Icons.how_to_reg_outlined,
                      size: 14,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${attendance!.present}/${attendance!.total} present'
                      '${attendance!.pending > 0 ? " · ${attendance!.pending} pending" : ""}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
    final period = h >= 12 ? 'PM' : 'AM';
    return '$hour12:${m.toString().padLeft(2, '0')} $period';
  }
}

/// Shown in place of the NOW tile when this group has nothing
/// scheduled right now — keeps the expanded card from feeling empty
/// and tells the teacher explicitly "you're between things, next up
/// is …"
class _IdleSlot extends StatelessWidget {
  const _IdleSlot({required this.group});

  final GroupSummary group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            Icons.hourglass_empty,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Nothing scheduled for ${group.name} right now.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact one-line "Next: Outdoor Play @ 11:00 · in 15 min" row under
/// the NOW tile. Tapping opens the activity's detail sheet — same as
/// tapping any schedule card on Today.
class _NextUpLine extends StatelessWidget {
  const _NextUpLine({
    required this.item,
    required this.now,
    required this.onTap,
  });

  final ScheduleItem item;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nowMinutes = now.hour * 60 + now.minute;
    final minsAway = item.startMinutes - nowMinutes;
    final awayLabel = minsAway <= 0
        ? 'starting now'
        : minsAway <= 60
            ? 'in $minsAway min'
            : '@ ${_fmt12h(item.startTime)}';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              Icons.east,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Next: ',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
              ),
            ),
            Expanded(
              child: Text(
                '${item.title} · $awayLabel',
                style: theme.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
    final period = h >= 12 ? 'PM' : 'AM';
    return '$hour12:${m.toString().padLeft(2, '0')} $period';
  }
}

/// Avatar + name row for the group's anchor leads. Shown only when
/// the group has at least one lead assigned (a just-seeded group can
/// legally have zero).
class _LeadsRow extends StatelessWidget {
  const _LeadsRow({required this.leads});

  final List<Adult> leads;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: [
        for (final s in leads)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SmallAvatar(
                path: s.avatarPath,
                storagePath: s.avatarStoragePath,
                etag: s.avatarEtag,
                fallbackInitial: s.name.isNotEmpty
                    ? s.name.characters.first.toUpperCase()
                    : '?',
                radius: 14,
                backgroundColor: theme.colorScheme.secondaryContainer,
                foregroundColor: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(s.name, style: theme.textTheme.bodyMedium),
            ],
          ),
      ],
    );
  }
}
