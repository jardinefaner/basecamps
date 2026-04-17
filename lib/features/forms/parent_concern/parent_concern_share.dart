import 'dart:async';
import 'dart:io';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/forms/parent_concern/parent_concern_export.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Bottom-sheet menu of export / share / print actions for a saved
/// Parent Concern Note. Keeps the four paths (PDF, text body, copy,
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
            subtitle: const Text(
              'Formatted document with signatures embedded',
            ),
            onTap: () {
              Navigator.of(ctx).pop();
              unawaited(_shareAsPdf(note));
            },
          ),
          ListTile(
            leading: const Icon(Icons.notes_outlined),
            title: const Text('Share as text'),
            subtitle: const Text(
              'Markdown in the email / message body — no attachment',
            ),
            onTap: () {
              Navigator.of(ctx).pop();
              unawaited(_shareAsText(note));
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text('Copy to clipboard'),
            subtitle: const Text(
              'Paste into an email, note, or anywhere',
            ),
            onTap: () async {
              Navigator.of(ctx).pop();
              await _copyAsText(note);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
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

/// Shares the markdown as the BODY of whatever target the user
/// picks (email, messages, notes). A previous version attached a
/// `.md` file, but iOS Mail and Gmail both mangle unfamiliar
/// attachment types — users reported nothing downloadable on the
/// receiving side. Putting the content in the share-sheet's text
/// payload sidesteps that entirely: every target treats it as the
/// message body and the recipient reads it immediately.
///
/// Drawn signatures ride along as PNG attachments — the markdown
/// references them by filename so the recipient can match which
/// image belongs to which signer, and PNGs travel cleanly through
/// every mail / messaging client we've tested.
Future<void> _shareAsText(ParentConcernNote note) async {
  final attachments = <XFile>[];
  final staffFile = await _signatureAttachment(
    path: note.staffSignaturePath,
    role: 'staff',
    note: note,
  );
  if (staffFile != null) attachments.add(staffFile);
  final supervisorFile = await _signatureAttachment(
    path: note.supervisorSignaturePath,
    role: 'supervisor',
    note: note,
  );
  if (supervisorFile != null) attachments.add(supervisorFile);

  final md = buildParentConcernMarkdown(
    note,
    staffSignatureAttachmentName: staffFile?.name,
    supervisorSignatureAttachmentName: supervisorFile?.name,
  );

  await SharePlus.instance.share(
    ShareParams(
      text: md,
      files: attachments.isEmpty ? null : attachments,
      subject: 'Parent Concern Note',
    ),
  );
}

/// Copies a saved signature to a share-friendly temp file with a
/// predictable name (so the markdown can reference it). Returns null
/// when there's no signature on file or the source has been moved.
Future<XFile?> _signatureAttachment({
  required String? path,
  required String role,
  required ParentConcernNote note,
}) async {
  if (path == null || kIsWeb) return null;
  final source = File(path);
  if (!source.existsSync()) return null;
  // Predictable name so the markdown can call it out. Keep the
  // timestamp from the filename helper so multi-note shares don't
  // collide if the recipient saves them off.
  final child = note.childNames.trim().isEmpty ? 'note' : note.childNames;
  final safe = child.replaceAll(RegExp('[^A-Za-z0-9_-]+'), '-');
  final stamp = DateTime.now().millisecondsSinceEpoch.toString();
  final filename = 'signature-$role-$safe-$stamp.png';
  return XFile(source.path, name: filename, mimeType: 'image/png');
}

Future<void> _copyAsText(ParentConcernNote note) async {
  final md = buildParentConcernMarkdown(note);
  await Clipboard.setData(ClipboardData(text: md));
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
