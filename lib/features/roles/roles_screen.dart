import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/roles/roles_repository.dart';
import 'package:basecamp/features/roles/widgets/edit_role_sheet.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `/more/roles` — list + add + edit staff roles. Populates the
/// picker on adult edit / new-adult wizard so teachers pick a role
/// instead of retyping "Art teacher" on every specialist.
class RolesScreen extends ConsumerStatefulWidget {
  const RolesScreen({super.key});

  @override
  ConsumerState<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends ConsumerState<RolesScreen> {
  Future<void> _openSheet({Role? role}) async {
    await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditRoleSheet(role: role),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rolesAsync = ref.watch(rolesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Roles')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openSheet,
        icon: const Icon(Icons.add),
        label: const Text('Role'),
      ),
      body: rolesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (roles) {
          if (roles.isEmpty) {
            return _EmptyState(onAdd: _openSheet);
          }
          return BreakpointBuilder(
            builder: (context, bp) {
              // Role rows are single-line — tight default ramp
              // (1 / 1 / 2 / 3) works without adjustment.
              final columns = Breakpoints.columnsFor(context);
              final hSide = bp == Breakpoint.compact
                  ? AppSpacing.lg
                  : AppSpacing.xl;
              final padding = EdgeInsets.only(
                left: hSide,
                right: hSide,
                top: AppSpacing.md,
                bottom: AppSpacing.xxxl * 2,
              );
              Widget tileFor(int i) {
                final r = roles[i];
                return _RoleTile(
                  role: r,
                  onTap: () => _openSheet(role: r),
                );
              }

              if (columns == 1) {
                return ListView.separated(
                  padding: padding,
                  itemCount: roles.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, i) => tileFor(i),
                );
              }
              return GridView.builder(
                padding: padding,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisExtent: 80,
                ),
                itemCount: roles.length,
                itemBuilder: (_, i) => tileFor(i),
              );
            },
          );
        },
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({required this.role, required this.onTap});

  final Role role;
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
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.work_outline,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(role.name, style: theme.textTheme.titleMedium),
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            Icon(
              Icons.work_outline,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No roles yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Add the job titles used by your program — Art teacher, '
              "Director, Head cook, etc. Once set, you'll pick from "
              'this list when editing an adult instead of retyping '
              'the same blurb.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add role'),
            ),
          ],
        ),
          ),
        ),
    );
  }
}
