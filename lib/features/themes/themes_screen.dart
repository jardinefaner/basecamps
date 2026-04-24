import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/themes/themes_repository.dart';
import 'package:basecamp/features/themes/widgets/edit_theme_sheet.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// `/more/themes` — list + add + edit program themes. Each theme marks
/// a date range ("Bug week") that later slices can use for tinting /
/// filtering. This round ships CRUD only; the visual integration on
/// Today / the planner is deferred.
class ThemesScreen extends ConsumerStatefulWidget {
  const ThemesScreen({super.key});

  @override
  ConsumerState<ThemesScreen> createState() => _ThemesScreenState();
}

class _ThemesScreenState extends ConsumerState<ThemesScreen> {
  Future<void> _openSheet({ProgramTheme? theme}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditThemeSheet(theme: theme),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themesAsync = ref.watch(themesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Themes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openSheet,
        icon: const Icon(Icons.add),
        label: const Text('Theme'),
      ),
      body: themesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (themes) {
          if (themes.isEmpty) {
            return _EmptyState(onAdd: _openSheet);
          }
          return ListView.separated(
            padding: const EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              top: AppSpacing.md,
              bottom: AppSpacing.xxxl * 2,
            ),
            itemCount: themes.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, i) {
              final t = themes[i];
              return _ThemeTile(
                programTheme: t,
                onTap: () => _openSheet(theme: t),
              );
            },
          );
        },
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.programTheme,
    required this.onTap,
  });

  final ProgramTheme programTheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final swatchColor = parseThemeColor(programTheme.colorHex);
    final rangeLabel =
        '${DateFormat.MMMd().format(programTheme.startDate)} – '
        '${DateFormat.MMMd().format(programTheme.endDate)}';
    return AppCard(
      onTap: onTap,
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
                Text(
                  programTheme.name,
                  style: theme.textTheme.titleMedium,
                ),
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
          Icon(
            Icons.chevron_right,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.palette_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No themes yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Themes mark date ranges so library filtering can suggest '
              'themed activities.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add theme'),
            ),
          ],
        ),
      ),
    );
  }
}
