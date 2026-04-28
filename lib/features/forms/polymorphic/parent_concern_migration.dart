import 'dart:async';
import 'dart:convert';

import 'package:basecamp/database/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One-shot migration that moves every legacy `parent_concern_notes`
/// row into the polymorphic `form_submissions` table with
/// `form_type = 'parent_concern'`. Runs once per install via a
/// SharedPreferences flag — re-running is idempotent (already-
/// migrated rows are skipped because they have a corresponding
/// form_submissions row with the original id).
///
/// What it does:
///   - Reads every parent_concern_notes row
///   - Reads every parent_concern_children join for the multi-child
///     id list
///   - Maps the typed columns into a JSON data blob keyed by the
///     polymorphic form's field keys (see
///     definitions/parent_concern.dart)
///   - Inserts/upserts a form_submissions row carrying that data,
///     stamped with the same id as the source row (so the migration
///     is idempotent without a per-row tracking column)
///   - Leaves the original parent_concern_notes row in place for
///     v1. A follow-up will drop the bespoke table once the new
///     polymorphic surface has shipped through every callsite.
///
/// Migration is local-only — sync picks up the new
/// form_submissions rows on the next push and other devices see
/// them through the regular pull.
class ParentConcernMigration {
  ParentConcernMigration(this._db);

  final AppDatabase _db;

  static const _kFlagKey = 'parent_concern_migrated_to_polymorphic_v1';

  /// Runs the migration if it hasn't run on this install. Logs the
  /// count of migrated rows. Called once at app startup from
  /// BasecampApp's initState.
  Future<void> runOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kFlagKey) ?? false) return;

    try {
      final rows = await _db.select(_db.parentConcernNotes).get();
      if (rows.isEmpty) {
        await prefs.setBool(_kFlagKey, true);
        return;
      }
      var migrated = 0;
      for (final row in rows) {
        // Multi-child join.
        final childLinks = await (_db.select(_db.parentConcernChildren)
              ..where((j) => j.concernId.equals(row.id)))
            .get();
        final childIds = [for (final l in childLinks) l.childId];

        final data = _serializeRow(row, childIds);

        // Upsert the form_submissions row using the original id —
        // re-running on the same DB stamps the same id, so
        // insertOnConflictUpdate keeps it idempotent.
        await _db.into(_db.formSubmissions).insertOnConflictUpdate(
              FormSubmissionsCompanion.insert(
                id: row.id,
                formType: 'parent_concern',
                // Migrating finished forms forward — they're
                // already-completed history, not drafts. Default
                // is 'draft' so override explicitly.
                status: const Value('completed'),
                submittedAt: Value(row.createdAt),
                childId: childIds.length == 1
                    ? Value(childIds.first)
                    : const Value.absent(),
                data: Value(jsonEncode(data)),
                programId: Value(row.programId),
                createdAt: Value(row.createdAt),
                updatedAt: Value(row.updatedAt),
              ),
            );
        migrated += 1;
      }
      await prefs.setBool(_kFlagKey, true);
      if (migrated > 0) {
        debugPrint(
          'Migrated $migrated parent_concern_notes rows into '
          'form_submissions.',
        );
      }
    } on Object catch (e, st) {
      debugPrint('Parent-concern migration failed: $e\n$st');
      // Don't set the flag — next launch retries.
    }
  }

  Map<String, dynamic> _serializeRow(
    ParentConcernNote row,
    List<String> childIds,
  ) {
    return <String, dynamic>{
      // Section 1: who & when
      'child_ids': childIds,
      'parent_name': row.parentName,
      if (row.concernDate != null)
        'concern_date': row.concernDate!.toUtc().toIso8601String(),
      'staff_receiving': row.staffReceiving,
      // Section 2: how it was raised
      'method_in_person': row.methodInPerson,
      'method_phone': row.methodPhone,
      'method_email': row.methodEmail,
      if (row.methodOther != null && row.methodOther!.isNotEmpty)
        'method_other': row.methodOther,
      // Section 3: what was said
      'concern_description': row.concernDescription,
      'immediate_response': row.immediateResponse,
      // Section 4: notification
      if (row.supervisorNotified != null &&
          row.supervisorNotified!.isNotEmpty)
        'supervisor_notified': row.supervisorNotified,
      // Section 5: follow-up
      'follow_up_monitor': row.followUpMonitor,
      'follow_up_staff_check_ins': row.followUpStaffCheckIns,
      'follow_up_supervisor_review': row.followUpSupervisorReview,
      'follow_up_parent_conversation': row.followUpParentConversation,
      if (row.followUpOther != null && row.followUpOther!.isNotEmpty)
        'follow_up_other': row.followUpOther,
      if (row.followUpDate != null)
        'follow_up_date': row.followUpDate!.toUtc().toIso8601String(),
      if (row.additionalNotes != null && row.additionalNotes!.isNotEmpty)
        'additional_notes': row.additionalNotes,
      // Section 6: signatures (composite shape — see
      // FormSignatureField docs)
      if (row.staffSignature != null ||
          row.staffSignaturePath != null ||
          row.staffSignatureDate != null)
        'staff_signature': <String, dynamic>{
          if (row.staffSignature != null) 'name': row.staffSignature,
          if (row.staffSignaturePath != null)
            'signaturePath': row.staffSignaturePath,
          if (row.staffSignatureDate != null)
            'signedAt':
                row.staffSignatureDate!.toUtc().toIso8601String(),
        },
      if (row.supervisorSignature != null ||
          row.supervisorSignaturePath != null ||
          row.supervisorSignatureDate != null)
        'supervisor_signature': <String, dynamic>{
          if (row.supervisorSignature != null)
            'name': row.supervisorSignature,
          if (row.supervisorSignaturePath != null)
            'signaturePath': row.supervisorSignaturePath,
          if (row.supervisorSignatureDate != null)
            'signedAt':
                row.supervisorSignatureDate!.toUtc().toIso8601String(),
        },
    };
  }
}

final parentConcernMigrationProvider =
    Provider<ParentConcernMigration>((ref) {
  return ParentConcernMigration(ref.read(databaseProvider));
});
