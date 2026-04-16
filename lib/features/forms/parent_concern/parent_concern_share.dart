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
/// Parent Concern Note. Keeps the three formats (PDF, markdown,
/// print) in one place so the form screen's app bar only needs a
/// single Share button.
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
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Share as PDF'),
            subtitle: const Text('Formatted document with signatures embedded'),
            onTap: () {
              Navigator.of(ctx).pop();
              unawaited(_shareAsPdf(note));
            },
          ),
          ListTile(
            leading: const Icon(Icons.notes_outlined),
            title: const Text('Share as markdown'),
            subtitle: const Text('Plain-text friendly, easy to paste into email'),
            onTap: () {
              Navigator.of(ctx).pop();
              unawaited(_shareAsMarkdown(note));
            },
          ),
          if (!kIsWeb)
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('Print'),
              subtitle: const Text('Send to a physical printer or save as PDF'),
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

Future<void> _shareAsMarkdown(ParentConcernNote note) async {
  final md = buildParentConcernMarkdown(note);
  // Write to a temp file so the recipient gets a real .md attachment
  // (share text APIs across platforms are inconsistent about long
  // bodies; a file is always handled correctly).
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, _safeFilename(note, 'md')));
  await file.writeAsString(md);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'text/markdown')],
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
