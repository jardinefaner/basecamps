import 'dart:convert';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/forms/polymorphic/form_definition.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// CRUD for the polymorphic forms table. Every form type goes through
/// here — the repository doesn't know anything form-specific, it just
/// shuttles the JSON blob + typed columns in and out.
class FormSubmissionRepository {
  FormSubmissionRepository(this._db);

  final AppDatabase _db;

  /// All submissions of a given [formType], newest first. Powers the
  /// forms-hub list screens.
  Stream<List<FormSubmission>> watchByType(String formType) {
    final query = _db.select(_db.formSubmissions)
      ..where((s) => s.formType.equals(formType))
      ..orderBy([
        // Submitted rows first by submit time; drafts (null
        // submittedAt) fall through to createdAt order. Both
        // descending so newest is on top either way.
        (s) => OrderingTerm(
              expression: s.submittedAt,
              mode: OrderingMode.desc,
              nulls: NullsOrder.last,
            ),
        (s) => OrderingTerm(
              expression: s.createdAt,
              mode: OrderingMode.desc,
            ),
      ]);
    return query.watch();
  }

  /// All submissions linked as children of [parentSubmissionId]
  /// (behavior monitorings linked to a concern, etc.).
  Stream<List<FormSubmission>> watchChildrenOf(String parentSubmissionId) {
    final query = _db.select(_db.formSubmissions)
      ..where((s) => s.parentSubmissionId.equals(parentSubmissionId))
      ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]);
    return query.watch();
  }

  /// All submissions whose status matches [status], across every form
  /// type. Feeds Today's close-out strip count of draft submissions.
  Stream<List<FormSubmission>> watchByStatus(FormStatus status) {
    final query = _db.select(_db.formSubmissions)
      ..where((s) => s.status.equals(status.dbValue))
      ..orderBy([(s) => OrderingTerm.desc(s.updatedAt)]);
    return query.watch();
  }

  /// All submissions with a review-due deadline <= [cutoff] that
  /// aren't yet completed. Feeds the Today flags strip's cross-form
  /// "needs follow-up" signal.
  Stream<List<FormSubmission>> watchReviewsDueBy(DateTime cutoff) {
    final query = _db.select(_db.formSubmissions)
      ..where((s) =>
          s.reviewDueAt.isNotNull() &
          s.reviewDueAt.isSmallerOrEqualValue(cutoff) &
          s.status.isNotValue(FormStatus.completed.dbValue) &
          s.status.isNotValue(FormStatus.archived.dbValue))
      ..orderBy([(s) => OrderingTerm.asc(s.reviewDueAt)]);
    return query.watch();
  }

  Future<FormSubmission?> getSubmission(String id) {
    return (_db.select(_db.formSubmissions)..where((s) => s.id.equals(id)))
        .getSingleOrNull();
  }

  Stream<FormSubmission?> watchSubmission(String id) {
    return (_db.select(_db.formSubmissions)..where((s) => s.id.equals(id)))
        .watchSingleOrNull();
  }

  /// Create a new draft submission. Everything except `formType` is
  /// optional — the form screen fills the rest in as the teacher
  /// edits.
  Future<String> createDraft({
    required String formType,
    Map<String, dynamic> data = const {},
    String? childId,
    String? groupId,
    String? tripId,
    String? parentSubmissionId,
    String? authorName,
    DateTime? reviewDueAt,
  }) async {
    final id = newId();
    await _db.into(_db.formSubmissions).insert(
          FormSubmissionsCompanion.insert(
            id: id,
            formType: formType,
            data: Value(jsonEncode(data)),
            childId: Value(childId),
            groupId: Value(groupId),
            tripId: Value(tripId),
            parentSubmissionId: Value(parentSubmissionId),
            authorName: Value(authorName),
            reviewDueAt: Value(reviewDueAt),
          ),
        );
    return id;
  }

  /// Partial update. Any field left at its default is untouched.
  /// Passing [data] REPLACES the whole JSON blob — callers should
  /// merge against the existing map before calling to avoid dropping
  /// fields.
  Future<void> updateSubmission({
    required String id,
    Map<String, dynamic>? data,
    FormStatus? status,
    DateTime? submittedAt,
    bool markSubmittedAtNull = false,
    String? childId,
    bool clearChildId = false,
    String? groupId,
    bool clearGroupId = false,
    String? tripId,
    bool clearTripId = false,
    DateTime? reviewDueAt,
    bool clearReviewDueAt = false,
    String? authorName,
  }) async {
    final companion = FormSubmissionsCompanion(
      data: data == null ? const Value.absent() : Value(jsonEncode(data)),
      status: status == null ? const Value.absent() : Value(status.dbValue),
      submittedAt: markSubmittedAtNull
          ? const Value<DateTime?>(null)
          : (submittedAt == null
              ? const Value.absent()
              : Value(submittedAt)),
      childId: clearChildId
          ? const Value<String?>(null)
          : (childId == null ? const Value.absent() : Value(childId)),
      groupId: clearGroupId
          ? const Value<String?>(null)
          : (groupId == null ? const Value.absent() : Value(groupId)),
      tripId: clearTripId
          ? const Value<String?>(null)
          : (tripId == null ? const Value.absent() : Value(tripId)),
      reviewDueAt: clearReviewDueAt
          ? const Value<DateTime?>(null)
          : (reviewDueAt == null
              ? const Value.absent()
              : Value(reviewDueAt)),
      authorName:
          authorName == null ? const Value.absent() : Value(authorName),
      updatedAt: Value(DateTime.now()),
    );
    await (_db.update(_db.formSubmissions)..where((s) => s.id.equals(id)))
        .write(companion);
  }

  Future<void> deleteSubmission(String id) async {
    await (_db.delete(_db.formSubmissions)..where((s) => s.id.equals(id))).go();
  }

  /// One-time back-fill for pre-picker incident submissions. The old
  /// incident form stored the child as a free-text `child_name` in
  /// the JSON blob and left the typed `child_id` FK column null.
  /// After the FormChildPickerField slice, new submissions stamp
  /// child_id directly — but the historical rows' JSON is orphaned.
  ///
  /// This walks every `form_submissions` row where:
  ///   * form_type == 'incident'
  ///   * child_id IS NULL
  ///   * data contains a non-empty 'child_name' string
  ///
  /// For each, it attempts an unambiguous match against the
  /// `children` table by first+last name (case-insensitive). Exactly
  /// one matching child → update child_id. Zero or multiple matches
  /// → leave untouched (teacher can re-link by hand later).
  ///
  /// Returns the number of rows successfully linked. Intended to run
  /// once on app startup behind a SharedPreferences flag; safe to
  /// re-run (idempotent — already-linked rows are skipped by the
  /// null filter).
  Future<int> backfillIncidentChildIds() async {
    final rows = await (_db.select(_db.formSubmissions)
          ..where((s) =>
              s.formType.equals('incident') & s.childId.isNull()))
        .get();
    if (rows.isEmpty) return 0;

    final kids = await _db.select(_db.children).get();
    // Precompute a lowercase "first last" → child lookup. Collisions
    // (two kids with the same name) produce a list; we skip those
    // ambiguous names at match time.
    final byName = <String, List<String>>{};
    for (final k in kids) {
      final last = k.lastName ?? '';
      final key = '${k.firstName} $last'.trim().toLowerCase();
      (byName[key] ??= <String>[]).add(k.id);
    }

    var linked = 0;
    for (final row in rows) {
      final data = decodeFormData(row);
      final raw = (data['child_name'] as String?)?.trim();
      if (raw == null || raw.isEmpty) continue;
      final key = raw.toLowerCase();
      // Also try the raw name against first-only (a teacher who
      // wrote just "Noah" without a last name). Skip ambiguous.
      var candidates = byName[key];
      if (candidates == null) {
        final firstOnly = key.split(' ').first;
        candidates = byName.entries
            .where((e) => e.key.startsWith('$firstOnly '))
            .expand((e) => e.value)
            .toList();
      }
      if (candidates.length != 1) continue;
      await (_db.update(_db.formSubmissions)
            ..where((s) => s.id.equals(row.id)))
          .write(FormSubmissionsCompanion(childId: Value(candidates.first)));
      linked++;
    }
    return linked;
  }
}

