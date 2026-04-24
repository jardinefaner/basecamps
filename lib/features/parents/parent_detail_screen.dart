import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/parents/parents_repository.dart';
import 'package:basecamp/features/parents/widgets/edit_parent_sheet.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// `/more/parents/:id` — one parent. Top: display-card with name,
/// relationship, phone/email. Below: list of linked children with
/// tap-through. Edit opens the sheet; delete lives inside the sheet.
class ParentDetailScreen extends ConsumerWidget {
  const ParentDetailScreen({required this.parentId, super.key});

  final String parentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parentAsync = ref.watch(parentProvider(parentId));
    return Scaffold(
      appBar: AppBar(title: const Text('Parent')),
      body: parentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (parent) {
          if (parent == null) {
            // Row got deleted while this screen was open — likely
            // from undo cleanup or a manual SQLite edit. Pop back.
            return const Center(child: Text('Parent not found.'));
          }
          return _Body(parent: parent);
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.parent});

  final Parent parent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final kidsAsync = ref.watch(childrenForParentProvider(parent.id));
    return ListView(
      padding: const EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.md,
        bottom: AppSpacing.xxxl * 2,
      ),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    foregroundColor:
                        theme.colorScheme.onSecondaryContainer,
                    child: Text(
                      parent.firstName.isEmpty
                          ? '?'
                          : parent.firstName[0].toUpperCase(),
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatName(parent),
                          style: theme.textTheme.titleLarge,
                        ),
                        if (parent.relationship != null &&
                            parent.relationship!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              parent.relationship!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color:
                                    theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _edit(context),
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
              if (parent.phone != null || parent.email != null) ...[
                const SizedBox(height: AppSpacing.md),
                if (parent.phone != null)
                  _ContactRow(
                    icon: Icons.call_outlined,
                    label: parent.phone!,
                  ),
                if (parent.email != null)
                  _ContactRow(
                    icon: Icons.mail_outlined,
                    label: parent.email!,
                  ),
              ],
              if (parent.notes != null && parent.notes!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Notes',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(parent.notes!, style: theme.textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'CHILDREN',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        kidsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => Text('Error: $err'),
          data: (kids) {
            if (kids.isEmpty) {
              return Text(
                'Not linked to any children yet. Open a child and use '
                '"Add parent" to link this parent.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final k in kids)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: AppCard(
                      onTap: () => context.push('/children/${k.id}'),
                      child: Row(
                        children: [
                          Icon(
                            Icons.child_care_outlined,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              _formatChild(k),
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context) async {
    final result = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditParentSheet(parent: parent),
    );
    // When the delete path fires, the sheet pops with `null` (not
    // the id); the parent provider watch in the parent screen will
    // fall to null, at which point we're already off this route.
    if (result == null && context.mounted) {
      // No-op — the stream will drive the state update.
    }
  }

  String _formatName(Parent p) {
    final last = p.lastName;
    return last == null || last.isEmpty
        ? p.firstName
        : '${p.firstName} $last';
  }

  String _formatChild(Child c) {
    final last = c.lastName;
    return last == null || last.isEmpty
        ? c.firstName
        : '${c.firstName} $last';
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
