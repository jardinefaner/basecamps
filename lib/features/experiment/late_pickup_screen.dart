// Late-pickup tracking log — Lab experiment.
//
// One row per kid pickup that ran past closing. Columns mirror
// the user's reference spreadsheet: Date · Pick up time ·
// Child · Parent · Reminder card · Staff · Notes.
//
// Same input grammar as the Calendar drop bar:
//   * Chat-style input pinned to the bottom.
//   * Type a short fragment ("phillip is late, gave reminder
//     card") → LLM parses → preview → confirm → row appears.
//   * Today's date, current time, and signed-in staff are
//     INJECTED — the teacher only types what's new.
//   * Parent autofills from the matched child's profile.
//
// In-memory only for the proof — same trade-off as the Calendar
// experiment. Graduate to a Drift-backed model + sync once the
// surface earns its keep.

import 'dart:async';

import 'package:basecamp/database/database.dart' show Child;
import 'package:basecamp/features/adults/adults_repository.dart'
    show currentAdultProvider;
import 'package:basecamp/features/ai/openai_client.dart';
import 'package:basecamp/features/children/children_repository.dart'
    show childrenProvider;
import 'package:basecamp/features/experiment/late_pickup_llm_service.dart';
import 'package:basecamp/features/experiment/late_pickup_store.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// ═════════════════════════════════════════════════════════════════
// Entry model + screen
// ═════════════════════════════════════════════════════════════════

// LateEntry lives in `late_pickup_store.dart` — public + Riverpod-
// backed so the Command Center can add rows the screen will see.

String _newId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${UniqueKey().hashCode}';

class LatePickupScreen extends ConsumerStatefulWidget {
  const LatePickupScreen({super.key});

  @override
  ConsumerState<LatePickupScreen> createState() => _LatePickupScreenState();
}

class _LatePickupScreenState extends ConsumerState<LatePickupScreen> {
  /// Read-through to the Drift-backed entries stream. Returns
  /// the latest emission or an empty list while the first one
  /// is in flight. Uses `ref.watch` so any read in build path
  /// (including the export `_copyAllAsTsv`) sees the freshest
  /// snapshot — the previous `ref.read` form returned a stale
  /// cached value when a remote sync push had just landed.
  List<LateEntry> get _entries =>
      ref.watch(lateEntriesProvider).asData?.value ?? const <LateEntry>[];

  /// Mutation pipe — writes go through the Drift-backed repo;
  /// the stream provider re-emits on commit. `ref.read` is fine
  /// here (the repo identity doesn't change between rebuilds).
  LatePickupsRepository get _entriesRepo =>
      ref.read(latePickupsRepoProvider);

  // Drop-bar state. `_loading` while the LLM call is in flight;
  // `_draft` is the preview chip the teacher confirms or tweaks;
  // `_error` surfaces parse / network errors as a small red note.
  LatePickupDraft? _draft;
  bool _loading = false;
  String? _error;

  // ——— Drop-bar handlers ——————————————————————————————————————