/// Decodes the stored [FormSubmission.data] JSON into a typed map.
/// Malformed JSON falls back to an empty map — never throws, because
/// a single corrupt row shouldn't brick the list screen.
Map<String, dynamic> decodeFormData(FormSubmission s) {
  try {
    final parsed = jsonDecode(s.data);
    if (parsed is Map<String, dynamic>) return parsed;
    return {};
  } on FormatException {
    return {};
  }
}

final formSubmissionRepositoryProvider =
    Provider<FormSubmissionRepository>((ref) {
  return FormSubmissionRepository(ref.watch(databaseProvider));
});

/// All submissions of a given form type, streamed.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final formSubmissionsByTypeProvider =
    StreamProvider.family<List<FormSubmission>, String>((ref, formType) {
  return ref.watch(formSubmissionRepositoryProvider).watchByType(formType);
});

/// One submission by id — used by the form screen when editing an
/// existing draft / submitted row.
// ignore: specify_nonobvious_property_types
final formSubmissionProvider =
    StreamProvider.family<FormSubmission?, String>((ref, id) {
  return ref.watch(formSubmissionRepositoryProvider).watchSubmission(id);
});

/// Child submissions of a parent (behavior monitorings under a concern).
// ignore: specify_nonobvious_property_types
final formSubmissionChildrenProvider =
    StreamProvider.family<List<FormSubmission>, String>((ref, parentId) {
  return ref
      .watch(formSubmissionRepositoryProvider)
      .watchChildrenOf(parentId);
});

/// All submissions in a particular lifecycle status, across every
/// form type. Today's close-out strip subscribes to this with
/// [FormStatus.draft] to surface the count of unfinished forms.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final formSubmissionsByStatusProvider =
    StreamProvider.family<List<FormSubmission>, FormStatus>((ref, status) {
  return ref.watch(formSubmissionRepositoryProvider).watchByStatus(status);
});

/// Submissions with a review deadline at-or-before today, across all
/// form types. Drives Today's "review due" flag entry — one query
/// answers "is anything overdue right now?" for the whole polymorphic
/// forms system.
final todayReviewDueProvider =
    StreamProvider<List<FormSubmission>>((ref) {
  final now = DateTime.now();
  final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
  return ref
      .watch(formSubmissionRepositoryProvider)
      .watchReviewsDueBy(endOfToday);
});
