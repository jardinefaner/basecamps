import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:basecamp/features/activity_library/widgets/edit_library_item_sheet.dart';
import 'package:basecamp/features/activity_library/widgets/library_card_detail_sheet.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/forms/polymorphic/definitions/incident.dart';
import 'package:basecamp/features/forms/polymorphic/definitions/parent_concern.dart';
import 'package:basecamp/features/forms/polymorphic/generic_form_screen.dart';
import 'package:basecamp/features/observations/widgets/observation_composer.dart';
import 'package:basecamp/features/rooms/rooms_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/widgets/edit_template_sheet.dart';
import 'package:basecamp/features/schedule/widgets/new_full_day_event_wizard.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/address_field.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:basecamp/ui/confirm_dialog.dart';
import 'package:basecamp/ui/undo_delete.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// Bottom sheet showing an activity's details and the child roster for it.
/// Roster is derived from group membership: children whose group is listed (or
/// all children if the item targets "all groups").
///
/// Also hosts the "Just for today" override actions — cancel this
/// instance, or shift its start/end times for this date only. The
/// template stays untouched so next week's occurrence is unaffected.
class ActivityDetailSheet extends ConsumerWidget {
  const ActivityDetailSheet({required this.item, super.key});

  final ScheduleItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final kidsAsync = ref.watch(childrenProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.md,
        bottom: AppSpacing.xl + insets,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TitleRow(
              item: item,
              hasEditor: (item.isFromTemplate && item.templateId != null) ||
                  (item.entryId != null),
              onEdit: () => _openEdit(context, ref),
              onOpenLibrary: () => _openLibraryCard(context, ref),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              item.isFullDay
                  ? 'All day'
                  : '${_formatTime(item.startTime)} – ${_formatTime(item.endTime)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _AdultRow(adultId: item.adultId),
            _LocationRow(roomId: item.roomId, fallback: item.location),
            _GroupsRow(
              groupIds: item.groupIds,
              isAllGroups: item.isAllGroups,
              isNoGroups: item.isNoGroups,
            ),
            if (item.notes != null && item.notes!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text('Notes', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(item.notes!, style: theme.textTheme.bodyMedium),
            ],
            // v40: reference link row. Self-hides when unset, so
            // activities without a link render unchanged. Tap launches
            // the URL via url_launcher; failure pops a snackbar.
            if (item.sourceUrl != null && item.sourceUrl!.isNotEmpty)
              _SourceUrlRow(url: item.sourceUrl!),
            const SizedBox(height: AppSpacing.xl),
            Text('Roster', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            kidsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text('Error: $err'),
              data: (children) {
                final attending = children
                    .where(
                      (k) =>
                          item.isAllGroups ||
                          (k.groupId != null && item.groupIds.contains(k.groupId)),
                    )
                    .toList();
                if (attending.isEmpty) {
                  return Text(
                    item.isNoGroups
                        ? 'No groups selected — this activity has no children.'
                        : 'No children assigned to these groups yet.',
                    style: theme.textTheme.bodySmall,
                  );
                }
                return Column(
                  children: [
                    for (final child in attending)
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _RosterTile(
                          child: child,
                          onTap: () {
                            Navigator.of(context).pop();
                            unawaited(context.push('/children/${child.id}'));
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
            if (_canOverride)
              _JustForTodaySection(item: item),
            // Capture shortcuts — observation / incident / concern
            // seeded with this activity's context. Sits above the
            // delete row so the destructive action stays visually
            // isolated.
            const SizedBox(height: AppSpacing.lg),
            _CaptureActionRow(item: item),
            // "Save to library" — only for items that aren't already
            // backed by a library card. Creates a fresh card from the
            // item's fields and rewires the template/entry to point at
            // it, so next time the teacher opens the detail sheet the
            // title tap routes to the rich card.
            if (item.sourceLibraryItemId == null) ...[
              const SizedBox(height: AppSpacing.sm),
              _PromoteToLibraryButton(item: item),
            ],
            // Exactly one delete button — the two paths are mutually
            // exclusive by intent, even though a template-sourced
            // item CAN carry both templateId AND entryId (the entry
            // being a per-date override). Template-sourced wins in
            // that case: the user is looking at a weekly pattern,
            // and the two-option sheet covers both "just this day"
            // and "every occurrence."
            if (item.isFromTemplate && item.templateId != null) ...[
              const SizedBox(height: AppSpacing.lg),
              _DeleteTemplateButton(item: item),
            ] else if (item.entryId != null) ...[
              // Pure one-off entry (full-day event, multi-day note,
              // trip-mirrored row). schedule_entries lives outside
              // the template/series world, so it gets its own
              // single-confirm delete.
              const SizedBox(height: AppSpacing.lg),
              _DeleteEntryButton(item: item),
            ],
          ],
        ),
      ),
    );
  }

  /// Close this sheet and open the template editor. Fetching the row
  /// by id (rather than constructing one from [item]) ensures the edit
  /// sheet sees the authoritative data — timing of inserts/updates
  /// elsewhere could otherwise leave a stale snapshot on the UI side.
  Future<void> _openEdit(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final repo = ref.read(scheduleRepositoryProvider);

    // Intentionally DON'T pop this detail sheet before opening the
    // editor — stacking lets the teacher close the editor and land
    // back on the details view (which is what they came here to see).
    // If they commit a change (save) or delete, we co-dismiss the
    // detail sheet after the editor closes, because its snapshot is
    // now stale / orphaned.

    // Template-sourced → open EditTemplateSheet.
    final templateId = item.templateId;
    if (item.isFromTemplate && templateId != null) {
      final template = await repo.getTemplate(templateId);
      if (template == null || !context.mounted) return;
      final result = await showModalBottomSheet<EditTemplateResult>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        isDismissible: false,
        builder: (_) => EditTemplateSheet(
          template: template,
          occurrenceDate: item.date,
        ),
      );
      if (result != null && navigator.mounted) {
        // Committed change or delete → close the (now-stale) detail
        // sheet too. User lands on Today, which is reactive and will
        // reflect the new state.
        navigator.pop();
      }
      return;
    }

    // One-off entry → open the full-day wizard in edit mode. The
    // wizard pops with a CreatedActivity on save, null on close.
    final entryId = item.entryId;
    if (entryId == null) return;
    final entry = await repo.getEntry(entryId);
    if (entry == null || !context.mounted) return;
    final result = await navigator.push<Object?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => NewFullDayEventWizardScreen(existing: entry),
      ),
    );
    if (result != null && navigator.mounted) {
      navigator.pop();
    }
  }

  /// Open the source activity-library card (hook / summary / key
  /// points / learning goals / source). Only reachable when the
  /// activity was created from a library pick — scheduled rows typed
  /// from scratch have no library back-reference.
  Future<void> _openLibraryCard(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final libraryId = item.sourceLibraryItemId;
    if (libraryId == null) return;
    final libraryItem = await ref
        .read(activityLibraryRepositoryProvider)
        .getItem(libraryId);
    if (libraryItem == null || !context.mounted) return;
    // Stacks on top of the detail sheet — closing returns here, so
    // the teacher can read the rich card and then keep going.
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => LibraryCardDetailSheet(item: libraryItem),
    );
  }

