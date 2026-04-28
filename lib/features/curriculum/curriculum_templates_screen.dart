import 'dart:async';

import 'package:basecamp/features/curriculum/curriculum_importer.dart';
import 'package:basecamp/features/curriculum/templates/curriculum_template.dart';
import 'package:basecamp/features/curriculum/templates/different_world.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/save_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// `/more/themes/templates` — list of bundled curriculum
/// templates the user can spin up in one tap.
///
/// First entry: "Different World" (10-week summer arc, ages 5–12).
/// Future: more templates can be appended to
/// [builtInCurriculumTemplates] without UI changes.
///
/// Tap a template → opens a sheet for theme name + start date,
/// then runs [CurriculumImporter] which creates theme + 10
/// sequences + 50 sequence items + 50 activity-library cards in
/// one go. After import, navigates to the curriculum view for
/// the new theme.
class CurriculumTemplatesScreen extends ConsumerWidget {
  const CurriculumTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      // Match the surface to the theme's scaffold background so
      // the SafeArea + status-bar area share one background and
      // there's no seam at the top of the screen.
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Curriculum templates'),
        backgroundColor: theme.scaffoldBackgroundColor,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xxxl * 2,
          ),
          children: [
            Text(
              'Spin up a multi-week program in one tap. After import '
              "everything's editable from Themes — rename, tweak "
              'activities, add invite codes, the works.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            for (final t in builtInCurriculumTemplates) ...[
              _TemplateCard(
                template: t,
                onUse: () => _useTemplate(context, ref, t),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _useTemplate(
    BuildContext context,
    WidgetRef ref,
    CurriculumTemplate template,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _UseTemplateSheet(template: template),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.onUse});

  final CurriculumTemplate template;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _parseHex(template.themeColorHex) ??
        theme.colorScheme.primary;
    return AppCard(
      onTap: onUse,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.auto_stories_outlined,
                  color: accent,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(template.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      template.audience,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            template.tagline,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            template.summary,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: onUse,
              child: const Text('Use this template'),
            ),
          ),
        ],
      ),
    );
  }
}

class _UseTemplateSheet extends ConsumerStatefulWidget {
  const _UseTemplateSheet({required this.template});

  final CurriculumTemplate template;

  @override
  ConsumerState<_UseTemplateSheet> createState() =>
      _UseTemplateSheetState();
}

class _UseTemplateSheetState
    extends ConsumerState<_UseTemplateSheet> {
  late final TextEditingController _name;
  late DateTime _startDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.template.name);
    // Default to next Monday. A teacher firing this off mid-week
    // almost always wants the curriculum to begin the following
    // Monday, not today.
    _startDate = _nextMonday();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  static DateTime _nextMonday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysUntilMonday = (DateTime.monday - today.weekday + 7) % 7;
    final delta = daysUntilMonday == 0 ? 7 : daysUntilMonday;
    return today.add(Duration(days: delta));
  }

  DateTime get _endDate {
    return _startDate
        .add(Duration(days: 7 * widget.template.weekCount));
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  Future<void> _import() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    await runWithErrorReport(context, () async {
      final themeId =
          await ref.read(curriculumImporterProvider).import(
                template: widget.template,
                themeName: name,
                startDate: _startDate,
                endDate: _endDate,
              );
      if (!mounted) return;
      Navigator.of(context).pop();
      if (!context.mounted) return;
      // Navigate straight to the curriculum view for the new
      // theme so the user sees their imported arc immediately.
      // Tiny delay lets the modal pop animation finish first so
      // the route push doesn't fight the dismissing sheet.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted || !context.mounted) return;
      unawaited(context.push('/more/themes/$themeId/curriculum'));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported "$name"'),
          duration: const Duration(seconds: 2),
        ),
      );
    });
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets;
    final dateLabel = DateFormat.yMMMMEEEEd().format(_startDate);
    final endLabel = DateFormat.yMMMd().format(_endDate);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg + viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.template.name,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.template.tagline,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Theme name',
                hintText: 'e.g. Summer 2026',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            InkWell(
              onTap: _pickStart,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Start date',
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        dateLabel,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Ends $endLabel · ${widget.template.weekCount} weeks',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _import,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Import'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Color? _parseHex(String hex) {
  try {
    var clean = hex.replaceFirst('#', '');
    if (clean.length == 6) clean = 'FF$clean';
    return Color(int.parse(clean, radix: 16));
  } on FormatException {
    return null;
  }
}
