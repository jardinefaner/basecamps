// Command Center — voice-first single-surface experiment.
//
// One screen. One bar at the bottom. A feed at the top of what
// the user just did. The bar accepts any short fragment — the
// dispatcher routes to the right tool, executes immediately,
// surfaces the result in the feed + a toast.
//
// Architectural shape (current):
//   * Anchored input ("note, ..." / "trip, ...") → registry's
//     `matchAnchor` strips the prefix + force-routes to the
//     matched tool via `tool_choice` in the LLM call. One
//     round-trip, deterministic.
//   * Unanchored input → context-filtered tool list, LLM picks
//     + extracts args in one round-trip via OpenAI tool-calling.
//   * Tool's `execute(args, ref)` runs immediately, writes to
//     the cloud-synced repo, returns a `CommandResult`.
//   * The bar inserts a feed row + shows a toast with a "View"
//     action linking to the source screen.
//
// Compared to the prior 2-pass classifier:
//   * 1 LLM round-trip instead of 2 — half the latency.
//   * Tool schemas enforce arg shape — no JSON parsing failures.
//   * Adding a new tool is one `registry.register(...)` call;
//     no central classifier prompt to maintain.
//   * Provider-abstracted — swap OpenAI → Anthropic / local
//     later by writing one more `LlmProvider`.
//   * Recent-records context window drives anaphora (append-to-
//     last) for any tool that needs it.

import 'dart:async';

import 'package:basecamp/features/ai/openai_client.dart';
import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:basecamp/features/experiment/command/dispatcher/command_dispatcher.dart';
import 'package:basecamp/features/programs/programs_repository.dart'
    show activeProgramIdProvider;
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Show a brief toast that doesn't queue and doesn't block the
/// docked input bar. `clearSnackBars()` first so repeated Adds
/// replace instead of stack; 3-second duration; floating
/// behavior with bottom margin so it sits above the bar.
void _showToast(
  BuildContext context,
  String message, {
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      action: action,
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 80),
    ),
  );
}

class CommandScreen extends ConsumerStatefulWidget {
  const CommandScreen({super.key});

  @override
  ConsumerState<CommandScreen> createState() => _CommandScreenState();
}

class _CommandScreenState extends ConsumerState<CommandScreen> {
  bool _loading = false;
  String? _error;

  /// Recent results, newest first. Drives the feed view + the
  /// `recentRecords` window the dispatcher passes to the LLM
  /// for anaphora resolution.
  final List<_FeedEntry> _feed = <_FeedEntry>[];

  /// Window of recent-record summaries the dispatcher includes
  /// in the system prompt so the LLM can route "and they were
  /// laughing" to an `append` tool with the right target id.
  static const int _recentCap = 5;
  List<RecentCommandRecord> get _recentRecords {
    return _feed
        .where((e) => e.recordId != null)
        .take(_recentCap)
        .map(
          (e) => RecentCommandRecord(
            id: e.recordId!,
            type: e.recordType,
            summary: e.title,
            createdAt: e.timestamp,
          ),
        )
        .toList();
  }

  Future<void> _onSubmit(String input) async {
    if (input.trim().isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final ctx = CommandContext(
      route: '/command',
      activeProgramId: ref.read(activeProgramIdProvider),
      recentRecords: _recentRecords,
    );
    try {
      final dispatcher = ref.read(commandDispatcherProvider);
      final results = await dispatcher.submit(input: input, ctx: ctx);
      if (!mounted) return;
      setState(() {
        _loading = false;
        for (final r in results) {
          _feed.insert(
            0,
            _FeedEntry(
              recordId: r.recordId,
              recordType: _inferType(r.badge),
              title: r.title,
              subtitle: r.subtitle,
              badge: r.badge,
              icon: r.icon,
              destinationPath: r.destinationPath,
              timestamp: DateTime.now(),
            ),
          );
        }
      });
      // Combined toast — covers single and multi-tool results.
      final first = results.first;
      final extras = results.length - 1;
      final message = extras == 0
          ? '${first.badge}: ${first.title}'
          : '${first.badge}: ${first.title} (+$extras more)';
      _showToast(
        context,
        message,
        action: first.destinationPath != null
            ? SnackBarAction(
                label: 'View',
                onPressed: () => context.push(first.destinationPath!),
              )
            : null,
      );
    } on CommandDispatcherException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't run that — try again.";
      });
      debugPrint('[command] $e');
    }
  }

  /// Infer the recent-record `type` slug from the tool's badge.
  /// Used so the LLM's classifier sees a consistent vocabulary
  /// for "what is this" when the recent-records context block
  /// goes into the system prompt.
  String _inferType(String badge) {
    final upper = badge.toUpperCase();
    if (upper.startsWith('OBSERVATION') || upper == 'APPEND') {
      return 'observation';
    }
    if (upper.startsWith('CALENDAR')) return 'calendarTile';
    if (upper.startsWith('LATE')) return 'latePickup';
    return 'record';
  }

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
            error: _error,
            onSubmit: _onSubmit,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// Feed
// ═════════════════════════════════════════════════════════════════

class _FeedEntry {
  const _FeedEntry({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.icon,
    required this.timestamp,
    required this.recordType,
    this.recordId,
    this.destinationPath,
  });

  final String? recordId;
  final String recordType;
  final String title;
  final String subtitle;
  final String badge;
  final IconData icon;
  final DateTime timestamp;
  final String? destinationPath;
}

class _Feed extends StatelessWidget {
  const _Feed({required this.entries});

  final List<_FeedEntry> entries;

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
            onTap: e.destinationPath == null
                ? null
                : () => context.push(e.destinationPath!),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.only(top: 2, right: AppSpacing.sm),
                    child: Icon(
                      e.icon,
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
                              e.badge,
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
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          e.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (e.destinationPath != null)
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
              'Type or anchor — the LLM picks the right tool.\n\n'
              '"Note, Phillip helped Maya tie his shoe"\n'
              '"Trip, aquarium next tuesday for sunflowers"\n'
              '"Late pickup, Phillip 6:15 reminder card"',
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
    required this.error,
    required this.onSubmit,
  });

  final bool enabled;
  final bool loading;
  final String? error;
  final ValueChanged<String> onSubmit;

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