  Future<void> _onSubmit(String input) async {
    final children = ref.read(childrenProvider).asData?.value ??
        const <Child>[];
    final adult = ref.read(currentAdultProvider).asData?.value;
    final staffName = (adult?.name.trim() ?? '').isEmpty
        ? 'Staff'
        : adult!.name.trim();
    if (children.isEmpty) {
      setState(() => _error = 'No children loaded yet — try again.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _draft = null;
    });
    try {
      final draft = await LatePickupLlmService.draftFromText(
        input: input,
        now: DateTime.now(),
        staffName: staffName,
        roster: children
            .map(
              (c) => LatePickupRosterChild(
                id: c.id,
                firstName: c.firstName,
                lastName: c.lastName,
                parentName: c.parentName,
              ),
            )
            .toList(),
      );
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't parse — try rephrasing.";
      });
      debugPrint('[late-pickup] $e');
    }
  }

  void _onConfirm() {
    final draft = _draft;
    if (draft == null) return;
    unawaited(
      _entriesRepo.add(
        LateEntry(
          id: _newId(),
          date: draft.date,
          pickupTime: draft.pickupTime,
          childId: draft.childId,
          childName: draft.childName,
          parentName: draft.parentName,
          reminderCardGiven: draft.reminderCardGiven,
          staffName: draft.staffName,
          notes: draft.notes ?? '',
        ),
      ),
    );
    setState(() {
      _draft = null;
      _error = null;
    });
  }

  void _onDismiss() {
    setState(() {
      _draft = null;
      _error = null;
    });
  }

  void _onToggleReminder(LateEntry e) {
    e.reminderCardGiven = !e.reminderCardGiven;
    unawaited(_entriesRepo.update(e));
  }

  Future<void> _onEditNotes(LateEntry e) async {
    final newNotes = await showDialog<String>(
      context: context,
      builder: (ctx) => _NotesDialog(initial: e.notes),
    );
    if (newNotes == null) return;
    e.notes = newNotes;
    unawaited(_entriesRepo.update(e));
  }

  void _onDelete(LateEntry e) {
    unawaited(_entriesRepo.remove(e.id));
  }

  // ——— Build ————————————————————————————————————————————————————

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Subscribe so writes from elsewhere (Command Center,
    // sync from another device) rebuild this screen.
    ref.watch(lateEntriesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Late pickup log'),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              tooltip: 'Copy as TSV',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: _copyAllAsTsv,
            ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _entries.isEmpty
                ? _EmptyState(theme: theme)
                : _LateLogSheet(
                    entries: _entries,
                    onToggleReminder: _onToggleReminder,
                    onEditNotes: _onEditNotes,
                    onDelete: _onDelete,
                  ),
          ),
          _DropBar(
            enabled: OpenAiClient.isAvailable,
            loading: _loading,
            draft: _draft,
            error: _error,
            onSubmit: _onSubmit,
            onConfirm: _onConfirm,
            onDismiss: _onDismiss,
          ),
        ],
      ),
    );
  }

  Future<void> _copyAllAsTsv() async {
    final dateFmt = DateFormat('M/d/yy');
    final buf = StringBuffer()
      ..writeln(
        "Date\tPick up time\tChild's name\tParent's name\tReminder card given\tStaff name\tNotes",
      );
    // Reverse so the copy reads chronologically (oldest first),
    // matching how a paper logbook gets filled in.
    for (final e in _entries.reversed) {
      buf.writeln([
        dateFmt.format(e.date),
        _formatTime(context, e.pickupTime),
        e.childName,
        e.parentName,
        if (e.reminderCardGiven) 'TRUE' else 'FALSE',
        e.staffName,
        e.notes,
      ].join('\t'));
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    // Clear any pending toasts and show this one floating + brief.
    // Default snackbars QUEUE behind any in-flight one and run for
    // 4 seconds each — repeated copies pile multi-second sheets on
    // top of the docked drop bar.
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard. Paste in Excel.'),
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(12, 0, 12, 80),
      ),
    );
  }
}

String _formatTime(BuildContext context, TimeOfDay t) => t.format(context);

// ═════════════════════════════════════════════════════════════════
// Sheet
// ═════════════════════════════════════════════════════════════════

class _LateLogSheet extends StatelessWidget {
  const _LateLogSheet({
    required this.entries,
    required this.onToggleReminder,
    required this.onEditNotes,
    required this.onDelete,
  });

  final List<LateEntry> entries;
  final ValueChanged<LateEntry> onToggleReminder;
  final ValueChanged<LateEntry> onEditNotes;
  final ValueChanged<LateEntry> onDelete;

  static const double _rowHeight = 36;
  static const double _headerHeight = 36;

