// Session store for the basket-survey experiment. One row per
// completed session; each row holds the chosen face per question.
// Persisted as a JSON array in `<docs>/basket_survey_sessions.json`
// so it survives app restarts but doesn't go through the cloud
// sync engine — this is a sandbox experiment, not production data.
//
// CSV exporter pivots the rows into a familiar "one row per kid"
// shape with one column per question id.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/features/experiment/basket_survey/painted_face.dart';
import 'package:basecamp/features/surveys/canonical_questions.dart';
import 'package:basecamp/features/surveys/survey_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One completed run through the basket survey by one kid.
class BasketSurveySession {
  const BasketSurveySession({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.answers,
  });

  final String id;
  final DateTime startedAt;
  final DateTime endedAt;

  /// `questionId → mood` for every question the kid answered.
  /// Mood is stored by enum index (0..4) so we don't mix up
  /// 3-point and 5-point columns when the schema evolves.
  final Map<String, FaceMood> answers;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'answers': <String, int>{
          for (final entry in answers.entries) entry.key: entry.value.index,
        },
      };

  // Static helper instead of named ctor — Dart's named ctor can't
  // shadow the const generative ctor's positional shape cleanly.
  // ignore: prefer_constructors_over_static_methods
  static BasketSurveySession fromJson(Map<String, dynamic> json) {
    final raw = json['answers'] as Map<String, dynamic>? ?? const {};
    return BasketSurveySession(
      id: json['id'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      endedAt: DateTime.parse(json['endedAt'] as String),
      answers: <String, FaceMood>{
        for (final entry in raw.entries)
          entry.key: FaceMood.values[entry.value as int],
      },
    );
  }
}

/// In-memory mirror of the JSON file on disk. Loads lazily on first
/// access; saves debounced after each completed session. The
/// notifier exposes `add` (appends a new session + persists) and
/// `clearAll` (wipes the file + the in-memory list).
class BasketSurveySessionsNotifier
    extends AsyncNotifier<List<BasketSurveySession>> {
  static const String _fileName = 'basket_survey_sessions.json';

  @override
  Future<List<BasketSurveySession>> build() async {
    return _readAll();
  }

  Future<List<BasketSurveySession>> _readAll() async {
    if (kIsWeb) return const <BasketSurveySession>[];
    try {
      final file = await _file();
      if (!file.existsSync()) return const <BasketSurveySession>[];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const <BasketSurveySession>[];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => BasketSurveySession.fromJson(e as Map<String, dynamic>))
          .toList();
    } on Object catch (e, st) {
      debugPrint('[basket-survey] read sessions failed: $e\n$st');
      return const <BasketSurveySession>[];
    }
  }

  Future<File> _file() async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, _fileName));
  }

  Future<void> _writeAll(List<BasketSurveySession> sessions) async {
    if (kIsWeb) return; // web has no docs folder; skip persistence
    try {
      final file = await _file();
      final encoded = jsonEncode(<Map<String, dynamic>>[
        for (final s in sessions) s.toJson(),
      ]);
      await file.writeAsString(encoded, flush: true);
    } on Object catch (e, st) {
      debugPrint('[basket-survey] write sessions failed: $e\n$st');
    }
  }

  /// Append a new completed session.
  Future<BasketSurveySession> add({
    required Map<String, FaceMood> answers,
    required DateTime startedAt,
    required DateTime endedAt,
  }) async {
    final session = BasketSurveySession(
      id: newId(),
      startedAt: startedAt,
      endedAt: endedAt,
      answers: Map<String, FaceMood>.unmodifiable(answers),
    );
    final current = await future;
    final next = <BasketSurveySession>[...current, session];
    state = AsyncData(next);
    await _writeAll(next);
    return session;
  }

  /// Wipe everything. Confirmation lives in the UI.
  Future<void> clearAll() async {
    state = const AsyncData(<BasketSurveySession>[]);
    await _writeAll(const <BasketSurveySession>[]);
  }
}

final basketSurveySessionsProvider = AsyncNotifierProvider<
    BasketSurveySessionsNotifier, List<BasketSurveySession>>(
  BasketSurveySessionsNotifier.new,
);

/// Build a CSV from the recorded sessions. One row per session,
/// one column per **mood** question in [questions]. Each cell is
/// the chosen mood as `0..4` (5-point Likert). Columns for
/// questions a session didn't answer are blank.
///
/// Header row also includes session metadata (id, started_at,
/// ended_at) so a teacher exporting can sort / dedupe by date.
String buildBasketSurveyCsv({
  required List<BasketSurveySession> sessions,
  List<SurveyQuestion> questions = kBasecampCanonicalQuestions,
}) {
  final moodQuestions =
      questions.where((q) => q.type == SurveyQuestionType.mood).toList();
  final headers = <String>[
    'session_id',
    'started_at',
    'ended_at',
    for (final q in moodQuestions) q.id,
  ];
  final buf = StringBuffer()..writeln(_csvRow(headers));
  // Oldest first so reading top-to-bottom matches chronological
  // order.
  final ordered = [...sessions]
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  for (final s in ordered) {
    final cells = <String>[
      s.id,
      s.startedAt.toUtc().toIso8601String(),
      s.endedAt.toUtc().toIso8601String(),
      for (final q in moodQuestions)
        if (s.answers[q.id] case final FaceMood m)
          basketLikert5(m).toString()
        else
          '',
    ];
    buf.writeln(_csvRow(cells));
  }
  return buf.toString();
}

String _csvRow(Iterable<String> cells) =>
    cells.map(_csvText).join(',');

String _csvText(String s) {
  if (s.isEmpty) return '';
  final needsQuote =
      s.contains(',') || s.contains('\n') || s.contains('\r') || s.contains('"');
  if (!needsQuote) return s;
  return '"${s.replaceAll('"', '""')}"';
}
