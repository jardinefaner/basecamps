// The RTF builder below writes many sequential lines into a single
// StringBuffer — cascading on every call hurts readability for a
// sequence this long, so we keep plain statement form instead.
// ignore_for_file: cascade_invocations

import 'dart:convert';
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

  // Signature box sizing: a real drawn sig is usually short and wide
  // (letter-like), so cap the rendering box at 240 × 70pt — roughly
  // a 3:1 aspect ratio that holds handwriting without dwarfing the
  // rest of the signatures card. The missing-signature placeholder
  // uses the same box so the layout doesn't jump between signed and
  // unsigned notes.
  const boxWidth = 240.0;
  const boxHeight = 70.0;

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
          width: boxWidth,
          height: boxHeight,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
          ),
          alignment: pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.all(6),
          child: pw.Image(image),
        )
      else
        pw.Container(
          width: boxWidth,
          height: boxHeight,
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
// RTF export
// ============================================================

/// A formatted Rich Text document of the note. Opens in Word,
/// Pages, Google Docs, TextEdit, and every major mobile mail
/// viewer — the recipient gets a proper "document" instead of raw
/// markdown, and drawn signatures embed inline as real images.
///
/// RTF was picked over .docx because it's a single text file (no
/// zip packaging, no multi-part XML relationships), and over HTML
/// because most people think of `.rtf` as a document while `.html`
/// reads as a web page.
Future<Uint8List> buildParentConcernRtf(ParentConcernNote note) async {
  final staffSigBytes = await _readSignatureBytes(note.staffSignaturePath);
  final supervisorSigBytes =
      await _readSignatureBytes(note.supervisorSignaturePath);

  final b = StringBuffer();

  // RTF preamble — font table, UTF-8 declaration, default font size.
  b.write(r'{\rtf1\ansi\ansicpg1252\deff0\nouicompat\deflang1033');
  b.write(r'{\fonttbl{\f0\fnil\fcharset0 Helvetica;}}');
  b.write(r'{\colortbl ;\red64\green64\blue64;\red130\green130\blue130;}');
  b.writeln();

  // Title
  b.write(r'\pard\sa120\fs36\b ');
  b.write(_rtfText('Parent Concern Note'));
  b.write(r'\b0\par');
  b.writeln();
  b.write(r'\pard\sa240\fs18\cf2 ');
  b.write(_rtfText('Generated ${_formatDateTime(DateTime.now())} · Basecamp'));
  b.write(r'\cf0\par');
  b.writeln();

  _rtfHeading(b, 'About this concern');
  _rtfKv(b, 'Child / children', note.childNames);
  _rtfKv(b, 'Parent or guardian', note.parentName);
  _rtfKv(
    b,
    'Date of concern',
    note.concernDate == null ? '' : _formatDate(note.concernDate!),
  );
  _rtfKv(b, 'Staff receiving', note.staffReceiving);
  _rtfKv(b, 'Supervisor notified', note.supervisorNotified);
  _rtfSpacer(b);

  _rtfHeading(b, 'Method of communication');
  _rtfCheck(b, 'In person', note.methodInPerson);
  _rtfCheck(b, 'Phone', note.methodPhone);
  _rtfCheck(b, 'Email', note.methodEmail);
  if ((note.methodOther ?? '').trim().isNotEmpty) {
    _rtfCheck(b, 'Other — ${note.methodOther}', true);
  }
  _rtfSpacer(b);

  _rtfHeading(b, 'Concern reported');
  _rtfNarrative(b, note.concernDescription);

  _rtfHeading(b, 'Immediate response / actions taken');
  _rtfNarrative(b, note.immediateResponse);

  _rtfHeading(b, 'Follow-up plan');
  _rtfCheck(b, 'Monitor situation', note.followUpMonitor);
  _rtfCheck(b, 'Staff check-ins with child', note.followUpStaffCheckIns);
  _rtfCheck(b, 'Supervisor review', note.followUpSupervisorReview);
  _rtfCheck(
    b,
    'Parent follow-up conversation',
    note.followUpParentConversation,
  );
  if ((note.followUpOther ?? '').trim().isNotEmpty) {
    _rtfCheck(b, 'Other — ${note.followUpOther}', true);
  }
  if (note.followUpDate != null) {
    _rtfKv(b, 'Follow-up date', _formatDateTime(note.followUpDate!));
  }
  _rtfSpacer(b);

  if ((note.additionalNotes ?? '').trim().isNotEmpty) {
    _rtfHeading(b, 'Additional notes');
    _rtfNarrative(b, note.additionalNotes!);
  }

  _rtfHeading(b, 'Signatures');
  _rtfSignature(
    b,
    role: 'Staff',
    printedName: note.staffSignature,
    signedAt: note.staffSignatureDate,
    signatureBytes: staffSigBytes,
  );
  _rtfSignature(
    b,
    role: 'Supervisor',
    printedName: note.supervisorSignature,
    signedAt: note.supervisorSignatureDate,
    signatureBytes: supervisorSigBytes,
  );

  b.write('}');
  return Uint8List.fromList(latin1.encode(b.toString()));
}

Future<Uint8List?> _readSignatureBytes(String? path) async {
  if (path == null) return null;
  final file = File(path);
  if (!file.existsSync()) return null;
  return file.readAsBytes();
}

void _rtfHeading(StringBuffer b, String title) {
  b.write(r'\pard\sa100\sb180\fs24\b ');
  b.write(_rtfText(title));
  b.write(r'\b0\fs20\par');
  b.writeln();
}

void _rtfKv(StringBuffer b, String key, String? value) {
  final v = (value ?? '').trim();
  b.write(r'\pard\sa40\fs20\b ');
  b.write(_rtfText('$key: '));
  b.write(r'\b0 ');
  b.write(_rtfText(v.isEmpty ? '—' : v));
  b.write(r'\par');
  b.writeln();
}

void _rtfCheck(StringBuffer b, String label, bool checked) {
  // Unicode checkboxes: ☑ (U+2611) / ☐ (U+2610). RTF uses \u<signed-int>?
  // where the trailing `?` is the fallback for readers that can't render
  // it.
  b.write(r'\pard\sa40\fs20 ');
  b.write(checked ? r'\u9745? ' : r'\u9744? ');
  b.write(_rtfText(label));
  b.write(r'\par');
  b.writeln();
}

void _rtfNarrative(StringBuffer b, String body) {
  final trimmed = body.trim();
  b.write(r'\pard\sa100\fs20 ');
  if (trimmed.isEmpty) {
    b.write(r'\cf2\i ');
    b.write(_rtfText('Nothing recorded.'));
    b.write(r'\i0\cf0');
  } else {
    // Respect paragraph breaks in the source text.
    final paragraphs = trimmed.split(RegExp(r'\n\s*\n'));
    for (var i = 0; i < paragraphs.length; i++) {
      b.write(_rtfText(paragraphs[i].replaceAll('\n', ' ').trim()));
      if (i != paragraphs.length - 1) {
        b.write(r'\par\pard\sa100\fs20 ');
      }
    }
  }
  b.write(r'\par');
  b.writeln();
}

void _rtfSpacer(StringBuffer b) {
  b.write(r'\pard\sa60\fs10\par');
  b.writeln();
}

void _rtfSignature(
  StringBuffer b, {
  required String role,
  required String? printedName,
  required DateTime? signedAt,
  required Uint8List? signatureBytes,
}) {
  // Role header
  b.write(r'\pard\sa40\fs20\b ');
  b.write(_rtfText('$role signature'));
  b.write(r'\b0\par');
  b.writeln();

  // Signature image (if drawn)
  if (signatureBytes != null) {
    // RTF pict dimensions are in twips (1440 per inch, 20 per point).
    // Box the image at ~240 × 70 points so it sits proportionally in
    // the document rather than spreading across the whole page.
    const widthTwips = 240 * 20;
    const heightTwips = 70 * 20;
    b.write(r'\pard ');
    b.write(
      r'{\pict\pngblip\picwgoal' '$widthTwips'
      r'\pichgoal' '$heightTwips ',
    );
    b.write(_hexEncode(signatureBytes));
    b.write('}');
    b.write(r'\par');
    b.writeln();
  } else {
    b.write(r'\pard\cf2\i\fs18 ');
    b.write(_rtfText('(No drawn signature)'));
    b.write(r'\i0\cf0\fs20\par');
    b.writeln();
  }

  // Printed name + timestamp
  final nameText = (printedName == null || printedName.trim().isEmpty)
      ? '(No printed name)'
      : printedName.trim();
  b.write(r'\pard\sa20\fs22\b ');
  b.write(_rtfText(nameText));
  b.write(r'\b0\par');
  b.writeln();

  b.write(r'\pard\sa100\fs18\cf2\i ');
  b.write(
    _rtfText(signedAt == null ? 'Not signed' : 'Signed ${_formatDateTime(signedAt)}'),
  );
  b.write(r'\i0\cf0\fs20\par');
  b.writeln();
}

/// Escape a plain Dart string for inclusion inside an RTF stream.
/// Handles the three structural characters (`\`, `{`, `}`) and
/// emits any non-ASCII as `\u<signed-int>?` so Unicode survives —
/// names with accents, dashes, curly quotes, em dashes, etc.
String _rtfText(String input) {
  final buf = StringBuffer();
  for (final codeUnit in input.runes) {
    if (codeUnit == 0x5C) {
      buf.write(r'\\');
    } else if (codeUnit == 0x7B) {
      buf.write(r'\{');
    } else if (codeUnit == 0x7D) {
      buf.write(r'\}');
    } else if (codeUnit == 0x0A) {
      buf.write(r'\line ');
    } else if (codeUnit < 0x80) {
      buf.writeCharCode(codeUnit);
    } else {
      // RTF \u takes a signed 16-bit integer; fold values above 32767
      // into the negative range so readers outside the BMP still
      // reconstruct the right code point.
      final signed = codeUnit > 32767 ? codeUnit - 65536 : codeUnit;
      buf.write(r'\u');
      buf.write(signed);
      buf.write('?');
    }
  }
  return buf.toString();
}

/// Produce a lowercase hex string suitable for an RTF `\pict` body.
/// Inserts soft linebreaks every 128 bytes so Office readers don't
/// trip on over-long lines.
String _hexEncode(List<int> bytes) {
  const chars = '0123456789abcdef';
  final buf = StringBuffer();
  for (var i = 0; i < bytes.length; i++) {
    final byte = bytes[i];
    buf.writeCharCode(chars.codeUnitAt((byte >> 4) & 0xF));
    buf.writeCharCode(chars.codeUnitAt(byte & 0xF));
    if (i.isOdd && (i + 1) % 128 == 0) buf.write('\n');
  }
  return buf.toString();
}
