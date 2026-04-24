import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/activity_library/activity_card_ai.dart';
import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:basecamp/features/activity_library/widgets/activity_card_preview.dart';
import 'package:basecamp/features/activity_library/widgets/edit_library_item_sheet.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/undo_delete.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full-view bottom sheet for a saved activity-library card. Opens
/// when the teacher taps a rich card in the library list — previously
/// a tap jumped straight to the dense preset-edit sheet, which hid
/// every AI-generated field and made saved cards feel one-way.
///
/// Actions at the bottom:
///   - Edit (preset fields only — title/duration/adult/location
///     /notes via the existing EditLibraryItemSheet)
///   - Delete (with confirm)
///   - Copy link (when a sourceUrl is set)
class LibraryCardDetailSheet extends ConsumerWidget {
  const LibraryCardDetailSheet({required this.item, super.key});

  final ActivityLibraryData item;

  Future<void> _openEdit(BuildContext context) async {
    final navigator = Navigator.of(context)..pop();
    await showModalBottomSheet<void>(
      context: navigator.context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditLibraryItemSheet(item: item),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final confirmed = await confirmDeleteWithUndo(
      context: context,
      title: 'Delete this activity?',
      message: "It'll be removed from your bucket. You'll get a "
          '5-second window to undo.',
      onDelete: () => ref
          .read(activityLibraryRepositoryProvider)
          .deleteItem(item.id),
      undoLabel: '"${item.title}" removed',
      onUndo: () => ref
          .read(activityLibraryRepositoryProvider)
          .restoreItem(item),
    );
    if (!confirmed) return;
    navigator.pop();
  }

  Future<void> _copyLink(BuildContext context) async {
    final url = item.sourceUrl;
    if (url == null || url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('Link copied'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  String? _audienceLabel() {
    final min = item.audienceMinAge;
    final max = item.audienceMaxAge;
    if (min == null || max == null) return null;
    return audienceLabelFor(min, max);
  }

  List<String> _splitLines(String? s) {
    if (s == null || s.trim().isEmpty) return const <String>[];
    return s
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final hasSourceUrl =
        item.sourceUrl != null && item.sourceUrl!.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.md,
        bottom: AppSpacing.md + insets,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The card itself — full layout, same widget used by the
          // wizard preview step so there's no rendering drift.
          Flexible(
            child: SingleChildScrollView(
              child: ActivityCardPreview(
                title: item.title,
                audienceLabel: _audienceLabel(),
                hook: item.hook,
                summary: item.summary,
                keyPoints: _splitLines(item.keyPoints),
                learningGoals: _splitLines(item.learningGoals),
                engagementTimeMin: item.engagementTimeMin,
                sourceUrl: item.sourceUrl,
                sourceAttribution: item.sourceAttribution,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Action row: Edit / Delete / Copy link (if source set).
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openEdit(context),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _delete(context, ref),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  label: Text(
                    'Delete',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: theme.colorScheme.error.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (hasSourceUrl) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: () => _copyLink(context),
              icon: const Icon(Icons.link, size: 16),
              label: const Text('Copy link'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
