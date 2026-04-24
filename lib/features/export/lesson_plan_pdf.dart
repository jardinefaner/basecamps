// Many of the PDF builders below chain a long sequence of widget
// writes / buffer appends. Cascading every call hurts readability for
// this shape, so we keep plain statement form.
// ignore_for_file: cascade_invocations

import 'dart:typed_data';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Pure-function PDF builders for the three teacher export surfaces:
/// a single day's schedule, a Monday-to-Friday week overview, and a
/// lesson sequence handout. Every builder takes already-materialized
/// data — no providers, no DB — so they're trivially testable and can
/// be reused from any future non-Flutter surface (server render, etc).
///
/// Layout intentionally prioritizes paper readability over looking
/// like the app. Letter paper, portrait for day/sequence, portrait
/// vertical-stack for the week (see [buildWeekPdf] for why).

// ---------------- Day ----------------

/// Builds a single-day schedule PDF.
///
/// [items] is the already-resolved list from the repository (whole-
/// day items + timed items in the same list — the builder sorts and
/// splits them internally). [groupNamesById] / [adultNamesById] /
/// [roomNamesById] let the builder resolve ids to display names
/// without re-hitting the DB. Unknown ids are shown as "—".
Future<Uint8List> buildDayPdf({
  required DateTime date,
  required List<ScheduleItem> items,
  required Map<String, String> groupNamesById,
  required Map<String, String> adultNamesById,
  required Map<String, String> roomNamesById,
  required String programName,
}) async {
  final doc = pw.Document(
    title: 'Schedule · ${_isoDate(date)}',
    author: programName,
  );

  // Whole-day items render first; timed items sort by start minute.
  final wholeDay = items.where((i) => i.isFullDay).toList();
  final timed = items.where((i) => !i.isFullDay).toList()
    ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
  final ordered = [...wholeDay, ...timed];

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.fromLTRB(48, 48, 48, 48),
      header: (ctx) => _dayHeader(
        programName: programName,
        date: date,
        firstPage: ctx.pageNumber == 1,
      ),
      footer: _footerBuilder(programName),
      build: (context) {
        if (ordered.isEmpty) {
          return [
            pw.SizedBox(height: 160),
            pw.Center(
              child: pw.Text(
                'Nothing scheduled',
                style: pw.TextStyle(
                  fontSize: 14,
                  color: PdfColors.grey600,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            ),
          ];
        }
        return [
          _scheduleTable(
            items: ordered,
            groupNamesById: groupNamesById,
            adultNamesById: adultNamesById,
            roomNamesById: roomNamesById,
          ),
        ];
      },
    ),
  );

  return doc.save();
}

pw.Widget _dayHeader({
  required String programName,
  required DateTime date,
  required bool firstPage,
}) {
  if (!firstPage) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Text(
        '$programName · ${_longDate(date)}',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      ),
    );
  }
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        programName,
        style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        _longDate(date),
        style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 8),
      pw.Divider(color: PdfColors.grey400, thickness: 0.6),
      pw.SizedBox(height: 6),
    ],
  );
}

pw.Widget _scheduleTable({
  required List<ScheduleItem> items,
  required Map<String, String> groupNamesById,
  required Map<String, String> adultNamesById,
  required Map<String, String> roomNamesById,
}) {
  final headerStyle = pw.TextStyle(
    fontSize: 9,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.grey800,
    letterSpacing: 0.6,
  );
  const cellStyle = pw.TextStyle(fontSize: 10);
  const mutedStyle = pw.TextStyle(fontSize: 9, color: PdfColors.grey600);

  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: [
        _tableCell('TIME', style: headerStyle),
        _tableCell('ACTIVITY', style: headerStyle),
        _tableCell('GROUPS', style: headerStyle),
        _tableCell('ADULT', style: headerStyle),
        _tableCell('ROOM', style: headerStyle),
        _tableCell('NOTES', style: headerStyle),
      ],
    ),
  ];

  for (final item in items) {
    rows.add(
      pw.TableRow(
        children: [
          _tableCell(_timeRange(item), style: cellStyle),
          _activityCell(item, cellStyle: cellStyle, mutedStyle: mutedStyle),
          _tableCell(
            _groupsLabel(item, groupNamesById),
            style: cellStyle,
          ),
          _tableCell(
            _adultLabel(item, adultNamesById),
            style: cellStyle,
          ),
          _tableCell(
            _roomLabel(item, roomNamesById),
            style: cellStyle,
          ),
          _tableCell(
            _truncate(item.notes, 140),
            style: cellStyle,
          ),
        ],
      ),
    );
  }

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
    columnWidths: const {
      0: pw.FlexColumnWidth(1.2),
      1: pw.FlexColumnWidth(2.4),
      2: pw.FlexColumnWidth(1.6),
      3: pw.FlexColumnWidth(1.2),
      4: pw.FlexColumnWidth(1.1),
      5: pw.FlexColumnWidth(2),
    },
    children: rows,
  );
}

