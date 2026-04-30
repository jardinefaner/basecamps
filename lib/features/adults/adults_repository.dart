import 'dart:async';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/program_scope.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/sync/media_service.dart';
import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:basecamp/features/sync/sync_specs.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

/// Structural role an adult plays on the schedule (v28). Distinct from
/// [Adult.role], which is the free-form job-title blurb
/// ("Art teacher", "Director").
///
///   - [AdultRole.lead]       — anchored to one group all day; the
///                               "steady" adult in that group's room
///   - [AdultRole.specialist] — rover that rotates across activities
///                               (existing behavior; default for
///                               legacy rows)
///   - [AdultRole.ambient]    — present in the building but not on the
///                               activity grid (director, nurse,
///                               kitchen, front desk)
enum AdultRole {
  lead('lead'),
  specialist('specialist'),
  ambient('ambient');

  const AdultRole(this.dbValue);
  final String dbValue;

  static AdultRole fromDb(String raw) {
    for (final r in AdultRole.values) {
      if (r.dbValue == raw) return r;
    }
    // Any bad / pre-v28 value falls back to the legacy behavior.
    return AdultRole.specialist;
  }
}

class AdultsRepository {
  AdultsRepository(this._db, this._ref);

  final Ref _ref;
  String? get _programId => _ref.read(activeProgramIdProvider);

  SyncEngine get _sync => _ref.read(syncEngineProvider);
  MediaService get _media => _ref.read(mediaServiceProvider);

  final AppDatabase _db;

  Stream<List<Adult>> watchAll() {
    final query = _db.select(_db.adults)
      ..where((s) => matchesActiveProgram(s.programId, _programId))
      ..orderBy([(s) => OrderingTerm.asc(s.name)]);
    return query.watch();
  }

  Future<Adult?> getAdult(String id) {
    return (_db.select(_db.adults)..where((s) => s.id.equals(id)))
        .getSingleOrNull();
  }

  /// Stream a single adult so tiles/detail rebuild on edit.
  Stream<Adult?> watchAdult(String id) {
    return (_db.select(_db.adults)..where((s) => s.id.equals(id)))
        .watchSingleOrNull();
  }

  Future<String> addAdult({
    required String name,
    String? role,
    String? roleId,
    String? notes,
    XFile? avatarFile,
    AdultRole adultRole = AdultRole.specialist,
    String? anchoredGroupId,
    // v40: direct contact columns + staff↔parent bridge. All
    // nullable — programs that don't capture staff phone/email (or
    // haven't linked a staff row to a parent row) leave them blank.
    String? phone,
    String? email,
    String? parentId,
  }) async {
    final id = newId();
    // avatar_path is local-only (T1.1). On native, store the
    // picker's filesystem path so SmallAvatar can fast-render and
    // the heal pass can recover. On web `XFile.path` is a `blob:`
    // URL useless to dart:io.File, so we skip it — the cross-
    // device handle is `avatar_storage_path`, stamped by the
    // upload below.
    final localAvatarPath =
        avatarFile != null && !kIsWeb ? avatarFile.path : null;
    await _db.into(_db.adults).insert(
          AdultsCompanion.insert(
            id: id,
            name: name,
            role: Value(role),
            roleId: Value(roleId),
            notes: Value(notes),
            avatarPath: Value(localAvatarPath),
            adultRole: Value(adultRole.dbValue),
            anchoredGroupId: Value(anchoredGroupId),
            phone: Value(phone),
            email: Value(email),
            parentId: Value(parentId),
            programId: Value(_programId),
          ),
        );
    unawaited(_sync.pushRow(adultsSpec, id));
    if (avatarFile != null) {
      // Hand the freshly-picked XFile straight to MediaService —
      // works on every platform (web reads bytes via XFile, no
      // dart:io needed).
      unawaited(_media.uploadAdultAvatar(id, source: avatarFile));
    }
    return id;
  }

