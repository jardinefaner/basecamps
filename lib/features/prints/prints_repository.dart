// Prints repository — saved keepsake-card prints from any survey
// kiosk. The thank-you card at end-of-session captures itself to
// a PNG, asks this repo to save it, and the Prints tab lists every
// saved card so a teacher can batch-print them later.
//
// **Polymorphic by [PrintRecord.kind]**: both kiosk styles
// (marble jar + basket) write to the same `prints` table; the
// kind discriminator drives any preview-rendering specifics. The
// list / detail screens render the snapshot identically; the kind
// just labels what flavor of card it is.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// What kind of card produced a given print. The polymorphism
/// dimension — both kiosk styles write to the same table; this
/// labels which one. Extensible: future card kinds (sequence
/// summaries, weekly digests) can add new values here without
/// schema changes.
enum PrintKind {
  /// Basket survey thank-you card — woven basket snapshot with
  /// orbs piled inside + overspill around. From the
  /// `BasketSurveyScreen`'s end-of-session capture.
  feelingsBasket('feelings_basket'),

  /// Marble jar kiosk thank-you card — 3D mason jar with painted
  /// marbles. From the `SurveyScreen`'s end-of-session capture.
  marbleJar('marble_jar');

  const PrintKind(this.code);
  final String code;

  static PrintKind fromCode(String code) {
    return PrintKind.values.firstWhere(
      (k) => k.code == code,
      orElse: () => PrintKind.feelingsBasket,
    );
  }

  /// Display label for the prints list.
  String get label => switch (this) {
        PrintKind.feelingsBasket => 'Feelings basket',
        PrintKind.marbleJar => 'Feelings jar',
      };
}

/// One saved print, with the snapshot path resolved to absolute
/// (`<docs>/prints/<id>.png`) so callers don't need to know about
/// the on-disk layout.
class SavedPrint {
  const SavedPrint({
    required this.id,
    required this.surveyId,
    required this.sessionId,
    required this.childName,
    required this.kind,
    required this.absoluteSnapshotPath,
    required this.metadata,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? surveyId;
  final String? sessionId;
  final String childName;
  final PrintKind kind;
  final String absoluteSnapshotPath;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class PrintsRepository {
  PrintsRepository(this._db);

  final AppDatabase _db;

  static const String _printsSubdir = 'prints';

  /// Save a new print. Writes the PNG to
  /// `<docs>/prints/<id>.png` and inserts a row.
  ///
  /// On web — where there's no docs folder — the snapshot is
  /// stored inline as a `data:` URL in `snapshotPath`. The
  /// detail screen handles both schemes when it reads back.
  Future<SavedPrint> save({
    required Uint8List snapshot,
    required PrintKind kind,
    String? surveyId,
    String? sessionId,
    String childName = '',
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) async {
    final id = newId();
    final relPath = '$_printsSubdir/$id.png';
    String storedPath;
    if (kIsWeb) {
      // Web fallback — embed bytes as a data URL. Limits:
      // ~1MB per print (above that the PRAGMA-prepared statement
      // bound to a TEXT column starts feeling sluggish). For the
      // print card snapshots that's fine.
      storedPath = 'data:image/png;base64,${base64Encode(snapshot)}';
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final printDir = Directory(p.join(dir.path, _printsSubdir));
      if (!printDir.existsSync()) {
        printDir.createSync(recursive: true);
      }
      final absPath = p.join(dir.path, relPath);
      await File(absPath).writeAsBytes(snapshot);
      storedPath = relPath;
    }
    final now = DateTime.now().toUtc();
    await _db.into(_db.prints).insert(
          PrintsCompanion(
            id: Value(id),
            surveyId: Value(surveyId),
            sessionId: Value(sessionId),
            childName: Value(childName),
            kind: Value(kind.code),
            snapshotPath: Value(storedPath),
            metadataJson: Value(
              metadata.isEmpty ? null : jsonEncode(metadata),
            ),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    final absSnapshotPath = await _resolveAbsolutePath(storedPath);
    return SavedPrint(
      id: id,
      surveyId: surveyId,
      sessionId: sessionId,
      childName: childName,
      kind: kind,
      absoluteSnapshotPath: absSnapshotPath,
      metadata: metadata,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Live stream of saved prints, newest first, soft-deleted
  /// rows filtered out.
  Stream<List<SavedPrint>> watchAll() {
    final query = _db.select(_db.prints)
      ..where((p) => p.deletedAt.isNull())
      ..orderBy([
        (p) => OrderingTerm(expression: p.createdAt, mode: OrderingMode.desc),
      ]);
    return query.watch().asyncMap((rows) async {
      final out = <SavedPrint>[];
      for (final row in rows) {
        out.add(await _rowToSaved(row));
      }
      return out;
    });
  }

  Future<SavedPrint?> getById(String id) async {
    final row = await (_db.select(_db.prints)
          ..where((p) => p.id.equals(id) & p.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) return null;
    return _rowToSaved(row);
  }

  /// Soft-delete: mark the row deleted. The PNG file stays put
  /// so an "undo" is still possible — purgeSoftDeleted() actually
  /// removes the bytes when we want to reclaim space.
  Future<void> softDelete(String id) async {
    await (_db.update(_db.prints)..where((p) => p.id.equals(id))).write(
      PrintsCompanion(
        deletedAt: Value(DateTime.now().toUtc()),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<SavedPrint> _rowToSaved(PrintRow row) async {
    final abs = await _resolveAbsolutePath(row.snapshotPath);
    return SavedPrint(
      id: row.id,
      surveyId: row.surveyId,
      sessionId: row.sessionId,
      childName: row.childName,
      kind: PrintKind.fromCode(row.kind),
      absoluteSnapshotPath: abs,
      metadata: row.metadataJson == null
          ? const <String, dynamic>{}
          : (jsonDecode(row.metadataJson!) as Map).cast<String, dynamic>(),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  /// Convert the stored path (relative under app docs, or a
  /// `data:` URL on web) back to something the loader can use.
  Future<String> _resolveAbsolutePath(String storedPath) async {
    if (storedPath.startsWith('data:')) return storedPath;
    if (kIsWeb) return storedPath;
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, storedPath);
  }
}

final printsRepositoryProvider = Provider<PrintsRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return PrintsRepository(db);
});

final printsListProvider = StreamProvider<List<SavedPrint>>((ref) {
  return ref.watch(printsRepositoryProvider).watchAll();
});

// ignore: specify_nonobvious_property_types
final printByIdProvider =
    FutureProvider.family<SavedPrint?, String>((ref, id) {
  return ref.watch(printsRepositoryProvider).getById(id);
});
