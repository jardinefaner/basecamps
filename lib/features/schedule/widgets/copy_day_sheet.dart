import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/week_days.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const List<String> _dayLabels = scheduleDayLabels;
const List<String> _dayShortLabels = ['M', 'T', 'W', 'T', 'F'];

/// Bottom sheet: pick target days to duplicate [sourceDay]'s activities into.
class CopyDaySheet extends ConsumerStatefulWidget {
  const CopyDaySheet({
    required this.sourceDay,
    required this.sourceCount,
    required this.onCopied,
    super.key,
  });

  final int sourceDay;
  final int sourceCount;
  final void Function(Set<int> targetDays, int countPerDay) onCopied;

  @override
  ConsumerState<CopyDaySheet> createState() => _CopyDaySheetState();
}

class _CopyDaySheetState extends ConsumerState<CopyDaySheet> {
  final Set<int> _targetDays = <int>{};
  bool _submitting = false;

  bool get _isValid => _targetDays.isNotEmpty;

  Future<void> _submit() async {
    if (!_isValid) return;
    setState(() => _submitting = true);
    final count = await ref.read(scheduleRepositoryProvider).copyDayTemplates(
          sourceDay: widget.sourceDay,
          targetDays: _targetDays,
        );
    if (!mounted) return;
    widget.onCopied(_targetDays, count);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sourceLabel = _dayLabels[widget.sourceDay - 1];

    return StickyActionSheet(
      title: "Copy $sourceLabel's schedule",
      subtitle: Text(
        '${widget.sourceCount} ${widget.sourceCount == 1 ? "activity" : "activities"} will be duplicated to each selected day.',
      ),
      actionBar: AppButton.primary(
        onPressed: _isValid ? _submit : null,
        label: _targetDays.isEmpty
            ? 'Copy'
            : 'Copy to ${_targetDays.length} ${_targetDays.length == 1 ? "day" : "days"}',
        isLoading: _submitting,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Copy to', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (var day = 1; day <= scheduleDayCount; day++) ...[
                _DayChip(
                  label: _dayShortLabels[day - 1],
                  selected: _targetDays.contains(day),
                  disabled: day == widget.sourceDay,
                  onTap: () => setState(() {
                    if (!_targetDays.add(day)) _targetDays.remove(day);
                  }),
                ),
                if (day < scheduleDayCount)
                  const SizedBox(width: AppSpacing.xs),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              ActionChip(
                label: const Text('All other weekdays'),
                onPressed: () => setState(() {
                  _targetDays
                    ..clear()
                    ..addAll(scheduleDayValues.toSet()
                      ..remove(widget.sourceDay));
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color bg;
    final Color fg;
    if (disabled) {
      bg = theme.colorScheme.surfaceContainerHigh;
      fg = theme.colorScheme.onSurfaceVariant;
    } else if (selected) {
      bg = theme.colorScheme.primary;
      fg = theme.colorScheme.onPrimary;
    } else {
      bg = theme.colorScheme.surfaceContainer;
      fg = theme.colorScheme.onSurface;
    }

    return Expanded(
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
              width: 0.5,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              color: fg,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
