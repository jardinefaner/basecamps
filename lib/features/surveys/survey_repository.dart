// Survey repository (Slice 1) — local-only persistence for the
// new BASECamp Student Survey tool. CRUD on `surveys`, plus
// helpers for the kiosk + the results sheet (slice 5).
//
// Sync wiring isn't included yet — surveys are device-local until
// the feature graduates from experiment. When we promote, register
// `surveys` / `survey_sessions` / `survey_responses` in
// sync_specs.dart and the existing engine handles realtime + push.

import 'dart:convert';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/surveys/canonical_questions.dart';
import 'package:basecamp/features/surveys/survey_models.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
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
  SurveyRepository(this._db);

  final AppDatabase _db;

  /// All non-deleted surveys, newest first. Wraps Drift's row →
  /// `SurveyConfig` mapping so the UI gets in-memory objects.
  Stream<List<SurveyConfig>> watchAll() {
    final query = _db.select(_db.surveys)
      ..where((s) => s.deletedAt.isNull())
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
    List<SurveyQuestion>? questions,
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
      questions: qs,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.surveys).insert(_toCompanion(config));
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

  /// Open a fresh session for a child going through the kiosk.
  /// Returns the session id for the caller to pass back when
  /// recording responses + closing.
  Future<String> startSession(String surveyId) async {
    final id = newId();
    await _db.into(_db.surveySessions).insert(
          SurveySessionsCompanion(
            id: Value(id),
            surveyId: Value(surveyId),
            startedAt: Value(DateTime.now().toUtc()),
          ),
        );
    return id;
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
          ),
        );
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
          ),
        );
  }

  /// Record an open-ended answer. `audioFilePath` is relative to
  /// the app docs folder. `transcription` is filled in
  /// asynchronously after Deepgram STT finishes — this method just
  /// stamps the audio path; transcription updates with
  /// `updateTranscription` when ready.
  ///
  /// Returns the row id so the caller can correlate when the
  /// background transcription finishes.
  Future<String> recordOpenEndedAnswer({
    required String surveyId,
    required String sessionId,
    required String questionId,
    required String audioFilePath,
    required int durationMs,
    required bool isPractice,
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
            durationMs: Value(durationMs),
            isPractice: Value(isPractice),
          ),
        );
    return id;
  }

  /// Patch in a transcription on a previously-recorded open-ended
  /// answer. Called from the background STT task once Deepgram
  /// returns a transcript.
  Future<void> updateTranscription(String responseId, String text) async {
    await (_db.update(_db.surveyResponses)
          ..where((r) => r.id.equals(responseId)))
        .write(SurveyResponsesCompanion(transcription: Value(text)));
  }

  // ——— Results (Slice 5) ———————————————————————————————————

  /// Live stream of result rows for [surveyId]. Each row is one
  /// session (= one child going through the kiosk) with all of
  /// its responses keyed by questionId. Newest sessions first.
  Stream<List<SurveyResultRow>> watchResults(String surveyId) {
    final sessions = _db.select(_db.surveySessions)
      ..where((s) => s.surveyId.equals(surveyId))
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
      questions: SurveyConfig.parseQuestions(row.questionsJson),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
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
        questionsJson: Value(config.questionsJson()),
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
  final db = ref.watch(databaseProvider);
  return SurveyRepository(db);
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
