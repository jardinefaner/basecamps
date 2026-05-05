// Basket-survey experiment — a cleaner, simpler take on the
// BASECamp student survey. Single column: question on top, replay
// icon to its left, 3 or 5 painted-face cards in a row, woven
// painterly basket at the bottom as the drop target.
//
// Compared to the marble-jar kiosk
// (`lib/features/experiment/survey/survey_screen.dart`):
//   * No Flame engine — pure Flutter widgets + CustomPainters.
//   * No chibi character / physics / overflow / 3D jar.
//   * No persistence wired to the cloud — sessions land in a
//     local JSON file, surfaced as a CSV for export.
//   * Same canonical questions and same Deepgram TTS service so
//     swapping the kid-facing UX is a clean A/B against the
//     marble version.

import 'dart:async';

import 'package:basecamp/features/experiment/basket_survey/basket_painter.dart';
import 'package:basecamp/features/experiment/basket_survey/basket_session_store.dart';
import 'package:basecamp/features/experiment/basket_survey/painted_face.dart';
import 'package:basecamp/features/surveys/canonical_questions.dart';
import 'package:basecamp/features/surveys/survey_audio_service.dart';
import 'package:basecamp/features/surveys/survey_models.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

class BasketSurveyScreen extends ConsumerStatefulWidget {
  const BasketSurveyScreen({super.key});

  @override
  ConsumerState<BasketSurveyScreen> createState() => _BasketSurveyScreenState();
}

class _BasketSurveyScreenState extends ConsumerState<BasketSurveyScreen> {
  /// Voice picked at the top of the screen. Defaults to Asteria.
  /// Hardcoded for the sandbox — not configurable yet.
  static const SurveyVoice _voice = SurveyVoice.asteria;

  /// Mood-only subset of the canonical questions. The basket
  /// experiment doesn't render multi-select / open-ended yet; it
  /// just skips them. The kiosk handles those via overlays.
  late final List<SurveyQuestion> _questions = kBasecampCanonicalQuestions
      .where((q) => q.type == SurveyQuestionType.mood)
      .toList();

  /// Index into [_questions] that we're currently asking.
  int _index = 0;

  /// Question-id → chosen mood. Saved at end-of-survey.
  final Map<String, BasketFaceMood> _answers = <String, BasketFaceMood>{};

  /// `true` while the basket is glowing (a drag is hovering over
  /// the drop target). Drives basket scale + glow halo.
  bool _basketGlow = false;

  /// `true` for the brief transition between questions — fades
  /// the question + faces out, then in. Locks input during the
  /// fade so a quick double-drop can't double-record.
  bool _transitioning = false;

  /// `true` for the final "thank you" beat after the last question.
  bool _showingDone = false;

