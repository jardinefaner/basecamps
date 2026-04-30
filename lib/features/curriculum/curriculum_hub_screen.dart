import 'dart:async';

import 'package:basecamp/core/format/color.dart';
import 'package:basecamp/core/format/date.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/curriculum/curriculum_importer.dart';
import 'package:basecamp/features/curriculum/curriculum_template_preview_screen.dart';
import 'package:basecamp/features/curriculum/templates/curriculum_template.dart';
import 'package:basecamp/features/curriculum/templates/different_world.dart';
import 'package:basecamp/features/themes/themes_repository.dart';
import 'package:basecamp/features/themes/widgets/edit_theme_sheet.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/responsive.dart';
import 'package:basecamp/ui/save_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// `/more/curriculum` — single hub that consolidates the previously-
/// scattered curriculum surfaces (Themes, Lesson sequences, Curriculum
/// templates) into one tabbed screen.
///
/// Tabs:
///   * **My curriculum** — your themes, each tappable into its
///     multi-week curriculum view. "+" creates a new theme.
///   * **Templates** — bundled multi-week starter sets that import
///     in one tap.
///
/// Activity library is reachable via the bookmark icon in the app bar
/// — it stays a standalone screen because it's used outside curriculum
/// (schedule + observations).
///
/// Before: 4 launcher rows (Themes / Lesson sequences / Curriculum /
/// Activity library). After: 2 — Curriculum + Activity library.
class CurriculumHubScreen extends ConsumerStatefulWidget {
  const CurriculumHubScreen({super.key});

  @override
  ConsumerState<CurriculumHubScreen> createState() =>
      _CurriculumHubScreenState();
}

class _CurriculumHubScreenState extends ConsumerState<CurriculumHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (mounted) setState(() {}); // rebuild for FAB visibility
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _newTheme() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const EditThemeSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Curriculum'),
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          IconButton(
            tooltip: 'Activity library',
            icon: const Icon(Icons.bookmarks_outlined),
            onPressed: () => context.push('/more/library'),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'My curriculum'),
            Tab(text: 'Templates'),
          ],
        ),
      ),
      // FAB only on the My-curriculum tab; templates are tap-to-import.
      floatingActionButton: _tabs.index == 0
          ? FloatingActionButton.extended(
              onPressed: _newTheme,
              icon: const Icon(Icons.add),
              label: const Text('New theme'),
            )
          : null,
      body: TabBarView(
        controller: _tabs,
        children: const [
          _MyCurriculumTab(),
          _TemplatesTab(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// My curriculum tab — themes list, each tappable into its curriculum view.
// ---------------------------------------------------------------------------

class _MyCurriculumTab extends ConsumerWidget {
  const _MyCurriculumTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themesAsync = ref.watch(themesProvider);
    return themesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error: $err')),
      data: (themes) {
        if (themes.isEmpty) return const _MyCurriculumEmpty();
        final columns = Breakpoints.columnsFor(context);
        if (columns == 1) {
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xxxl * 2,
            ),
            itemCount: themes.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, i) => _ThemeRow(programTheme: themes[i]),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xxxl * 2,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            mainAxisExtent: 96,
          ),
          itemCount: themes.length,
          itemBuilder: (_, i) => _ThemeRow(programTheme: themes[i]),
        );
      },
    );
  }
}

class _ThemeRow extends StatelessWidget {
  const _ThemeRow({required this.programTheme});

  final ProgramTheme programTheme;

  Future<void> _edit(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditThemeSheet(theme: programTheme),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final swatchColor = parseThemeColor(programTheme.colorHex);
    final rangeLabel =
        formatDateRange(programTheme.startDate, programTheme.endDate);
    return AppCard(
      onTap: () => context.push('/more/themes/${programTheme.id}/curriculum'),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: swatchColor ?? theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.palette_outlined,
              color: swatchColor == null
                  ? theme.colorScheme.onSecondaryContainer
                  : Colors.white,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(programTheme.name, style: theme.textTheme.titleMedium),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    rangeLabel,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit theme',
            color: theme.colorScheme.onSurfaceVariant,
            onPressed: () => _edit(context),
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

class _MyCurriculumEmpty extends StatelessWidget {
  const _MyCurriculumEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No curriculum yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Spin one up from the Templates tab, or tap "+ New theme" '
              'to build your own multi-week arc from scratch.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Templates tab — list of bundled curriculum templates.
//
// Inlined from the (now-removed) standalone CurriculumTemplatesScreen
// so that screen's body lives directly in the hub without a nested
// Scaffold. The route `/more/themes/templates` continues to resolve
// (it points at this hub with the Templates tab pre-selected).
// ---------------------------------------------------------------------------

class _TemplatesTab extends ConsumerWidget {
  const _TemplatesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxxl * 2,
      ),
      children: [
        Text(
          'Spin up a multi-week program in one tap. After import '
          "everything's editable from My curriculum — rename, tweak "
          'activities, add invite codes, the works.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        for (final t in builtInCurriculumTemplates) ...[
          _TemplateCard(
            template: t,
            onTap: () => _previewTemplate(context, t),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }

  /// Tap a template card → push the read-only preview. The preview
  /// owns the "Use this template" CTA at the bottom; it pops itself
  /// and calls back to [_openImportSheet] so the import sheet ends
  /// up parented to the templates tab (not stacked on top of the
  /// preview screen).
  Future<void> _previewTemplate(
    BuildContext context,
    CurriculumTemplate template,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CurriculumTemplatePreviewScreen(
          template: template,
          onUse: () => _openImportSheet(context, template),
        ),
      ),
    );
  }

  Future<void> _openImportSheet(
    BuildContext context,
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

/// One template's surface in the Templates tab. Tap-anywhere opens
/// the read-only preview (week-by-week walk-through); the preview
/// is where the actual "Use this template" import action lives. The
/// previous flow had a "Use this template" button on this card that
/// jumped straight to the import sheet — the teacher committed to a
/// 10-week curriculum from a 4-line summary. Now the card's CTA is
/// "Preview" and the import is one screen deeper, behind a sticky
/// bottom button on the preview itself.
class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.onTap});

  final CurriculumTemplate template;

  /// Fired on tap-anywhere and on the explicit "Preview" button.
  /// Both routes go to the preview screen; the button is only there
  /// for visual signaling that the card is tappable.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = parseHex(template.themeColorHex) ??
        theme.colorScheme.primary;
    return AppCard(
      onTap: onTap,
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
            child: FilledButton.tonalIcon(
              onPressed: onTap,
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('Preview'),
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

class _UseTemplateSheetState extends ConsumerState<_UseTemplateSheet> {
  late final TextEditingController _name;
  late DateTime _startDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.template.name);
    _startDate = _nextMonday();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  static DateTime _nextMonday() {
    final now = DateTime.now();
    final today = now.dayOnly;
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
    final dateLabel = DateFormat.yMMMMEEEEd().format(_startDate);
    final endLabel = DateFormat.yMMMd().format(_endDate);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
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
      ),
    );
  }
}
