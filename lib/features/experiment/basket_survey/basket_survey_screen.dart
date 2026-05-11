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
import 'dart:ui' as ui;

import 'package:basecamp/features/experiment/basket_survey/basket_session_store.dart';
import 'package:basecamp/features/experiment/basket_survey/basket_world.dart';
import 'package:basecamp/features/experiment/basket_survey/basket_world_widget.dart';
import 'package:basecamp/features/experiment/basket_survey/painted_face.dart';
import 'package:basecamp/features/experiment/basket_survey/thank_you_card.dart';
import 'package:basecamp/features/surveys/canonical_questions.dart';
import 'package:basecamp/features/surveys/kiosk_exit_pin_modal.dart';
import 'package:basecamp/features/surveys/multi_select_overlay.dart';
import 'package:basecamp/features/surveys/open_ended_overlay.dart';
import 'package:basecamp/features/surveys/preflight_school_gate.dart';
import 'package:basecamp/features/surveys/survey_audio_service.dart';
import 'package:basecamp/features/surveys/survey_models.dart';
import 'package:basecamp/features/surveys/survey_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

class BasketSurveyScreen extends ConsumerStatefulWidget {
  const BasketSurveyScreen({
    super.key,
    this.surveyId,
    this.resumeSessionId,
  });

  /// When non-null, the screen runs in **kiosk mode** — loads
  /// the survey config from the cloud-synced `surveys` table,
  /// opens a real `survey_sessions` row, and writes each answer
  /// to `survey_responses` (same path as the marble kiosk).
  /// When null, sandbox mode — questions still come from the
  /// canonical list, but nothing persists.
  final String? surveyId;

  /// When supplied (kiosk mode only), reopens an existing
  /// `survey_sessions` row instead of starting a new one. The
  /// kiosk re-derives the next question by skipping any already-
  /// answered question ids. Used by the results-screen tap-to-
  /// resume flow.
  final String? resumeSessionId;

  @override
  ConsumerState<BasketSurveyScreen> createState() => _BasketSurveyScreenState();
}

class _BasketSurveyScreenState extends ConsumerState<BasketSurveyScreen> {
  /// Survey config for kiosk mode — null in sandbox.
  SurveyConfig? _survey;

  /// Active `survey_sessions.id` for kiosk mode — null in sandbox.
  String? _sessionId;

  /// Has the kid completed the pre-flight school gate? Sandbox
  /// + resumed sessions skip it (sandbox has no session row;
  /// resumed sessions already carry a `school` value from the
  /// first run). Fresh kiosk sessions show the gate before Q1.
  bool _preflightDone = false;

  /// Triple-tap-on-title timestamps for the kiosk-exit gesture
  /// (3 taps within 800ms → PIN modal, same as marble kiosk).
  final List<DateTime> _titleTapTimes = <DateTime>[];

  bool get _isKiosk => widget.surveyId != null;

  /// Voice pulled from the survey when in kiosk mode; sandbox
  /// falls back to a sane default. The survey's `audioMode` is
  /// honoured implicitly through the audio service's gating.
  SurveyVoice get _voice => _survey?.voice ?? SurveyVoice.asteria;

  /// All questions in the survey, in reading order. The basket
  /// kiosk now handles every type:
  ///   * mood        — drag-thumb-into-basket flow (incl. the
  ///                   2-point Yes/No activity-recall block)
  ///   * multiSelect — legacy: activity grid (still supported
  ///                   for any non-canonical custom survey)
  ///   * openEnded   — Deepgram realtime STT overlay
  ///
  /// **Always re-derived from the canonical list keyed by age
  /// band.** The frozen `survey.questions` snapshot is ignored:
  /// it goes stale every time we evolve the canonical question
  /// set (e.g. splitting the multi-select activity question into
  /// 7 yes/no questions), which would otherwise leave running
  /// kiosks rendering the old shape forever. Sandbox mode falls
  /// through to the TK-3 list since there's no age band to key on.
  List<SurveyQuestion> get _questions {
    final survey = _survey;
    if (survey == null) return kBasecampCanonicalQuestions;
    return canonicalQuestionsForBand(survey.ageBand);
  }

  int _index = 0;
  final Map<String, FaceMood> _answers = <String, FaceMood>{};

  /// Key on the BasketWorldWidget so we can call its `reset()` on
  /// session reset. The world owns the marble bodies (positions,
  /// velocities, settled state); the screen no longer keeps a
  /// parallel list.
  final GlobalKey<BasketWorldWidgetState> _worldKey =
      GlobalKey<BasketWorldWidgetState>();

