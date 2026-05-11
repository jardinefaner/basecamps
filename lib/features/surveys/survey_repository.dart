// Survey repository — local Drift + cloud sync for the BASECamp
// Student Survey. CRUD on `surveys`, plus helpers for the kiosk
// + the results sheet.
//
// Cloud sync (cloud migration 0037 / Drift v63):
//   * Each row's program_id is stamped from
//     `activeProgramIdProvider` at insert time. The sync engine
//     pushes/pulls every program-scoped row through `surveysSpec`
//     (see sync_specs.dart).
//   * Cascades — survey_sessions, survey_responses — denormalise
//     program_id onto the row so the engine + RLS don't have to
//     JOIN through the parent.

import 'dart:async';
import 'dart:convert';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/program_scope.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/surveys/canonical_questions.dart';
import 'package:basecamp/features/surveys/survey_models.dart';
import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:basecamp/features/sync/sync_specs.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One row in the results sheet — a single child's run through
/// the kiosk. `responsesByQuestionId` lets the UI look up the
/// answer for each question column without iterating.
class SurveyResultRow {
  const SurveyResultRow({
    required this.session,
    required this.responsesByQuestionId,
  });
  final SurveySession session;
  final Map<String, SurveyResponse> responsesByQuestionId;
}

class SurveyRepository {
  SurveyRepository(this._db, this._ref);

  final AppDatabase _db;
  final Ref _ref;

  /// Current program id from the bootstrap. Null when there's no
  /// active program (sandbox / pre-bootstrap state); rows inserted
  /// then stay local-only and the engine skips them on push.
  String? get _programId => _ref.read(activeProgramIdProvider);

  /// Trigger a debounced cloud push for [surveyId]. The sync
  /// engine's `pushRow` fans out the survey + its cascades
  /// (sessions, responses). Every mutating method below funnels
  /// through here — without it, local writes never reach cloud
  /// and other devices see nothing.
  ///
  /// Also bumps the parent survey's `updated_at` so the cascade
  /// fingerprint changes and the engine actually pushes the new
  /// session/response rows (cascade push short-circuits when the
  /// parent's fingerprint hasn't moved).
  Future<void> _pushSurvey(String surveyId) async {
    try {
      await (_db.update(_db.surveys)
            ..where((s) => s.id.equals(surveyId)))
          .write(SurveysCompanion(updatedAt: Value(DateTime.now().toUtc())));
      unawaited(_ref.read(syncEngineProvider).pushRow(surveysSpec, surveyId));
    } on Object catch (e, st) {
      debugPrint('[survey-repo] push trigger failed for $surveyId: $e\n$st');
    }
  }

  /// All non-deleted surveys for the active program, newest
  /// first. Wraps Drift's row → `SurveyConfig` mapping so the UI
  /// gets in-memory objects. Includes null-program rows too
  /// (legacy / sandbox state) so a switched-out user doesn't lose
  /// pre-bootstrap entries.
  Stream<List<SurveyConfig>> watchAll() {
    final query = _db.select(_db.surveys)
      ..where(
        (s) =>
            s.deletedAt.isNull() &
            matchesActiveProgram(s.programId, _programId),
      )
      ..orderBy([
        (s) => OrderingTerm(expression: s.createdAt, mode: OrderingMode.desc),
      ]);
    return query.watch().map(
          (rows) => rows.map(_fromRow).toList(),
        );
  }

