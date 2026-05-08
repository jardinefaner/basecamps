// Command Center — voice-first single-surface experiment.
//
// One screen. One bar at the bottom. A feed at the top showing
// what's been created today. The bar accepts any short fragment
// — observations, calendar tiles, late-pickup rows — and the
// LLM picks the right tool from the verb in the sentence.
//
// What this proves: that voice-first is a viable replacement
// for "navigate to a screen, find a button, fill out a form."
// If teachers naturally fall into the bar instead of the
// per-feature drop bars, we promote this pattern, dock the bar
// at the bottom of every screen, and consolidate.
//
// What this doesn't do (yet):
//   * no voice input — text only for v0; Deepgram plug-in is
//     trivial once the loop is proven
//   * no append-to-last — every utterance is a fresh action
//   * no cross-program / cross-time queries — feed is "today"
//   * no editing inline — feed entries link to the source screen
//
// Lab proof. Real if we promote.

import 'dart:async';

import 'package:basecamp/database/database.dart' show Child;
import 'package:basecamp/features/adults/adults_repository.dart'
    show currentAdultProvider;
import 'package:basecamp/features/ai/openai_client.dart';
import 'package:basecamp/features/children/children_repository.dart'
    show childrenProvider, groupsProvider;
import 'package:basecamp/features/experiment/command_llm_service.dart';
import 'package:basecamp/features/experiment/late_pickup_llm_service.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class CommandScreen extends ConsumerStatefulWidget {
  const CommandScreen({super.key});

  @override
  ConsumerState<CommandScreen> createState() => _CommandScreenState();
}

class _CommandScreenState extends ConsumerState<CommandScreen> {
  CommandDraft? _draft;
  bool _loading = false;
  String? _error;

  /// Local feed of items committed THIS session. Observations
  /// are also persisted to the cloud-synced repo, but we keep
  /// the local feed for fast rendering + so calendar/late-pickup
  /// drafts (which today land in their own in-memory lab models)
  /// have somewhere to surface from this screen.
  final List<_FeedEntry> _feed = <_FeedEntry>[];

  // ——— Submission ———————————————————————————————————————————————

  Future<void> _onSubmit(String input) async {
    setState(() {
      _loading = true;
      _error = null;
      _draft = null;
    });
    try {
      final children = ref.read(childrenProvider).asData?.value ??
          const <Child>[];
      final groups = ref.read(groupsProvider).asData?.value ?? const [];
      final adult = ref.read(currentAdultProvider).asData?.value;
      final staffName = (adult?.name.trim() ?? '').isEmpty
          ? 'Staff'
          : adult!.name.trim();
      final activeGroupName = groups.isEmpty ? 'group' : groups.first.name;
      final draft = await CommandLlmService.draftFromText(
        input: input,
        now: DateTime.now(),
        roster: CommandRoster(
          staffName: staffName,
          activeGroupName: activeGroupName,
          availableGroups: groups.map((g) => g.name).toList(),
          children: children
              .map(
                (c) => LatePickupRosterChild(
                  id: c.id,
                  firstName: c.firstName,
                  lastName: c.lastName,
                  parentName: c.parentName,
                ),
              )
              .toList(),
        ),
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
      debugPrint('[command] $e');
    }
  }

  Future<void> _onConfirm() async {
    final draft = _draft;
    if (draft == null) return;
    switch (draft) {
      case ObservationCommandDraft():
        await _commitObservation(draft);
      case CalendarTileCommandDraft():
        _commitCalendarTile(draft);
      case LatePickupCommandDraft():
        _commitLatePickup(draft);
    }
    if (!mounted) return;
    setState(() {
      _draft = null;
      _error = null;
    });
  }

  Future<void> _commitObservation(ObservationCommandDraft d) async {
    final repo = ref.read(observationsRepositoryProvider);
    try {
      final id = await repo.addObservation(
        domains: [d.domain],
        sentiment: d.sentiment,
        note: d.note,
        childIds: d.childIds,
        // The current adult's name flows in via `_authorName` on the
        // repo, but addObservation also accepts an explicit string —
        // pass it so the row lights up "Logged by ..." even when the
        // adult provider is mid-load on a fresh launch.
        authorName: ref
            .read(currentAdultProvider)
            .asData
            ?.value
            ?.name,
      );
      if (!mounted) return;
      setState(() {
        _feed.insert(
          0,
          _FeedEntry(
            kind: _FeedKind.observation,
            timestamp: DateTime.now(),
            title: d.note,
            subtitle: d.summary(),
            destinationPath: '/observations',
            payload: id,
          ),
        );
      });
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save observation: $e')),
      );
    }
  }

  void _commitCalendarTile(CalendarTileCommandDraft d) {
    // The calendar tile doesn't persist (in-memory lab); we
    // still surface it on the feed and link to /calendar so the
    // teacher can finish there if they want a real tile.
    final c = d.calendar;
    final timeFmt = DateFormat('h:mm a');
    final dateFmt = DateFormat.MMMEd();
    final summary = StringBuffer()..write(dateFmt.format(c.date));
    if (c.startTime != null) {
      summary
        ..write(' · ')
        ..write(timeFmt.format(
          DateTime(0, 1, 1, c.startTime!.hour, c.startTime!.minute),
        ));
    }
    if (c.destination != null && c.destination!.isNotEmpty) {
      summary
        ..write(' · ')
        ..write(c.destination);
    }
    setState(() {
      _feed.insert(
        0,
        _FeedEntry(
          kind: _FeedKind.calendarTile,
          timestamp: DateTime.now(),
          title: c.title,
          subtitle: summary.toString(),
          destinationPath: '/calendar',
        ),
      );
    });
  }

