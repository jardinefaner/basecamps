// The markdown builder below writes many sequential lines into a
// single StringBuffer — cascading on every call hurts readability for
// a sequence this long, so we keep plain statement form instead.
// ignore_for_file: cascade_invocations

import 'dart:io';
import 'dart:typed_data';

import 'package:basecamp/database/database.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Build a self-contained PDF of a [ParentConcernNote], suitable for
/// emailing, printing, or stashing as a record. Typed fields render as
/// plain text; signature PNGs embed inline at their captured aspect so
/// the recipient gets a complete paper-form equivalent without needing
/// access to the app.
Future<Uint8List> buildParentConcernPdf(ParentConcernNote note) async {
  final doc = pw.Document(
    title: 'Parent Concern Note',
    author: 'Basecamp',
  );

  final regular = await PdfGoogleFonts.interRegular();
  final bold = await PdfGoogleFonts.interSemiBold();
  final italic = await PdfGoogleFonts.interLight();

  final staffSig = await _loadSignature(note.staffSignaturePath);
  final supervisorSig = await _loadSignature(note.supervisorSignaturePath);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.fromLTRB(48, 48, 48, 48),
      theme: pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        italic: italic,
      ),
      header: (ctx) => ctx.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 12),
              child: pw.Text(
                'Parent Concern Note · p${ctx.pageNumber}',
                style: pw.TextStyle(
                  font: regular,
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
            ),
      build: (context) => [
        _title(note),
        pw.SizedBox(height: 16),
        _aboutSection(note),
        pw.SizedBox(height: 14),
        _methodSection(note),
        pw.SizedBox(height: 14),
        _narrativeSection(
          'Concern Reported',
          note.concernDescription,
          emptyCopy:
              '(No concern narrative recorded.)',
        ),
        pw.SizedBox(height: 14),
        _narrativeSection(
          'Immediate Response / Actions Taken',
          note.immediateResponse,
          emptyCopy: '(No response recorded.)',
        ),
        pw.SizedBox(height: 14),
        _followUpSection(note),
        pw.SizedBox(height: 14),
        if ((note.additionalNotes ?? '').trim().isNotEmpty) ...[
          _narrativeSection(
            'Additional Notes',
            note.additionalNotes!,
            emptyCopy: '',
          ),
          pw.SizedBox(height: 14),
        ],
        _signaturesSection(note, staffSig, supervisorSig),
      ],
    ),
  );

  return doc.save();
}

// ---- sections ----

pw.Widget _title(ParentConcernNote note) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Parent Concern Note',
        style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        'Generated ${_formatDateTime(DateTime.now())} · Basecamp',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 8),
      pw.Divider(color: PdfColors.grey400, thickness: 0.6),
    ],
  );
}

pw.Widget _aboutSection(ParentConcernNote note) {
  return _card(
    'About this concern',
    [
      _kv('Child / children', note.childNames),
      _kv('Parent or guardian', note.parentName),
      _kv(
        'Date of concern',
        note.concernDate == null ? '—' : _formatDate(note.concernDate!),
      ),
      _kv('Staff receiving', note.staffReceiving),
      _kv('Supervisor notified', note.supervisorNotified ?? '—'),
    ],
  );
}

pw.Widget _methodSection(ParentConcernNote note) {
  return _card(
    'Method of Communication',
    [
      _checkbox('In person', note.methodInPerson),
      _checkbox('Phone', note.methodPhone),
      _checkbox('Email', note.methodEmail),
      if ((note.methodOther ?? '').trim().isNotEmpty)
        _checkbox('Other — ${note.methodOther}', true),
    ],
  );
}

pw.Widget _narrativeSection(
  String title,
  String body, {
  required String emptyCopy,
}) {
  final trimmed = body.trim();
  final display = trimmed.isEmpty ? emptyCopy : trimmed;
  return _card(
    title,
    [
      pw.Text(
        display,
        style: pw.TextStyle(
          fontSize: 11,
          lineSpacing: 4,
          color: trimmed.isEmpty ? PdfColors.grey600 : PdfColors.black,
          fontStyle:
              trimmed.isEmpty ? pw.FontStyle.italic : pw.FontStyle.normal,
        ),
      ),
    ],
  );
}

