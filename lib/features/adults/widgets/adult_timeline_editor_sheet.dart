import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adult_timeline_repository.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/schedule/week_days.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Per-adult day-timeline editor. Opens from the adult edit sheet
/// for adults whose day is more complicated than "adult all
/// day" or "lead anchored to group X" — lets them mark out "lead
/// Butterflies 8:30-11, adult rotator 11-12, back to
/// Butterflies 12-3."
///
/// Gaps between blocks are implied off. Break + lunch stay on the
/// shift availability row and overlay on top of the timeline — not
/// tracked here to keep the editor single-purpose.
///
/// Save = atomic replace: the sheet builds a full in-memory block
/// list and calls [AdultTimelineRepository.replaceBlocks], matching
/// how the availability editor saves.
class AdultTimelineEditorSheet extends ConsumerStatefulWidget {
  const AdultTimelineEditorSheet({
    required this.adultId,
    required this.adultName,
    this.initialBlocks = const [],
    super.key,
  });

  final String adultId;
  final String adultName;

  /// Existing blocks when the sheet opens (so edits start from what's
  /// already saved). Empty = new timeline.
  final List<AdultTimelineBlock> initialBlocks;

  @override
  ConsumerState<AdultTimelineEditorSheet> createState() =>
      _AdultTimelineEditorSheetState();
}

