// Survey results sheet (Slice 5) — the Excel-styled grid for
// reviewing what children have answered. Sits at
// `/surveys/:id` (the default landing for a saved
// survey); a "Start kiosk" button on this page opens
// `/:id/play` for the next round of children.
//
// **One row per child (session). Columns per question.** Wide
// screens get the grid; narrow screens (<700dp) collapse to a
// stacked card view. Multi-select cells render as a chip cluster
// inline with one chip per selected activity (icons-only,
// tap to read full label). Open-ended cells show truncated
// transcription; tapping plays the recorded audio (when audio
// service support lands).
//
// Slice 6 wires the "Export CSV" button.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/surveys/canonical_questions.dart';
import 'package:basecamp/features/surveys/feelings_jar_card.dart';
import 'package:basecamp/features/surveys/multi_select_overlay.dart';
import 'package:basecamp/features/surveys/survey_csv_exporter.dart';
import 'package:basecamp/features/surveys/survey_models.dart';
import 'package:basecamp/features/surveys/survey_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class SurveyResultsScreen extends ConsumerWidget {
  const SurveyResultsScreen({required this.surveyId, super.key});

  final String surveyId;

  /// Mobile fallback breakpoint. Below this width we render one
  /// card per child stacked vertically (the grid is too cramped).
  static const double _gridMinWidth = 700;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final surveyAsync = ref.watch(surveyByIdProvider(surveyId));
    final resultsAsync = ref.watch(surveyResultsProvider(surveyId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        actions: [
          surveyAsync.maybeWhen(
            data: (survey) => survey == null
                ? const SizedBox.shrink()
                : TextButton.icon(
                    onPressed: () => context.push(
                      '/surveys/${survey.id}/play',
                    ),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start kiosk'),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
          surveyAsync.maybeWhen(
            data: (survey) => survey == null
                ? const SizedBox.shrink()
                : IconButton(
                    onPressed: () => _exportCsv(context, ref, survey),
                    icon: const Icon(Icons.file_download_outlined),
                    tooltip: 'Export CSV',
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: surveyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(message: 'Could not load survey: $e'),
        data: (survey) {
          if (survey == null) {
            return const _ErrorView(
              message: 'This survey has been deleted.',
            );
          }
          return Column(
            children: [
              _Header(survey: survey, theme: theme),
              const Divider(height: 0),
              Expanded(
                child: resultsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) =>
                      _ErrorView(message: 'Could not load results: $e'),
                  data: (rows) => rows.isEmpty
                      ? _EmptyState(theme: theme)
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth < _gridMinWidth) {
                              return _CardList(
                                survey: survey,
                                rows: rows,
                                theme: theme,
                              );
                            }
                            return _ResultsGrid(
                              survey: survey,
                              rows: rows,
                              theme: theme,
                            );
                          },
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// `true` when this child's run reached the end-of-survey beat.
/// Mirrors the `endSession(completed: true)` write path:
/// completion is `endedAt != null && childCount >= 1`.
bool _isSessionComplete(SurveySession s) =>
    s.endedAt != null && s.childCount >= 1;

/// Tap handler for a child row. Behavior:
///   * Incomplete session  → push the kiosk with a `resume=<id>`
///                            query param. The kiosk re-opens the
///                            session and jumps to the first
///                            unanswered question.
///   * Complete session    → show the FeelingsJarCard in a modal
///                            so the teacher (or the kid back for
///                            another keepsake) can re-print it.
void _onChildRowTapped({
  required BuildContext context,
  required SurveyConfig survey,
  required SurveyResultRow row,
}) {
  if (_isSessionComplete(row.session)) {
    final moods = <int>[
      for (final q in survey.questions)
        if (q.type == SurveyQuestionType.mood)
          if (row.responsesByQuestionId[q.id]?.moodValue case final int v) v,
    ];
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: const Text('Feelings Jar'),
            ),
            body: FeelingsJarCard(
              moodValues: moods,
              siteName: survey.siteName,
              classroom: survey.classroom,
              doneLabel: 'Close',
              onDone: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    );
    return;
  }
  // Incomplete — resume the kiosk on this session.
  unawaited(
    context.push(
      Uri(
        path: '/surveys/${survey.id}/play',
        queryParameters: <String, String>{'resume': row.session.id},
      ).toString(),
    ),
  );
}

/// Build the CSV from the current results stream value, then
/// hand off to the platform share / save flow.
///
/// Mobile: native share sheet via `share_plus`.
/// Web: copies the CSV to clipboard (no native share for files
/// in pure Flutter web; clipboard is the most universal "do
/// something with this" path that works in any browser).
/// Desktop: falls through to share_plus's desktop adapter.
Future<void> _exportCsv(
  BuildContext context,
  WidgetRef ref,
  SurveyConfig survey,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    // Read straight from the repository instead of waiting on the
    // StreamProvider's `.future` — that future resolves on the
    // *next* emission, which can hang if the stream is idle (no
    // new sessions opening). A single-shot pull from the repo
    // gives us an immediate snapshot.
    final rows = await ref
        .read(surveyRepositoryProvider)
        .watchResults(survey.id)
        .first;
    if (rows.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No responses yet — nothing to export.'),
        ),
      );
      return;
    }
    final csv = kSurveyCsvExporter.exportToCsv(survey, rows);
    final filename = kSurveyCsvExporter.fileName(survey);
    debugPrint('[csv] $filename · ${rows.length} sessions · '
        '${csv.length} chars');

    if (kIsWeb) {
      // Web fallback — clipboard. share_plus's web build only
      // supports text shares, not file shares from a plain
      // browser tab. Pasting into Sheets / Excel works fine.
      await Clipboard.setData(ClipboardData(text: csv));
      messenger.showSnackBar(
        SnackBar(
          content: Text('Copied $filename to clipboard. '
              'Paste into Sheets or Excel.'),
        ),
      );
      return;
    }

    // Mobile + desktop: write the CSV to a temp file, hand off.
    // We write to **app docs**, not temp, so the file stays put if
    // the share sheet itself fails — the teacher can then find it
    // by path from the snackbar instead of losing the export.
    final docs = await getApplicationDocumentsDirectory();
    final filePath = p.join(docs.path, filename);
    await File(filePath).writeAsString(csv);
    debugPrint('[csv] wrote $filePath');
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile(filePath, name: filename, mimeType: 'text/csv'),
          ],
          subject: '${survey.siteName} · ${survey.classroom} survey',
          text: '$filename — ${rows.length} '
              'response${rows.length == 1 ? '' : 's'} from '
              '${survey.classroom}.',
        ),
      );
      debugPrint('[csv] share result: ${result.status}');
      if (result.status == ShareResultStatus.unavailable) {
        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 12),
            content: Text(
              'Share sheet unavailable. Saved to:\n$filePath',
            ),
            action: SnackBarAction(
              label: 'Copy path',
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: filePath)),
            ),
          ),
        );
      }
    } on Object catch (e, st) {
      debugPrint('[csv] share failed: $e\n$st');
      // Share failed but the file did write — surface the path so
      // the teacher can pull it via Files / adb / a file manager.
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 15),
          content: Text(
            'Saved to $filePath (share failed: $e)',
          ),
          action: SnackBarAction(
            label: 'Copy path',
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: filePath)),
          ),
        ),
      );
    }
  } on Object catch (e, st) {
    debugPrint('[csv] export failed: $e\n$st');
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: Text('Could not export CSV: $e'),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.survey, required this.theme});

  final SurveyConfig survey;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  survey.siteName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${survey.classroom} · ${survey.ageBand.label} · '
                  '${survey.questions.length} questions',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsGrid extends StatelessWidget {
  const _ResultsGrid({
    required this.survey,
    required this.rows,
    required this.theme,
  });

  final SurveyConfig survey;
  final List<SurveyResultRow> rows;
  final ThemeData theme;

  static const double _rowHeight = 72;
  static const double _firstColWidth = 180;
  static const double _moodColWidth = 96;
  static const double _multiSelectColWidth = 220;
  static const double _openEndedColWidth = 280;

  double _columnWidth(SurveyQuestion q) {
    switch (q.type) {
      case SurveyQuestionType.mood:
        return _moodColWidth;
      case SurveyQuestionType.multiSelect:
        return _multiSelectColWidth;
      case SurveyQuestionType.openEnded:
        return _openEndedColWidth;
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalQuestionWidth = survey.questions
        .map(_columnWidth)
        .fold<double>(0, (sum, w) => sum + w);

    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _firstColWidth + totalQuestionWidth,
          child: Column(
            children: [
              _GridHeaderRow(
                survey: survey,
                firstColWidth: _firstColWidth,
                columnWidthFor: _columnWidth,
                theme: theme,
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    return _GridDataRow(
                      survey: survey,
                      row: row,
                      index: rows.length - i, // newest at top, but
                      // numbered from the start of the run so
                      // session #1 is the first child.
                      firstColWidth: _firstColWidth,
                      columnWidthFor: _columnWidth,
                      rowHeight: _rowHeight,
                      theme: theme,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridHeaderRow extends StatelessWidget {
  const _GridHeaderRow({
    required this.survey,
    required this.firstColWidth,
    required this.columnWidthFor,
    required this.theme,
  });

  final SurveyConfig survey;
  final double firstColWidth;
  final double Function(SurveyQuestion) columnWidthFor;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          _HeaderCell(
            width: firstColWidth,
            label: 'Child',
            theme: theme,
          ),
          for (final q in survey.questions)
            _HeaderCell(
              width: columnWidthFor(q),
              label: _shortLabel(q),
              tooltip: q.prompt,
              isPractice: q.isPractice,
              theme: theme,
            ),
        ],
      ),
    );
  }

  /// Compact column header — strips the wordy prompt down to the
  /// kiosk-readable nub. Falls back to the full prompt when no
  /// shortening is obvious.
  String _shortLabel(SurveyQuestion q) {
    final p = q.prompt;
    // Heuristic: trim trailing punctuation, take up to ~32 chars,
    // append … if we cut. Practice questions get a leading p.
    var s = p.trim();
    if (s.endsWith('.') || s.endsWith('?') || s.endsWith('…')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.length > 32) s = '${s.substring(0, 30).trimRight()}…';
    return q.isPractice ? '(p) $s' : s;
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.width,
    required this.label,
    required this.theme,
    this.tooltip,
    this.isPractice = false,
  });

  final double width;
  final String label;
  final String? tooltip;
  final bool isPractice;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final cell = SizedBox(
      width: width,
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: isPractice
                  ? theme.colorScheme.outline
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
    final t = tooltip;
    if (t == null) return cell;
    return Tooltip(message: t, child: cell);
  }
}

class _GridDataRow extends StatelessWidget {
  const _GridDataRow({
    required this.survey,
    required this.row,
    required this.index,
    required this.firstColWidth,
    required this.columnWidthFor,
    required this.rowHeight,
    required this.theme,
  });

  final SurveyConfig survey;
  final SurveyResultRow row;
  final int index;
  final double firstColWidth;
  final double Function(SurveyQuestion) columnWidthFor;
  final double rowHeight;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat.Md().add_jm();
    final complete = _isSessionComplete(row.session);
    final inProgress =
        row.session.endedAt == null; // session was never closed
    final incomplete = row.session.endedAt != null && !complete;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onChildRowTapped(
          context: context,
          survey: survey,
          row: row,
        ),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant,
                width: 0.5,
              ),
            ),
          ),
          height: rowHeight,
          child: Row(
            children: [
              SizedBox(
                width: firstColWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Child #$index',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (complete)
                            const Icon(
                              Icons.check_circle,
                              size: 14,
                              color: Color(0xFF3A9C7B),
                            )
                          else if (inProgress)
                            const Icon(
                              Icons.play_circle_outline,
                              size: 14,
                              color: Color(0xFFB47A48),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateFmt.format(row.session.startedAt.toLocal()),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (incomplete) ...[
                        const SizedBox(height: 2),
                        Text(
                          'incomplete · tap to resume',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ] else if (inProgress) ...[
                        const SizedBox(height: 2),
                        Text(
                          'in progress · tap to continue',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFFB47A48),
                          ),
                        ),
                      ] else if (complete) ...[
                        const SizedBox(height: 2),
                        Text(
                          'tap to view jar',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              for (final q in survey.questions)
                SizedBox(
                  width: columnWidthFor(q),
                  child: _AnswerCell(
                    question: q,
                    response: row.responsesByQuestionId[q.id],
                    theme: theme,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnswerCell extends StatelessWidget {
  const _AnswerCell({
    required this.question,
    required this.response,
    required this.theme,
  });

  final SurveyQuestion question;
  final SurveyResponse? response;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (response == null) {
      return Center(
        child: Text(
          '—',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }
    switch (question.type) {
      case SurveyQuestionType.mood:
        return Center(child: _MoodCell(response: response!, theme: theme));
      case SurveyQuestionType.multiSelect:
        return _MultiSelectCell(response: response!, theme: theme);
      case SurveyQuestionType.openEnded:
        return _OpenEndedCell(response: response!, theme: theme);
    }
  }
}

class _MoodCell extends StatelessWidget {
  const _MoodCell({required this.response, required this.theme});

  final SurveyResponse response;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final v = response.moodValue ?? -1;
    final (label, color) = switch (v) {
      0 => ('Disagree', const Color(0xFFA32D2D)),
      1 => ('Kind of', const Color(0xFF854F0B)),
      2 => ('Agree', const Color(0xFF27500A)),
      _ => ('?', theme.colorScheme.outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MultiSelectCell extends StatelessWidget {
  const _MultiSelectCell({required this.response, required this.theme});

  final SurveyResponse response;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final ids = _decodeSelections(response.selectionsJson);
    if (ids.isEmpty) {
      return Center(
        child: Text(
          'none',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        children: ids.map((id) {
          final option = kBasecampActivityOptions.firstWhere(
            (o) => o.id == id,
            orElse: () => SurveyActivityOption(id: id, label: id),
          );
          return Tooltip(
            message: option.label,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                multiSelectIconForId(id),
                size: 16,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  List<String> _decodeSelections(String? raw) {
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.cast<String>();
    } on FormatException {
      // Tolerate corrupt JSON — show empty.
    }
    return const <String>[];
  }
}

class _OpenEndedCell extends StatelessWidget {
  const _OpenEndedCell({required this.response, required this.theme});

  final SurveyResponse response;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final transcript = response.transcription;
    final hasAudio = response.audioFilePath != null;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          if (hasAudio)
            IconButton(
              onPressed: () =>
                  ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Audio playback ships with CSV export.'),
                  duration: Duration(seconds: 2),
                ),
              ),
              icon: const Icon(Icons.play_circle_outline, size: 20),
              tooltip: 'Play recording',
              visualDensity: VisualDensity.compact,
            ),
          Expanded(
            child: Text(
              transcript ??
                  (hasAudio
                      ? '[audio recorded — transcription pending]'
                      : '—'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: transcript == null ? FontStyle.italic : null,
                color: transcript == null
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardList extends StatelessWidget {
  const _CardList({
    required this.survey,
    required this.rows,
    required this.theme,
  });

  final SurveyConfig survey;
  final List<SurveyResultRow> rows;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat.MMMd().add_jm();
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) {
        final row = rows[i];
        final complete = _isSessionComplete(row.session);
        final inProgress = row.session.endedAt == null;
        final tapHint = complete
            ? 'tap to view jar'
            : inProgress
                ? 'in progress · tap to continue'
                : 'incomplete · tap to resume';
        final tapHintColor = complete
            ? theme.colorScheme.outline
            : inProgress
                ? const Color(0xFFB47A48)
                : theme.colorScheme.error;
        return InkWell(
          borderRadius: AppSpacing.cardBorderRadius,
          onTap: () => _onChildRowTapped(
            context: context,
            survey: survey,
            row: row,
          ),
          child: Container(
            padding: AppSpacing.cardPadding,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: AppSpacing.cardBorderRadius,
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
                width: 0.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Child #${rows.length - i}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (complete)
                      const Icon(
                        Icons.check_circle,
                        size: 14,
                        color: Color(0xFF3A9C7B),
                      )
                    else if (inProgress)
                      const Icon(
                        Icons.play_circle_outline,
                        size: 14,
                        color: Color(0xFFB47A48),
                      ),
                    const Spacer(),
                    Text(
                      dateFmt.format(row.session.startedAt.toLocal()),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    tapHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tapHintColor,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              for (final q in survey.questions) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          q.prompt,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: q.isPractice
                                ? theme.colorScheme.outline
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 2,
                        child: _AnswerCell(
                          question: q,
                          response: row.responsesByQuestionId[q.id],
                          theme: theme,
                        ),
                      ),
                    ],
                  ),
                ),
                if (q != survey.questions.last)
                  Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.5),
                  ),
              ],
              ],
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
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.poll_outlined,
              size: 56,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No responses yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tap “Start kiosk” at the top right to start recording responses.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
