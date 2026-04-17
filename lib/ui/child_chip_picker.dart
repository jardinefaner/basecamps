import 'package:basecamp/database/database.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

class ChildChipPicker extends StatelessWidget {
  const ChildChipPicker({
    required this.children,
    required this.selectedIds,
    required this.onToggle,
    super.key,
  });

  final List<Child> children;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
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
        for (final child in children)
          FilterChip(
            label: Text(_displayName(child)),
            selected: selectedIds.contains(child.id),
            onSelected: (_) => onToggle(child.id),
          ),
      ],
    );
  }

  String _displayName(Child child) {
    final last = child.lastName;
    if (last == null || last.isEmpty) return child.firstName;
    final initial = last.isNotEmpty ? last[0] : '';
    return '${child.firstName} $initial.';
  }
}