  Future<void> updateAdult({
    required String id,
    required String name,
    String? role,
    String? notes,
    XFile? avatarFile,
    bool clearAvatarPath = false,
    // Both default to Value.absent() so callers that only touch the
    // legacy fields (name / role / notes / avatar) don't accidentally
    // clobber adultRole / anchoredGroupId back to their defaults.
    Value<String> adultRole = const Value.absent(),
    Value<String?> anchoredGroupId = const Value.absent(),
    // v39: FK to the Roles entity. Defaults to Value.absent() so
    // callers that don't touch roleId leave the existing link alone.
    // Explicit `Value(null)` clears the link (e.g. when teacher
    // types a one-off legacy string after picking a chip).
    Value<String?> roleId = const Value.absent(),
    // v40: contact info + staff↔parent bridge. Value.absent() means
    // "leave untouched"; Value(null) clears. Callers (the edit sheet)
    // always pass Value(phone) / Value(email) so the field reflects
    // exactly what the teacher saved.
    Value<String?> phone = const Value.absent(),
    Value<String?> email = const Value.absent(),
    Value<String?> parentId = const Value.absent(),
  }) async {
    // avatar_path is local-only (T1.1) — never pushed to cloud and
    // never marked dirty. On native we stamp the picker's local
    // path so SmallAvatar / AvatarPicker can fast-render and the
    // heal pass can recover. On web we leave it null because
    // `XFile.path` there is a `blob:` URL that won't survive a
    // page reload.
    final localAvatarPath =
        avatarFile != null && !kIsWeb ? avatarFile.path : null;
    await (_db.update(_db.adults)..where((s) => s.id.equals(id))).write(
      AdultsCompanion(
        name: Value(name),
        role: Value(role),
        roleId: roleId,
        notes: Value(notes),
        avatarPath: clearAvatarPath
            ? const Value<String?>(null)
            : (avatarFile == null
                ? const Value.absent()
                : Value(localAvatarPath)),
        adultRole: adultRole,
        anchoredGroupId: anchoredGroupId,
        phone: phone,
        email: email,
        parentId: parentId,
        updatedAt: Value(DateTime.now()),
      ),
    );
    // Phase 4: field-level dirty tracking. Mark every column the
    // caller is actually changing. `name` is required (always set,
    // always dirty). `role` and `notes` are positional `String?`
    // params — null means "set to null" here (the existing
    // companion uses `Value(role)` so null does write through), so
    // they're always dirty when the call happens. The Value-wrapped
    // params are dirty only when `.present`.
    //
    // `avatar_path` deliberately omitted: it's local-only (T1.1),
    // so the sync engine filters it out of every push; marking it
    // dirty would have no cloud effect. The cross-device avatar
    // handle is `avatar_storage_path`, which the media-service
    // upload below stamps and dirty-marks on its own.
    final dirty = <String>[
      'name',
      'role',
      'notes',
      if (roleId.present) 'role_id',
      if (adultRole.present) 'adult_role',
      if (anchoredGroupId.present) 'anchored_group_id',
      if (phone.present) 'phone',
      if (email.present) 'email',
      if (parentId.present) 'parent_id',
    ];
    await _db.markDirty('adults', id, dirty);
    unawaited(_sync.pushRow(adultsSpec, id));
    if (avatarFile != null && !clearAvatarPath) {
      unawaited(_media.uploadAdultAvatar(id, source: avatarFile));
    }
  }

  /// v40: returns the (at-most-one) Adult linked to [parentId] via
  /// the `adults.parent_id` FK. Used by the parent detail / edit
  /// surfaces to surface the reverse of the staff↔parent bridge
  /// without a dedicated column on Parents. Returns null when no
  /// staff row claims this parent.
  Stream<Adult?> watchAdultLinkedToParent(String parentId) {
    return (_db.select(_db.adults)
          ..where((a) => a.parentId.equals(parentId))
          ..limit(1))
        .watchSingleOrNull();
  }