class _AdultTimelineEditorSheetState
    extends ConsumerState<AdultTimelineEditorSheet> {
  /// Per-day state — list of all blocks across every day. Used when
  /// the teacher is on the per-day tab; also fed back on save when
  /// [_uniformMode] is false.
  late final List<_EditableBlock> _blocks;

  /// Uniform state — a single "template" block list that applies
  /// across every day in [_uniformDays]. Used when the teacher has
  /// turned on "Same schedule every day." All template blocks
  /// live under dayOfWeek = 1 (Monday) as the canonical slot; save
  /// fans them out across the picked days.
  late final List<_EditableBlock> _uniformTemplate;
  late final Set<int> _uniformDays;

  /// Which tab the editor is showing. Defaults on load:
  ///   - ON  when every day that has blocks has the *same* set of
  ///         blocks (shape-equal). That's the "I set it up uniform
  ///         last time" case — respect it.
  ///   - OFF when days diverge (different hours, different roles,
  ///         different group picks, or uneven block counts).
  late bool _uniformMode;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final all = [
      for (final b in widget.initialBlocks) _EditableBlock.fromDomain(b),
    ];
    final detected = _detectUniform(all);
    _blocks = all;
    _uniformTemplate = detected.template;
    _uniformDays = detected.days;
    _uniformMode = detected.uniform;
  }

  Future<void> _save() async {
    setState(() => _submitting = true);
    try {
      // Resolve the to-save set depending on the active mode.
      //   Uniform: expand the template across every picked day.
      //   Per-day: write _blocks as they stand.
      final draft = _uniformMode
          ? _expandUniform()
          : _blocks;
      // Drop any half-configured row (blank time range) rather than
      // refusing the save — teacher probably added a placeholder and
      // then tapped Save without filling it in.
      final clean = draft
          .where((b) =>
              b.startTime != null &&
              b.endTime != null &&
              b.endTime!.toMinutes() > b.startTime!.toMinutes())
          .toList();
      final domain = [
        for (final b in clean)
          AdultTimelineBlock(
            dayOfWeek: b.dayOfWeek,
            startTime: b.startTime!.hhmm(),
            endTime: b.endTime!.hhmm(),
            role: b.role,
            // Non-lead blocks drop any leftover groupId — a adult
            // block never anchors a group regardless of what picker
            // state the editor might have cached.
            groupId: b.role == AdultBlockRole.lead ? b.groupId : null,
          ),
      ];
      await ref.read(adultTimelineRepositoryProvider).replaceBlocks(
            adultId: widget.adultId,
            blocks: domain,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Takes the template + picked-days set and fans it out into one
  /// block per (template entry × day). Consumed at save time in
  /// uniform mode.
  List<_EditableBlock> _expandUniform() {
    final out = <_EditableBlock>[];
    for (final d in _uniformDays) {
      for (final t in _uniformTemplate) {
        out.add(
          _EditableBlock(
            dayOfWeek: d,
            startTime: t.startTime,
            endTime: t.endTime,
            role: t.role,
            groupId: t.groupId,
          ),
        );
      }
    }
    return out;
  }

  /// Toggle the uniform switch. When turning ON, seed the template
  /// from the per-day state (first day with blocks) so the teacher
  /// doesn't lose what they've typed. When turning OFF, fan out the
  /// template across the picked days and drop into [_blocks].
  void _setUniformMode({required bool on}) {
    setState(() {
      if (on) {
        // Seed template from the first day that has anything, else
        // start fresh on M–F with no blocks.
        final byDay = <int, List<_EditableBlock>>{};
        for (final b in _blocks) {
          (byDay[b.dayOfWeek] ??= []).add(b);
        }
        if (byDay.isNotEmpty) {
          final daysSorted = byDay.keys.toList()..sort();
          final refDay = daysSorted.first;
          _uniformTemplate
            ..clear()
            ..addAll([
              for (final b in byDay[refDay]!)
                _EditableBlock(
                  dayOfWeek: 1,
                  startTime: b.startTime,
                  endTime: b.endTime,
                  role: b.role,
                  groupId: b.groupId,
                ),
            ]);
          _uniformDays
            ..clear()
            ..addAll(byDay.keys);
        } else {
          _uniformDays
            ..clear()
            ..addAll({1, 2, 3, 4, 5});
        }
      } else {
        // Turning off: hydrate per-day from the template so the
        // teacher doesn't lose the hours they've set up.
        final expanded = _expandUniform();
        _blocks
          ..clear()
          ..addAll(expanded);
      }
      _uniformMode = on;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = ref.watch(groupsProvider).asData?.value ?? const <Group>[];

    return StickyActionSheet(
      title: 'Day timeline',
      subtitle: Text(
        '${widget.adultName} · add a block for each span of their '
        'day. Gaps count as off. Break & lunch stay on the shift row.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      showCloseButton: true,
      actionBar: AppButton.primary(
        onPressed: _submitting ? null : _save,
        label: 'Save timeline',
        isLoading: _submitting,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            value: _uniformMode,
            onChanged: (v) => _setUniformMode(on: v),
            title: const Text('Same schedule every day'),
            subtitle: Text(
              _uniformMode
                  ? 'Edit once, apply to the picked days below.'
                  : 'Each day has its own blocks.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_uniformMode) ...[
            _DaysPicker(
              picked: _uniformDays,
              onToggle: (day, {required on}) => setState(() {
                if (on) {
                  _uniformDays.add(day);
                } else {
                  _uniformDays.remove(day);
                }
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            _DaySection(
              // dayOfWeek is a canonical slot in uniform mode — the
              // save expander fans every block across _uniformDays
              // so this value never surfaces in user-visible output.
              day: 1,
              overrideLabel: 'Blocks (every picked day)',
              blocks: _uniformTemplate,
              groups: groups,
              onAdd: () => setState(
                () => _uniformTemplate.add(
                  _EditableBlock.blank(dayOfWeek: 1),
                ),
              ),
              onRemove: (block) =>
                  setState(() => _uniformTemplate.remove(block)),
              onChanged: () => setState(() {}),
            ),
          ] else
            for (final day in scheduleDayValues) ...[
              _DaySection(
                day: day,
                blocks:
                    _blocks.where((b) => b.dayOfWeek == day).toList(),
                groups: groups,
                onAdd: () => setState(
                  () => _blocks.add(
                    _EditableBlock.blank(dayOfWeek: day),
                  ),
                ),
                onRemove: (block) =>
                    setState(() => _blocks.remove(block)),
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
        ],
      ),
    );
  }
}

/// Mon–Fri chip row used in uniform mode to pick which days the
/// template applies to. Empty set is legal but self-defeating —
/// saving with no picked days wipes the timeline clean. We don't
/// block the save; the teacher can always toggle back to per-day
/// and reconstruct.
class _DaysPicker extends StatelessWidget {
  const _DaysPicker({required this.picked, required this.onToggle});

  final Set<int> picked;
  final void Function(int day, {required bool on}) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'APPLY TO',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final d in scheduleDayValues)
              FilterChip(
                label: Text(scheduleDayShortLabels[d - 1]),
                selected: picked.contains(d),
                onSelected: (v) => onToggle(d, on: v),
              ),
          ],
        ),
      ],
    );
  }
}

/// Detects whether the initial block list is uniform — every day
/// that has blocks carries the same block shape (same count, same
/// times, same roles, same groups). Returns a template + the set of
/// days that have content so the editor can start in uniform mode
/// with the values already in place.
///
/// Empty block lists count as uniform (nothing to diverge), and the
/// picked days default to Mon–Fri — teachers adding their first
/// timeline usually mean weekdays.
({bool uniform, Set<int> days, List<_EditableBlock> template})
    _detectUniform(List<_EditableBlock> all) {
  final byDay = <int, List<_EditableBlock>>{};
  for (final b in all) {
    (byDay[b.dayOfWeek] ??= []).add(b);
  }
  if (byDay.isEmpty) {
    return (uniform: true, days: {1, 2, 3, 4, 5}, template: []);
  }
  // Sort each day's blocks by start time so the shape comparison is
  // order-agnostic (the teacher may have added blocks out of order).
  for (final list in byDay.values) {
    list.sort((a, b) => (a.startTime?.toMinutes() ?? 0)
        .compareTo(b.startTime?.toMinutes() ?? 0));
  }
  final daysSorted = byDay.keys.toList()..sort();
  final refDay = daysSorted.first;
  final refBlocks = byDay[refDay]!;
  for (final d in daysSorted.skip(1)) {
    final list = byDay[d]!;
    if (list.length != refBlocks.length) {
      return (uniform: false, days: byDay.keys.toSet(), template: []);
    }
    for (var i = 0; i < list.length; i++) {
      final a = list[i];
      final b = refBlocks[i];
      if (a.startTime?.hhmm() != b.startTime?.hhmm() ||
          a.endTime?.hhmm() != b.endTime?.hhmm() ||
          a.role != b.role ||
          a.groupId != b.groupId) {
        return (uniform: false, days: byDay.keys.toSet(), template: []);
      }
    }
  }
  // Uniform — build the template with dayOfWeek=1 placeholders.
  final template = [
    for (final b in refBlocks)
      _EditableBlock(
        dayOfWeek: 1,
        startTime: b.startTime,
        endTime: b.endTime,
        role: b.role,
        groupId: b.groupId,
      ),
  ];
  return (uniform: true, days: byDay.keys.toSet(), template: template);
}

/// One day's block list. Renders the day header plus a vertical
/// list of editable row cards and the Add button. Rows know how to
/// self-edit via callbacks on their model; this widget just owns
/// the layout.
class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.day,
    required this.blocks,
    required this.groups,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
    this.overrideLabel,
  });

  /// ISO day of week this section represents. Used for the default
  /// header label (Mon/Tue/…) and passed through when the teacher
  /// adds a blank block. Ignored when [overrideLabel] is set
  /// (uniform-mode single-day template).
  final int day;

  /// Custom header text, used by the uniform-mode template to read
  /// "Blocks (every picked day)" instead of a weekday name.
  final String? overrideLabel;

  final List<_EditableBlock> blocks;
  final List<Group> groups;
  final VoidCallback onAdd;
  final ValueChanged<_EditableBlock> onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label =
        overrideLabel ?? scheduleDayShortLabels[day - 1].toUpperCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add block'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        if (blocks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              'No blocks — off, or falls back to static role.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final b in blocks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _BlockRow(
                block: b,
                groups: groups,
                onChanged: onChanged,
                onRemove: () => onRemove(b),
              ),
            ),
      ],
    );
  }
}