  static const List<_LateCol> _cols = [
    _LateCol(label: 'Date', width: 90),
    _LateCol(label: 'Pickup', width: 90),
    _LateCol(label: 'Child', width: 200),
    _LateCol(label: 'Parent', width: 200),
    _LateCol(label: 'Reminder card', width: 130),
    _LateCol(label: 'Staff', width: 160),
    _LateCol(label: 'Notes', width: 320),
    _LateCol(label: '', width: 56), // delete button
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalWidth = _cols.fold<double>(0, (s, c) => s + c.width);
    final dateFmt = DateFormat('M/d/yy');
    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: totalWidth,
          child: Column(
            children: [
              _LateHeader(cols: _cols, theme: theme, height: _headerHeight),
              Expanded(
                child: ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    return _LateRow(
                      entry: e,
                      cols: _cols,
                      height: _rowHeight,
                      theme: theme,
                      dateFmt: dateFmt,
                      onToggleReminder: () => onToggleReminder(e),
                      onEditNotes: () => onEditNotes(e),
                      onDelete: () => onDelete(e),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LateCol {
  const _LateCol({required this.label, required this.width});
  final String label;
  final double width;
}

class _LateHeader extends StatelessWidget {
  const _LateHeader({
    required this.cols,
    required this.theme,
    required this.height,
  });

  final List<_LateCol> cols;
  final ThemeData theme;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          for (final col in cols)
            Container(
              width: col.width,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.4),
                  ),
                ),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                col.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LateRow extends StatelessWidget {
  const _LateRow({
    required this.entry,
    required this.cols,
    required this.height,
    required this.theme,
    required this.dateFmt,
    required this.onToggleReminder,
    required this.onEditNotes,
    required this.onDelete,
  });

  final LateEntry entry;
  final List<_LateCol> cols;
  final double height;
  final ThemeData theme;
  final DateFormat dateFmt;
  final VoidCallback onToggleReminder;
  final VoidCallback onEditNotes;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    Widget cell(int i, Widget child) {
      return Container(
        width: cols[i].width,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
        alignment: Alignment.centerLeft,
        child: child,
      );
    }

    Text txt(String s) => Text(
          s,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        );

    return Container(
      height: height,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          cell(0, txt(dateFmt.format(entry.date))),
          cell(1, txt(_formatTime(context, entry.pickupTime))),
          cell(2, txt(entry.childName)),
          cell(3, txt(entry.parentName)),
          cell(
            4,
            InkWell(
              onTap: onToggleReminder,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: entry.reminderCardGiven,
                    onChanged: (_) => onToggleReminder(),
                    visualDensity: VisualDensity.compact,
                  ),
                  Text(
                    entry.reminderCardGiven ? 'TRUE' : 'FALSE',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          cell(5, txt(entry.staffName)),
          cell(
            6,
            InkWell(
              onTap: onEditNotes,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  entry.notes.isEmpty ? '— tap to add —' : entry.notes,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: entry.notes.isEmpty
                        ? theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.6)
                        : theme.colorScheme.onSurface,
                    fontStyle: entry.notes.isEmpty
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: cols.last.width,
            child: IconButton(
              tooltip: 'Delete row',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: onDelete,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.access_time_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No late pickups yet.',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Type something like "phillip is late" below to add a row.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// Notes editor dialog
// ═════════════════════════════════════════════════════════════════

class _NotesDialog extends StatefulWidget {
  const _NotesDialog({required this.initial});
  final String initial;

  @override
  State<_NotesDialog> createState() => _NotesDialogState();
}

class _NotesDialogState extends State<_NotesDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Notes'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLines: 4,
        decoration: const InputDecoration(
          hintText: 'Anything else worth logging?',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// Drop bar
// ═════════════════════════════════════════════════════════════════

class _DropBar extends StatefulWidget {
  const _DropBar({
    required this.enabled,
    required this.loading,
    required this.draft,
    required this.error,
    required this.onSubmit,
    required this.onConfirm,
    required this.onDismiss,
  });

  final bool enabled;
  final bool loading;
  final LatePickupDraft? draft;
  final String? error;
  final ValueChanged<String> onSubmit;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  @override
  State<_DropBar> createState() => _DropBarState();
}

class _DropBarState extends State<_DropBar> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty || widget.loading) return;
    widget.onSubmit(text);
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = widget.draft;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (draft != null) ...[
                _DraftPreview(
                  draft: draft,
                  onConfirm: widget.onConfirm,
                  onDismiss: widget.onDismiss,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (widget.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    widget.error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 18,
                    color: widget.enabled
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      enabled: widget.enabled && !widget.loading,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: widget.enabled
                            ? '"phillip is late, gave reminder card"'
                            : 'Sign in to use AI input',
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  if (widget.loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      tooltip: 'Send',
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: widget.enabled ? _submit : null,
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

class _DraftPreview extends StatelessWidget {
  const _DraftPreview({
    required this.draft,
    required this.onConfirm,
    required this.onDismiss,
  });

  final LatePickupDraft draft;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.tertiary;
    final timeFmt = DateFormat('h:mm a');
    final timeLabel = timeFmt.format(
      DateTime(0, 1, 1, draft.pickupTime.hour, draft.pickupTime.minute),
    );
    final summary = StringBuffer()
      ..write(timeLabel)
      ..write(' · ')
      ..write(draft.childName);
    if (draft.parentName.isNotEmpty) {
      summary
        ..write(' · ')
        ..write(draft.parentName);
    }
    if (draft.reminderCardGiven) {
      summary.write(' · 📩 reminder card');
    }
    if (draft.notes != null && draft.notes!.isNotEmpty) {
      summary
        ..write(' · ')
        ..write(draft.notes);
    }
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.access_time, color: accent, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LATE PICKUP',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  summary.toString(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Logged by ${draft.staffName}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDismiss,
          ),
          FilledButton.icon(
            onPressed: onConfirm,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
