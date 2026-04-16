import 'package:basecamp/features/schedule/widgets/add_full_day_event_sheet.dart';
import 'package:basecamp/features/schedule/widgets/edit_template_sheet.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';

/// First-step sheet that asks "what kind of activity?" — recurring template
/// (weekly pattern) vs full-day event (specific date).
class AddActivityPicker extends StatelessWidget {
  const AddActivityPicker({super.key, this.initialDays, this.initialDate});

  final Set<int>? initialDays;
  final DateTime? initialDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('What are you adding?', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xl),
          _PickerCard(
            icon: Icons.repeat_outlined,
            title: 'Recurring activity',
            description: 'Weekly pattern — e.g. Art every Mon/Wed/Fri.',
            onTap: () => _openRecurring(context),
          ),
          const SizedBox(height: AppSpacing.md),
          _PickerCard(
            icon: Icons.event_outlined,
            title: 'Full-day event',
            description:
                'Specific date, no times — e.g. field trip, staff day, closure.',
            onTap: () => _openFullDay(context),
          ),
        ],
      ),
    );
  }

  Future<void> _openRecurring(BuildContext context) async {
    Navigator.of(context).pop();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditTemplateSheet(initialDays: initialDays),
    );
  }

  Future<void> _openFullDay(BuildContext context) async {
    Navigator.of(context).pop();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AddFullDayEventSheet(initialDate: initialDate),
    );
  }
}

class _PickerCard extends StatelessWidget {
  const _PickerCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
