import 'package:basecamp/database/database.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

class ChildChipPicker extends StatelessWidget {
  const ChildChipPicker({
    required this.kids,
    required this.selectedIds,
    required this.onToggle,
    super.key,
  });

  final List<Child> kids;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    if (kids.isEmpty) {
      final theme = Theme.of(context);
      return Text(
        'No children yet — add some in the Children tab.',
        style: theme.textTheme.bodySmall,
      );
    }

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final kid in kids)
          FilterChip(
            label: Text(_displayName(kid)),
            selected: selectedIds.contains(kid.id),
            onSelected: (_) => onToggle(kid.id),
          ),
      ],
    );
  }

  String _displayName(Child kid) {
    final last = kid.lastName;
    if (last == null || last.isEmpty) return kid.firstName;
    final initial = last.isNotEmpty ? last[0] : '';
    return '${kid.firstName} $initial.';
  }
}