  void _commitLatePickup(LatePickupCommandDraft d) {
    final l = d.latePickup;
    final timeLabel = l.pickupTime.format(context);
    final summary = StringBuffer()..write(timeLabel);
    if (l.parentName.isNotEmpty) {
      summary
        ..write(' · ')
        ..write(l.parentName);
    }
    if (l.reminderCardGiven) summary.write(' · 📩 reminder card');
    setState(() {
      _feed.insert(
        0,
        _FeedEntry(
          kind: _FeedKind.latePickup,
          timestamp: DateTime.now(),
          title: l.childName,
          subtitle: summary.toString(),
          destinationPath: '/late-pickup',
        ),
      );
    });
  }

  void _onDismiss() {
    setState(() {
      _draft = null;
      _error = null;
    });
  }

  // ——— Build ————————————————————————————————————————————————————

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Command Center')),
      body: Column(
        children: [
          Expanded(
            child: _feed.isEmpty
                ? _EmptyState(theme: theme)
                : _Feed(entries: _feed),
          ),
          _CommandBar(
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
}

// ═════════════════════════════════════════════════════════════════
// Feed
// ═════════════════════════════════════════════════════════════════

enum _FeedKind { observation, calendarTile, latePickup }

class _FeedEntry {
  const _FeedEntry({
    required this.kind,
    required this.timestamp,
    required this.title,
    required this.subtitle,
    required this.destinationPath,
    this.payload,
  });

  final _FeedKind kind;
  final DateTime timestamp;
  final String title;
  final String subtitle;
  final String destinationPath;
  final Object? payload;
}

class _Feed extends StatelessWidget {
  const _Feed({required this.entries});

  final List<_FeedEntry> entries;

  IconData _iconFor(_FeedKind k) => switch (k) {
        _FeedKind.observation => Icons.edit_note_outlined,
        _FeedKind.calendarTile => Icons.calendar_today_outlined,
        _FeedKind.latePickup => Icons.access_time_outlined,
      };

  String _badgeFor(_FeedKind k) => switch (k) {
        _FeedKind.observation => 'OBSERVATION',
        _FeedKind.calendarTile => 'CALENDAR',
        _FeedKind.latePickup => 'LATE PICKUP',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeFmt = DateFormat.jm();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) {
        final e = entries[i];
        return Material(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => context.push(e.destinationPath),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: AppSpacing.sm),
                    child: Icon(
                      _iconFor(e.kind),
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _badgeFor(e.kind),
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              timeFmt.format(e.timestamp),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          e.title,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          e.subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
              Icons.auto_awesome_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Voice-first command surface.',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Type below — the LLM picks the right tool.\n\n'
              '"Phillip helped Maya tie her shoe today" → observation\n'
              '"Field trip aquarium next tuesday" → calendar\n'
              '"Phillip is late, gave reminder card" → late pickup',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// Command bar
// ═════════════════════════════════════════════════════════════════

class _CommandBar extends StatefulWidget {
  const _CommandBar({
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
  final CommandDraft? draft;
  final String? error;
  final ValueChanged<String> onSubmit;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  @override
  State<_CommandBar> createState() => _CommandBarState();
}

class _CommandBarState extends State<_CommandBar> {
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
              if (widget.draft != null) ...[
                _DraftPreview(
                  draft: widget.draft!,
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
                            ? 'Say or type anything…'
                            : 'Sign in to use AI commands',
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

  final CommandDraft draft;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  ({IconData icon, String badge, String title, String subtitle, Color accent})
      _content(BuildContext context) {
    final theme = Theme.of(context);
    switch (draft) {
      case ObservationCommandDraft(
          :final note,
          :final domain,
          :final sentiment,
          :final childNames
        ):
        final kids =
            childNames.isEmpty ? 'no child tagged' : childNames.join(' + ');
        return (
          icon: Icons.edit_note_outlined,
          badge: 'OBSERVATION',
          title: note,
          subtitle: '$kids · ${domain.code} · ${sentiment.name}',
          accent: theme.colorScheme.primary,
        );
      case CalendarTileCommandDraft(:final calendar):
        final timeFmt = DateFormat('h:mm a');
        final dateFmt = DateFormat.MMMEd();
        final pieces = <String>[dateFmt.format(calendar.date)];
        if (calendar.startTime != null) {
          pieces.add(timeFmt.format(DateTime(
            0,
            1,
            1,
            calendar.startTime!.hour,
            calendar.startTime!.minute,
          )));
        }
        if (calendar.destination != null && calendar.destination!.isNotEmpty) {
          pieces.add(calendar.destination!);
        }
        return (
          icon: calendar.type.icon,
          badge: 'CALENDAR · ${calendar.type.singularLabel.toUpperCase()}',
          title: calendar.title,
          subtitle: pieces.join(' · '),
          accent: theme.colorScheme.secondary,
        );
      case LatePickupCommandDraft(:final latePickup):
        final timeLabel = latePickup.pickupTime.format(context);
        final pieces = <String>[timeLabel];
        if (latePickup.parentName.isNotEmpty) pieces.add(latePickup.parentName);
        if (latePickup.reminderCardGiven) pieces.add('📩 reminder card');
        return (
          icon: Icons.access_time,
          badge: 'LATE PICKUP',
          title: latePickup.childName,
          subtitle: pieces.join(' · '),
          accent: theme.colorScheme.tertiary,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = _content(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: 0.10),
        border: Border.all(color: c.accent.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(c.icon, color: c.accent, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.badge,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  c.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  c.subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
