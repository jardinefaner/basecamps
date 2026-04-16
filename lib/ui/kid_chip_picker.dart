import 'package:basecamp/database/database.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

class KidChipPicker extends StatelessWidget {
  const KidChipPicker({
    required this.kids,
    required this.selectedIds,
    required this.onToggle,
    super.key,
  });

  final List<Kid> kids;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    if (kids.isEmpty) {
      final theme = Theme.of(context);
      return Text(
        'No kids yet — add some in the Kids tab.',
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

  String _displayName(Kid kid) {
    final last = kid.lastName;
    if (last == null || last.isEmpty) return kid.firstName;
    final initial = last.isNotEmpty ? last[0] : '';
    return '${kid.firstName} $initial.';
  }
}