class _BlockRow extends StatelessWidget {
  const _BlockRow({
    required this.block,
    required this.groups,
    required this.onChanged,
    required this.onRemove,
  });

  final _EditableBlock block;
  final List<Group> groups;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _TimeChip(
                  label: block.startTime?.display() ?? 'Start',
                  onTap: () async {
                    final picked = await _pickTime(
                      context,
                      seed: block.startTime,
                      fallback: const TimeOfDay(hour: 9, minute: 0),
                    );
                    if (picked == null) return;
                    block.startTime = picked;
                    onChanged();
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                ),
                child: Text(
                  '→',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: _TimeChip(
                  label: block.endTime?.display() ?? 'End',
                  onTap: () async {
                    final picked = await _pickTime(
                      context,
                      seed: block.endTime,
                      fallback: const TimeOfDay(hour: 11, minute: 0),
                    );
                    if (picked == null) return;
                    block.endTime = picked;
                    onChanged();
                  },
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close, size: 16),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (final r in AdultBlockRole.values) ...[
                Expanded(
                  child: ChoiceChip(
                    label: Text(_roleLabel(r)),
                    selected: block.role == r,
                    onSelected: (_) {
                      block.role = r;
                      if (r != AdultBlockRole.lead) block.groupId = null;
                      onChanged();
                    },
                  ),
                ),
                if (r != AdultBlockRole.values.last)
                  const SizedBox(width: AppSpacing.xs),
              ],
            ],
          ),
          if (block.role == AdultBlockRole.lead) ...[
            const SizedBox(height: AppSpacing.sm),
            // Group picker only appears for lead blocks — adult
            // blocks don't anchor a group, and showing a grayed-out
            // dropdown for them would be clutter.
            DropdownButtonFormField<String?>(
              initialValue: block.groupId,
              decoration: const InputDecoration(
                labelText: 'Group',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String?>(
                  child: Text('— pick group —'),
                ),
                for (final g in groups)
                  DropdownMenuItem<String?>(
                    value: g.id,
                    child: Text(g.name),
                  ),
              ],
              onChanged: (v) {
                block.groupId = v;
                onChanged();
              },
            ),
          ],
        ],
      ),
    );
  }

  String _roleLabel(AdultBlockRole r) {
    switch (r) {
      case AdultBlockRole.lead:
        return 'Lead';
      case AdultBlockRole.specialist:
        return 'Adult';
    }
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(label, style: theme.textTheme.bodyMedium),
      ),
    );
  }
}

