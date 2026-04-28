import 'dart:async';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:basecamp/features/sync/sync_specs.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Plain-Dart shape the UI works with. Mirrors the [ParentConcernNote]
/// drift row but is owned by the form screen's local state — that way
/// the form can stage edits without repeatedly rebuilding companions.
class ParentConcernInput {
  ParentConcernInput({
    this.childNames = '',
    List<String>? childIds,
    this.parentName = '',
    this.concernDate,
    this.staffReceiving = '',
    this.supervisorNotified,
    this.methodInPerson = false,
    this.methodPhone = false,
    this.methodEmail = false,
    this.methodOther,
    this.concernDescription = '',
    this.immediateResponse = '',
    this.followUpMonitor = false,
    this.followUpStaffCheckIns = false,
    this.followUpSupervisorReview = false,
    this.followUpParentConversation = false,
    this.followUpOther,
    this.followUpDate,
    this.additionalNotes,
    this.staffSignature,
    this.staffSignaturePath,
    this.staffSignatureDate,
    this.supervisorSignature,
    this.supervisorSignaturePath,
    this.supervisorSignatureDate,
  }) : childIds = childIds ?? <String>[];

  /// Build the form's editable state from an existing drift row — the
  /// "edit existing note" path. The structured child-id list is loaded
  /// separately (via `ParentConcernRepository.childIdsForConcern`) and
  /// passed through [childIds] so hydration runs in a single frame.
  factory ParentConcernInput.fromRow(
    ParentConcernNote row, {
    List<String> childIds = const [],
  }) {
    return ParentConcernInput(
      childNames: row.childNames,
      childIds: List<String>.from(childIds),
      parentName: row.parentName,
      concernDate: row.concernDate,
      staffReceiving: row.staffReceiving,
      supervisorNotified: row.supervisorNotified,
      methodInPerson: row.methodInPerson,
      methodPhone: row.methodPhone,
      methodEmail: row.methodEmail,
      methodOther: row.methodOther,
      concernDescription: row.concernDescription,
      immediateResponse: row.immediateResponse,
      followUpMonitor: row.followUpMonitor,
      followUpStaffCheckIns: row.followUpStaffCheckIns,
      followUpSupervisorReview: row.followUpSupervisorReview,
      followUpParentConversation: row.followUpParentConversation,
      followUpOther: row.followUpOther,
      followUpDate: row.followUpDate,
      additionalNotes: row.additionalNotes,
      staffSignature: row.staffSignature,
      staffSignaturePath: row.staffSignaturePath,
      staffSignatureDate: row.staffSignatureDate,
      supervisorSignature: row.supervisorSignature,
      supervisorSignaturePath: row.supervisorSignaturePath,
      supervisorSignatureDate: row.supervisorSignatureDate,
    );
  }

  String childNames;

  /// Structured list of children this concern references, authoritative
  /// for "does this concern mention a child in this group" queries.
  /// [childNames] stays as the free-text version (what the parent
  /// actually said, used in PDF / document exports).
  List<String> childIds;

  String parentName;
  DateTime? concernDate;
  String staffReceiving;
  String? supervisorNotified;

  bool methodInPerson;
  bool methodPhone;
  bool methodEmail;
  String? methodOther;

  String concernDescription;
  String immediateResponse;

  bool followUpMonitor;
  bool followUpStaffCheckIns;
  bool followUpSupervisorReview;
  bool followUpParentConversation;
  String? followUpOther;
  DateTime? followUpDate;

  String? additionalNotes;

  String? staffSignature;
  String? staffSignaturePath;
  DateTime? staffSignatureDate;
  String? supervisorSignature;
  String? supervisorSignaturePath;
  DateTime? supervisorSignatureDate;
}

class ParentConcernRepository {
  ParentConcernRepository(this._db, this._ref);

  final AppDatabase _db;
  final Ref _ref;

  /// See ObservationsRepository._programId for why we read this on
  /// every insert rather than caching at construction time.
  String? get _programId => _ref.read(activeProgramIdProvider);

  SyncEngine get _sync => _ref.read(syncEngineProvider);