  /// Wall-clock start of the current session. Recorded at first
  /// build; reset on `_resetForNextChild`.
  late DateTime _sessionStartedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Read the first question aloud after layout settles. Same
    // best-effort no-op semantics as the kiosk.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playCurrentQuestionAudio();
    });
  }

  void _playCurrentQuestionAudio() {
    if (_showingDone) return;
    if (_index >= _questions.length) return;
    final q = _questions[_index];
    final audio = ref.read(surveyAudioServiceProvider);
    unawaited(audio.playQuestion(_voice, q.prompt));
  }

  Future<void> _onDropped(BasketFaceMood mood) async {
    if (_transitioning || _showingDone) return;
    final q = _questions[_index];
    _answers[q.id] = mood;
    unawaited(HapticFeedback.lightImpact());
    setState(() {
      _basketGlow = false;
      _transitioning = true;
    });
    // Hold on the basket bounce before advancing — the kid sees
    // the face land before the next question fades in.
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    if (_index + 1 >= _questions.length) {
      await _onSurveyComplete();
      return;
    }
    setState(() {
      _index += 1;
      _transitioning = false;
    });
    _playCurrentQuestionAudio();
  }

  Future<void> _onSurveyComplete() async {
    setState(() {
      _showingDone = true;
      _transitioning = false;
    });
    // Persist the session before the celebration beat ends — the
    // CSV button on the appbar reads from the same provider.
    final notifier = ref.read(basketSurveySessionsProvider.notifier);
    await notifier.add(
      answers: _answers,
      startedAt: _sessionStartedAt,
      endedAt: DateTime.now(),
    );
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    _resetForNextChild();
  }

  void _resetForNextChild() {
    setState(() {
      _index = 0;
      _answers.clear();
      _showingDone = false;
      _transitioning = false;
      _sessionStartedAt = DateTime.now();
    });
    _playCurrentQuestionAudio();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Basket Survey'),
        actions: [
          IconButton(
            tooltip: 'Sessions CSV',
            icon: const Icon(Icons.table_view_outlined),
            onPressed: () => _openCsvSheet(context),
          ),
        ],
      ),
      body: SafeArea(
        child: _showingDone
            ? const _DoneOverlay()
            : LayoutBuilder(
                builder: (context, constraints) {
                  return Column(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.xl,
                            AppSpacing.lg,
                            AppSpacing.md,
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, anim) {
                              final slide = Tween<Offset>(
                                begin: const Offset(0, 0.06),
                                end: Offset.zero,
                              ).animate(anim);
                              return FadeTransition(
                                opacity: anim,
                                child: SlideTransition(
                                  position: slide,
                                  child: child,
                                ),
                              );
                            },
                            child: _transitioning
                                ? const SizedBox.shrink(
                                    key: ValueKey('transition'),
                                  )
                                : _QuestionAndChoices(
                                    key: ValueKey('q$_index'),
                                    question: _questions[_index],
                                    onReplay: _playCurrentQuestionAudio,
                                  ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Center(
                          child: _BasketDropTarget(
                            glow: _basketGlow,
                            onWillAccept: () {
                              if (_transitioning) return false;
                              setState(() => _basketGlow = true);
                              return true;
                            },
                            onLeave: () =>
                                setState(() => _basketGlow = false),
                            onAccept: _onDropped,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Future<void> _openCsvSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CsvSheet(),
    );
  }
}

/// Question text + replay icon + the row of draggable face cards.
/// Lifted out of the screen so AnimatedSwitcher can fade it as a
/// single unit between questions.
class _QuestionAndChoices extends StatelessWidget {
  const _QuestionAndChoices({
    required this.question,
    required this.onReplay,
    super.key,
  });

  final SurveyQuestion question;
  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final moods = question.choiceCount == 5
        ? kBasket5Choices
        : kBasket3Choices;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Replay icon — sits to the LEFT of the question per
            // the user's spec. Compact size; tap → replay TTS.
            IconButton(
              tooltip: 'Replay question',
              onPressed: onReplay,
              icon: Icon(
                Icons.volume_up_outlined,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                question.prompt,
                textAlign: TextAlign.left,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.30,
                ),
              ),
            ),
          ],
        ),
        const Spacer(),
        // Face row — wraps to multi-line on narrow screens (5 faces
        // on a small phone wouldn't fit on one row).
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.md,
          children: [
            for (var i = 0; i < moods.length; i++)
              _DraggableFace(
                mood: moods[i],
                seed: i,
                size: _faceSize(context, moods.length),
              ),
          ],
        ),
        const Spacer(),
      ],
    );
  }

  double _faceSize(BuildContext context, int count) {
    final w = MediaQuery.of(context).size.width;
    final per = (w - AppSpacing.xl * 2 - AppSpacing.lg * (count - 1)) / count;
    return per.clamp(72, 120).toDouble();
  }
}

/// Face card you can drag onto the basket. The face widget
/// continues to animate during the drag thanks to its own ticker;
/// we just wrap it in `Draggable<BasketFaceMood>`.
class _DraggableFace extends StatefulWidget {
  const _DraggableFace({
    required this.mood,
    required this.seed,
    required this.size,
  });

  final BasketFaceMood mood;
  final int seed;
  final double size;

  @override
  State<_DraggableFace> createState() => _DraggableFaceState();
}

