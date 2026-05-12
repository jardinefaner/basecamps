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
import 'dart:convert';

import 'package:basecamp/features/ai/openai_client.dart';
import 'package:basecamp/features/children/children_repository.dart'
    show childrenProvider, groupsProvider;
import 'package:basecamp/features/experiment/command/command_feed.dart';
import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:basecamp/features/experiment/command/dispatcher/command_dispatcher.dart';
import 'package:basecamp/features/observations/voice_service.dart';
import 'package:basecamp/features/programs/programs_repository.dart'
    show activeProgramIdProvider;
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

// _showToast removed — feed entries are the confirmation
// surface. Earlier snackbars duplicated info AND could persist
// past a navigation if the user moved away mid-fade.

class CommandScreen extends ConsumerStatefulWidget {
  const CommandScreen({super.key});

  @override
  ConsumerState<CommandScreen> createState() => _CommandScreenState();
}

class _CommandScreenState extends ConsumerState<CommandScreen> {
  // Global error banner removed — every dispatch failure lives
  // on its own feed card now, with retry + dismiss actions right
  // there. The teacher sees what failed AND what they originally
  // typed, on the same card.

  /// Window of recent-record summaries the dispatcher includes
  /// in the system prompt so the LLM can route "and they were
  /// laughing" to an `append` tool with the right target id.
  static const int _recentCap = 5;
  List<RecentCommandRecord> _recentRecordsFromFeed(
    List<CommandFeedEntry> feed,
  ) {
    return feed
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

  /// Optimistic submit flow. Prepends a pending card with the
  /// raw input the moment the user hits send, clears the input
  /// bar IMMEDIATELY, then dispatches the LLM call detached. The
  /// pending card morphs into the real result (or a failure
  /// card with retry) when the future resolves. The user can
  /// type another command while the previous one is still in
  /// flight — each in-flight submit gets its own card.
  void _onSubmit(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;
    final pendingId = 'feed-${DateTime.now().microsecondsSinceEpoch}-'
        '${UniqueKey().hashCode}';
    final feedNotifier = ref.read(commandFeedProvider.notifier);
    feedNotifier.prepend(pendingEntryFromInput(trimmed, id: pendingId));
    unawaited(_dispatchAndResolve(trimmed, pendingId));
  }

  /// The dispatch + resolve half of the optimistic flow. Runs
  /// detached from `_onSubmit` so the bar isn't blocked.
  Future<void> _dispatchAndResolve(String input, String pendingId) async {
    final feedNotifier = ref.read(commandFeedProvider.notifier);
    try {
      // Inject the live roster so the LLM resolves "for sunflowers
      // and acorns" / "phillip helped maya" against REAL names.
      final groups = ref.read(groupsProvider).asData?.value ?? const [];
      final children = ref.read(childrenProvider).asData?.value ?? const [];
      final firstNames = <String>{
        for (final c in children) c.firstName.trim(),
      }..removeWhere((s) => s.isEmpty);
      // Use the feed snapshot BEFORE the optimistic insert went
      // in — the pending card itself shouldn't show up in the
      // recent-records anaphora window.
      final currentFeed = ref
          .read(commandFeedProvider)
          .where((e) => e.id != pendingId)
          .toList();
      final ctx = CommandContext(
        route: '/command',
        activeProgramId: ref.read(activeProgramIdProvider),
        recentRecords: _recentRecordsFromFeed(currentFeed),
        groupNames: [for (final g in groups) g.name],
        childNames: firstNames.toList(),
      );
      final dispatcher = ref.read(commandDispatcherProvider);
      final results = await dispatcher.submit(input: input, ctx: ctx);
      // First result replaces the pending card in place; any
      // extra results (rare; only happens for multi-tool calls)
      // get prepended as fresh entries with their own ids.
      if (results.isEmpty) {
        feedNotifier.markFailed(
          pendingId,
          "Couldn't run that — try rephrasing.",
        );
        return;
      }
      final first = results.first;
      feedNotifier.replace(
        pendingId,
        feedEntryFromResult(
          first,
          id: pendingId,
          recordType: _inferType(first.badge),
        ),
      );
      for (final extra in results.skip(1)) {
        feedNotifier.prepend(
          feedEntryFromResult(
            extra,
            id: 'feed-${DateTime.now().microsecondsSinceEpoch}-'
                '${UniqueKey().hashCode}',
            recordType: _inferType(extra.badge),
          ),
        );
      }
    } on CommandDispatcherException catch (e) {
      feedNotifier.markFailed(pendingId, e.message);
    } on Object catch (e, st) {
      final asString = e.toString();
      final summary =
          asString.length > 200 ? '${asString.substring(0, 197)}…' : asString;
      final isAiProxy = asString.contains('openai-chat') ||
          asString.contains('OpenAiClientException');
      feedNotifier.markFailed(
        pendingId,
        isAiProxy ? 'AI proxy error — $summary' : summary,
      );
      debugPrint('[command] $e\n$st');
    }
  }

  /// Retry the dispatch for a card that failed earlier. Resets
  /// the card to pending, kicks off the same flow with the
  /// original raw input.
  void _retryEntry(CommandFeedEntry entry) {
    final input = entry.userInput?.trim() ?? entry.title.trim();
    if (input.isEmpty) return;
    ref.read(commandFeedProvider.notifier).replace(
          entry.id,
          pendingEntryFromInput(input, id: entry.id),
        );
    unawaited(_dispatchAndResolve(input, entry.id));
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
    final feed = ref.watch(commandFeedProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Command Center')),
      body: Column(
        children: [
          Expanded(
            child: feed.isEmpty
                ? _EmptyState(theme: theme)
                : _Feed(
                    entries: feed,
                    onRetry: _retryEntry,
                  ),
          ),
          _CommandBar(
            enabled: OpenAiClient.isAvailable,
            // No global loading flag — each in-flight dispatch
            // has its own pending card in the feed; the bar
            // stays usable so the teacher can stack commands.
            loading: false,
            // No global error banner either — failures live on
            // their own feed cards with retry / dismiss.
            error: null,
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

class _Feed extends StatelessWidget {
  const _Feed({required this.entries, required this.onRetry});

  final List<CommandFeedEntry> entries;
  final ValueChanged<CommandFeedEntry> onRetry;

  @override
  Widget build(BuildContext context) {
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
      itemBuilder: (context, i) => _FeedRow(
        entry: entries[i],
        timeFmt: timeFmt,
        onRetry: onRetry,
      ),
    );
  }
}

/// Single feed row with an expandable "Why did it pick that?"
/// section showing the LLM's actual tool call. Without this, when
/// the kiosk lands the wrong record there's no way to know whether
/// the model misread the input or the tool misexecuted — so we
/// can't tell each other "this is what the model returned for that
/// input." Now we can.
class _FeedRow extends ConsumerStatefulWidget {
  const _FeedRow({
    required this.entry,
    required this.timeFmt,
    required this.onRetry,
  });

  final CommandFeedEntry entry;
  final DateFormat timeFmt;
  final ValueChanged<CommandFeedEntry> onRetry;

  @override
  ConsumerState<_FeedRow> createState() => _FeedRowState();
}

class _FeedRowState extends ConsumerState<_FeedRow> {
  bool _expanded = false;

  String _prettyArgs(Map<String, dynamic>? args) {
    if (args == null || args.isEmpty) return '(no args)';
    final encoder = const JsonEncoder.withIndent('  ');
    try {
      return encoder.convert(args);
    } on Object {
      return args.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = widget.entry;
    final hasDebug = e.toolName != null || e.userInput != null;
    final isPending = e.status == CommandFeedStatus.pending;
    final isFailed = e.status == CommandFeedStatus.failed;
    // Card background tints status: pending = soft surface,
    // failed = errorContainer, done = surfaceContainerHigh.
    final bgColor = isFailed
        ? theme.colorScheme.errorContainer.withValues(alpha: 0.55)
        : theme.colorScheme.surfaceContainerHigh;
    final accentColor = isFailed
        ? theme.colorScheme.error
        : isPending
            ? theme.colorScheme.outline
            : theme.colorScheme.primary;
    // Pending + failed cards aren't tappable for navigation —
    // they're not pointing at a real record yet.
    final canTap = !isPending && !isFailed && e.destinationPath != null;
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: canTap ? () => context.push(e.destinationPath!) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 2,
                      right: AppSpacing.sm,
                    ),
                    child: isPending
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation(accentColor),
                            ),
                          )
                        : Icon(e.icon, size: 20, color: accentColor),
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
                              widget.timeFmt.format(e.timestamp),
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
                  if (canTap)
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
              // Failed cards: error message + Retry / Dismiss
              // actions. Keeps the raw user input visible above
              // (it's in `title`) so the teacher can see what
              // they tried + decide whether to retry verbatim or
              // type a fresh command.
              if (isFailed) ...[
                if ((e.errorMessage ?? '').isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    e.errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => ref
                          .read(commandFeedProvider.notifier)
                          .remove(e.id),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Dismiss'),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    FilledButton.tonalIcon(
                      onPressed: () => widget.onRetry(e),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ],
              if (hasDebug) ...[
                const SizedBox(height: AppSpacing.sm),
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _expanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _expanded ? 'Hide details' : 'Why this?',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_expanded) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _DebugBlock(
                    label: 'YOU SAID',
                    content: e.userInput ?? '(unknown)',
                    theme: theme,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _DebugBlock(
                    label: 'TOOL',
                    content: e.toolName ?? '(unknown)',
                    theme: theme,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _DebugBlock(
                    label: 'ARGS',
                    content: _prettyArgs(e.toolArgs),
                    theme: theme,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DebugBlock extends StatelessWidget {
  const _DebugBlock({
    required this.label,
    required this.content,
    required this.theme,
  });

  final String label;
  final String content;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            content,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Menlo', 'Courier', 'monospace'],
              height: 1.3,
              color: theme.colorScheme.onSurface,
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

  // ——— Voice state ——————————————————————————————————————————
  //
  // Tapping the mic spins up a `DeepgramVoiceSession`. Partials
  // stream into `_voicePartial` so the field shows live
  // transcription; finals accumulate into `_voiceFinals` so the
  // final composed transcript survives mid-utterance pauses
  // (Deepgram closes/reopens the partial on natural breaks).
  // Tapping the stop button submits the composed transcript.

  DeepgramVoiceSession? _voiceSession;
  StreamSubscription<String>? _voicePartialSub;
  StreamSubscription<String>? _voiceFinalSub;
  StreamSubscription<Object>? _voiceErrorSub;
  final List<String> _voiceFinals = <String>[];
  String _voicePartial = '';
  bool _voiceRecording = false;
  bool _voiceStarting = false;
  String? _voiceError;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    unawaited(_tearDownVoice());
    super.dispose();
  }

  String get _composedVoiceText {
    final parts = <String>[..._voiceFinals];
    final p = _voicePartial.trim();
    if (p.isNotEmpty) parts.add(p);
    return parts.join(' ').trim();
  }

  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty || widget.loading) return;
    widget.onSubmit(text);
    _ctrl.clear();
  }

  Future<void> _toggleVoice() async {
    if (_voiceRecording) {
      await _stopAndSubmit();
    } else {
      await _startVoice();
    }
  }

  Future<void> _startVoice() async {
    if (_voiceStarting || _voiceRecording) return;
    setState(() {
      _voiceStarting = true;
      _voiceError = null;
      _voiceFinals.clear();
      _voicePartial = '';
      _ctrl.clear();
    });
    final session = DeepgramVoiceSession();
    _voicePartialSub = session.partials.listen((p) {
      if (!mounted) return;
      setState(() => _voicePartial = p);
    });
    _voiceFinalSub = session.finals.listen((f) {
      if (!mounted) return;
      setState(() {
        final t = f.trim();
        if (t.isNotEmpty) _voiceFinals.add(t);
        _voicePartial = '';
      });
    });
    _voiceErrorSub = session.errors.listen((e) {
      if (!mounted) return;
      setState(() => _voiceError = e.toString());
    });
    try {
      await session.start();
      if (!mounted) {
        await session.stop();
        await session.dispose();
        return;
      }
      _voiceSession = session;
      setState(() {
        _voiceStarting = false;
        _voiceRecording = true;
      });
    } on VoicePermissionError catch (e) {
      await session.dispose();
      _failVoice(e.message);
    } on VoiceUnsupportedError catch (e) {
      await session.dispose();
      _failVoice(e.message);
    } on VoiceConfigError catch (e) {
      await session.dispose();
      _failVoice(e.message);
    } on Object catch (e) {
      await session.dispose();
      _failVoice("Couldn't start voice: $e");
    }
  }

  Future<void> _stopAndSubmit() async {
    final transcript = _composedVoiceText;
    await _tearDownVoice();
    if (!mounted) return;
    setState(() {
      _voiceRecording = false;
      _voicePartial = '';
      _voiceFinals.clear();
    });
    if (transcript.isEmpty) return;
    widget.onSubmit(transcript);
  }

  Future<void> _tearDownVoice() async {
    final session = _voiceSession;
    _voiceSession = null;
    await _voicePartialSub?.cancel();
    await _voiceFinalSub?.cancel();
    await _voiceErrorSub?.cancel();
    _voicePartialSub = null;
    _voiceFinalSub = null;
    _voiceErrorSub = null;
    if (session != null) {
      try {
        await session.stop();
      } on Object {/* best-effort */}
      await session.dispose();
    }
  }

  void _failVoice(String message) {
    if (!mounted) return;
    setState(() {
      _voiceStarting = false;
      _voiceRecording = false;
      _voicePartial = '';
      _voiceFinals.clear();
      _voiceError = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final voiceTranscript = _composedVoiceText;
    final showingVoice = _voiceRecording || _voiceStarting;
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
              if (_voiceError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    _voiceError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
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
                  // Voice toggle. Lights up red while recording so
                  // the user has unambiguous state.
                  IconButton(
                    tooltip: showingVoice ? 'Stop + send' : 'Voice input',
                    onPressed:
                        widget.enabled && !widget.loading ? _toggleVoice : null,
                    icon: Icon(
                      showingVoice ? Icons.stop_rounded : Icons.mic_rounded,
                      color: showingVoice
                          ? theme.colorScheme.error
                          : (widget.enabled
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  Expanded(
                    child: showingVoice
                        ? _LiveTranscript(
                            text: voiceTranscript.isEmpty
                                ? (_voiceStarting
                                    ? 'Connecting…'
                                    : 'Listening — say it')
                                : voiceTranscript,
                            italic: voiceTranscript.isEmpty,
                            theme: theme,
                          )
                        : TextField(
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
                  else if (!showingVoice)
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

/// Live transcript view shown in place of the TextField while
/// the mic is recording. Finals render solid; the active
/// partial trails them in italic so the user can see Deepgram
/// catching up to them in real time.
class _LiveTranscript extends StatelessWidget {
  const _LiveTranscript({
    required this.text,
    required this.italic,
    required this.theme,
  });

  final String text;
  final bool italic;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          color: italic
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}