pw.Widget _tableCell(String text, {required pw.TextStyle style}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    child: pw.Text(text, style: style),
  );
}

pw.Widget _activityCell(
  ScheduleItem item, {
  required pw.TextStyle cellStyle,
  required pw.TextStyle mutedStyle,
}) {
  final url = item.sourceUrl;
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(item.title, style: cellStyle),
        if (url != null && url.trim().isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(url.trim(), style: mutedStyle),
        ],
      ],
    ),
  );
}

// ---------------- Week ----------------

/// Builds a Monday-to-Friday week PDF.
///
/// Chosen layout: **portrait, vertical day-blocks** stacked top-to-
/// bottom. A landscape 5-column grid renders fine on screen but cramps
/// each day's contents into ~1.5in of horizontal space on letter
/// paper, which chops titles and hides locations. A vertical stack
/// gives each day a full-width strip and reliably fits a week on one
/// or two pages of letter paper.
///
/// Per-day rows carry Time + Activity + Groups — adult / room / notes
/// are omitted intentionally (the single-day export covers those when
/// a teacher needs the fine grain).
Future<Uint8List> buildWeekPdf({
  required DateTime mondayOfWeek,
  required Map<int, List<ScheduleItem>> itemsByWeekday,
  required Map<String, String> groupNamesById,
  required Map<String, String> adultNamesById,
  required Map<String, String> roomNamesById,
  required String programName,
}) async {
  final doc = pw.Document(
    title: 'Week of ${_isoDate(mondayOfWeek)}',
    author: programName,
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.fromLTRB(48, 48, 48, 48),
      header: (ctx) => _weekHeader(
        programName: programName,
        monday: mondayOfWeek,
        firstPage: ctx.pageNumber == 1,
      ),
      footer: _footerBuilder(programName),
      build: (context) {
        final children = <pw.Widget>[];
        for (var offset = 0; offset < 5; offset++) {
          final date = mondayOfWeek.add(Duration(days: offset));
          final items = itemsByWeekday[offset + 1] ?? const <ScheduleItem>[];
          children.add(
            _weekDayBlock(
              date: date,
              items: items,
              groupNamesById: groupNamesById,
            ),
          );
          if (offset != 4) {
            children.add(pw.SizedBox(height: 10));
          }
        }
        return children;
      },
    ),
  );

  return doc.save();
}

pw.Widget _weekHeader({
  required String programName,
  required DateTime monday,
  required bool firstPage,
}) {
  if (!firstPage) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Text(
        '$programName · Week of ${_longDate(monday)}',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      ),
    );
  }
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        programName,
        style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        'Week of ${_longDate(monday)}',
        style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 8),
      pw.Divider(color: PdfColors.grey400, thickness: 0.6),
      pw.SizedBox(height: 6),
    ],
  );
}

