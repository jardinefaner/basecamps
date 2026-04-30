import 'package:basecamp/core/format/text.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adult_timeline_repository.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/schedule/week_days.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Whole-program adult timeline — one row per adult, horizontal time
/// axis, blocks rendered for each adult's day. Read-only for now;
/// edits still go through the per-adult timeline sheet. Good for
/// answering "who's covering Ladybugs at 2pm?" in one glance without
/// tapping through six adult detail pages.
///
/// Selectable weekday at the top defaults to today. Break + lunch
/// overlay on top of role blocks, not inside them, so a "adult
/// 11-12 with lunch 11:30-12" block reads as "rotating 11-11:30, at
/// lunch 11:30-12" without duplicating the data.
class ProgramTimelineScreen extends ConsumerStatefulWidget {
  const ProgramTimelineScreen({super.key});

  @override
  ConsumerState<ProgramTimelineScreen> createState() =>
      _ProgramTimelineScreenState();
}

class _ProgramTimelineScreenState
    extends ConsumerState<ProgramTimelineScreen> {
  /// Window the timeline grid covers, in minutes-from-midnight.
  /// 7am–7pm matches the practical open-hours most programs run; rows
  /// outside the window get clamped at the edge with an ellipsis.
  static const int _startMin = 7 * 60;
  static const int _endMin = 19 * 60;
  static const int _windowMin = _endMin - _startMin;

  /// Width reserved for the leading adult-name column.
  static const double _nameColWidth = 110;

  /// Per-row height, including vertical padding.
  static const double _rowHeight = 56;

  late int _day = _todayWeekday();

  static int _todayWeekday() {
    final w = DateTime.now().weekday;
    // Clamp to Mon–Fri; a teacher opening the screen on a Saturday
    // sees Monday rather than an empty blank.
    return (w >= 1 && w <= 5) ? w : 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final adultsAsync = ref.watch(adultsProvider);
    final blocksAsync = ref.watch(
      _blocksForDayProvider(_day),
    );
    final availabilityAsync = ref.watch(allAvailabilityProvider);
    final groups =
        ref.watch(groupsProvider).asData?.value ?? const <Group>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Program timeline'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DaySelector(
            day: _day,
            onChanged: (d) => setState(() => _day = d),
          ),
          const Divider(height: 1),
          Expanded(
            child: _buildBody(
              theme,
              adultsAsync,
              blocksAsync,
              availabilityAsync,
              groups,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    AsyncValue<List<Adult>> adultsAsync,
    AsyncValue<List<AdultDayBlock>> blocksAsync,
    AsyncValue<List<AdultAvailabilityData>> availabilityAsync,
    List<Group> groups,
  ) {
    if (adultsAsync.hasError) {
      return Center(child: Text('Error: ${adultsAsync.error}'));
    }
    final adults = adultsAsync.asData?.value;
    if (adults == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (adults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: Text(
            'No adults on file yet. Add one from the Adults screen.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final blocks = blocksAsync.asData?.value ?? const <AdultDayBlock>[];
    final availability =
        availabilityAsync.asData?.value ?? const <AdultAvailabilityData>[];

    // Index by adult for O(n) row build.
    final blocksByAdult = <String, List<AdultDayBlock>>{};
    for (final b in blocks) {
      (blocksByAdult[b.adultId] ??= []).add(b);
    }
    final availByAdult = <String, AdultAvailabilityData?>{};
    for (final a in availability) {
      if (a.dayOfWeek != _day) continue;
      availByAdult[a.adultId] = a;
    }
    final groupsById = {for (final g in groups) g.id: g};

    final isTodaySelected = DateTime.now().weekday == _day;
    final nowMin = isTodaySelected
        ? DateTime.now().hour * 60 + DateTime.now().minute
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth - _nameColWidth;
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HourAxis(trackWidth: trackWidth),
              for (final s in adults)
                _AdultRow(
                  adult: s,
                  blocks: blocksByAdult[s.id] ?? const [],
                  availability: availByAdult[s.id],
                  groupsById: groupsById,
                  trackWidth: trackWidth,
                  nowMin: nowMin,
                  onTap: () =>
                      context.push('/more/adults/${s.id}'),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Per-day override of [todayAdultBlocksProvider] — the main provider
/// is hardwired to "today's weekday" so this screen's day picker
/// needs its own family variant.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final _blocksForDayProvider =
    StreamProvider.family<List<AdultDayBlock>, int>((ref, dayOfWeek) {
  final repo = ref.watch(adultTimelineRepositoryProvider);
  return repo.watchBlocksForDay(dayOfWeek);
});

/// Mon–Fri chip row at the top. Selected day controls the whole
/// grid below.
class _DaySelector extends StatelessWidget {
  const _DaySelector({required this.day, required this.onChanged});

  final int day;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        children: [
          for (final d in scheduleDayValues)
            ChoiceChip(
              label: Text(scheduleDayShortLabels[d - 1]),
              selected: d == day,
              onSelected: (_) => onChanged(d),
            ),
        ],
      ),
    );
  }
}

/// Hour labels + tick marks above the grid. Sits inside the scrollable
/// body so it scrolls with content when the page grows past the fold.
class _HourAxis extends StatelessWidget {
  const _HourAxis({required this.trackWidth});

  final double trackWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 7, 8, …, 19 — 13 tick positions → 12 hour slots. We only draw
    // labels at each integer hour so the axis doesn't shout.
    final hours = <int>[
      for (var h = 7; h <= 19; h++) h,
    ];
    return SizedBox(
      height: 24,
      child: Row(
        children: [
          const SizedBox(width: _ProgramTimelineScreenState._nameColWidth),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final h in hours)
                      Positioned(
                        left: _timeX(h * 60, c.maxWidth) - 1,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 1,
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                    for (final h in hours)
                      Positioned(
                        left: _timeX(h * 60, c.maxWidth) - 12,
                        bottom: 0,
                        child: SizedBox(
                          width: 24,
                          child: Text(
                            _fmtHour(h),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _fmtHour(int h) {
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final period = h >= 12 ? 'p' : 'a';
    return '$h12$period';
  }
}

/// Single adult row — name column + time track. Renders shift bounds
/// (availability) as a subtle band, timeline blocks as colored bars,
/// and break/lunch windows as hatched overlays.
class _AdultRow extends StatelessWidget {
  const _AdultRow({
    required this.adult,
    required this.blocks,
    required this.availability,
    required this.groupsById,
    required this.trackWidth,
    required this.nowMin,
    required this.onTap,
  });

  final Adult adult;
  final List<AdultDayBlock> blocks;
  final AdultAvailabilityData? availability;
  final Map<String, Group> groupsById;
  final double trackWidth;
  final int? nowMin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shiftStart = availability == null
        ? null
        : _parseHHmm(availability!.startTime);
    final shiftEnd = availability == null
        ? null
        : _parseHHmm(availability!.endTime);

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: _ProgramTimelineScreenState._rowHeight,
        child: Row(
          children: [
            SizedBox(
              width: _ProgramTimelineScreenState._nameColWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    SmallAvatar(
                      path: adult.avatarPath,
                      storagePath: adult.avatarStoragePath,
                      etag: adult.avatarEtag,
                      fallbackInitial: adult.name.initial,
                      radius: 12,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        adult.name,
                        style: theme.textTheme.labelMedium,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  // Shift band — subtle background showing when this
                  // adult is at work. Falls through to "no shift" for
                  // adults without an availability row for this day.
                  if (shiftStart != null && shiftEnd != null)
                    _Band(
                      startMin: shiftStart,
                      endMin: shiftEnd,
                      trackWidth: trackWidth,
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: 6,
                    ),
                  // Timeline role blocks. Gaps are implied off, so we
                  // just render what's there.
                  for (final b in blocks) _roleBlock(theme, b),
                  // Break 1 + break 2 + lunch overlays on top of
                  // whatever block they fall inside.
                  if (availability?.breakStart != null &&
                      availability?.breakEnd != null)
                    _BreakOverlay(
                      startMin: _parseHHmm(availability!.breakStart!),
                      endMin: _parseHHmm(availability!.breakEnd!),
                      trackWidth: trackWidth,
                      label: 'Break',
                      color: theme.colorScheme.tertiaryContainer,
                    ),
                  if (availability?.break2Start != null &&
                      availability?.break2End != null)
                    _BreakOverlay(
                      startMin: _parseHHmm(availability!.break2Start!),
                      endMin: _parseHHmm(availability!.break2End!),
                      trackWidth: trackWidth,
                      label: 'Break',
                      color: theme.colorScheme.tertiaryContainer,
                    ),
                  if (availability?.lunchStart != null &&
                      availability?.lunchEnd != null)
                    _BreakOverlay(
                      startMin: _parseHHmm(availability!.lunchStart!),
                      endMin: _parseHHmm(availability!.lunchEnd!),
                      trackWidth: trackWidth,
                      label: 'Lunch',
                      color: theme.colorScheme.secondaryContainer,
                    ),
                  // Now line — only when the selected day is today.
                  if (nowMin != null &&
                      nowMin! >= _ProgramTimelineScreenState._startMin &&
                      nowMin! <= _ProgramTimelineScreenState._endMin)
                    Positioned(
                      left: _timeX(nowMin!, trackWidth) - 1,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleBlock(ThemeData theme, AdultDayBlock b) {
    final start = _parseHHmm(b.startTime);
    final end = _parseHHmm(b.endTime);
    final role = AdultBlockRole.fromDb(b.role);
    Color bg;
    Color fg;
    String label;
    if (role == AdultBlockRole.lead) {
      final g = b.groupId == null ? null : groupsById[b.groupId];
      final groupColor = _parseGroupHex(g?.colorHex);
      bg = groupColor ?? theme.colorScheme.primary;
      fg = _onColorFor(bg);
      label = g?.name ?? 'Lead';
    } else {
      bg = theme.colorScheme.tertiary;
      fg = theme.colorScheme.onTertiary;
      label = 'Specialist';
    }
    return _Band(
      startMin: start,
      endMin: end,
      trackWidth: trackWidth,
      color: bg,
      label: label,
      labelColor: fg,
      borderRadius: 6,
    );
  }

  Color _onColorFor(Color bg) {
    // Cheap luminance check — good enough for the ~10 group swatches
    // we offer. Full WCAG contrast isn't needed; we just need "light
    // text on dark, dark text on light."
    final luminance = bg.computeLuminance();
    return luminance > 0.55 ? Colors.black : Colors.white;
  }

  Color? _parseGroupHex(String? hex) {
    if (hex == null) return null;
    final h = hex.startsWith('#') ? hex.substring(1) : hex;
    if (h.length != 6 && h.length != 8) return null;
    final intVal = int.tryParse(h, radix: 16);
    if (intVal == null) return null;
    return Color(h.length == 6 ? 0xFF000000 | intVal : intVal);
  }
}

/// Positioned-in-track rectangle. Centralizes the left/width math so
/// every block / shift band / overlay uses the same projection.
class _Band extends StatelessWidget {
  const _Band({
    required this.startMin,
    required this.endMin,
    required this.trackWidth,
    required this.color,
    this.label,
    this.labelColor,
    this.borderRadius = 4,
  });

  final int startMin;
  final int endMin;
  final double trackWidth;
  final Color color;
  final String? label;
  final Color? labelColor;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final left = _timeX(startMin, trackWidth);
    final right = _timeX(endMin, trackWidth);
    final width = (right - left).clamp(0.0, trackWidth);
    if (width <= 0) return const SizedBox.shrink();
    return Positioned(
      left: left,
      top: 6,
      bottom: 6,
      width: width,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: label == null || width < 40
            ? null
            : Text(
                label!,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
      ),
    );
  }
}

/// Hatched pill overlaying a break / lunch window on top of whatever
/// block sits underneath. Keeps the role block readable (you can see
/// what kind of block the break is interrupting) while marking the
/// span as off-duty.
class _BreakOverlay extends StatelessWidget {
  const _BreakOverlay({
    required this.startMin,
    required this.endMin,
    required this.trackWidth,
    required this.color,
    required this.label,
  });

  final int startMin;
  final int endMin;
  final double trackWidth;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final left = _timeX(startMin, trackWidth);
    final right = _timeX(endMin, trackWidth);
    final width = (right - left).clamp(0.0, trackWidth);
    if (width <= 0) return const SizedBox.shrink();
    return Positioned(
      left: left,
      top: 14,
      bottom: 14,
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: width < 40
              ? null
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Projects a minute-of-day onto the track's horizontal extent, with
/// clamping so blocks straddling the visible window don't overflow.
double _timeX(int minute, double trackWidth) {
  final clamped = minute.clamp(
    _ProgramTimelineScreenState._startMin,
    _ProgramTimelineScreenState._endMin,
  );
  final offset = clamped - _ProgramTimelineScreenState._startMin;
  return (offset / _ProgramTimelineScreenState._windowMin) * trackWidth;
}

int _parseHHmm(String hhmm) {
  final parts = hhmm.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}
