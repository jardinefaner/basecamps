import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

/// End-of-day close-out prompt. Shows in a short window around program
/// close (the latest endTime of today's timed schedule items) so the
/// teacher can sweep up pending observations, draft forms, and any
/// unsigned concern notes before walking out. Outside that window the
/// strip hides itself.
///
/// Kept intentionally dumb: the parent computes counts + visibility
/// (via [shouldShowCloseOutStrip]) and passes them in. This widget just
/// lays out the four possible rows and wires taps back to the parent.
///
/// TODO: promote the 60-minute lead-in to ProgramSettings so programs
/// that wrap up gradually can stretch the window.
const int _closeOutLeadMinutes = 60;

/// After close, keep the strip up for this long so the teacher who
/// checks Today on the way out the door still sees the checklist.
const int _closeOutTrailMinutes = 30;

/// When the program closes today, based on the max endTime minute of
/// all timed (non-full-day) schedule items. Returns null when there
/// are no timed items — the close-out strip can't anchor to a time it
/// doesn't have.
int? closeOfProgramMinutes(List<int> timedEndMinutes) {
  if (timedEndMinutes.isEmpty) return null;
  var maxEnd = timedEndMinutes.first;
  for (final m in timedEndMinutes) {
    if (m > maxEnd) maxEnd = m;
  }
  return maxEnd;
}

/// Should the strip render right now? Rules:
///   1. Hide before noon (covers all-day programs that start/end
///      before most of the close-out signal exists).
///   2. Hide if there's no computable close time (no timed items).
///   3. Show in `[close - 60min, close + 30min]`. Outside that, hide.
bool shouldShowCloseOutStrip({
  required int nowMinutes,
  required int? closeMinutes,
}) {
  const noonMinutes = 12 * 60;
  if (nowMinutes < noonMinutes) return false;
  if (closeMinutes == null) return false;
  final start = closeMinutes - _closeOutLeadMinutes;
  final end = closeMinutes + _closeOutTrailMinutes;
  return nowMinutes >= start && nowMinutes <= end;
}

/// Pure shape-carrier for the strip's inputs. Makes the widget a
/// plain `StatelessWidget` — no provider watches, no ref.
class CloseOutCounts {
  const CloseOutCounts({
    required this.pendingObs,
    required this.draftForms,
    required this.unsignedConcerns,
  });

  /// Past activities with zero observations logged today.
  final int pendingObs;

  /// Forms whose status is still `draft`.
  final int draftForms;

  /// Concern notes without a supervisor signature yet.
  final int unsignedConcerns;

  int get total => pendingObs + draftForms + unsignedConcerns;
  bool get allCaughtUp => total == 0;
}

class CloseOutStrip extends StatelessWidget {
  const CloseOutStrip({
    required this.counts,
    required this.onTapPendingObs,
    required this.onTapDraftForms,
    required this.onTapUnsignedConcerns,
    super.key,
  });

  final CloseOutCounts counts;
  final VoidCallback onTapPendingObs;
  final VoidCallback onTapDraftForms;
  final VoidCallback onTapUnsignedConcerns;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Muted container — this strip nudges, it doesn't demand
    // attention. Red/error tints would compete with genuinely
    // urgent lateness flags that sit nearby.
    final bg = theme.colorScheme.surfaceContainerLow;
    final border = theme.colorScheme.outlineVariant;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.checklist_rtl,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Close out the day',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (counts.allCaughtUp)
            _CaughtUpRow()
          else ...[
            if (counts.pendingObs > 0)
              _CountRow(
                icon: Icons.edit_note_outlined,
                label: counts.pendingObs == 1
                    ? '1 past activity missing observations'
                    : '${counts.pendingObs} past activities missing observations',
                onTap: onTapPendingObs,
              ),
            if (counts.draftForms > 0)
              _CountRow(
                icon: Icons.assignment_outlined,
                label: counts.draftForms == 1
                    ? '1 draft form submission'
                    : '${counts.draftForms} draft form submissions',
                onTap: onTapDraftForms,
              ),
            if (counts.unsignedConcerns > 0)
              _CountRow(
                icon: Icons.edit_outlined,
                label: counts.unsignedConcerns == 1
                    ? '1 unsigned concern note'
                    : '${counts.unsignedConcerns} unsigned concern notes',
                onTap: onTapUnsignedConcerns,
              ),
          ],
        ],
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 6,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _CaughtUpRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 6,
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 14,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            "You're all caught up",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