  Future<void> deleteAdult(String id) async {
    final row = await (_db.select(_db.adults)..where((s) => s.id.equals(id)))
        .getSingleOrNull();
    final programId = row?.programId;
    await (_db.delete(_db.adults)..where((s) => s.id.equals(id))).go();
    if (programId != null) {
      unawaited(
        _sync.pushDelete(spec: adultsSpec, id: id, programId: programId),
      );
    }
  }

  Future<void> deleteAdults(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final rows = await (_db.select(_db.adults)..where((s) => s.id.isIn(list)))
        .get();
    await (_db.delete(_db.adults)..where((s) => s.id.isIn(list))).go();
    for (final r in rows) {
      final programId = r.programId;
      if (programId != null) {
        unawaited(
          _sync.pushDelete(
            spec: adultsSpec,
            id: r.id,
            programId: programId,
          ),
        );
      }
    }
  }

  /// Re-insert a previously-deleted adult row. Used by the undo
  /// snackbar on delete. Cascaded joins (availability rows, day-
  /// timeline blocks, observation authorship by name) aren't
  /// restored — same 5-second-window tradeoff as other restores.
  Future<void> restoreAdult(Adult row) async {
    await _db.into(_db.adults).insertOnConflictUpdate(row);
    unawaited(_sync.pushRow(adultsSpec, row.id));
  }

  /// Batch restore for bulk-undo on the Adults screen.
  Future<void> restoreAdults(Iterable<Adult> rows) async {
    await _db.transaction(() async {
      for (final row in rows) {
        await _db.into(_db.adults).insertOnConflictUpdate(row);
      }
    });
    for (final row in rows) {
      unawaited(_sync.pushRow(adultsSpec, row.id));
    }
  }

  // -------- Availability --------

  Stream<List<AdultAvailabilityData>> watchAvailabilityFor(
    String adultId,
  ) {
    return (_db.select(_db.adultAvailability)
          ..where((a) => a.adultId.equals(adultId))
          ..orderBy([
            (a) => OrderingTerm.asc(a.dayOfWeek),
            (a) => OrderingTerm.asc(a.startTime),
          ]))
        .watch();
  }

  /// All availability rows across every adult. Feeds the whole-
  /// program timeline view — one watched stream instead of N
  /// per-adult subscriptions, which matters once the program has
  /// 10+ adults running across 5 weekdays.
  Stream<List<AdultAvailabilityData>> watchAllAvailability() {
    return (_db.select(_db.adultAvailability)
          ..orderBy([
            (a) => OrderingTerm.asc(a.adultId),
            (a) => OrderingTerm.asc(a.dayOfWeek),
            (a) => OrderingTerm.asc(a.startTime),
          ]))
        .watch();
  }

  Future<List<AdultAvailabilityData>> availabilityFor(
    String adultId,
  ) {
    return (_db.select(_db.adultAvailability)
          ..where((a) => a.adultId.equals(adultId))
          ..orderBy([
            (a) => OrderingTerm.asc(a.dayOfWeek),
            (a) => OrderingTerm.asc(a.startTime),
          ]))
        .get();
  }

  Future<String> addAvailability({
    required String adultId,
    required int dayOfWeek,
    required String startTime,
    required String endTime,
    DateTime? startDate,
    DateTime? endDate,
    String? breakStart,
    String? breakEnd,
    String? lunchStart,
    String? lunchEnd,
  }) async {
    final id = newId();
    await _db.into(_db.adultAvailability).insert(
          AdultAvailabilityCompanion.insert(
            id: id,
            adultId: adultId,
            dayOfWeek: dayOfWeek,
            startTime: startTime,
            endTime: endTime,
            startDate: Value(startDate),
            endDate: Value(endDate),
            breakStart: Value(breakStart),
            breakEnd: Value(breakEnd),
            lunchStart: Value(lunchStart),
            lunchEnd: Value(lunchEnd),
          ),
        );
    // Cascade write — push the parent adult so the new
    // adult_availability row rides along with it through sync.
    unawaited(_sync.pushRow(adultsSpec, adultId));
    return id;
  }