pw.Widget _weekDayBlock({
  required DateTime date,
  required List<ScheduleItem> items,
  required Map<String, String> groupNamesById,
}) {
  // Full-day first, then timed in start order.
  final wholeDay = items.where((i) => i.isFullDay).toList();
  final timed = items.where((i) => !i.isFullDay).toList()
    ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
  final ordered = [...wholeDay, ...timed];

  final headerStyle = pw.TextStyle(
    fontSize: 9,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.grey800,
    letterSpacing: 0.6,
  );
  const cellStyle = pw.TextStyle(fontSize: 10);

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        child: pw.Text(
          '${_weekdayName(date).toUpperCase()} · ${_shortDate(date)}',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.6,
          ),
        ),
      ),
      pw.SizedBox(height: 4),
      if (ordered.isEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          child: pw.Text(
            'Nothing scheduled',
            style: pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey600,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        )
      else
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.1),
            1: pw.FlexColumnWidth(2.6),
            2: pw.FlexColumnWidth(1.8),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              children: [
                _tableCell('TIME', style: headerStyle),
                _tableCell('ACTIVITY', style: headerStyle),
                _tableCell('GROUPS', style: headerStyle),
              ],
            ),
            for (final item in ordered)
              pw.TableRow(
                children: [
                  _tableCell(_timeRange(item), style: cellStyle),
                  _tableCell(item.title, style: cellStyle),
                  _tableCell(
                    _groupsLabel(item, groupNamesById),
                    style: cellStyle,
                  ),
                ],
              ),
          ],
        ),
    ],
  );
}

// ---------------- Sequence ----------------

/// Builds a lesson-sequence handout PDF. Items render inline (no
/// forced page break per item) so a short sequence fits on one page
/// — the PDF engine will split longer sequences across pages
/// automatically.
Future<Uint8List> buildSequencePdf({
  required LessonSequence sequence,
  required List<ActivityLibraryData> items,
  required String programName,
}) async {
  final doc = pw.Document(
    title: sequence.name,
    author: programName,
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.fromLTRB(48, 48, 48, 48),
      header: (ctx) => _sequenceHeader(
        programName: programName,
        sequence: sequence,
        firstPage: ctx.pageNumber == 1,
      ),
      footer: _footerBuilder(programName),
      build: (context) {
        if (items.isEmpty) {
          return [
            pw.SizedBox(height: 160),
            pw.Center(
              child: pw.Text(
                'No activities in this sequence yet',
                style: pw.TextStyle(
                  fontSize: 14,
                  color: PdfColors.grey600,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            ),
          ];
        }
        final widgets = <pw.Widget>[];
        for (var i = 0; i < items.length; i++) {
          widgets.add(_sequenceItemBlock(position: i + 1, item: items[i]));
          if (i != items.length - 1) {
            widgets.add(pw.SizedBox(height: 16));
          }
        }
        return widgets;
      },
    ),
  );

  return doc.save();
}

pw.Widget _sequenceHeader({
  required String programName,
  required LessonSequence sequence,
  required bool firstPage,
}) {
  if (!firstPage) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Text(
        '$programName · ${sequence.name}',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      ),
    );
  }
  final description = sequence.description?.trim();
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        programName,
        style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        sequence.name,
        style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
      ),
      if (description != null && description.isNotEmpty) ...[
        pw.SizedBox(height: 4),
        pw.Text(
          description,
          style: pw.TextStyle(
            fontSize: 11,
            fontStyle: pw.FontStyle.italic,
            color: PdfColors.grey700,
          ),
        ),
      ],
      pw.SizedBox(height: 8),
      pw.Divider(color: PdfColors.grey400, thickness: 0.6),
      pw.SizedBox(height: 6),
    ],
  );
}

pw.Widget _sequenceItemBlock({
  required int position,
  required ActivityLibraryData item,
}) {
  final age = _ageRangeLabel(item);
  final keyPoints = _splitLines(item.keyPoints);
  final goals = _splitLines(item.learningGoals);
  final materials = (item.materials ?? '').trim();
  final summary = (item.summary ?? '').trim();
  final source = (item.sourceUrl ?? '').trim();
  final attribution = (item.sourceAttribution ?? '').trim();

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        '$position. ${item.title}',
        style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
      ),
      if (age != null) ...[
        pw.SizedBox(height: 2),
        pw.Text(
          age,
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      ],
      if (summary.isNotEmpty) ...[
        pw.SizedBox(height: 6),
        pw.Text(
          summary,
          style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
        ),
      ],
      if (keyPoints.isNotEmpty) ...[
        pw.SizedBox(height: 6),
        _subHeading('Key points'),
        _bulletList(keyPoints),
      ],
      if (goals.isNotEmpty) ...[
        pw.SizedBox(height: 6),
        _subHeading('Learning goals'),
        _bulletList(goals),
      ],
      if (materials.isNotEmpty) ...[
        pw.SizedBox(height: 6),
        _subHeading('Materials'),
        pw.Text(
          materials,
          style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
        ),
      ],
      if (source.isNotEmpty || attribution.isNotEmpty) ...[
        pw.SizedBox(height: 8),
        pw.Text(
          _joinNonEmpty(' · ', [source, attribution]),
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
      ],
    ],
  );
}

