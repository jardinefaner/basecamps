import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/forms/parent_concern/parent_concern_repository.dart';
import 'package:basecamp/features/forms/polymorphic/definitions/incident.dart';
import 'package:basecamp/features/forms/polymorphic/form_submission_repository.dart';
import 'package:basecamp/features/forms/polymorphic/generic_form_screen.dart';
import 'package:basecamp/features/parents/parents_repository.dart';
import 'package:basecamp/features/parents/widgets/edit_parent_sheet.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

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
                if (parent.phone case final phone?)
                  _ContactRow(
                    icon: Icons.call_outlined,
                    label: phone,
                    uri: Uri(scheme: 'tel', path: phone),
                    failMessage: "Couldn't start a call.",
                  ),
                if (parent.email case final email?)
                  _ContactRow(
                    icon: Icons.mail_outlined,
                    label: email,
                    uri: Uri(scheme: 'mailto', path: email),
                    failMessage: "Couldn't open your email app.",
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
              // v40: reverse of the staff↔parent bridge. Shows when
              // an adult row points here. Tap jumps to that adult's
              // detail screen.
              _AlsoOnStaffBadge(parentId: parent.id),
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
        const SizedBox(height: AppSpacing.lg),
        Text(
          'RECENT ACTIVITY',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _RecentActivitySection(parentId: parent.id),
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

/// One contact row (phone / email). Tap launches the corresponding
/// `tel:` / `mailto:` URI via url_launcher — if the OS has no handler
/// (e.g. desktop sim) we surface a brief snackbar instead of failing
/// silently.
class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.uri,
    required this.failMessage,
  });

  final IconData icon;
  final String label;
  final Uri uri;
  final String failMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _launch(context),
      borderRadius: BorderRadius.circular(AppSpacing.xs),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xs,
          horizontal: 2,
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(label, style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launch(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await launchUrl(uri);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(failMessage)));
    }
  }
}

/// Merged feed of parent-concern notes + incident form submissions
/// that touch any child linked to this parent. Both streams are
/// watched broadly (all concerns + all incidents) and filtered
/// client-side by child id — the parent-linked-children set is tiny
/// (single-digit) and each stream is already bounded to a form type,
/// so no repository-side join needed yet. Bounded to the 10 most
/// recent entries.
class _RecentActivitySection extends ConsumerWidget {
  const _RecentActivitySection({required this.parentId});

  final String parentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final kidsAsync = ref.watch(childrenForParentProvider(parentId));
    final concernsAsync = ref.watch(parentConcernNotesProvider);
    final linksAsync = ref.watch(concernKidLinksProvider);
    final incidentsAsync =
        ref.watch(formSubmissionsByTypeProvider('incident'));

    if (kidsAsync.isLoading ||
        concernsAsync.isLoading ||
        linksAsync.isLoading ||
        incidentsAsync.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final kids = kidsAsync.asData?.value ?? const <Child>[];
    final concerns =
        concernsAsync.asData?.value ?? const <ParentConcernNote>[];
    final links =
        linksAsync.asData?.value ?? const <String, Set<String>>{};
    final incidents =
        incidentsAsync.asData?.value ?? const <FormSubmission>[];

    final childIds = kids.map((k) => k.id).toSet();
    if (childIds.isEmpty) {
      return _EmptyActivity(theme: theme);
    }

    final items = <_ActivityItem>[];
    for (final note in concerns) {
      final linked = links[note.id] ?? const <String>{};
      if (linked.any(childIds.contains)) {
        items.add(
          _ActivityItem.concern(
            id: note.id,
            createdAt: note.updatedAt,
            headline: _concernHeadline(note),
          ),
        );
      }
    }
    for (final sub in incidents) {
      final childId = sub.childId;
      if (childId == null || !childIds.contains(childId)) continue;
      items.add(
        _ActivityItem.incident(
          id: sub.id,
          createdAt: sub.submittedAt ?? sub.createdAt,
          headline: _incidentHeadline(sub, kids),
        ),
      );
    }

    if (items.isEmpty) {
      return _EmptyActivity(theme: theme);
    }

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final trimmed = items.take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in trimmed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: AppCard(
              onTap: () => _open(context, item),
              child: Row(
                children: [
                  Icon(
                    item.kind == _ActivityKind.concern
                        ? Icons.record_voice_over_outlined
                        : Icons.report_problem_outlined,
                    color: item.kind == _ActivityKind.concern
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.error,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.headline,
                          style: theme.textTheme.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _relative(item.createdAt),
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
            ),
          ),
      ],
    );
  }

  void _open(BuildContext context, _ActivityItem item) {
    switch (item.kind) {
      case _ActivityKind.concern:
        unawaited(context.push('/more/forms/parent-concern/${item.id}'));
      case _ActivityKind.incident:
        unawaited(
          Navigator.of(context, rootNavigator: true).push<void>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => GenericFormScreen(
                definition: incidentForm,
                submissionId: item.id,
              ),
            ),
          ),
        );
    }
  }

  String _concernHeadline(ParentConcernNote note) {
    final desc = note.concernDescription.trim();
    if (desc.isNotEmpty) return 'Concern — $desc';
    final kids = note.childNames.trim();
    return kids.isEmpty ? 'Parent concern' : 'Concern — $kids';
  }

  String _incidentHeadline(FormSubmission sub, List<Child> kids) {
    final data = decodeFormData(sub);
    final desc = (data['description'] as String?)?.trim() ?? '';
    final childId = sub.childId;
    Child? child;
    if (childId != null) {
      for (final k in kids) {
        if (k.id == childId) {
          child = k;
          break;
        }
      }
    }
    final label =
        child == null ? 'Incident' : 'Incident — ${child.firstName}';
    if (desc.isEmpty) return label;
    return '$label: $desc';
  }

  String _relative(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }
}

/// v40: "Also on staff" pill rendered on the parent card when a staff
/// row points at this parent via `adults.parent_id`. Tap jumps to
/// `/more/adults/<id>` so the teacher can swap between the two
/// surfaces without digging through tabs.
class _AlsoOnStaffBadge extends ConsumerWidget {
  const _AlsoOnStaffBadge({required this.parentId});

  final String parentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final adult = ref.watch(adultLinkedToParentProvider(parentId)).asData?.value;
    if (adult == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: () => context.push('/more/adults/${adult.id}'),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.badge_outlined,
                  size: 14,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Also on staff — ${adult.name}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  Icons.chevron_right,
                  size: 14,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      'No concerns or incidents yet.',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

enum _ActivityKind { concern, incident }

class _ActivityItem {
  _ActivityItem.concern({
    required this.id,
    required this.createdAt,
    required this.headline,
  }) : kind = _ActivityKind.concern;

  _ActivityItem.incident({
    required this.id,
    required this.createdAt,
    required this.headline,
  }) : kind = _ActivityKind.incident;

  final _ActivityKind kind;
  final String id;
  final DateTime createdAt;
  final String headline;
}