class _DraggableFaceState extends State<_DraggableFace> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final body = AnimatedScale(
      scale: _dragging ? 0.5 : 1.0,
      duration: const Duration(milliseconds: 160),
      child: AnimatedOpacity(
        opacity: _dragging ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: PaintedFace(
            mood: widget.mood,
            size: widget.size,
            seed: widget.seed,
          ),
        ),
      ),
    );
    return Draggable<BasketFaceMood>(
      data: widget.mood,
      feedback: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: PaintedFace(
            mood: widget.mood,
            size: widget.size,
            seed: widget.seed,
            state: BasketFaceState.held,
          ),
        ),
      ),
      childWhenDragging: SizedBox(
        width: widget.size,
        height: widget.size,
      ),
      onDragStarted: () {
        unawaited(HapticFeedback.selectionClick());
        setState(() => _dragging = true);
      },
      onDraggableCanceled: (_, _) =>
          setState(() => _dragging = false),
      onDragCompleted: () => setState(() => _dragging = false),
      child: body,
    );
  }
}

/// The basket drop target. Wraps `BasketPainter` in a `DragTarget`
/// + an `AnimatedScale` so it pops up a tick when a face hovers
/// over it. The painter handles the visual glow / drop-in shadow.
class _BasketDropTarget extends StatefulWidget {
  const _BasketDropTarget({
    required this.glow,
    required this.onWillAccept,
    required this.onLeave,
    required this.onAccept,
  });

  final bool glow;
  final bool Function() onWillAccept;
  final VoidCallback onLeave;
  final ValueChanged<BasketFaceMood> onAccept;

  @override
  State<_BasketDropTarget> createState() => _BasketDropTargetState();
}

class _BasketDropTargetState extends State<_BasketDropTarget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<BasketFaceMood>(
      onWillAcceptWithDetails: (_) => widget.onWillAccept(),
      onLeave: (_) => widget.onLeave(),
      onAcceptWithDetails: (details) {
        // Trigger the bounce animation and forward to parent.
        _bounce.reset();
        unawaited(_bounce.forward());
        widget.onAccept(details.data);
      },
      builder: (context, candidates, _) {
        return AnimatedScale(
          scale: widget.glow ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: AnimatedBuilder(
            animation: _bounce,
            builder: (context, _) {
              // Elastic bounce pulse: 1.0 → 1.08 → 1.0
              final v = _bounce.value == 0
                  ? 0.0
                  : Curves.elasticOut.transform(_bounce.value);
              final pulse = 1.0 + v * 0.04 * (1 - _bounce.value);
              return Transform.scale(
                scale: pulse,
                child: SizedBox(
                  width: 220,
                  height: 200,
                  child: CustomPaint(
                    painter: BasketPainter(glow: widget.glow),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _DoneOverlay extends StatelessWidget {
  const _DoneOverlay();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'All done!',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Thank you. Pass the basket to the next friend.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sessions-CSV bottom sheet. Renders the current CSV as
/// SelectableText so a teacher can preview, plus Copy / Share /
/// Clear-all buttons.
class _CsvSheet extends ConsumerWidget {
  const _CsvSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncSessions = ref.watch(basketSurveySessionsProvider);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: asyncSessions.when(
          loading: () => const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => SizedBox(
            height: 200,
            child: Center(child: Text('Could not load: $e')),
          ),
          data: (sessions) {
            final csv = buildBasketSurveyCsv(sessions: sessions);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'Sessions CSV',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${sessions.length} '
                      'session${sessions.length == 1 ? '' : 's'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                      width: 0.5,
                    ),
                  ),
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: SelectableText(
                          csv,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Clear all'),
                      onPressed: sessions.isEmpty
                          ? null
                          : () => _confirmClear(context, ref),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy'),
                      onPressed: sessions.isEmpty
                          ? null
                          : () => _copy(context, csv),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Share'),
                      onPressed: sessions.isEmpty
                          ? null
                          : () => _share(csv),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context, String csv) async {
    await Clipboard.setData(ClipboardData(text: csv));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CSV copied to clipboard')),
    );
  }

  Future<void> _share(String csv) async {
    await SharePlus.instance.share(
      ShareParams(
        text: csv,
        subject: 'Basket Survey — sessions',
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all sessions?'),
        content: const Text(
          'This wipes every recorded session for the basket-survey '
          "experiment. The marble-jar kiosk's data isn't affected.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(basketSurveySessionsProvider.notifier).clearAll();
  }
}