  /// Wraps the `BasketWorldWidget` so we can rasterise it (and
  /// only it) into a PNG for the thank-you card. Captured the
  /// moment the survey completes — every marble in its settled
  /// position, every overspill in place — so the card freezes
  /// the kid's actual final state.
  final GlobalKey _worldSnapshotKey = GlobalKey();

  /// PNG of the basket world captured at survey-complete. Null
  /// while the survey is in progress; the thank-you card hides
  /// behind null while the capture is in flight.
  Uint8List? _basketSnapshot;

  bool _basketGlow = false;
  bool _transitioning = false;
  bool _showingDone = false;
  late DateTime _sessionStartedAt = DateTime.now();

  /// Cached repository reference. Captured in `initState` before
  /// the widget can be unmounted, so `dispose` can call
  /// `endSession` without going through `ref.read` (Riverpod
  /// rejects ref usage during dispose because the BuildContext
  /// is already gone).
  late final SurveyRepository _surveyRepoCached =
      ref.read(surveyRepositoryProvider);

  @override
  void initState() {
    super.initState();
    // Touch the cached repo getter so the late-final initialiser
    // runs while the element is still mounted.
    _surveyRepoCached;
    if (_isKiosk) {
      unawaited(_initializeKiosk());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _playCurrentQuestionAudio();
      });
    }
  }

  /// Kiosk mode init: load the SurveyConfig, create or resume a
  /// session, derive the starting question index. Mirrors the
  /// marble kiosk's `_initializeKiosk` so both styles share the
  /// same lifecycle shape.
  Future<void> _initializeKiosk() async {
    final repo = ref.read(surveyRepositoryProvider);
    final survey = await repo.getById(widget.surveyId!);
    if (!mounted || survey == null) return;

    final resumeId = widget.resumeSessionId;
    String sessionId;
    var startIndex = 0;
    var preflightAlreadyDone = false;
    if (resumeId != null) {
      final existing = await repo.getSession(resumeId);
      if (existing != null && existing.surveyId == survey.id) {
        await repo.reopenSession(resumeId);
        final answered = await repo.getResponsesForSession(resumeId);
        final answeredIds = answered.map((r) => r.questionId).toSet();
        // First question (any type) without a recorded response —
        // that's where the child left off.
        for (var i = 0; i < survey.questions.length; i++) {
          if (!answeredIds.contains(survey.questions[i].id)) {
            startIndex = i;
            break;
          }
          if (i == survey.questions.length - 1) startIndex = i;
        }
        sessionId = resumeId;
        // Resumed sessions already passed the gate on their first
        // run — don't make the kid pick a school again.
        preflightAlreadyDone = true;
      } else {
        sessionId = await repo.startSession(survey.id);
      }
    } else {
      sessionId = await repo.startSession(survey.id);
    }

    if (!mounted) return;
    setState(() {
      _survey = survey;
      _sessionId = sessionId;
      _index = startIndex;
      _sessionStartedAt = DateTime.now();
      _preflightDone = preflightAlreadyDone;
    });
    // Only kick the question-prompt audio if the kid is past the
    // gate. The gate has its own (silent) UX and shouldn't get
    // a Deepgram-rendered prompt over it.
    if (_preflightDone) {
      _playCurrentQuestionAudio();
    }
  }

  /// Pre-flight gate handler — the kid picked a school. Stamp
  /// the session, mark the gate done, and let the regular
  /// question flow take over.
  Future<void> _onPreflightSchoolPicked(String school) async {
    final sessionId = _sessionId;
    if (sessionId != null) {
      await _surveyRepoCached.setSessionSchool(sessionId, school);
    }
    if (!mounted) return;
    setState(() => _preflightDone = true);
    _playCurrentQuestionAudio();
  }

  void _playCurrentQuestionAudio() {
    if (_showingDone) return;
    if (_index >= _questions.length) return;
    final q = _questions[_index];
    // Multi-select + open-ended overlays play the prompt
    // themselves in their own initState — don't double-play here.
    if (q.type != SurveyQuestionType.mood) return;
    final audio = ref.read(surveyAudioServiceProvider);
    unawaited(audio.playQuestion(_voice, q.prompt));
  }

  Future<void> _onDropped(FaceMood mood) async {
    if (_transitioning || _showingDone) return;
    final q = _questions[_index];
    _answers[q.id] = mood;
    unawaited(HapticFeedback.lightImpact());

    // Kiosk-mode persistence: write the response to the same
    // cloud-synced `survey_responses` table the marble kiosk
    // writes to. Sandbox mode keeps everything in-memory.
    if (_isKiosk) {
      final survey = _survey;
      final sessionId = _sessionId;
      if (survey != null && sessionId != null) {
        final moodValue = _faceMoodToLikert(mood, q.scale);
        if (moodValue != null) {
          final reactionMs =
              DateTime.now().difference(_sessionStartedAt).inMilliseconds;
          unawaited(
            ref.read(surveyRepositoryProvider).recordMoodAnswer(
                  surveyId: survey.id,
                  sessionId: sessionId,
                  questionId: q.id,
                  moodValue: moodValue,
                  reactionTimeMs: reactionMs,
                  isPractice: q.isPractice,
                ),
          );
        }
      }
    }

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

  /// Map a painted FaceMood to the Likert index stored in
  /// `survey_responses.mood_value`. Index meanings depend on the
  /// scale on the question:
  ///   * `twoPtYesNo` — 0 = No (head-shake), 1 = Yes (nod)
  ///   * `threePt*`    — 0/1/2 across the 3-face row
  ///   * `fivePt*`     — 0..4 across the 5-face row
  /// Returns null if the mood doesn't belong to the scale's spawn
  /// set (shouldn't happen — `_QuestionAndChoices` only spawns
  /// the moods that map cleanly).
  int? _faceMoodToLikert(FaceMood mood, SurveyScale scale) {
    switch (scale.count) {
      case 2:
        return switch (mood) {
          FaceMood.stronglyDisagree => 0,
          FaceMood.stronglyAgree => 1,
          _ => null,
        };
      case 5:
        return switch (mood) {
          FaceMood.stronglyDisagree => 0,
          FaceMood.disagree => 1,
          FaceMood.notSure => 2,
          FaceMood.agree => 3,
          FaceMood.stronglyAgree => 4,
        };
      default:
        return switch (mood) {
          FaceMood.stronglyDisagree => 0,
          FaceMood.notSure => 1,
          FaceMood.stronglyAgree => 2,
          _ => null,
        };
    }
  }

  Future<void> _onSurveyComplete() async {
    setState(() {
      _transitioning = false;
    });

    // Kiosk-mode: end the session in the cloud-synced table.
    // Sandbox mode: append to the local JSON file the same way
    // it always has, for the in-app CSV viewer.
    if (_isKiosk) {
      final sessionId = _sessionId;
      if (sessionId != null) {
        unawaited(
          ref.read(surveyRepositoryProvider).endSession(
                sessionId,
                completed: true,
              ),
        );
      }
    } else {
      final notifier = ref.read(basketSurveySessionsProvider.notifier);
      unawaited(notifier.add(
        answers: _answers,
        startedAt: _sessionStartedAt,
        endedAt: DateTime.now(),
      ));
    }

    // Wait for the basket world to fully settle before we freeze
    // the snapshot. The original 500ms wait was too short — a
    // marble dropped from mid-rim with the highest spawn velocity
    // bounces for ~1.2-1.8s; the card frequently caught marbles
    // mid-bounce. Now we poll every 80ms for up to 2s, taking
    // the snapshot the moment everything has settled (or hitting
    // the 2s cap as a safety net so the card never hangs).
    await _waitForBasketToSettle();
    if (!mounted) return;
    final snap = await _captureBasketSnapshot();
    if (!mounted) return;
    setState(() {
      _basketSnapshot = snap;
      _showingDone = true;
    });
    // No auto-reset — the kid stays on the thank-you card until
    // they tap "Pass to next friend" (or a teacher does).
  }

  /// Poll the basket world until every marble has settled, capped
  /// at 2 seconds so the thank-you card never hangs if a marble
  /// gets wedged. Returns immediately if the world is already
  /// fully settled.
  Future<void> _waitForBasketToSettle() async {
    const maxWait = Duration(seconds: 2);
    const pollInterval = Duration(milliseconds: 80);
    final deadline = DateTime.now().add(maxWait);
    while (DateTime.now().isBefore(deadline)) {
      final state = _worldKey.currentState;
      if (state == null) break;
      if (state.isFullySettled) return;
      await Future<void>.delayed(pollInterval);
      if (!mounted) return;
    }
  }

  /// Snapshot the BasketWorldWidget via its RepaintBoundary.
  /// Returns null on any failure; the card has a fallback.
  Future<Uint8List?> _captureBasketSnapshot() async {
    try {
      final ctx = _worldSnapshotKey.currentContext;
      if (ctx == null) return null;
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return bytes?.buffer.asUint8List();
    } on Object catch (e, st) {
      debugPrint('[basket-survey] snapshot failed: $e\n$st');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Question-type dispatch
  // ═══════════════════════════════════════════════════════════

  /// Body builder that picks the right UI for the current
  /// question's type:
  ///   * `mood`        — drag-thumb-into-basket (existing flow)
  ///   * `multiSelect` — activity grid; each tap drops a happy
  ///                     marble; commit advances
  ///   * `openEnded`   — Deepgram realtime STT overlay
  Widget _buildQuestionBody() {
    final q = _questions[_index];
    switch (q.type) {
      case SurveyQuestionType.mood:
        return _buildMoodBody(q);
      case SurveyQuestionType.multiSelect:
        return _buildMultiSelectBody(q);
      case SurveyQuestionType.openEnded:
        return _buildOpenEndedBody(q);
    }
  }

  Widget _buildMoodBody(SurveyQuestion q) {
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
            child: _QuestionAndChoices(
              question: q,
              onReplay: _playCurrentQuestionAudio,
              transitioning: _transitioning,
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: RepaintBoundary(
            key: _worldSnapshotKey,
            child: BasketWorldWidget(
              key: _worldKey,
              glow: _basketGlow,
              onWillAccept: () {
                if (_transitioning) return false;
                setState(() => _basketGlow = true);
                return true;
              },
              onLeave: () => setState(() => _basketGlow = false),
              onAccept: _onDropped,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMultiSelectBody(SurveyQuestion q) {
    return Column(
      children: [
        Expanded(
          flex: 5,
          child: MultiSelectQuestionOverlay(
            // Re-key on the question id so switching from one
            // multi-select question to another tears down + rebuilds
            // the overlay (clears the selection set + re-reads the
            // new prompt).
            key: ValueKey('ms_${q.id}'),
            question: q,
            voice: _voice,
            audioMode: _audioMode,
            onCommit: _onMultiSelectCommit,
            onSkip: _advance,
            onActivityTapped: _onActivityTapped,
            onActivityUntapped: _onActivityUntapped,
          ),
        ),
        Expanded(
          flex: 4,
          // Basket stays visible during multi-select — each
          // tapped activity drops a happy marble in.
          child: RepaintBoundary(
            key: _worldSnapshotKey,
            child: BasketWorldWidget(
              key: _worldKey,
              glow: false,
              // No drag-and-drop during multi-select; the
              // overlay drives marble spawns instead.
              onWillAccept: () => false,
              onLeave: () {},
              onAccept: (_) {},
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOpenEndedBody(SurveyQuestion q) {
    // Keep the basket world mounted during open-ended so the
    // end-of-survey snapshot has marbles to capture. The
    // open-ended overlay sits on top of an Offstage basket —
    // the kid sees the STT UI fullscreen, but the basket's
    // RepaintBoundary is still in the widget tree (and still
    // paintable, because Offstage's renderObject keeps a layer
    // when `offstage: false` was already set this frame for the
    // capture; we set it false transiently when capturing).
    return Stack(
      children: [
        // Basket sits at the bottom of the stack, mounted but
        // hidden behind the overlay. It's NOT offstage — the
        // overlay just covers it visually. This keeps the
        // RepaintBoundary in the layer tree so toImage() works
        // when the survey-complete handler captures it.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 200,
          child: RepaintBoundary(
            key: _worldSnapshotKey,
            child: BasketWorldWidget(
              key: _worldKey,
              glow: false,
              onWillAccept: () => false,
              onLeave: () {},
              onAccept: (_) {},
            ),
          ),
        ),
        Positioned.fill(
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: OpenEndedQuestionOverlay(
              key: ValueKey('oe_${q.id}'),
              question: q,
              voice: _voice,
              audioMode: _audioMode,
              onCommit: _onOpenEndedCommit,
              onSkip: _advance,
            ),
          ),
        ),
      ],
    );
  }

  /// Get the audio mode for kiosk; sandbox falls back to full.
  SurveyAudioMode get _audioMode =>
      _survey?.audioMode ?? SurveyAudioMode.full;

  /// Tracks which marble each activity dropped — so untap can
  /// remove the *exact* marble that went in for that activity.
  /// Cleared on advance to the next question.
  final Map<String, MarbleBody> _activityMarbles =
      <String, MarbleBody>{};

  /// Cycle pointer for picking which mood-color the next dropped
  /// activity-marble wears. Each tap rotates through all 5 moods
  /// so the basket fills with a colorful mix instead of a wall
  /// of identical happy faces.
  int _activityMarbleCursor = 0;

  /// Pleasant order through the 5 moods — starts on the happy
  /// end so the first marble feels celebratory, then rotates.
  static const List<FaceMood> _activityMoodCycle = <FaceMood>[
    FaceMood.stronglyAgree,
    FaceMood.agree,
    FaceMood.notSure,
    FaceMood.disagree,
    FaceMood.stronglyDisagree,
  ];

  /// Called when the kid taps an activity card. Drops a marble
  /// into the basket with a different mood color than the
  /// previous tap so the pile has visual variety.
  void _onActivityTapped(String activityId) {
    final state = _worldKey.currentState;
    if (state == null) return;
    final mood = _activityMoodCycle[
        _activityMarbleCursor % _activityMoodCycle.length];
    _activityMarbleCursor += 1;
    final body = state.world.addMarble(mood);
    _activityMarbles[activityId] = body;
  }

  /// Called when the kid un-checks an activity. Removes the
  /// exact marble the matching tap dropped, so the basket pile
  /// stays in sync with the selection set.
  void _onActivityUntapped(String activityId) {
    final state = _worldKey.currentState;
    if (state == null) return;
    final body = _activityMarbles.remove(activityId);
    if (body != null) {
      state.world.removeMarble(body);
    }
  }

  Future<void> _onMultiSelectCommit(List<String> selectedIds) async {
    if (_transitioning) return;
    final q = _questions[_index];
    if (_isKiosk) {
      final survey = _survey;
      final sessionId = _sessionId;
      if (survey != null && sessionId != null) {
        final durationMs = DateTime.now()
            .difference(_sessionStartedAt)
            .inMilliseconds;
        unawaited(
          ref.read(surveyRepositoryProvider).recordMultiSelectAnswer(
                surveyId: survey.id,
                sessionId: sessionId,
                questionId: q.id,
                selectedOptionIds: selectedIds,
                durationMs: durationMs,
                isPractice: q.isPractice,
              ),
        );
      }
    }
    _advance();
  }

  Future<void> _onOpenEndedCommit(
    String transcription,
    int durationMs,
  ) async {
    if (_transitioning) return;
    final q = _questions[_index];
    if (_isKiosk) {
      final survey = _survey;
      final sessionId = _sessionId;
      if (survey != null && sessionId != null) {
        unawaited(
          ref.read(surveyRepositoryProvider).recordOpenEndedAnswer(
                surveyId: survey.id,
                sessionId: sessionId,
                questionId: q.id,
                transcription: transcription,
                durationMs: durationMs,
                isPractice: q.isPractice,
              ),
        );
      }
    }
    _advance();
  }

  /// Advance to the next question — used by multi-select +
  /// open-ended commit handlers (they don't go through the
  /// drag-end physics path).
  void _advance() {
    if (_transitioning) return;
    // Activity-marble bookkeeping is per-question — once we move
    // off a multi-select question, the previous activity → marble
    // map shouldn't follow us into the next one.
    _activityMarbles.clear();
    _activityMarbleCursor = 0;
    setState(() => _transitioning = true);
    if (_index + 1 >= _questions.length) {
      unawaited(_onSurveyComplete());
      return;
    }
    setState(() {
      _index += 1;
      _transitioning = false;
    });
    _playCurrentQuestionAudio();
  }

  Future<void> _resetForNextChild() async {
    _worldKey.currentState?.reset();
    String? newSessionId;
    if (_isKiosk) {
      final survey = _survey;
      if (survey != null) {
        newSessionId =
            await ref.read(surveyRepositoryProvider).startSession(survey.id);
      }
    }
    if (!mounted) return;
    setState(() {
      _index = 0;
      _answers.clear();
      _showingDone = false;
      _transitioning = false;
      _basketSnapshot = null;
      _sessionStartedAt = DateTime.now();
      if (newSessionId != null) _sessionId = newSessionId;
    });
    _playCurrentQuestionAudio();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scaffold = Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        // Kiosk mode: hide the back button (PopScope blocks it
        // anyway), and the title is tappable for the triple-
        // tap PIN exit gesture.
        automaticallyImplyLeading: !_isKiosk,
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTitleTap,
          child: _isKiosk
              ? _kioskTitle(theme)
              : const Text('Basket Survey'),
        ),
        actions: [
          // CSV button only makes sense in sandbox mode (where
          // sessions live in a local JSON file). In kiosk mode the
          // results sheet at /surveys/:id handles export.
          if (!_isKiosk)
            IconButton(
              tooltip: 'Sessions CSV',
              icon: const Icon(Icons.table_view_outlined),
              onPressed: () => _openCsvSheet(context),
            ),
        ],
      ),
      body: SafeArea(
        child: _showingDone
            ? BasketThankYouCard(
                basketSnapshot: _basketSnapshot,
                onPassAlong: _resetForNextChild,
                surveyId: widget.surveyId,
                sessionId: _sessionId,
              )
            : _buildBeforeQuestions() ?? _buildQuestionBody(),
      ),
    );
    // Kiosk mode wraps in PopScope so the system back gesture
    // can't accidentally exit the survey — the only way out is
    // the teacher's PIN-gated triple-tap on the title.
    if (!_isKiosk) return scaffold;
    return PopScope(canPop: false, child: scaffold);
  }

  /// Pre-question gates. Returns the first non-null gate widget
  /// in priority order, or null when the kid is ready for Q1.
  /// Currently just the school gate; future gates (consent,
  /// orientation video, etc.) plug in here.
  Widget? _buildBeforeQuestions() {
    final survey = _survey;
    if (!_isKiosk || survey == null) return null;
    if (!_preflightDone) {
      return PreflightSchoolGate(
        config: survey,
        onSchoolPicked: _onPreflightSchoolPicked,
      );
    }
    return null;
  }

  /// Kiosk title: site name on top, classroom subtitle below —
  /// matches the marble kiosk's title layout. Tap-target stays
  /// full-width so a teacher can land taps confidently.
  Widget _kioskTitle(ThemeData theme) {
    final survey = _survey;
    if (survey == null) return const Text('Loading…');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          survey.siteName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          survey.classroom,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// Triple-tap on the appbar title — same PIN-exit gesture the
  /// marble kiosk uses. Three taps within 800ms → PIN modal; on
  /// success the kiosk pops.
  void _onTitleTap() {
    if (!_isKiosk) return;
    final now = DateTime.now();
    _titleTapTimes.add(now);
    while (_titleTapTimes.length > 3) {
      _titleTapTimes.removeAt(0);
    }
    if (_titleTapTimes.length < 3) return;
    final span =
        _titleTapTimes.last.difference(_titleTapTimes.first).inMilliseconds;
    if (span > 800) return;
    _titleTapTimes.clear();
    unawaited(_handleExitTap());
  }

  Future<void> _handleExitTap() async {
    final survey = _survey;
    if (survey == null) return;
    // Pause any audio so the modal isn't fighting a question read.
    await ref.read(surveyAudioServiceProvider).stop();
    if (!mounted) return;
    final ok = await KioskExitPinModal.show(context, survey);
    if (!mounted) return;
    if (ok) {
      // Mark this child's session as not-completed so the results
      // screen can flag it. Best-effort; if the write doesn't
      // flush before pop, the dispose hook below catches it.
      final sessionId = _sessionId;
      if (sessionId != null) {
        unawaited(
          ref.read(surveyRepositoryProvider).endSession(
                sessionId,
                completed: false,
              ),
        );
      }
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    // If the teacher exits mid-flow without going through the PIN
    // (e.g. system kill, parent route swap), mark the session
    // abandoned. Uses the **cached** repo reference because
    // `ref.read` in dispose throws — the BuildContext is already
    // gone by the time we get here.
    final sessionId = _sessionId;
    if (sessionId != null && _isKiosk && !_showingDone) {
      unawaited(
        _surveyRepoCached.endSession(sessionId, completed: false),
      );
    }
    super.dispose();
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
    final moods = switch (question.choiceCount) {
      2 => kBasket2Choices,
      5 => kBasket5Choices,
      _ => kBasket3Choices,
    };
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
      child: Draggable<BasketDropPayload>(
        data: BasketDropPayload(
          mood: widget.mood,
          palette: widget.palette,
        ),
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
