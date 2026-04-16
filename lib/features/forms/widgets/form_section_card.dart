import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';

/// One section of a structured form. Each card has a strong title, an
/// optional one-line helper subtitle, and the fillable content below.
/// Keeps every section of a long form visually equal and obvious.
class FormSectionCard extends StatelessWidget {
  const FormSectionCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}

/// A small tappable row that opens a date picker. Formats the current
/// date or shows a hint when no date is set. Use inside [FormSectionCard]
/// with a Field label above it.
class FormDateField extends StatelessWidget {
  const FormDateField({
    required this.value,
    required this.onChanged,
    this.hint = 'Pick a date',
    this.firstDate,
    this.lastDate,
    super.key,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String hint;
  final DateTime? firstDate;
  final DateTime? lastDate;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: firstDate ?? DateTime(now.year - 5),
      lastDate: lastDate ?? DateTime(now.year + 5),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasValue = value != null;
    final label = hasValue
        ? _formatDate(value!)
        : hint;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _pick(context),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              Icons.event_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: hasValue
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (hasValue)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                iconSize: 18,
                icon: Icon(
                  Icons.close,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                tooltip: 'Clear',
                onPressed: () => onChanged(null),
              ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}
