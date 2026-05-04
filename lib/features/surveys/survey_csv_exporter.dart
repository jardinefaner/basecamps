// CSV exporter for the BASECamp Student Survey results sheet
// (Slice 6).
//
// Pivots the response data into one CSV row per session × one
// column per (question, sub-key) pair. Excel-friendly:
//   * Mood (Likert) questions  → numeric 0/1/2 column
//   * Multi-select questions   → 7 boolean columns (one per
//                                option) + a count column
//   * Open-ended questions     → audio file path + transcription
//   * Plus session metadata    → started_at, ended_at, status,
//                                child_index
//
// **Pure function**, by design — separable from the share/save
// step so we can test the CSV shape without mocking platform
// channels.

import 'dart:convert';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/surveys/canonical_questions.dart';
import 'package:basecamp/features/surveys/survey_models.dart';
import 'package:basecamp/features/surveys/survey_repository.dart';

class SurveyCsvExportOptions {
  const SurveyCsvExportOptions({
    this.includePractice = false,
    this.includeAudioPath = true,
  });

  /// Practice questions are excluded by default — they don't
  /// belong in the analysis. Toggle on to include them as
  /// dim-tagged columns.
  final bool includePractice;

  /// Whether to include the audio file path column for open-
  /// ended questions. Off if the teacher just wants the
  /// transcription text without the file reference.
  final bool includeAudioPath;
}

class SurveyCsvExporter {
  const SurveyCsvExporter();

  /// Build the CSV body. The caller writes the bytes; this
  /// function is pure.
  String exportToCsv(
    SurveyConfig survey,
    List<SurveyResultRow> rows, {
    SurveyCsvExportOptions options = const SurveyCsvExportOptions(),
  }) {
    final headers = <String>[
      'child_index',
      'started_at',
      'ended_at',
      'status',
    ];

    // Decide which questions go in the export based on practice
    // flag. Same order as the survey for predictable column
    // layout.
    final questions = survey.questions
        .where((q) => options.includePractice || !q.isPractice)
        .toList();

    // Build column list per question type.
    for (final q in questions) {
      final base = _slug(q.id);
      switch (q.type) {
        case SurveyQuestionType.mood:
          headers.add(base);
        case SurveyQuestionType.multiSelect:
          for (final option in q.options) {
            headers.add('${base}__${_slug(option.id)}');
          }
          headers.add('${base}__count');
        case SurveyQuestionType.openEnded:
          headers.add('${base}_transcription');
          if (options.includeAudioPath) {
            headers.add('${base}_audio_path');
          }
      }
    }

    final buffer = StringBuffer()..writeln(_csvRow(headers));

    // Sessions come from the repo newest-first; reverse so the
    // exported CSV reads in chronological order, with child #1 as
    // the first row.
    final ordered = rows.reversed.toList();
    for (var i = 0; i < ordered.length; i++) {
      final row = ordered[i];
      final session = row.session;
      final String status;
      if (session.endedAt == null) {
        status = 'in_progress';
      } else if (session.childCount >= 1) {
        status = 'completed';
      } else {
        status = 'incomplete';
      }
      final cells = <String>[
        '${i + 1}',
        session.startedAt.toUtc().toIso8601String(),
        session.endedAt?.toUtc().toIso8601String() ?? '',
        status,
      ];
      for (final q in questions) {
        final response = row.responsesByQuestionId[q.id];
        switch (q.type) {
          case SurveyQuestionType.mood:
            cells.add(_moodCell(response));
          case SurveyQuestionType.multiSelect:
            cells.addAll(_multiSelectCells(q, response));
          case SurveyQuestionType.openEnded:
            cells.add(_csvText(response?.transcription ?? ''));
            if (options.includeAudioPath) {
              cells.add(_csvText(response?.audioFilePath ?? ''));
            }
        }
      }
      buffer.writeln(_csvRow(cells));
    }

    return buffer.toString();
  }

  /// Suggested file name for the export. Stable across calls so
  /// the share sheet doesn't get cluttered with timestamped
  /// duplicates — the teacher decides whether to overwrite or
  /// rename.
  String fileName(SurveyConfig survey) {
    final date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    return '${_slug(survey.siteName)}_${_slug(survey.classroom)}_$date.csv';
  }

  // ——— Cell shapers ————————————————————————————————————————

  String _moodCell(SurveyResponse? r) {
    if (r == null) return '';
    final v = r.moodValue;
    if (v == null) return '';
    return v.toString();
  }

  List<String> _multiSelectCells(SurveyQuestion q, SurveyResponse? r) {
    final selected = _decodeSelections(r?.selectionsJson);
    final cells = <String>[];
    for (final option in q.options) {
      if (r == null) {
        cells.add('');
      } else if (selected.contains(option.id)) {
        cells.add('1');
      } else {
        cells.add('0');
      }
    }
    cells.add(r == null ? '' : selected.length.toString());
    return cells;
  }

  Set<String> _decodeSelections(String? raw) {
    if (raw == null || raw.isEmpty) return const <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toSet();
      }
    } on FormatException {
      // Tolerate corrupt JSON.
    }
    return const <String>{};
  }

  // ——— CSV escaping ————————————————————————————————————————

  String _csvRow(Iterable<String> cells) =>
      cells.map(_csvText).join(',');

  /// RFC 4180 escape: quote any field with comma / newline / quote;
  /// double-up internal quotes.
  String _csvText(String s) {
    if (s.isEmpty) return '';
    final needsQuote = s.contains(',') ||
        s.contains('\n') ||
        s.contains('\r') ||
        s.contains('"');
    if (!needsQuote) return s;
    final escaped = s.replaceAll('"', '""');
    return '"$escaped"';
  }

  /// Slug helper — keeps the survey + activity ids out of file
  /// names that share-sheets might mangle (slashes, colons, etc).
  String _slug(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
}

/// Singleton — exporter is stateless.
const SurveyCsvExporter kSurveyCsvExporter = SurveyCsvExporter();

/// Used by the BASECamp survey when it wants to seed the canonical
/// activity options column order even if the survey config carries
/// a stale snapshot. (Slice-6 forward-compatibility hook.)
List<String> kBasecampCanonicalActivityIds = <String>[
  for (final option in kBasecampActivityOptions) option.id,
];
