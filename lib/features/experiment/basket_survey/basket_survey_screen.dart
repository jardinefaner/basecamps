// Basket-survey experiment — a cleaner, simpler take on the
// BASECamp student survey. Single column: question on top with a
// replay icon to its left (vertically centred together), 3 or 5
// painted-face cards in a row, woven painterly basket at the
// bottom as the drop target.
//
// **What stays put across questions:**
//   * Replay icon (always in the same slot on the left).
//   * Basket + every face that's already been dropped into it.
//
// **What animates between questions:**
//   * Question text — fades / slides in with a small ease.
//   * Choice row — same fade/slide.
//
// **Dropped marbles:**
//   * Each accepted drop accumulates inside the basket. Marbles
//     pile up, slightly visible through the translucent weave,
//     and once the basket is "full" they overspill onto the
//     surrounding floor (left side, right side, in front).
//
// Compared to the marble-jar kiosk:
//   * No Flame engine — pure Flutter widgets + CustomPainters.
//   * No chibi character / 3D physics / overflow rim collision.
//   * Same canonical questions + same Deepgram TTS, so the basket
//     is a clean A/B against the marble version.

import 'dart:async';
import 'dart:math' as math;

import 'package:basecamp/features/experiment/basket_survey/basket_session_store.dart';
import 'package:basecamp/features/experiment/basket_survey/basket_world_widget.dart';
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
  /// Voice — hardcoded for the sandbox.
  static const SurveyVoice _voice = SurveyVoice.asteria;

  /// Mood-only subset of the canonical questions.
  late final List<SurveyQuestion> _questions = kBasecampCanonicalQuestions
      .where((q) => q.type == SurveyQuestionType.mood)
      .toList();

  int _index = 0;
  final Map<String, FaceMood> _answers = <String, FaceMood>{};

  /// Key on the BasketWorldWidget so we can call its `reset()` on
  /// session reset. The world owns the marble bodies (positions,
  /// velocities, settled state); the screen no longer keeps a
  /// parallel list.
  final GlobalKey<BasketWorldWidgetState> _worldKey =
      GlobalKey<BasketWorldWidgetState>();

  bool _basketGlow = false;
  bool _transitioning = false;
  bool _showingDone = false;
  late DateTime _sessionStartedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
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

  Future<void> _onDropped(FaceMood mood) async {
    if (_transitioning || _showingDone) return;
    final q = _questions[_index];
    _answers[q.id] = mood;
    unawaited(HapticFeedback.lightImpact());
    setState(() {
      _basketGlow = false;
      _transitioning = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 360));
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
    _worldKey.currentState?.reset();
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
            : Column(
                children: [
                  // ——— Question + choices (this part swaps) ———————
                  // Wrapped in an AnimatedSwitcher so ONLY the
                  // prompt + choices change between questions; the
                  // replay icon and the basket below stay put.
                  Expanded(
                    flex: 5,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.xl,
                        AppSpacing.lg,
                        AppSpacing.md,
                      ),
                      child: _QuestionAndChoices(
                        question: _questions[_index],
                        onReplay: _playCurrentQuestionAudio,
                        transitioning: _transitioning,
                      ),
                    ),
                  ),
                  // ——— Basket (sticks across questions) ————————
                  // Now driven by `BasketWorldWidget`, which owns
                  // the physics simulation and renders every
                  // marble (back / front / overspill) directly via
                  // a CustomPainter. The screen only feeds it
                  // glow + drop events.
                  Expanded(
                    flex: 4,
                    child: BasketWorldWidget(
                      key: _worldKey,
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
                ],
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
/// Built so the **replay icon stays put** across question changes
/// — only the question text + choice row are wrapped in the
/// AnimatedSwitcher.
class _QuestionAndChoices extends StatelessWidget {
  const _QuestionAndChoices({
    required this.question,
    required this.onReplay,
    required this.transitioning,
  });

  final SurveyQuestion question;
  final VoidCallback onReplay;
  final bool transitioning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final moods = question.choiceCount == 5
        ? kBasket5Choices
        : kBasket3Choices;
    // Per-question color rotation. Mood positions are unchanged
    // (sad on the left, happy on the right always); only the body
    // / ring / cheek colors rotate, so the smiling face might be
    // green on q1, yellow on q2, pink on q3. Expressions (smile
    // shape, sparkles, tears) stay tied to the mood — kids can't
    // memorise "tap the green one".
    final colors = _colorRotationForQuestion(question, moods.length);
    return Column(
      children: [
        // Top row — replay icon (fixed) + animated question text.
        // The replay icon and the question text are vertically
        // centred relative to each other (CrossAxisAlignment.center).
        Row(
          children: [
            IconButton(
              tooltip: 'Replay question',
              onPressed: onReplay,
              icon: Icon(
                Icons.volume_up_outlined,
                size: 26,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.08),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: Text(
                  question.prompt,
                  key: ValueKey('prompt_${question.id}'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.30,
                  ),
                ),
              ),
            ),
          ],
        ),
        const Spacer(),
        // Choice row — animates separately (its own switcher) so a
        // 3-choice question can swap to a 5-choice question without
        // dragging the question text along for the ride.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: transitioning
              ? const SizedBox(
                  key: ValueKey('choices_transition'),
                  height: 1,
                )
              : Wrap(
                  key: ValueKey('choices_${question.id}'),
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.md,
                  children: [
                    for (var i = 0; i < moods.length; i++)
                      _DraggableFace(
                        mood: moods[i],
                        seed: i + question.id.hashCode,
                        size: _faceSize(context, moods.length),
                        palette: colors[i],
                      ),
                  ],
                ),
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

  /// Per-question color rotation. Mood positions stay put (sad
  /// on the left, happy on the right); only the body / ring /
  /// cheek colors rotate, so each question dresses the faces in
  /// a different hue. The five color palettes the kiosk ships
  /// (pink / coral / amber / green / teal) get shuffled and
  /// dealt out across the choice slots. Keyed on question id so
  /// the same question always shows the same colors.
  List<FacePalette> _colorRotationForQuestion(
    SurveyQuestion q,
    int count,
  ) {
    final palettes = FaceMood.values
        .map((m) => kFacePalettes[m]!)
        .toList()
      ..shuffle(math.Random(q.id.hashCode));
    return palettes.take(count).toList();
  }
}

class _DraggableFace extends StatefulWidget {
  const _DraggableFace({
    required this.mood,
    required this.seed,
    required this.size,
    this.palette,
  });

  final FaceMood mood;
  final int seed;
  final double size;
  final FacePalette? palette;

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
            palette: widget.palette,
          ),
        ),
      ),
    );
    return Tooltip(
      message: basketFaceLabel(widget.mood),
      child: Draggable<FaceMood>(
        data: widget.mood,
        feedback: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: widget.size * 1.05,
            height: widget.size * 1.05,
            child: PaintedFace(
              mood: widget.mood,
              size: widget.size * 1.05,
              seed: widget.seed,
              state: BasketFaceState.held,
              palette: widget.palette,
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
      ),
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
