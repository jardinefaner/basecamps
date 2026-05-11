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

import 'package:basecamp/core/share_origin.dart';
import 'package:basecamp/core/web_file_download.dart';
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

/// Two view modes for the wide-screen results display:
///   * `rich`  — the original grid with mood chips, multi-select
///               icons, action hints. Easier to scan a single
///               kid's session at a glance.
///   * `sheet` — dense spreadsheet view. All metadata columns up
///               front (Site / Classroom / Grade / School / etc.),
///               tight rows, monospace numbers. Looks like Excel
///               and exports to Excel by copy-paste cleanly.
/// Narrow screens always use the card list (sheet is unusable
/// at phone widths regardless of mode).
enum _ResultsViewMode { rich, sheet }

class SurveyResultsScreen extends ConsumerStatefulWidget {
  const SurveyResultsScreen({required this.surveyId, super.key});

  final String surveyId;

  /// Mobile fallback breakpoint. Below this width we render one
  /// card per child stacked vertically (the grid is too cramped).
  static const double _gridMinWidth = 700;

  @override
  ConsumerState<SurveyResultsScreen> createState() =>
      _SurveyResultsScreenState();
}

class _SurveyResultsScreenState extends ConsumerState<SurveyResultsScreen> {
  _ResultsViewMode _mode = _ResultsViewMode.rich;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surveyAsync = ref.watch(surveyByIdProvider(widget.surveyId));
    final resultsAsync = ref.watch(surveyResultsProvider(widget.surveyId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        actions: [
          // View-mode toggle (only meaningful on wide screens — on
          // phones the card list always wins, so the segmented
          // control just sits inert there).
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 6,
            ),
            child: SegmentedButton<_ResultsViewMode>(
              segments: const [
                ButtonSegment(
                  value: _ResultsViewMode.rich,
                  icon: Icon(Icons.view_agenda_outlined),
                  tooltip: 'Cards',
                ),
                ButtonSegment(
                  value: _ResultsViewMode.sheet,
                  icon: Icon(Icons.table_chart_outlined),
                  tooltip: 'Sheet',
                ),
              ],
              selected: {_mode},
              showSelectedIcon: false,
              onSelectionChanged: (s) =>
                  setState(() => _mode = s.first),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
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
                            if (constraints.maxWidth <
                                SurveyResultsScreen._gridMinWidth) {
                              return _CardList(
                                survey: survey,
                                rows: rows,
                                theme: theme,
                              );
                            }
                            return switch (_mode) {
                              _ResultsViewMode.rich => _ResultsGrid(
                                  survey: survey,
                                  rows: rows,
                                  theme: theme,
                                ),
                              _ResultsViewMode.sheet => _SheetView(
                                  survey: survey,
                                  rows: rows,
                                  theme: theme,
                                ),
                            };
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

/// Confirm + soft-delete a single session. The parent survey + its
/// other sessions stay; the results sheet filters this one out on
/// next refresh. Used by long-press on a session row in both the
/// grid and the mobile card list.
Future<void> _confirmDeleteSession({
  required BuildContext context,
  required SurveyResultRow row,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete this session?'),
      content: const Text(
        'The kid\'s answers will be removed from the results. '
        'The survey itself and every other session stay put.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await container
      .read(surveyRepositoryProvider)
      .softDeleteSession(row.session.id);
  messenger.showSnackBar(
    const SnackBar(content: Text('Session deleted')),
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
      // Web: trigger a real file download. We used to
      // `Clipboard.setData` here, but Safari rejects clipboard
      // writes that don't fire synchronously inside a user-
      // gesture handler — and the export has multiple awaits
      // (stream pull, CSV build) before we can write. The
      // download is a passive operation that doesn't need
      // user-activation, so it works after any async gap.
      // The user gets a real .csv that opens in Sheets / Excel.
      try {
        downloadTextFile(
          filename: filename,
          mimeType: 'text/csv;charset=utf-8',
          content: csv,
        );
        messenger.showSnackBar(
          SnackBar(content: Text('Downloaded $filename.')),
        );
      } on Object catch (e, st) {
        debugPrint('[csv] web download failed, falling back '
            'to clipboard: $e\n$st');
        // Last-ditch fallback: try clipboard. Safari will likely
        // throw again, but Chrome/Firefox might succeed.
        await Clipboard.setData(ClipboardData(text: csv));
        messenger.showSnackBar(
          SnackBar(
            content: Text('Copied $filename to clipboard '
                '(download blocked). Paste into Sheets.'),
          ),
        );
      }
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
    // iPadOS share sheet is a popover that REQUIRES an anchor
    // rect — without it share_plus throws PlatformException
    // ("copy fail" / "presented popover does not have anchor").
    // Compute from the tap source (the export IconButton in the
    // AppBar) so the popover arrow points at the button.
    final sharePositionOrigin = shareOriginFromContext(context);
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
          sharePositionOrigin: sharePositionOrigin,
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
        onLongPress: () =>
            _confirmDeleteSession(context: context, row: row),
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
                      if ((row.session.school ?? '').isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          row.session.school!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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
        return Center(
          child: _MoodCell(
            question: question,
            response: response!,
            theme: theme,
          ),
        );
      case SurveyQuestionType.multiSelect:
        return _MultiSelectCell(response: response!, theme: theme);
      case SurveyQuestionType.openEnded:
        return _OpenEndedCell(response: response!, theme: theme);
    }
  }
}

class _MoodCell extends StatelessWidget {
  const _MoodCell({
    required this.question,
    required this.response,
    required this.theme,
  });

  final SurveyQuestion question;
  final SurveyResponse response;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final v = response.moodValue ?? -1;
    final scale = question.scale;
    final labels = scale.labels;
    final (label, color) = (v >= 0 && v < labels.length)
        ? (labels[v], _colorForPosition(v, labels.length))
        : ('?', theme.colorScheme.outline);
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

  /// Interpolate negative → positive across the scale. Two-point
  /// scales jump directly from red to green; three- and five-point
  /// scales pass through the warm midrange so "kind of" reads as
  /// hesitant rather than wrong.
  static Color _colorForPosition(int v, int count) {
    if (count <= 1) return const Color(0xFF27500A);
    const cold = Color(0xFFA32D2D);
    const warm = Color(0xFF854F0B);
    const warmer = Color(0xFF27500A);
    final t = v / (count - 1);
    if (t <= 0.5) return Color.lerp(cold, warm, t * 2) ?? warm;
    return Color.lerp(warm, warmer, (t - 0.5) * 2) ?? warmer;
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

class _OpenEndedCell extends ConsumerStatefulWidget {
  const _OpenEndedCell({required this.response, required this.theme});

  final SurveyResponse response;
  final ThemeData theme;

  @override
  ConsumerState<_OpenEndedCell> createState() => _OpenEndedCellState();
}

class _OpenEndedCellState extends ConsumerState<_OpenEndedCell> {
  @override
  Widget build(BuildContext context) {
    final response = widget.response;
    final theme = widget.theme;
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
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => _editTranscript(transcript),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  transcript ??
                      (hasAudio
                          ? '[audio recorded — transcription pending]'
                          : '— tap to add'),
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
            ),
          ),
          IconButton(
            onPressed: () => _editTranscript(transcript),
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: transcript == null ? 'Add transcript' : 'Edit transcript',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Future<void> _editTranscript(String? current) async {
    final controller = TextEditingController(text: current ?? '');
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(current == null ? 'Add transcript' : 'Edit transcript'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'What the kid said',
              hintText: 'Type or correct the transcription…',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (result == null) return;
      if (result == (current ?? '')) return;
      if (!mounted) return;
      await ref.read(surveyRepositoryProvider).updateTranscription(
            responseId: widget.response.id,
            surveyId: widget.response.surveyId,
            text: result,
          );
    } finally {
      controller.dispose();
    }
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
          onLongPress: () =>
              _confirmDeleteSession(context: context, row: row),
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

// ═════════════════════════════════════════════════════════════════
// Sheet view — dense spreadsheet rendering
// ═════════════════════════════════════════════════════════════════

/// Excel-like view of the same data the rich grid shows. Rules:
///   * Metadata columns up front: Site · Classroom · Grade ·
///     School · Child # · Started · Status. Match the CSV
///     exporter so a screenshot of the sheet view ≈ the CSV.
///   * Question columns mirror the CSV — one column per mood
///     question, one Yes/No column per multi-select option, one
///     transcript column per open-ended.
///   * Tight rows (32dp). Light cell borders. Tabular figures
///     for numbers. Header row sticks to the top.
///   * Tap a row to fall through to the same handler the rich
///     grid uses (resume incomplete; jar print on complete).
class _SheetView extends StatelessWidget {
  const _SheetView({
    required this.survey,
    required this.rows,
    required this.theme,
  });

  final SurveyConfig survey;
  final List<SurveyResultRow> rows;
  final ThemeData theme;

  static const double _rowHeight = 32;
  static const double _headerHeight = 36;
  static const double _metaWidth = 130;
  static const double _moodWidth = 110;
  static const double _ynWidth = 70;
  static const double _openWidth = 240;

  List<_SheetCol> _columns() {
    final cols = <_SheetCol>[
      const _SheetCol(label: 'Site', width: _metaWidth, type: _ColType.text),
      const _SheetCol(label: 'Classroom', width: _metaWidth, type: _ColType.text),
      const _SheetCol(label: 'Grade', width: 80, type: _ColType.text),
      const _SheetCol(label: 'School', width: 110, type: _ColType.text),
      const _SheetCol(label: 'Child #', width: 60, type: _ColType.numericLike),
      const _SheetCol(label: 'Started', width: 130, type: _ColType.text),
      const _SheetCol(label: 'Status', width: 100, type: _ColType.text),
    ];
    for (final q in survey.questions) {
      switch (q.type) {
        case SurveyQuestionType.mood:
          cols.add(_SheetCol(
            label: q.prompt,
            width: _moodWidth,
            type: _ColType.text,
          ));
        case SurveyQuestionType.multiSelect:
          for (final opt in q.options) {
            cols.add(_SheetCol(
              label: opt.label,
              width: _ynWidth,
              type: _ColType.text,
            ));
          }
        case SurveyQuestionType.openEnded:
          cols.add(_SheetCol(
            label: q.prompt,
            width: _openWidth,
            type: _ColType.text,
          ));
      }
    }
    return cols;
  }

  String _statusFor(SurveySession s) {
    if (s.endedAt == null) return 'In progress';
    return s.childCount >= 1 ? 'Completed' : 'Incomplete';
  }

  /// Decode a multi-select response's selectionsJson into a Set
  /// of option ids. Mirrors the CSV exporter's helper — kept local
  /// to avoid pulling the exporter as a dep.
  Set<String> _decodeSelections(String? raw) {
    if (raw == null || raw.isEmpty) return const <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toSet();
      }
    } on FormatException {
      // tolerate corrupt JSON
    }
    return const <String>{};
  }

  /// Build the row of cell strings for one session, in the same
  /// order as `_columns()`.
  List<String> _cellsFor(SurveyResultRow row, int childNumber) {
    final session = row.session;
    final dateFmt = DateFormat.Md().add_jm();
    final cells = <String>[
      survey.siteName,
      survey.classroom,
      survey.ageBand.label,
      session.school ?? '',
      '$childNumber',
      dateFmt.format(session.startedAt.toLocal()),
      _statusFor(session),
    ];
    for (final q in survey.questions) {
      final response = row.responsesByQuestionId[q.id];
      switch (q.type) {
        case SurveyQuestionType.mood:
          if (response == null) {
            cells.add('');
          } else {
            final v = response.moodValue;
            final labels = q.scale.labels;
            cells.add(
              v == null || v < 0 || v >= labels.length ? '' : labels[v],
            );
          }
        case SurveyQuestionType.multiSelect:
          final selected = _decodeSelections(response?.selectionsJson);
          for (final opt in q.options) {
            if (response == null) {
              cells.add('');
            } else {
              cells.add(selected.contains(opt.id) ? 'Yes' : 'No');
            }
          }
        case SurveyQuestionType.openEnded:
          cells.add(response?.transcription ?? '');
      }
    }
    return cells;
  }

  @override
  Widget build(BuildContext context) {
    final cols = _columns();
    final totalWidth = cols.fold<double>(0, (s, c) => s + c.width);
    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: totalWidth,
          child: Column(
            children: [
              _SheetHeader(cols: cols, theme: theme, height: _headerHeight),
              Expanded(
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    final childNumber = rows.length - i;
                    return _SheetRow(
                      cols: cols,
                      cells: _cellsFor(row, childNumber),
                      height: _rowHeight,
                      theme: theme,
                      onTap: () => _onChildRowTapped(
                        context: context,
                        survey: survey,
                        row: row,
                      ),
                      onLongPress: () => _confirmDeleteSession(
                        context: context,
                        row: row,
                      ),
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

class _SheetCol {
  const _SheetCol({
    required this.label,
    required this.width,
    required this.type,
  });
  final String label;
  final double width;
  final _ColType type;
}

enum _ColType { text, numericLike }

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.cols,
    required this.theme,
    required this.height,
  });

  final List<_SheetCol> cols;
  final ThemeData theme;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          for (final col in cols)
            Container(
              width: col.width,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.4),
                  ),
                ),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                col.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.cols,
    required this.cells,
    required this.height,
    required this.theme,
    required this.onTap,
    this.onLongPress,
  });

  final List<_SheetCol> cols;
  final List<String> cells;
  final double height;
  final ThemeData theme;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Row(
            children: [
              for (var i = 0; i < cols.length; i++)
                _SheetCell(
                  col: cols[i],
                  text: i < cells.length ? cells[i] : '',
                  theme: theme,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetCell extends StatelessWidget {
  const _SheetCell({
    required this.col,
    required this.text,
    required this.theme,
  });

  final _SheetCol col;
  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final tabular = col.type == _ColType.numericLike;
    return Container(
      width: col.width,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface,
          fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
        ),
      ),
    );
  }
}
