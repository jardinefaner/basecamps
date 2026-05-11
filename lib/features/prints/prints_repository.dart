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

import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/program_scope.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
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
  PrintsRepository(this._db, this._ref);

  final AppDatabase _db;
  final Ref _ref;

  String? get _programId => _ref.read(activeProgramIdProvider);

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
    // EVERY platform now embeds the PNG as a `data:` URL in
    // `snapshot_path`. Previously native wrote the file to disk
    // and stored a relative path; that broke cross-device sync
    // because the path on Device A meant nothing on Device B.
    // Data URLs ARE the bytes — they travel as a string through
    // the sync engine without a separate Storage round-trip.
    // Thank-you-card snapshots are ~50-100KB; Postgres TEXT
    // toasts these automatically. For a per-program volume of
    // a few hundred prints, total storage is a couple MB.
    //
    // Native still also writes the file to disk as a
    // best-effort cache so existing read paths
    // (`_resolveAbsolutePath`) keep working for already-printed
    // local rows; new rows just decode from the data URL.
    final dataUrl = 'data:image/png;base64,${base64Encode(snapshot)}';
    if (!kIsWeb) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final printDir = Directory(p.join(dir.path, _printsSubdir));
        if (!printDir.existsSync()) {
          printDir.createSync(recursive: true);
        }
        final absPath = p.join(dir.path, '$_printsSubdir/$id.png');
        await File(absPath).writeAsBytes(snapshot);
      } on Object {
        // Best-effort local cache. The data URL is authoritative.
      }
    }
    final now = DateTime.now().toUtc();
    await _db.into(_db.prints).insert(
          PrintsCompanion(
            id: Value(id),
            surveyId: Value(surveyId),
            sessionId: Value(sessionId),
            childName: Value(childName),
            kind: Value(kind.code),
            snapshotPath: Value(dataUrl),
            metadataJson: Value(
              metadata.isEmpty ? null : jsonEncode(metadata),
            ),
            programId: Value(_programId),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    final absSnapshotPath = await _resolveAbsolutePath(dataUrl);
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
      ..where(
        (p) =>
            p.deletedAt.isNull() &
            matchesActiveProgram(p.programId, _programId),
      )
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

  /// Edit the kid's name on a saved print. Useful when the
  /// kid typed it wrong on the kiosk and a teacher needs to
  /// correct it after the fact. The snapshot PNG itself was
  /// already captured with the original name baked in — we
  /// don't re-render the image, just update the column the
  /// detail screen / CSV export reads.
  Future<void> updateChildName(String id, String childName) async {
    await (_db.update(_db.prints)..where((p) => p.id.equals(id))).write(
      PrintsCompanion(
        childName: Value(childName.trim()),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
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
  return PrintsRepository(db, ref);
});

final printsListProvider = StreamProvider<List<SavedPrint>>((ref) {
  return ref.watch(printsRepositoryProvider).watchAll();
});

// ignore: specify_nonobvious_property_types
final printByIdProvider =
    FutureProvider.family<SavedPrint?, String>((ref, id) {
  return ref.watch(printsRepositoryProvider).getById(id);
});