  /// Only show override actions on a concrete date — the adult-
  /// detail preview uses a 1970 sentinel date, and multi-day entries
  /// can't be partially shifted without more UX.
  bool get _canOverride {
    if (item.date.year < 2000) return false;
    if (item.isMultiDay) return false;
    if (item.isFullDay) return false;
    return true;
  }

  String _formatTime(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.parse(parts[0]);
    final m = parts[1];
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final period = h < 12 ? 'a' : 'p';
    return m == '00' ? '$hour12$period' : '$hour12:$m$period';
  }
}

/// Action strip at the bottom of the detail sheet: "just for today"
/// overrides that don't touch the template. Template-sourced items get
/// both a shift and a cancel; one-off entries just get a shift (cancel
/// is the existing delete flow).
class _JustForTodaySection extends ConsumerWidget {
  const _JustForTodaySection({required this.item});

  final ScheduleItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dateLabel = _dateLabel(item.date);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'JUST FOR TODAY · $dateLabel',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Changes apply to this date only — the weekly schedule stays.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => _shift(context, ref),
            icon: const Icon(Icons.schedule_outlined, size: 18),
            label: const Text('Shift time'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => _cancel(context, ref),
            icon: Icon(
              Icons.event_busy_outlined,
              size: 18,
              color: theme.colorScheme.error,
            ),
            label: Text(
              'Cancel today',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: theme.colorScheme.error.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shift(BuildContext context, WidgetRef ref) async {
    final start = item.startTimeOfDay;
    final end = item.endTimeOfDay;
    final durationMinutes =
        (end.hour * 60 + end.minute) - (start.hour * 60 + start.minute);

    final newStart = await showTimePicker(
      context: context,
      initialTime: start,
      helpText: 'Shift starts at',
    );
    if (newStart == null || !context.mounted) return;

    final newEndDefault = _addMinutes(newStart, durationMinutes);
    final newEnd = await showTimePicker(
      context: context,
      initialTime: newEndDefault,
      helpText: 'And ends at',
    );
    if (newEnd == null || !context.mounted) return;

    final startMin = newStart.hour * 60 + newStart.minute;
    final endMin = newEnd.hour * 60 + newEnd.minute;
    if (endMin <= startMin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start.')),
      );
      return;
    }

    final repo = ref.read(scheduleRepositoryProvider);
    final startHhmm = _hhmm(newStart);
    final endHhmm = _hhmm(newEnd);
    if (item.isFromTemplate && item.templateId != null) {
      await repo.shiftTemplateForDate(
        templateId: item.templateId!,
        date: item.date,
        startTime: startHhmm,
        endTime: endHhmm,
      );
    } else if (item.entryId != null) {
      await repo.shiftEntryTimes(
        entryId: item.entryId!,
        startTime: startHhmm,
        endTime: endHhmm,
      );
    }
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Cancel "${item.title}" today?',
      message:
          'This skips the activity on ${_dateLabel(item.date)}. The '
          'weekly schedule is unchanged — it will run next week as '
          'usual.',
      confirmLabel: 'Cancel today',
    );
    if (!confirmed || !context.mounted) return;

    final repo = ref.read(scheduleRepositoryProvider);
    if (item.isFromTemplate && item.templateId != null) {
      await repo.cancelTemplateForDate(
        templateId: item.templateId!,
        date: item.date,
      );
    } else if (item.entryId != null) {
      await repo.deleteEntry(item.entryId!);
    }
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  TimeOfDay _addMinutes(TimeOfDay t, int minutes) {
    final total = t.hour * 60 + t.minute + minutes;
    final wrapped = ((total % (24 * 60)) + 24 * 60) % (24 * 60);
    return TimeOfDay(hour: wrapped ~/ 60, minute: wrapped % 60);
  }

  String _dateLabel(DateTime date) {
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
    return '${months[date.month - 1]} ${date.day}';
  }
}

/// v40: reference link row on the detail sheet. Sits near the Notes
/// block. Renders as icon + truncated URL; tap launches via
/// url_launcher. When the OS can't handle the scheme we surface a
/// brief snackbar rather than failing silently.
class _SourceUrlRow extends StatelessWidget {
  const _SourceUrlRow({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: InkWell(
        onTap: () => _launch(context),
        borderRadius: BorderRadius.circular(AppSpacing.xs),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              Icon(
                Icons.link,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  url,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launch(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(url);
    if (uri == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't parse that link.")),
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't open that link.")),
      );
    }
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _AdultRow extends ConsumerWidget {
  const _AdultRow({required this.adultId});

  final String? adultId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (adultId == null) return const SizedBox.shrink();
    final adult = ref.watch(adultProvider(adultId!)).asData?.value;
    if (adult == null) return const SizedBox.shrink();
    final label = adult.role == null || adult.role!.isEmpty
        ? adult.name
        : '${adult.name} · ${adult.role}';
    return _MetaRow(icon: Icons.badge_outlined, text: label);
  }
}

/// Location row that prefers the tracked-room name (when set),
/// otherwise falls back to the free-form location string. Free-form
/// strings render as a tappable AddressRow that opens Google Maps —
/// so teachers tapping a "Aquarium day" detail can go straight to
/// directions. Tracked rooms stay as a plain meta row (no map for
/// in-building locations).
class _LocationRow extends ConsumerWidget {
  const _LocationRow({required this.roomId, required this.fallback});

  final String? roomId;
  final String? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (roomId != null) {
      final room = ref.watch(roomProvider(roomId!)).asData?.value;
      if (room != null) {
        return _MetaRow(
          icon: Icons.meeting_room_outlined,
          text: room.name,
        );
      }
    }
    if (fallback == null || fallback!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: AddressRow(address: fallback!),
    );
  }
}

class _GroupsRow extends ConsumerWidget {
  const _GroupsRow({
    required this.groupIds,
    required this.isAllGroups,
    required this.isNoGroups,
  });

  final List<String> groupIds;
  final bool isAllGroups;
  final bool isNoGroups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Empty groupIds used to mean "all groups", but that loses the
    // three-state audience: "everyone" vs "no one (staff prep)" vs
    // "these specific groups". Honor the flags directly.
    if (isAllGroups) {
      return const _MetaRow(
        icon: Icons.groups_outlined,
        text: 'All groups',
      );
    }
    if (isNoGroups) {
      return const _MetaRow(
        icon: Icons.groups_outlined,
        text: 'No groups · staff prep',
      );
    }
    final names = <String>[];
    for (final id in groupIds) {
      final group = ref.watch(groupProvider(id)).asData?.value;
      if (group != null) names.add(group.name);
    }
    if (names.isEmpty) return const SizedBox.shrink();
    return _MetaRow(
      icon: Icons.groups_outlined,
      text: names.join(' + '),
    );
  }
}

/// Title row at the top of the detail sheet. Shape depends on whether
/// the activity has a library source and/or an editor:
///   - No source, no editor  → plain title text (rare, legacy rows)
///   - No source, editor     → title + Edit button
///   - Has source, editor    → tappable title (↗ opens library card)
///                             + Edit button
/// The library-source tap is the ask: "title should open activity
/// detail" meaning the rich library card with hook/summary/key points.
class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.item,
    required this.hasEditor,
    required this.onEdit,
    required this.onOpenLibrary,
  });