  Stream<List<ParentConcernNote>> watchAll() {
    return (_db.select(_db.parentConcernNotes)
          ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]))
        .watch();
  }

  /// Notes whose `concernDate` falls on the given day, plus any notes
  /// with no concernDate that were created/updated today — teachers
  /// often leave that field blank when typing a note on the fly. The
  /// Today screen uses this to surface an "active concern" flag.
  Stream<List<ParentConcernNote>> watchForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return (_db.select(_db.parentConcernNotes)
          ..where(
            (n) =>
                (n.concernDate.isBiggerOrEqualValue(start) &
                        n.concernDate.isSmallerThanValue(end)) |
                    (n.concernDate.isNull() &
                        n.updatedAt.isBiggerOrEqualValue(start) &
                        n.updatedAt.isSmallerThanValue(end)),
          )
          ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]))
        .watch();
  }

  Stream<ParentConcernNote?> watchOne(String id) {
    return (_db.select(_db.parentConcernNotes)
          ..where((n) => n.id.equals(id)))
        .watchSingleOrNull();
  }

  Future<ParentConcernNote?> getOne(String id) {
    return (_db.select(_db.parentConcernNotes)
          ..where((n) => n.id.equals(id)))
        .getSingleOrNull();
  }

  /// Create a brand-new note. Returns the new id.
  Future<String> create(ParentConcernInput input) async {
    final id = newId();
    await _db.transaction(() async {
      await _db.into(_db.parentConcernNotes).insert(_companion(id, input));
      await _replaceKidLinks(id, input.childIds);
    });
    unawaited(_sync.pushRow(parentConcernNotesSpec, id));
    return id;
  }

  /// Overwrite an existing note. Uses the same companion as create
  /// (minus `createdAt`) — every field is replaced so the form is the
  /// source of truth, not a partial patch.
  Future<void> update(String id, ParentConcernInput input) async {
    await _db.transaction(() async {
      await (_db.update(_db.parentConcernNotes)
            ..where((n) => n.id.equals(id)))
          .write(
        _companion(id, input, updating: true),
      );
      await _replaceKidLinks(id, input.childIds);
    });
    unawaited(_sync.pushRow(parentConcernNotesSpec, id));
  }

  Future<void> delete(String id) async {
    final row = await (_db.select(_db.parentConcernNotes)
          ..where((n) => n.id.equals(id)))
        .getSingleOrNull();
    final programId = row?.programId;
    await (_db.delete(_db.parentConcernNotes)..where((n) => n.id.equals(id)))
        .go();
    if (programId != null) {
      unawaited(
        _sync.pushDelete(
          spec: parentConcernNotesSpec,
          id: id,
          programId: programId,
        ),
      );
    }
  }

  /// Structured child ids linked to a concern. Used by the form to hydrate
  /// its chip picker on edit, and by the Today screen to figure out
  /// which activity card a concern should flag.
  Future<List<String>> childIdsForConcern(String concernId) async {
    final rows = await (_db.select(_db.parentConcernChildren)
          ..where((k) => k.concernId.equals(concernId)))
        .get();
    return rows.map((r) => r.childId).toList();
  }

  /// Live view of the (concern → child) join as a map from concern id
  /// to the set of linked child ids — feeds Today's concern-flag lookup
  /// so adding/removing a link causes a rebuild.
  Stream<Map<String, Set<String>>> watchConcernChildLinks() {
    return _db.select(_db.parentConcernChildren).watch().map((rows) {
      final map = <String, Set<String>>{};
      for (final r in rows) {
        (map[r.concernId] ??= <String>{}).add(r.childId);
      }
      return map;
    });
  }

  Future<void> _replaceKidLinks(
    String concernId,
    List<String> childIds,
  ) async {
    await (_db.delete(_db.parentConcernChildren)
          ..where((k) => k.concernId.equals(concernId)))
        .go();
    // Dedupe while preserving order — same defensive pattern other
    // repos use so accidental double-taps don't violate the PK.
    final seen = <String>{};
    for (final childId in childIds) {
      if (!seen.add(childId)) continue;
      await _db.into(_db.parentConcernChildren).insert(
            ParentConcernChildrenCompanion.insert(
              concernId: concernId,
              childId: childId,
            ),
          );
    }
  }

  /// Batch version. One `WHERE id IN (...)` delete; any drawn-
  /// signature PNGs stay on disk — they're shared-documents-style
  /// artefacts a teacher may have already emailed out, not owned by
  /// the app the way observation media is.
  Future<void> deleteMany(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final rows = await (_db.select(_db.parentConcernNotes)
          ..where((n) => n.id.isIn(list)))
        .get();
    await (_db.delete(_db.parentConcernNotes)..where((n) => n.id.isIn(list)))
        .go();
    for (final r in rows) {
      final programId = r.programId;
      if (programId != null) {
        unawaited(
          _sync.pushDelete(
            spec: parentConcernNotesSpec,
            id: r.id,
            programId: programId,
          ),
        );
      }
    }
  }

  /// Restore helpers for the undo snackbar — re-insert with original
  /// id. Cascaded parent_concern_children join rows aren't restored
  /// (same 5-second-window tradeoff as other restores in the app);
  /// the concern's narrative comes back, the structured child links
  /// don't.
  Future<void> restore(ParentConcernNote row) async {
    await _db.into(_db.parentConcernNotes).insertOnConflictUpdate(row);
    unawaited(_sync.pushRow(parentConcernNotesSpec, row.id));
  }

  Future<void> restoreMany(Iterable<ParentConcernNote> rows) async {
    await _db.transaction(() async {
      for (final row in rows) {
        await _db.into(_db.parentConcernNotes).insertOnConflictUpdate(row);
      }
    });
    for (final row in rows) {
      unawaited(_sync.pushRow(parentConcernNotesSpec, row.id));
    }
  }

  ParentConcernNotesCompanion _companion(
    String id,
    ParentConcernInput input, {
    bool updating = false,
  }) {
    final now = DateTime.now();
    return ParentConcernNotesCompanion(
      id: Value(id),
      childNames: Value(input.childNames),
      parentName: Value(input.parentName),
      concernDate: Value(input.concernDate),
      staffReceiving: Value(input.staffReceiving),
      supervisorNotified: Value(input.supervisorNotified),
      methodInPerson: Value(input.methodInPerson),
      methodPhone: Value(input.methodPhone),
      methodEmail: Value(input.methodEmail),
      methodOther: Value(input.methodOther),
      concernDescription: Value(input.concernDescription),
      immediateResponse: Value(input.immediateResponse),
      followUpMonitor: Value(input.followUpMonitor),
      followUpStaffCheckIns: Value(input.followUpStaffCheckIns),
      followUpSupervisorReview: Value(input.followUpSupervisorReview),
      followUpParentConversation: Value(input.followUpParentConversation),
      followUpOther: Value(input.followUpOther),
      followUpDate: Value(input.followUpDate),
      additionalNotes: Value(input.additionalNotes),
      staffSignature: Value(input.staffSignature),
      staffSignaturePath: Value(input.staffSignaturePath),
      staffSignatureDate: Value(input.staffSignatureDate),
      supervisorSignature: Value(input.supervisorSignature),
      supervisorSignaturePath: Value(input.supervisorSignaturePath),
      supervisorSignatureDate: Value(input.supervisorSignatureDate),
      // Insert path writes createdAt via the table default; update path
      // must refresh updatedAt only.
      createdAt: updating ? const Value.absent() : Value(now),
      updatedAt: Value(now),
      // Stamp the active program on insert only — update paths leave
      // programId untouched so a row's tenant scope can't drift.
      programId: updating ? const Value.absent() : Value(_programId),
    );
  }
}

final parentConcernRepositoryProvider =
    Provider<ParentConcernRepository>((ref) {
  return ParentConcernRepository(ref.watch(databaseProvider), ref);
});

final parentConcernNotesProvider =
    StreamProvider<List<ParentConcernNote>>((ref) {
  return ref.watch(parentConcernRepositoryProvider).watchAll();
});

/// Concern notes dated (or captured) today. Feeds the Today dashboard's
/// concern flags and day-summary strip.
final todayConcernNotesProvider =
    StreamProvider<List<ParentConcernNote>>((ref) {
  return ref
      .watch(parentConcernRepositoryProvider)
      .watchForDay(DateTime.now());
});

/// Map of concern id → set of linked child ids, live. Today's
/// per-activity concern flag uses this to know which cards to annotate
/// without substring-matching free text.
final concernKidLinksProvider =
    StreamProvider<Map<String, Set<String>>>((ref) {
  return ref.watch(parentConcernRepositoryProvider).watchConcernChildLinks();
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final parentConcernNoteProvider =
    StreamProvider.family<ParentConcernNote?, String>((ref, id) {
  return ref.watch(parentConcernRepositoryProvider).watchOne(id);
});