/// Mutable editor-scoped block. The sheet holds a list of these and
/// flushes to [AdultTimelineBlock] rows on save.
class _EditableBlock {
  _EditableBlock({
    required this.dayOfWeek,
    this.startTime,
    this.endTime,
    this.role = AdultBlockRole.specialist,
    this.groupId,
  });

  factory _EditableBlock.blank({required int dayOfWeek}) =>
      _EditableBlock(dayOfWeek: dayOfWeek);

  factory _EditableBlock.fromDomain(AdultTimelineBlock b) =>
      _EditableBlock(
        dayOfWeek: b.dayOfWeek,
        startTime: _parseHHmm(b.startTime),
        endTime: _parseHHmm(b.endTime),
        role: b.role,
        groupId: b.groupId,
      );

  int dayOfWeek;
  TimeOfDay? startTime;
  TimeOfDay? endTime;
  AdultBlockRole role;
  String? groupId;
}

TimeOfDay _parseHHmm(String hhmm) {
  final parts = hhmm.split(':');
  return TimeOfDay(
    hour: int.parse(parts[0]),
    minute: int.parse(parts[1]),
  );
}

Future<TimeOfDay?> _pickTime(
  BuildContext context, {
  required TimeOfDay? seed,
  required TimeOfDay fallback,
}) {
  return showTimePicker(
    context: context,
    initialTime: seed ?? fallback,
  );
}

extension on TimeOfDay {
  String hhmm() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  int toMinutes() => hour * 60 + minute;

  String display() {
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final period = hour >= 12 ? 'PM' : 'AM';
    return '$h12:${minute.toString().padLeft(2, '0')} $period';
  }
}