  final ScheduleItem item;
  final bool hasEditor;
  final VoidCallback onEdit;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasLibrarySource = item.sourceLibraryItemId != null;

    final titleWidget = hasLibrarySource
        ? InkWell(
            onTap: onOpenLibrary,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 4,
                horizontal: 4,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      item.title,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    // Subtle hint that the title opens something.
                    Icons.north_east,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
          )
        : Text(item.title, style: theme.textTheme.titleLarge);

    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: titleWidget,
          ),
        ),
        if (hasEditor)
          TextButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    );
  }
}

/// Recurring-template delete. Taps open a modal-sheet with two
/// choices: "Just this day" (non-destructive cancel-for-date) or
/// "Every occurrence" (nukes the template + sibling pattern with an
/// undo). Placed on the detail sheet so teachers don't have to go
/// through Edit to delete a weekly pattern.
class _DeleteTemplateButton extends ConsumerWidget {
  const _DeleteTemplateButton({required this.item});

  final ScheduleItem item;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final templateId = item.templateId;
    if (templateId == null) return;
    final choice = await showModalBottomSheet<_TemplateDeleteChoice>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _TemplateDeleteChoiceSheet(title: item.title),
    );
    if (choice == null || !context.mounted) return;
    final repo = ref.read(scheduleRepositoryProvider);
    final navigator = Navigator.of(context);
    switch (choice) {
      case _TemplateDeleteChoice.thisDay:
        // cancelTemplateForDate writes a 'cancellation' entry for
        // this date — the weekly pattern stays, just this occurrence
        // hides. Confirmation snackbar only, no undo helper.
        await repo.cancelTemplateForDate(
          templateId: templateId,
          date: item.date,
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                '"${item.title}" hidden for this day only.',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        navigator.pop();
      case _TemplateDeleteChoice.everyOccurrence:
        // Snapshot the sibling set before delete so the 5-second
        // undo restores the whole weekly pattern, not just one row.
        final siblings = await repo.siblingTemplatesFor(templateId);
        if (!context.mounted) return;
        final confirmed = await confirmDeleteWithUndo(
          context: context,
          title: 'Delete every occurrence?',
          message: siblings.length > 1
              ? 'This removes "${item.title}" from all '
                  '${siblings.length} days it runs. '
                  "You'll get a 5-second window to undo."
              : 'This removes "${item.title}" from every day it '
                  "runs (weekly pattern). You'll get a 5-second "
                  'window to undo.',
          confirmLabel: 'Delete all',
          onDelete: () => repo.deleteTemplateGroupFor(templateId),
          undoLabel: '"${item.title}" removed',
          onUndo: () => repo.restoreTemplates(siblings),
        );
        if (!confirmed) return;
        navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return OutlinedButton.icon(
      onPressed: () => _open(context, ref),
      icon: Icon(
        Icons.delete_outline,
        color: theme.colorScheme.error,
      ),
      label: Text(
        'Delete…',
        style: TextStyle(color: theme.colorScheme.error),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(
          color: theme.colorScheme.error.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

enum _TemplateDeleteChoice { thisDay, everyOccurrence }

class _TemplateDeleteChoiceSheet extends StatelessWidget {
  const _TemplateDeleteChoiceSheet({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.md,
                top: AppSpacing.xs,
                bottom: AppSpacing.md,
              ),
              child: Text(
                'Delete "$title"',
                style: theme.textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.today_outlined),
              title: const Text('Just this day'),
              subtitle: const Text(
                'Hides the activity on this date; the weekly pattern '
                'keeps running every other week.',
              ),
              onTap: () => Navigator.of(context).pop(
                _TemplateDeleteChoice.thisDay,
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.event_busy_outlined,
                color: theme.colorScheme.error,
              ),
              title: Text(
                'Every occurrence (weekly)',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              subtitle: const Text(
                'Removes the template entirely. Past instances stay '
                'in history; future ones stop happening.',
              ),
              onTap: () => Navigator.of(context).pop(
                _TemplateDeleteChoice.everyOccurrence,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

class _DeleteEntryButton extends ConsumerWidget {
  const _DeleteEntryButton({required this.item});

  final ScheduleItem item;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final entryId = item.entryId;
    if (entryId == null) return;
    final repo = ref.read(scheduleRepositoryProvider);
    final entry = await repo.getEntry(entryId);
    if (entry == null || !context.mounted) return;
    final navigator = Navigator.of(context);
    final title = item.isMultiDay ? 'Delete every day?' : 'Delete event?';
    final message = item.isMultiDay
        ? 'This removes "${item.title}" from all '
            '${item.rangeEnd!.difference(item.rangeStart!).inDays + 1}'
            " days it spans. You'll get a 5-second window to undo."
        : "You'll get a 5-second window to undo.";
    final confirmed = await confirmDeleteWithUndo(
      context: context,
      title: title,
      message: message,
      confirmLabel: item.isMultiDay ? 'Delete all days' : 'Delete',
      onDelete: () => repo.deleteEntry(entryId),
      undoLabel: '"${item.title}" removed',
      onUndo: () => repo.restoreEntry(entry),
    );
    if (!confirmed) return;
    navigator.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return OutlinedButton.icon(
      onPressed: () => _delete(context, ref),
      icon: Icon(
        Icons.delete_outline,
        color: theme.colorScheme.error,
      ),
      label: Text(
        item.isMultiDay ? 'Delete all days' : 'Delete event',
        style: TextStyle(color: theme.colorScheme.error),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(
          color: theme.colorScheme.error.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _RosterTile extends ConsumerWidget {
  const _RosterTile({required this.child, required this.onTap});

  final Child child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fullName =
        [child.firstName, child.lastName].whereType<String>().join(' ');
    final initial = child.firstName.isNotEmpty
        ? child.firstName.characters.first.toUpperCase()
        : '?';
    final groupId = child.groupId;
    final group =
        groupId == null ? null : ref.watch(groupProvider(groupId)).asData?.value;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          SmallAvatar(
            // Same drift-first pipeline every other roster tile
            // uses — photo flows in via avatar_storage_path
            // when the device hasn't captured the photo locally.
            path: child.avatarPath,
            storagePath: child.avatarStoragePath,
            etag: child.avatarEtag,
            fallbackInitial: initial,
            radius: 16,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fullName, style: theme.textTheme.titleMedium),
                if (group != null)
                  Text(group.name, style: theme.textTheme.bodySmall),
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

/// "Save to library" — promote a one-off scheduled activity into a
/// reusable library card. Fires when the item has no back-link
/// (`sourceLibraryItemId == null`); creates a card from the item's
/// fields, rewires the template/entry to point at the new card, then
/// offers an "Open" action on the confirmation snackbar so the
/// teacher can immediately enrich the card with materials, domains,
/// audience, etc.
class _PromoteToLibraryButton extends ConsumerStatefulWidget {
  const _PromoteToLibraryButton({required this.item});

  final ScheduleItem item;

  @override
  ConsumerState<_PromoteToLibraryButton> createState() =>
      _PromoteToLibraryButtonState();
}

class _PromoteToLibraryButtonState
    extends ConsumerState<_PromoteToLibraryButton> {
  bool _saving = false;

  Future<void> _promote() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final rootNav = Navigator.of(context, rootNavigator: true);
    final libraryRepo = ref.read(activityLibraryRepositoryProvider);
    final scheduleRepo = ref.read(scheduleRepositoryProvider);
    try {
      final newId =
          await libraryRepo.createFromScheduleItem(widget.item);
      final templateId = widget.item.templateId;
      final entryId = widget.item.entryId;
      // Template-sourced wins when both are set (same precedence as
      // the delete button below): the teacher's looking at a
      // recurring row, so the weekly pattern becomes the thing
      // linked to the new card.
      if (widget.item.isFromTemplate && templateId != null) {
        await scheduleRepo.setTemplateSourceLibraryItem(
          templateId: templateId,
          libraryItemId: newId,
        );
      } else if (entryId != null) {
        await scheduleRepo.setEntrySourceLibraryItem(
          entryId: entryId,
          libraryItemId: newId,
        );
      }
      if (!mounted) return;
      final newCard = await libraryRepo.getItem(newId);
      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: const Text(
              'Saved to library. Edit the card to add materials, '
              'domains, etc.',
            ),
            duration: const Duration(seconds: 6),
            action: newCard == null
                ? null
                : SnackBarAction(
                    label: 'Open',
                    onPressed: () {
                      if (!rootNav.mounted) return;
                      unawaited(
                        showModalBottomSheet<void>(
                          context: rootNav.context,
                          isScrollControlled: true,
                          showDragHandle: true,
                          useSafeArea: true,
                          builder: (_) =>
                              EditLibraryItemSheet(item: newCard),
                        ),
                      );
                    },
                  ),
          ),
        );
    } on Object catch (e) {
      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text("Couldn't save to library: $e")),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _saving ? null : _promote,
      icon: _saving
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.bookmark_add_outlined, size: 18),
      label: const Text('Save to library'),
    );
  }
}

/// Three-button shortcut row: log observation, report incident, or
/// start a concern note — all pre-seeded with the activity's context
/// so the teacher doesn't retype it.
///
/// The row lives on every activity detail sheet (the unified drill-
/// through surface), so a teacher reading about what's running can
/// go straight into capture without bouncing back to the FAB. Each
/// button pops the sheet first and then opens the target surface on
/// the root navigator — keeps the nav stack shallow.
class _CaptureActionRow extends StatelessWidget {
  const _CaptureActionRow({required this.item});

  final ScheduleItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        OutlinedButton.icon(
          onPressed: () => _openObservation(context),
          icon: const Icon(Icons.visibility_outlined, size: 18),
          label: const Text('Observation'),
        ),
        OutlinedButton.icon(
          onPressed: () => _openIncident(context),
          icon: Icon(
            Icons.report_problem_outlined,
            size: 18,
            color: theme.colorScheme.error,
          ),
          label: Text(
            'Incident',
            style: TextStyle(color: theme.colorScheme.error),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: theme.colorScheme.error.withValues(alpha: 0.4),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _openConcern(context),
          icon: const Icon(Icons.chat_outlined, size: 18),
          label: const Text('Concern'),
        ),
      ],
    );
  }

  /// Open the observation composer as a bottom sheet scoped to this
  /// activity. Mirrors Today's wrapper so the "Saved" snackbar renders
  /// inside the sheet rather than on a messenger hidden behind the
  /// modal backdrop.
  Future<void> _openObservation(BuildContext context) async {
    final rootNav = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).pop();
    // Defer to the next frame so the detail sheet is fully dismissed
    // before the composer sheet mounts. Without this, Flutter warns
    // about pushing while a route is being removed.
    await Future<void>.delayed(Duration.zero);
    if (!rootNav.mounted) return;
    await showModalBottomSheet<void>(
      context: rootNav.context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: ObservationComposer(forActivity: item),
          ),
        );
      },
    );
  }

  /// Open the incident form as a fullscreen dialog. activity_label
  /// and location prefill so the teacher doesn't retype context
  /// they're literally looking at — the "where" and "during what"
  /// fields come filled in.
  Future<void> _openIncident(BuildContext context) async {
    final rootNav = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).pop();
    await Future<void>.delayed(Duration.zero);
    if (!rootNav.mounted) return;
    await rootNav.push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => GenericFormScreen(
          definition: incidentForm,
          prefillData: {
            'activity_label': item.title,
            if (item.location != null && item.location!.isNotEmpty)
              'location': item.location,
          },
        ),
      ),
    );
  }

  /// Open a fresh concern note in wizard presentation. Concerns
  /// aren't activity-scoped (they're parent-raised about a child),
  /// so nothing prefills — the button is here for consistency with
  /// the other detail screens.
  Future<void> _openConcern(BuildContext context) async {
    final rootNav = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).pop();
    await Future<void>.delayed(Duration.zero);
    if (!rootNav.mounted) return;
    await rootNav.push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            const GenericFormScreen(definition: parentConcernForm),
      ),
    );
  }
}
