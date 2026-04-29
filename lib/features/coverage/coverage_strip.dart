import 'package:basecamp/features/adults/role_blocks_repository.dart';
import 'package:basecamp/features/coverage/coverage_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Horizontal coverage strip for the Today screen. One row per
/// classroom (in the active program), showing how many adults
/// are scheduled to be in that room *right now* per the v48
/// role-block tables. Tap "Show day" to expand into a full-day
/// timeline that visualizes coverage every 30 minutes from
/// 7am to 6pm — useful for spotting gaps before they happen.
///
/// Slice 2 is informational only — no validation pop-ups, no
/// "must have 2" enforcement. The user said coverage is a
/// preference, not a rule. The dot count makes "I'm short here"
/// visible at a glance without being prescriptive.
class CoverageStrip extends ConsumerStatefulWidget {
  const CoverageStrip({super.key});

  @override
  ConsumerState<CoverageStrip> createState() => _CoverageStripState();
}

class _CoverageStripState extends ConsumerState<CoverageStrip> {
  bool _showDay = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coverageAsync = ref.watch(coverageNowProvider);
    final clockLabel = DateFormat.jm().format(DateTime.now());
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Coverage now',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                clockLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Who the day-plan says is in each classroom right '
            'now. Tap "Show day" for a full-day view.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          coverageAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => Text('Couldn’t load coverage: $err'),
            data: (groups) {
              if (groups.isEmpty) {
                return Text(
                  'No groups yet. Add classrooms in '
                  'Children & groups.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              }
              return Column(
                children: [
                  for (final g in groups) _CoverageRow(group: g),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => ref.invalidate(coverageNowProvider),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _showDay = !_showDay),
                icon: Icon(
                  _showDay
                      ? Icons.unfold_less
                      : Icons.unfold_more,
                  size: 16,
                ),
                label: Text(_showDay ? 'Hide day' : 'Show day'),
              ),
            ],
          ),
          if (_showDay) ...[
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            const _DayCoverageTimeline(),
          ],
        ],
      ),
    );
  }
}

class _CoverageRow extends StatelessWidget {
  const _CoverageRow({required this.group});