pw.Widget _followUpSection(ParentConcernNote note) {
  return _card(
    'Follow-Up Plan',
    [
      _checkbox('Monitor situation', note.followUpMonitor),
      _checkbox('Staff check-ins with child', note.followUpStaffCheckIns),
      _checkbox('Supervisor review', note.followUpSupervisorReview),
      _checkbox(
        'Parent follow-up conversation',
        note.followUpParentConversation,
      ),
      if ((note.followUpOther ?? '').trim().isNotEmpty)
        _checkbox('Other — ${note.followUpOther}', true),
      pw.SizedBox(height: 6),
      _kv(
        'Follow-up date',
        note.followUpDate == null
            ? '—'
            : _formatDateTime(note.followUpDate!),
      ),
    ],
  );
}

pw.Widget _signaturesSection(
  ParentConcernNote note,
  pw.MemoryImage? staffSig,
  pw.MemoryImage? supervisorSig,
) {
  return _card('Signatures', [
    _signatureBlock(
      role: 'Staff',
      printedName: note.staffSignature,
      signedAt: note.staffSignatureDate,
      image: staffSig,
    ),
    pw.SizedBox(height: 16),
    _signatureBlock(
      role: 'Supervisor',
      printedName: note.supervisorSignature,
      signedAt: note.supervisorSignatureDate,
      image: supervisorSig,
    ),
  ]);
}

pw.Widget _signatureBlock({
  required String role,
  required String? printedName,
  required DateTime? signedAt,
  required pw.MemoryImage? image,
}) {
  final signedText = signedAt == null
      ? 'Not signed'
      : 'Signed ${_formatDateTime(signedAt)}';
  final nameText = (printedName == null || printedName.trim().isEmpty)
      ? '(No printed name)'
      : printedName.trim();

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        '$role Signature',
        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 4),
      if (image != null)
        pw.Container(
          height: 80,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
          ),
          alignment: pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.all(6),
          child: pw.Image(image),
        )
      else
        pw.Container(
          height: 56,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(
              color: PdfColors.grey300,
              width: 0.5,
              style: pw.BorderStyle.dashed,
            ),
          ),
          alignment: pw.Alignment.center,
          child: pw.Text(
            '(No drawn signature)',
            style:
                const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
          ),
        ),
      pw.SizedBox(height: 4),
      pw.Text(
        nameText,
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
      pw.Text(
        signedText,
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      ),
    ],
  );
}

// ---- shared building blocks ----

pw.Widget _card(String title, List<pw.Widget> children) {
  return pw.Container(
    decoration: pw.BoxDecoration(
      color: PdfColors.grey100,
      borderRadius: pw.BorderRadius.circular(6),
    ),
    padding: const pw.EdgeInsets.all(14),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 10,
            letterSpacing: 0.8,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey800,
          ),
        ),
        pw.SizedBox(height: 8),
        ...children,
      ],
    ),
  );
}

pw.Widget _kv(String key, String? value, {String placeholder = '—'}) {
  final display =
      (value == null || value.trim().isEmpty) ? placeholder : value.trim();
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 140,
          child: pw.Text(
            key,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ),
        pw.Expanded(
          child: pw.Text(display, style: const pw.TextStyle(fontSize: 11)),
        ),
      ],
    ),
  );
}

pw.Widget _checkbox(String label, bool checked) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      children: [
        pw.Container(
          width: 10,
          height: 10,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey700, width: 0.8),
            color: checked ? PdfColors.grey800 : PdfColors.white,
          ),
        ),
        pw.SizedBox(width: 6),
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 11,
              color: checked ? PdfColors.black : PdfColors.grey600,
            ),
          ),
        ),
      ],
    ),
  );
}

// ---- helpers ----

Future<pw.MemoryImage?> _loadSignature(String? path) async {
  if (path == null) return null;
  final file = File(path);
  if (!file.existsSync()) return null;
  final bytes = await file.readAsBytes();
  return pw.MemoryImage(bytes);
}

String _formatDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

String _formatDateTime(DateTime d) {
  final hour12 = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
  final period = d.hour < 12 ? 'a' : 'p';
  final minutes = d.minute.toString().padLeft(2, '0');
  return '${_formatDate(d)} · $hour12:$minutes$period';
}

// ============================================================
// Markdown export
// ============================================================

