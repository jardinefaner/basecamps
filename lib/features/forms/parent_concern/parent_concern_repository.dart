import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Plain-Dart shape the UI works with. Mirrors the [ParentConcernNote]
/// drift row but is owned by the form screen's local state — that way
/// the form can stage edits without repeatedly rebuilding companions.
class ParentConcernInput {
  ParentConcernInput({
    this.childNames = '',
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
  });

  /// Build the form's editable state from an existing drift row — the
  /// "edit existing note" path.
  factory ParentConcernInput.fromRow(ParentConcernNote row) {
    return ParentConcernInput(
      childNames: row.childNames,
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
  ParentConcernRepository(this._db);

  final AppDatabase _db;

  Stream<List<ParentConcernNote>> watchAll() {
    return (_db.select(_db.parentConcernNotes)
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
    await _db.into(_db.parentConcernNotes).insert(_companion(id, input));
    return id;
  }

  /// Overwrite an existing note. Uses the same companion as create
  /// (minus `createdAt`) — every field is replaced so the form is the
  /// source of truth, not a partial patch.
  Future<void> update(String id, ParentConcernInput input) async {
    await (_db.update(_db.parentConcernNotes)..where((n) => n.id.equals(id)))
        .write(
      _companion(id, input, updating: true),
    );
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.parentConcernNotes)..where((n) => n.id.equals(id)))
        .go();
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
    );
  }
}

final parentConcernRepositoryProvider =
    Provider<ParentConcernRepository>((ref) {
  return ParentConcernRepository(ref.watch(databaseProvider));
});

final parentConcernNotesProvider =
    StreamProvider<List<ParentConcernNote>>((ref) {
  return ref.watch(parentConcernRepositoryProvider).watchAll();
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final parentConcernNoteProvider =
    StreamProvider.family<ParentConcernNote?, String>((ref, id) {
  return ref.watch(parentConcernRepositoryProvider).watchOne(id);
});