pw.Widget _subHeading(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.Text(
      text.toUpperCase(),
      style: pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.grey800,
        letterSpacing: 0.6,
      ),
    ),
  );
}

pw.Widget _bulletList(List<String> lines) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (final line in lines)
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 6, bottom: 1),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '• ',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.Expanded(
                child: pw.Text(
                  line,
                  style: const pw.TextStyle(fontSize: 10, lineSpacing: 2),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

// ---------------- Shared ----------------

pw.Widget Function(pw.Context) _footerBuilder(String programName) {
  return (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 12),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generated by $programName · ${_longDateTime(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
            pw.Text(
              'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
      );
}

String _timeRange(ScheduleItem item) {
  if (item.isFullDay) return 'All day';
  return '${_displayTime(item.startTime)}–${_displayTime(item.endTime)}';
}

String _displayTime(String hhmm) {
  final parts = hhmm.split(':');
  final hour = int.parse(parts[0]);
  final minute = int.parse(parts[1]);
  final period = hour >= 12 ? 'pm' : 'am';
  final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
  final minuteStr = minute.toString().padLeft(2, '0');
  if (minute == 0) return '$displayHour$period';
  return '$displayHour:$minuteStr$period';
}

String _groupsLabel(ScheduleItem item, Map<String, String> groupNamesById) {
  if (item.groupIds.isNotEmpty) {
    final names = item.groupIds
        .map((id) => groupNamesById[id])
        .whereType<String>()
        .toList();
    if (names.isEmpty) return '—';
    return names.join(', ');
  }
  if (item.isAllGroups) return 'All groups';
  return '—';
}

String _adultLabel(ScheduleItem item, Map<String, String> adultNamesById) {
  final id = item.adultId;
  if (id == null) return '—';
  final name = adultNamesById[id];
  if (name == null || name.isEmpty) return '—';
  return name;
}

String _roomLabel(ScheduleItem item, Map<String, String> roomNamesById) {
  final id = item.roomId;
  if (id != null) {
    final name = roomNamesById[id];
    if (name != null && name.isNotEmpty) return name;
  }
  final loc = item.location;
  if (loc != null && loc.trim().isNotEmpty) return loc.trim();
  return '—';
}

String _truncate(String? raw, int limit) {
  final trimmed = (raw ?? '').trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.length <= limit) return trimmed;
  return '${trimmed.substring(0, limit - 1)}…';
}

List<String> _splitLines(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return const [];
  return s
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

String? _ageRangeLabel(ActivityLibraryData item) {
  final min = item.audienceMinAge;
  final max = item.audienceMaxAge;
  if (min == null && max == null) return null;
  if (min != null && max != null) {
    if (min == max) return 'Age $min';
    return 'Ages $min–$max';
  }
  if (min != null) return 'Ages $min+';
  return 'Up to age $max';
}

String _joinNonEmpty(String sep, List<String> parts) {
  return parts.where((p) => p.isNotEmpty).join(sep);
}

// -------- date formatting --------

String _longDate(DateTime d) {
  return '${_weekdayName(d)}, ${_monthName(d.month)} ${d.day}, ${d.year}';
}

String _shortDate(DateTime d) {
  return '${_monthName(d.month).substring(0, 3)} ${d.day}';
}

String _isoDate(DateTime d) {
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd';
}

String _longDateTime(DateTime d) {
  final hour12 = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
  final period = d.hour < 12 ? 'am' : 'pm';
  final minutes = d.minute.toString().padLeft(2, '0');
  return '${_shortDate(d)}, ${d.year} · $hour12:$minutes$period';
}

String _weekdayName(DateTime d) {
  const names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return names[d.weekday - 1];
}

String _monthName(int m) {
  const names = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return names[m - 1];
}
