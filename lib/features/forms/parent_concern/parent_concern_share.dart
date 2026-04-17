import 'dart:async';
import 'dart:io';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/forms/parent_concern/parent_concern_export.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Bottom-sheet menu of export / share / print actions for a saved
/// Parent Concern Note. Two formats live here:
///
///  - **PDF** for archival copies and printing.
///  - **Document (RTF)** for email, Word / Pages / Google Docs etc.
///    Opens as a proper formatted document on the recipient's side
///    with signatures embedded inline.
Future<void> showParentConcernShareSheet(
  BuildContext context,
  ParentConcernNote note,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Share this concern note',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Share as document'),
            subtitle: const Text(
              'Formatted Rich Text — opens in Word, Pages, Google Docs',
            ),
            onTap: () {
              Navigator.of(ctx).pop();
              unawaited(_shareAsDocument(note));
            },
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Share as PDF'),
            subtitle: const Text(
              'Formatted document with signatures embedded',
            ),
            onTap: () {
              Navigator.of(ctx).pop();
              unawaited(_shareAsPdf(note));
            },
          ),
          if (!kIsWeb)
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('Print'),
              subtitle: const Text(
                'Send to a physical printer or save as PDF',
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                unawaited(_printPdf(note));
              },
            ),
        ],
      ),
    ),
  );
}

Future<void> _shareAsPdf(ParentConcernNote note) async {
  final bytes = await buildParentConcernPdf(note);
  await Printing.sharePdf(
    bytes: bytes,
    filename: _safeFilename(note, 'pdf'),
  );
}

Future<void> _printPdf(ParentConcernNote note) async {
  await Printing.layoutPdf(
    onLayout: (_) async => buildParentConcernPdf(note),
    name: 'Parent Concern Note',
  );
}

/// Writes the note to a temp `.rtf` file and hands it to the share
/// sheet. RTF was chosen over `.docx` because a single text stream
/// is simpler to generate (no zip + multipart XML), and over HTML
/// because recipients see `.rtf` as a document rather than a web
/// page. Drawn signatures embed inline via `\pict\pngblip` — every
/// modern Office / iWork / Google Docs opener renders them.
Future<void> _shareAsDocument(ParentConcernNote note) async {
  final bytes = await buildParentConcernRtf(note);
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, _safeFilename(note, 'rtf')));
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile(file.path, mimeType: 'application/rtf'),
      ],
      subject: 'Parent Concern Note',
    ),
  );
}

String _safeFilename(ParentConcernNote note, String ext) {
  final child = note.childNames.trim().isEmpty ? 'note' : note.childNames;
  // Replace everything that isn't a letter, digit, dash or underscore
  // with a dash — keeps the filename safe across macOS, iOS, Android,
  // and email gateways.
  final safe = child.replaceAll(RegExp('[^A-Za-z0-9_-]+'), '-');
  final stamp = DateTime.now().millisecondsSinceEpoch.toString();
  return 'parent-concern-$safe-$stamp.$ext';
}
