import 'package:basecamp/features/schedule/widgets/new_activity_wizard.dart';
import 'package:basecamp/features/schedule/widgets/new_full_day_event_wizard.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';

/// Public alias so callers of [AddActivityPicker] can match against the
/// pop result without depending on the wizard file directly.
typedef ActivityCreated = CreatedActivity;

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
            title: 'Event or multi-day note',
            description:
                'Single date or a range — field trip, closure, spring '
                'break, ongoing note.',
            onTap: () => _openFullDay(context),
          ),
        ],
      ),
    );
  }

  Future<void> _openRecurring(BuildContext context) async {
    // Push the wizard BEFORE popping the picker, so we can forward the
    // wizard's result up through the picker's own pop. If we popped the
    // picker first, the wizard's pop would return to the editor with no
    // way to re-enter the picker's return channel — the editor would
    // never find out what got created, so it couldn't jump the week
    // view or flash a confirmation snackbar.
    final navigator = Navigator.of(context);
    final result = await navigator.push<CreatedActivity>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => NewActivityWizardScreen(initialDays: initialDays),
      ),
    );
    // Pop the picker sheet, carrying the wizard's result upward.
    if (navigator.mounted) {
      navigator.pop(result);
    }
  }

  Future<void> _openFullDay(BuildContext context) async {
    final navigator = Navigator.of(context);
    final result = await navigator.push<CreatedActivity>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            NewFullDayEventWizardScreen(initialDate: initialDate),
      ),
    );
    if (navigator.mounted) {
      navigator.pop(result);
    }
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