  Future<void> deleteAvailability(String id) async {
    final row = await (_db.select(_db.adultAvailability)
          ..where((a) => a.id.equals(id)))
        .getSingleOrNull();
    await (_db.delete(_db.adultAvailability)
          ..where((a) => a.id.equals(id)))
        .go();
    final adultId = row?.adultId;
    if (adultId != null) {
      unawaited(_sync.pushRow(adultsSpec, adultId));
    }
  }

  /// Replace the whole availability set for a adult in one atomic
  /// write — used by the wizard/edit sheet where the teacher is
  /// editing multiple blocks at once.
  Future<void> replaceAvailability({
    required String adultId,
    required List<AvailabilityInput> blocks,
  }) async {
    await _db.transaction(() async {
      await (_db.delete(_db.adultAvailability)
            ..where((a) => a.adultId.equals(adultId)))
          .go();
      for (final b in blocks) {
        await _db.into(_db.adultAvailability).insert(
              AdultAvailabilityCompanion.insert(
                id: newId(),
                adultId: adultId,
                dayOfWeek: b.dayOfWeek,
                startTime: b.startTime,
                endTime: b.endTime,
                startDate: Value(b.startDate),
                endDate: Value(b.endDate),
                breakStart: Value(b.breakStart),
                breakEnd: Value(b.breakEnd),
                break2Start: Value(b.break2Start),
                break2End: Value(b.break2End),
                lunchStart: Value(b.lunchStart),
                lunchEnd: Value(b.lunchEnd),
              ),
            );
      }
    });
    // Cascade rewrite — push the parent adult so the engine
    // re-reads its full cascade footprint and mirrors to cloud.
    unawaited(_sync.pushRow(adultsSpec, adultId));
  }
}

/// Transport struct for a single availability block, used by the UI
/// while the teacher edits N rows locally.
class AvailabilityInput {
  const AvailabilityInput({
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.startDate,
    this.endDate,
    this.breakStart,
    this.breakEnd,
    this.break2Start,
    this.break2End,
    this.lunchStart,
    this.lunchEnd,
  });

  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final DateTime? startDate;
  final DateTime? endDate;
  // HH:MM short breaks + lunch inside this shift. All nullable —
  // many shifts are short enough to have neither. break2 is a second
  // break window for programs that run morning AND afternoon breaks
  // (schema v35).
  final String? breakStart;
  final String? breakEnd;
  final String? break2Start;
  final String? break2End;
  final String? lunchStart;
  final String? lunchEnd;
}

final adultsRepositoryProvider = Provider<AdultsRepository>((ref) {
  return AdultsRepository(ref.watch(databaseProvider), ref);
});

final adultsProvider = StreamProvider<List<Adult>>((ref) {
  ref.watch(activeProgramIdProvider);
  return ref.watch(adultsRepositoryProvider).watchAll();
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final adultProvider =
    StreamProvider.family<Adult?, String>((ref, id) {
  return ref.watch(adultsRepositoryProvider).watchAdult(id);
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final adultAvailabilityProvider = StreamProvider.family<
    List<AdultAvailabilityData>, String>((ref, adultId) {
  return ref
      .watch(adultsRepositoryProvider)
      .watchAvailabilityFor(adultId);
});

/// Every availability row across the whole program. Used by the
/// program-wide timeline screen — one subscription beats N per-adult
/// family reads.
final allAvailabilityProvider =
    StreamProvider<List<AdultAvailabilityData>>((ref) {
  return ref.watch(adultsRepositoryProvider).watchAllAvailability();
});

/// v40: "which adult (if any) is linked to this parent?" Reverse of
/// `Adults.parentId` — at most one row in practice. Used by the
/// parent detail / edit surfaces to render the "also on staff" chip.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final adultLinkedToParentProvider =
    StreamProvider.family<Adult?, String>((ref, parentId) {
  return ref
      .watch(adultsRepositoryProvider)
      .watchAdultLinkedToParent(parentId);
});