/// A plain-markdown render of the note — lighter than the PDF, ideal
/// for pasting into an email body or a team channel. Signatures
/// appear as `[Signed Apr 17, 2026 · 3:30p]` callouts rather than
/// embedded images, since inline base64 images balloon email size
/// and break in many renderers.
String buildParentConcernMarkdown(ParentConcernNote note) {
  final b = StringBuffer();

  b.writeln('# Parent Concern Note');
  b.writeln();
  b.writeln('_Generated ${_formatDateTime(DateTime.now())} · Basecamp_');
  b.writeln();
  b.writeln('---');
  b.writeln();

  // About
  b.writeln('## About this concern');
  b.writeln();
  _mdKv(b, 'Child / children', note.childNames);
  _mdKv(b, 'Parent or guardian', note.parentName);
  _mdKv(
    b,
    'Date of concern',
    note.concernDate == null ? '' : _formatDate(note.concernDate!),
  );
  _mdKv(b, 'Staff receiving', note.staffReceiving);
  _mdKv(b, 'Supervisor notified', note.supervisorNotified);
  b.writeln();

  // Method
  b.writeln('## Method of communication');
  b.writeln();
  _mdCheck(b, 'In person', note.methodInPerson);
  _mdCheck(b, 'Phone', note.methodPhone);
  _mdCheck(b, 'Email', note.methodEmail);
  if ((note.methodOther ?? '').trim().isNotEmpty) {
    _mdCheck(b, 'Other — ${note.methodOther}', true);
  }
  b.writeln();

  // Narratives
  _mdNarrative(b, 'Concern reported', note.concernDescription);
  _mdNarrative(b, 'Immediate response / actions taken', note.immediateResponse);

  // Follow-up
  b.writeln('## Follow-up plan');
  b.writeln();
  _mdCheck(b, 'Monitor situation', note.followUpMonitor);
  _mdCheck(b, 'Staff check-ins with child', note.followUpStaffCheckIns);
  _mdCheck(b, 'Supervisor review', note.followUpSupervisorReview);
  _mdCheck(
    b,
    'Parent follow-up conversation',
    note.followUpParentConversation,
  );
  if ((note.followUpOther ?? '').trim().isNotEmpty) {
    _mdCheck(b, 'Other — ${note.followUpOther}', true);
  }
  if (note.followUpDate != null) {
    b.writeln();
    b.writeln('**Follow-up date:** ${_formatDateTime(note.followUpDate!)}');
  }
  b.writeln();

  if ((note.additionalNotes ?? '').trim().isNotEmpty) {
    _mdNarrative(b, 'Additional notes', note.additionalNotes!);
  }

  // Signatures
  b.writeln('## Signatures');
  b.writeln();
  _mdSignature(
    b,
    role: 'Staff',
    printedName: note.staffSignature,
    signedAt: note.staffSignatureDate,
    drawn: note.staffSignaturePath != null,
  );
  _mdSignature(
    b,
    role: 'Supervisor',
    printedName: note.supervisorSignature,
    signedAt: note.supervisorSignatureDate,
    drawn: note.supervisorSignaturePath != null,
  );

  return b.toString();
}

void _mdKv(StringBuffer b, String key, String? value) {
  final v = (value ?? '').trim();
  b.writeln('- **$key:** ${v.isEmpty ? '—' : v}');
}

void _mdCheck(StringBuffer b, String label, bool checked) {
  b.writeln('- ${checked ? '[x]' : '[ ]'} $label');
}

void _mdNarrative(StringBuffer b, String title, String body) {
  b.writeln('## $title');
  b.writeln();
  final trimmed = body.trim();
  b.writeln(trimmed.isEmpty ? '_Nothing recorded._' : trimmed);
  b.writeln();
}

void _mdSignature(
  StringBuffer b, {
  required String role,
  required String? printedName,
  required DateTime? signedAt,
  required bool drawn,
}) {
  final name = (printedName == null || printedName.trim().isEmpty)
      ? '_(no printed name)_'
      : '**${printedName.trim()}**';
  final signed = signedAt == null
      ? '_(not signed)_'
      : '_signed ${_formatDateTime(signedAt)}${drawn ? " · drawn signature on file" : ""}_';
  b.writeln('- **$role:** $name — $signed');
}