  final GroupCoverage group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = _toneFor(theme, group.count);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group name column — fixed-width so the dot column
          // lines up across rows.
          SizedBox(
            width: 96,
            child: Text(
              group.groupName,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Two-dot indicator — capped at 2 visible dots even
          // when more than 2 adults are in the room (3rd+ get
          // a "+N" suffix). Two is the conventional baseline;
          // overflow is a flex that still reads clearly.
          _DotIndicator(count: group.count, tone: tone),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.count == 0 ? 'empty' : '${group.count} in room',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (group.adults.isNotEmpty)
                  Text(
                    _adultsLabel(group.adults),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Tone:
  ///   * 0 → grey (no one assigned).
  ///   * 1 → amber (under typical 2-per-room).
  ///   * 2+ → primary (covered).
  Color _toneFor(ThemeData theme, int count) {
    if (count == 0) return theme.colorScheme.outline;
    if (count == 1) return theme.colorScheme.tertiary;
    return theme.colorScheme.primary;
  }

  /// "Sarah · Maria S." — comma-joined names with a specialist
  /// flag if any of them is a specialist (so the user can see
  /// "the second person here is the visiting Art teacher").
  String _adultsLabel(List<CoverageAdult> adults) {
    final parts = <String>[];
    for (final a in adults) {
      final tag = a.kind == RoleBlockKind.specialist ? ' (specialist)' :
                  a.kind == RoleBlockKind.sub ? ' (sub)' : '';
      parts.add('${a.name}$tag');
    }
    return parts.join(' · ');
  }
}

class _DotIndicator extends StatelessWidget {
  const _DotIndicator({required this.count, required this.tone});

  final int count;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filled = count.clamp(0, 2);
    final empty = 2 - filled;
    final overflow = count > 2 ? count - 2 : 0;
    return Row(
      children: [
        for (var i = 0; i < filled; i++) ...[
          _Dot(color: tone),
          if (i < filled - 1) const SizedBox(width: 3),
        ],
        if (filled > 0 && empty > 0) const SizedBox(width: 3),
        for (var i = 0; i < empty; i++) ...[
          _Dot(color: theme.colorScheme.outline.withValues(alpha: 0.4)),
          if (i < empty - 1) const SizedBox(width: 3),
        ],
        if (overflow > 0) ...[
          const SizedBox(width: 4),
          Text(
            '+$overflow',
            style: theme.textTheme.labelSmall?.copyWith(color: tone),
          ),
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Full-day coverage view: a heat-strip per classroom showing
/// every 30-minute slot's adult count. Color-coded the same way
/// the "right now" strip is — primary for ≥2, tertiary for 1,
/// outline for 0. Hovering / tapping a cell could surface the
/// names; for slice 2 we keep it visual-only.
///
/// Layout:
///                    07  08  09  10  11  12  13  14  15  16  17
///   Lions   ┃ ▓▓ ▓▓ ▓▓ ░░ ▓▓ ▓▓ ▓▓ ▓▓ ▓▓ ▓▓ ▓▓ ┃
///   Bears   ┃ ▓▓ ▓▓ ░░ ▓▓ ▓▓ ▓▓ ▓▓ ▓▓ ▓▓ ▓▓ ▓▓ ┃
///   Cubs    ┃ ░░ ▓▓ ▓▓ ▓▓ ▓▓ ▓▓ ▓▓ ▓▓ ▓▓ ▓▓ ░░ ┃
///
/// Each cell is one sample; 30-min granularity. Vertical line
/// marks "now" so the user can see what's coming up.
class _DayCoverageTimeline extends ConsumerWidget {
  const _DayCoverageTimeline();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dayAsync = ref.watch(coverageDayProvider);
    return dayAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Text('Day timeline error: $err'),
      data: (day) {
        if (day.groups.isEmpty) {
          return Text(
            'No coverage data for today.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }
        final now = DateTime.now();
        final nowMinute = now.hour * 60 + now.minute;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HourLabels(day: day),
              const SizedBox(height: 4),
              for (final g in day.groups) ...[
                _GroupTimelineRow(
                  timeline: g,
                  day: day,
                  nowMinute: nowMinute,
                ),
                const SizedBox(height: 4),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HourLabels extends StatelessWidget {
  const _HourLabels({required this.day});

  final DayCoverage day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // One label per hour (every 2 cells when stepMinutes = 30).
    const cellWidth = 24.0;
    final cellsPerHour = 60 ~/ day.stepMinutes;
    final hours = <Widget>[
      const SizedBox(width: 96), // matches the group-name column
    ];
    for (var m = day.startMinute; m <= day.endMinute; m += 60) {
      final h = m ~/ 60;
      final h12 = h % 12 == 0 ? 12 : h % 12;
      hours.add(SizedBox(
        width: cellWidth * cellsPerHour,
        child: Text(
          '$h12',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ));
    }
    return Row(children: hours);
  }
}

class _GroupTimelineRow extends StatelessWidget {
  const _GroupTimelineRow({
    required this.timeline,
    required this.day,
    required this.nowMinute,
  });

  final GroupCoverageTimeline timeline;
  final DayCoverage day;
  final int nowMinute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const cellWidth = 24.0;
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            timeline.groupName,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        for (final s in timeline.samples)
          _CoverageCell(
            sample: s,
            width: cellWidth,
            isNow: nowMinute >= s.minuteOfDay &&
                nowMinute < s.minuteOfDay + day.stepMinutes,
          ),
      ],
    );
  }
}

class _CoverageCell extends StatelessWidget {
  const _CoverageCell({
    required this.sample,
    required this.width,
    required this.isNow,
  });

  final CoverageSample sample;
  final double width;
  final bool isNow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = sample.count == 0
        ? theme.colorScheme.outline.withValues(alpha: 0.25)
        : sample.count == 1
            ? theme.colorScheme.tertiary.withValues(alpha: 0.7)
            : theme.colorScheme.primary;
    return Tooltip(
      message: '${sample.count} adult'
          '${sample.count == 1 ? '' : 's'}'
          ' · ${_fmtMinute(sample.minuteOfDay)}',
      child: Container(
        width: width - 2,
        height: 18,
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
          border: isNow
              ? Border.all(
                  color: theme.colorScheme.onSurface,
                  width: 1.5,
                )
              : null,
        ),
        alignment: Alignment.center,
        child: sample.count >= 1
            ? Text(
                '${sample.count}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.surface,
                  fontWeight: FontWeight.w700,
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  static String _fmtMinute(int m) {
    final h = m ~/ 60;
    final mm = m % 60;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    final ampm = h >= 12 ? 'pm' : 'am';
    if (mm == 0) return '$h12 $ampm';
    return '$h12:${mm.toString().padLeft(2, '0')} $ampm';
  }
}
