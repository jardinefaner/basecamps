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
/// role-block tables.
///
/// Visual:
///   Lions    ●● 2 in room   Sarah, Maria S.
///   Bears    ●○ 1 in room   Marcus K.       ← amber dot
///   Cubs     ○○ empty                       ← grey dot
///
/// Slice 2 is informational only — no validation pop-ups, no
/// "must have 2" enforcement. The user said coverage is a
/// preference, not a rule. The dot count makes "I'm short here"
/// visible at a glance without being prescriptive.
class CoverageStrip extends ConsumerWidget {
  const CoverageStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final coverageAsync = ref.watch(coverageNowProvider);
    final clockLabel =
        DateFormat.jm().format(DateTime.now()); // "9:42 AM"
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
            'now. Tap "Refresh" to recheck.',
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
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => ref.invalidate(coverageNowProvider),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
            ),
          ),
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
