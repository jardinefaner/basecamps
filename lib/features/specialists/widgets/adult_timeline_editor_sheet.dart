import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/schedule/week_days.dart';
import 'package:basecamp/features/specialists/adult_timeline_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Per-adult day-timeline editor. Opens from the adult edit sheet
/// for adults whose day is more complicated than "specialist all
/// day" or "lead anchored to pod X" — lets them mark out "lead
/// Butterflies 8:30-11, specialist rotator 11-12, back to
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
    required this.specialistId,
    required this.specialistName,
    this.initialBlocks = const [],
    super.key,
  });

  final String specialistId;
  final String specialistName;

  /// Existing blocks when the sheet opens (so edits start from what's
  /// already saved). Empty = new timeline.
  final List<AdultTimelineBlock> initialBlocks;

  @override
  ConsumerState<AdultTimelineEditorSheet> createState() =>
      _AdultTimelineEditorSheetState();
}

class _AdultTimelineEditorSheetState
    extends ConsumerState<AdultTimelineEditorSheet> {
  late final List<_EditableBlock> _blocks = [
    for (final b in widget.initialBlocks) _EditableBlock.fromDomain(b),
  ];

  bool _submitting = false;

  Future<void> _save() async {
    setState(() => _submitting = true);
    try {
      // Drop any half-configured row (blank time range) rather than
      // refusing the save — teacher probably added a placeholder and
      // then tapped Save without filling it in.
      final clean = _blocks
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
            // Non-lead blocks drop any leftover podId — a specialist
            // block never anchors a pod regardless of what picker
            // state the editor might have cached.
            podId: b.role == AdultBlockRole.lead ? b.podId : null,
          ),
      ];
      await ref.read(adultTimelineRepositoryProvider).replaceBlocks(
            specialistId: widget.specialistId,
            blocks: domain,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = ref.watch(groupsProvider).asData?.value ?? const <Group>[];

    return StickyActionSheet(
      title: 'Day timeline',
      subtitle: Text(
        '${widget.specialistName} · add a block for each span of their '
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
          for (final day in scheduleDayValues) ...[
            _DaySection(
              day: day,
              blocks: _blocks.where((b) => b.dayOfWeek == day).toList(),
              groups: groups,
              onAdd: () => setState(
                () => _blocks.add(
                  _EditableBlock.blank(dayOfWeek: day),
                ),
              ),
              onRemove: (block) => setState(() => _blocks.remove(block)),
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }
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
  });

  final int day;
  final List<_EditableBlock> blocks;
  final List<Group> groups;
  final VoidCallback onAdd;
  final ValueChanged<_EditableBlock> onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 60,
              child: Text(
                scheduleDayShortLabels[day - 1].toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
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
            padding: const EdgeInsets.only(
              left: 60,
              bottom: AppSpacing.xs,
            ),
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
                      if (r != AdultBlockRole.lead) block.podId = null;
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
            // Pod picker only appears for lead blocks — specialist
            // blocks don't anchor a pod, and showing a grayed-out
            // dropdown for them would be clutter.
            DropdownButtonFormField<String?>(
              initialValue: block.podId,
              decoration: const InputDecoration(
                labelText: 'Pod',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String?>(
                  child: Text('— pick pod —'),
                ),
                for (final g in groups)
                  DropdownMenuItem<String?>(
                    value: g.id,
                    child: Text(g.name),
                  ),
              ],
              onChanged: (v) {
                block.podId = v;
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
        return 'Specialist';
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
    this.podId,
  });

  factory _EditableBlock.blank({required int dayOfWeek}) =>
      _EditableBlock(dayOfWeek: dayOfWeek);

  factory _EditableBlock.fromDomain(AdultTimelineBlock b) =>
      _EditableBlock(
        dayOfWeek: b.dayOfWeek,
        startTime: _parseHHmm(b.startTime),
        endTime: _parseHHmm(b.endTime),
        role: b.role,
        podId: b.podId,
      );

  int dayOfWeek;
  TimeOfDay? startTime;
  TimeOfDay? endTime;
  AdultBlockRole role;
  String? podId;
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