  /// One survey by id. Returns null if missing or soft-deleted.
  Future<SurveyConfig?> getById(String id) async {
    final row = await (_db.select(_db.surveys)
          ..where((s) => s.id.equals(id) & s.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) return null;
    return _fromRow(row);
  }

  /// Create a new survey. PIN is hashed before being stored — we
  /// salt with the survey id so the same 4 digits across surveys
  /// produce different hashes.
  Future<SurveyConfig> create({
    required String siteName,
    required String classroom,
    required SurveyAgeBand ageBand,
    required String pinDigits,
    required SurveyAudioMode audioMode,
    required SurveyVoice voice,
    SurveyStyle style = SurveyStyle.marbleJar,
    List<SurveyQuestion>? questions,
    List<String> schools = const <String>[],
  }) async {
    final id = newId();
    final now = DateTime.now().toUtc();
    final qs = questions ?? kBasecampCanonicalQuestions;
    final config = SurveyConfig(
      id: id,
      siteName: siteName.trim(),
      classroom: classroom.trim(),
      ageBand: ageBand,
      pinHash: _hashPin(pinDigits, id),
      audioMode: audioMode,
      voice: voice,
      style: style,
      questions: qs,
      createdAt: now,
      updatedAt: now,
      schools: schools
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
    );
    await _db.into(_db.surveys).insert(_toCompanion(config));
    unawaited(
      _ref.read(syncEngineProvider).pushRow(surveysSpec, id),
    );
    return config;
  }

  /// Verify a 4-digit PIN against the survey's stored hash.
  /// Constant-time comparison so timing attacks can't probe digits.
  bool verifyPin(SurveyConfig survey, String pinDigits) {
    final candidate = _hashPin(pinDigits, survey.id);
    if (candidate.length != survey.pinHash.length) return false;
    var diff = 0;
    for (var i = 0; i < candidate.length; i++) {
      diff |= candidate.codeUnitAt(i) ^ survey.pinHash.codeUnitAt(i);
    }
    return diff == 0;
  }

  // ——— Sessions ——————————————————————————————————————————————

  /// One session by id (or null if missing). Used by the results-
  /// screen tap-to-resume flow.
  Future<SurveySession?> getSession(String sessionId) async {
    return (_db.select(_db.surveySessions)
          ..where((s) => s.id.equals(sessionId)))
        .getSingleOrNull();
  }

  /// All responses for [sessionId]. Used by tap-to-resume to
  /// decide which question the child stopped on, and by the
  /// preview-card path to feed mood values into the painter.
  Future<List<SurveyResponse>> getResponsesForSession(
    String sessionId,
  ) async {
    return (_db.select(_db.surveyResponses)
          ..where((r) => r.sessionId.equals(sessionId)))
        .get();
  }

  /// Re-open a session that had been ended (e.g. teacher tapped
  /// in to resume from the results sheet). Clears `endedAt` and
  /// `childCount` so a fresh "complete" can land later.
  Future<void> reopenSession(String sessionId) async {
    // Soft-deleted sessions stay deleted — a bookmarked
    // `/surveys/:id/play?resume=<id>` URL or a race between the
    // results-screen filter and a tap could otherwise silently
    // un-delete them by clearing endedAt below.
    final existing = await getSession(sessionId);
    if (existing == null || existing.deletedAt != null) return;
    await (_db.update(_db.surveySessions)
          ..where((s) => s.id.equals(sessionId)))
        .write(
      const SurveySessionsCompanion(
        endedAt: Value<DateTime?>(null),
        childCount: Value<int>(0),
      ),
    );
    await _pushSurvey(existing.surveyId);
  }

  /// Open a fresh session for a child going through the kiosk.
  /// Returns the session id for the caller to pass back when
  /// recording responses + closing.
  ///
  /// [school] is the kiosk's pre-flight gate answer — `'KIPP'`
  /// when the kid tapped Yes on the KIPP? prompt, otherwise the
  /// school name they typed. Null is allowed (resume / sandbox
  /// callers) but production kiosk callers always pass it.
  Future<String> startSession(
    String surveyId, {
    String? school,
  }) async {
    final id = newId();
    final cleanSchool = school?.trim();
    await _db.into(_db.surveySessions).insert(
          SurveySessionsCompanion(
            id: Value(id),
            surveyId: Value(surveyId),
            startedAt: Value(DateTime.now().toUtc()),
            school: cleanSchool == null || cleanSchool.isEmpty
                ? const Value<String?>(null)
                : Value<String?>(cleanSchool),
            programId: Value(_programId),
          ),
        );
    await _pushSurvey(surveyId);
    return id;
  }

  /// Stamp the kiosk's pre-flight gate answer onto an already-
  /// open session. Called the moment the kid taps Yes on the
  /// KIPP? prompt, or hits Continue after typing a school name.
  /// Empty / whitespace-only strings clear the field rather than
  /// writing blanks.
  Future<void> setSessionSchool(
    String sessionId,
    String school,
  ) async {
    final cleaned = school.trim();
    await (_db.update(_db.surveySessions)
          ..where((s) => s.id.equals(sessionId)))
        .write(
      SurveySessionsCompanion(
        school: cleaned.isEmpty
            ? const Value<String?>(null)
            : Value<String?>(cleaned),
      ),
    );
    final session = await getSession(sessionId);
    if (session != null) await _pushSurvey(session.surveyId);
  }

  /// Close a session. `completed = true` when the child reached
  /// the end of the question list; `false` when the kiosk was
  /// exited mid-flow (teacher PIN, app close, etc).
  Future<void> endSession(
    String sessionId, {
    required bool completed,
  }) async {
    await (_db.update(_db.surveySessions)
          ..where((s) => s.id.equals(sessionId)))
        .write(
      SurveySessionsCompanion(
        endedAt: Value(DateTime.now().toUtc()),
        childCount: Value(completed ? 1 : 0),
      ),
    );
    final session = await getSession(sessionId);
    if (session != null) await _pushSurvey(session.surveyId);
  }

  // ——— Responses ————————————————————————————————————————————————

  /// Record a Likert (mood) answer. `moodValue` is 0 (disagree),
  /// 1 (kind of agree), or 2 (agree). `reactionTimeMs` is from
  /// when the question first appeared to when the marble was
  /// dropped — a signal of confidence vs hesitation.
  Future<void> recordMoodAnswer({
    required String surveyId,
    required String sessionId,
    required String questionId,
    required int moodValue,
    required int reactionTimeMs,
    required bool isPractice,
  }) async {
    await _db.into(_db.surveyResponses).insert(
          SurveyResponsesCompanion(
            id: Value(newId()),
            surveyId: Value(surveyId),
            sessionId: Value(sessionId),
            questionId: Value(questionId),
            answerType: const Value('mood'),
            moodValue: Value(moodValue),
            reactionTimeMs: Value(reactionTimeMs),
            durationMs: Value(reactionTimeMs),
            isPractice: Value(isPractice),
            programId: Value(_programId),
            createdAt: Value(DateTime.now().toUtc()),
          ),
        );
    await _pushSurvey(surveyId);
  }

  /// Record a multi-select answer (the activities checkbox
  /// question). `selectedOptionIds` is the set of activity ids the
  /// child checked. Stored as JSON in `selections_json`.
  Future<void> recordMultiSelectAnswer({
    required String surveyId,
    required String sessionId,
    required String questionId,
    required List<String> selectedOptionIds,
    required int durationMs,
    required bool isPractice,
  }) async {
    await _db.into(_db.surveyResponses).insert(
          SurveyResponsesCompanion(
            id: Value(newId()),
            surveyId: Value(surveyId),
            sessionId: Value(sessionId),
            questionId: Value(questionId),
            answerType: const Value('multi_select'),
            selectionsJson: Value(jsonEncode(selectedOptionIds)),
            durationMs: Value(durationMs),
            isPractice: Value(isPractice),
            programId: Value(_programId),
            createdAt: Value(DateTime.now().toUtc()),
          ),
        );
    await _pushSurvey(surveyId);
  }

  /// Record an open-ended answer. Either or both of
  /// [audioFilePath] / [transcription] can be supplied — the live
  /// streaming flow saves transcription only, while a future
  /// "save audio backup too" mode could pass both.
  ///
  /// Returns the row id so the caller can correlate when a
  /// follow-up update lands.
  Future<String> recordOpenEndedAnswer({
    required String surveyId,
    required String sessionId,
    required String questionId,
    required int durationMs,
    required bool isPractice,
    String? audioFilePath,
    String? transcription,
  }) async {
    final id = newId();
    await _db.into(_db.surveyResponses).insert(
          SurveyResponsesCompanion(
            id: Value(id),
            surveyId: Value(surveyId),
            sessionId: Value(sessionId),
            questionId: Value(questionId),
            answerType: const Value('audio'),
            audioFilePath: Value(audioFilePath),
            transcription: Value(transcription),
            durationMs: Value(durationMs),
            isPractice: Value(isPractice),
            programId: Value(_programId),
            createdAt: Value(DateTime.now().toUtc()),
          ),
        );
    await _pushSurvey(surveyId);
    return id;
  }

  /// Patch in a transcription on a previously-recorded open-ended
  /// answer. Called from the background STT task once Deepgram
  /// returns a transcript, and from the results screen when a
  /// teacher corrects the transcript manually.
  ///
  /// [surveyId] is required so we can fan out the cloud push
  /// without a TOCTOU read-back. The caller already has it (the
  /// response carries it on the row).
  Future<void> updateTranscription({
    required String responseId,
    required String surveyId,
    required String text,
  }) async {
    await (_db.update(_db.surveyResponses)
          ..where((r) => r.id.equals(responseId)))
        .write(SurveyResponsesCompanion(transcription: Value(text)));
    await _pushSurvey(surveyId);
  }

  // ——— Results (Slice 5) ———————————————————————————————————

  /// Live stream of result rows for [surveyId]. Each row is one
  /// session (= one child going through the kiosk) with all of
  /// its responses keyed by questionId. Newest sessions first.
  Stream<List<SurveyResultRow>> watchResults(String surveyId) {
    final sessions = _db.select(_db.surveySessions)
      ..where(
        (s) => s.surveyId.equals(surveyId) & s.deletedAt.isNull(),
      )
      ..orderBy([
        (s) => OrderingTerm(
              expression: s.startedAt,
              mode: OrderingMode.desc,
            ),
      ]);
    return sessions.watch().asyncMap((sessionRows) async {
      if (sessionRows.isEmpty) return <SurveyResultRow>[];
      final ids = sessionRows.map((s) => s.id).toList();
      final responses = await (_db.select(_db.surveyResponses)
            ..where((r) => r.sessionId.isIn(ids)))
          .get();
      final byId = <String, List<SurveyResponse>>{};
      for (final r in responses) {
        byId.putIfAbsent(r.sessionId, () => <SurveyResponse>[]).add(r);
      }
      return sessionRows
          .map((s) => SurveyResultRow(
                session: s,
                responsesByQuestionId: <String, SurveyResponse>{
                  for (final r in (byId[s.id] ?? const <SurveyResponse>[]))
                    r.questionId: r,
                },
              ))
          .toList();
    });
  }

  /// Soft-delete: stamp deletedAt. The row stays so historical
  /// responses keep resolving the parent survey for the results
  /// sheet, but pickers + the list filter it out.
  Future<void> softDelete(String id) async {
    await (_db.update(_db.surveys)..where((s) => s.id.equals(id))).write(
      SurveysCompanion(
        deletedAt: Value(DateTime.now().toUtc()),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    unawaited(_ref.read(syncEngineProvider).pushRow(surveysSpec, id));
  }

  /// Soft-delete a single session (one kid's run through the
  /// kiosk). The parent survey + its other sessions stay; the
  /// results sheet filters this one out on next refresh.
  /// Idempotent — already-deleted sessions just re-stamp the
  /// timestamp. Restoring a session means setting `deletedAt`
  /// back to null; not exposed today but easy to add.
  Future<void> softDeleteSession(String sessionId) async {
    final session = await getSession(sessionId);
    if (session == null) return;
    await (_db.update(_db.surveySessions)
          ..where((s) => s.id.equals(sessionId)))
        .write(
      SurveySessionsCompanion(
        deletedAt: Value(DateTime.now().toUtc()),
      ),
    );
    await _pushSurvey(session.surveyId);
  }

  // ——— Mappings ——————————————————————————————————————————————

  SurveyConfig _fromRow(Survey row) {
    return SurveyConfig(
      id: row.id,
      siteName: row.siteName,
      classroom: row.classroom,
      ageBand: SurveyAgeBand.fromCode(row.ageBand),
      pinHash: row.pinHash,
      audioMode: SurveyAudioMode.fromCode(row.audioMode),
      voice: SurveyVoice.fromCode(row.voiceId),
      style: SurveyStyle.fromCode(row.style),
      questions: SurveyConfig.parseQuestions(row.questionsJson),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      schools: SurveyConfig.parseSchools(row.schoolsJson),
    );
  }

  SurveysCompanion _toCompanion(SurveyConfig config) => SurveysCompanion(
        id: Value(config.id),
        siteName: Value(config.siteName),
        classroom: Value(config.classroom),
        ageBand: Value(config.ageBand.code),
        pinHash: Value(config.pinHash),
        audioMode: Value(config.audioMode.code),
        voiceId: Value(config.voice.code),
        style: Value(config.style.code),
        questionsJson: Value(config.questionsJson()),
        schoolsJson: Value(config.schoolsJsonString()),
        programId: Value(_programId),
        createdAt: Value(config.createdAt),
        updatedAt: Value(config.updatedAt),
      );

  /// SHA-256 of `salt|pin`. Salt is the survey id so the same
  /// 4-digit PIN ("1234") used across surveys produces different
  /// hashes per survey.
  String _hashPin(String pinDigits, String salt) {
    final bytes = utf8.encode('$salt|${pinDigits.trim()}');
    return sha256.convert(bytes).toString();
  }
}

/// Riverpod provider for `SurveyRepository`. Reads the shared
/// `databaseProvider` so all features see the same DB.
final surveyRepositoryProvider = Provider<SurveyRepository>((ref) {
  // ref is captured in the repo so insert-time `activeProgramIdProvider`
  // reads stamp the current program onto fresh rows.
  final db = ref.watch(databaseProvider);
  return SurveyRepository(db, ref);
});

/// Live list of surveys (non-deleted, newest first). Watches the
/// table via Drift's stream.
final surveysListProvider = StreamProvider<List<SurveyConfig>>((ref) {
  return ref.watch(surveyRepositoryProvider).watchAll();
});

/// Single-survey lookup by id. `family` keyed on the id.
// Single-survey lookup by id. `family` keyed on the id.
// ignore: specify_nonobvious_property_types
final surveyByIdProvider =
    FutureProvider.family<SurveyConfig?, String>((ref, id) {
  return ref.watch(surveyRepositoryProvider).getById(id);
});

/// Live result rows for a survey. Updates as children complete
/// kiosk sessions.
// ignore: specify_nonobvious_property_types
final surveyResultsProvider =
    StreamProvider.family<List<SurveyResultRow>, String>((ref, id) {
  return ref.watch(surveyRepositoryProvider).watchResults(id);
});
