import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/role_blocks_repository.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Per-group classroom coverage (slice 2 of the rotation feature).
///
/// Layered model: who's scheduled to be in each classroom right
/// now. The data source is the v48 role-block tables —
/// `adult_role_blocks` (recurring weekday pattern) layered with
/// `adult_role_block_overrides` (date-specific substitutions).
///
/// Output is the per-(group × time-slot) head count:
///
///   Lions   09:00-10:00  ✓ 2 in room (Sarah, Maria)
///   Bears   09:00-10:00  ⚠ 1 in room (Marcus)
///   Cubs    09:00-10:00  ✓ 2 in room (Jen, Lily)
///
/// Slice 2 is informational — no validation gates, no RLS — but
/// the same pipeline drives any future "this slot is short
/// staffed" alerts. Coverage is computed for whatever
/// `(date, minute)` the caller asks for; the Today widget queries
/// for "right now" with `DateTime.now()`.
class CoverageRepository {
  CoverageRepository(this._db, this._ref);

  final AppDatabase _db;
  // Reserved for future per-program filtering (today the
  // coverage query is implicitly scoped by Drift's program-id
  // filter on the underlying tables).
  // ignore: unused_field
  final Ref _ref;

  /// Returns [GroupCoverage] for every group in the active
  /// program, scoped to the moment ([date], [minuteOfDay]).
  ///
  /// Algorithm:
  ///   1. Pull every adult's pattern blocks for `date.weekday`.
  ///   2. Pull overrides for `date`.
  ///   3. Layer per adult: if any override with `replaces=true`
  ///      covers the queried minute, the override wins.
  ///      Otherwise the pattern wins.
  ///   4. Group results by `groupId` (skipping off-duty kinds:
  ///      break / lunch / admin which have no group).
  ///
  /// Cost: one read per role-block table for the date in scope —
  /// not a per-group fan-out. Even with 50 adults the query is
  /// hundreds of rows. Aggregation runs in Dart on the result.
  Future<List<GroupCoverage>> coverageAt({
    required DateTime date,
    required int minuteOfDay,
  }) async {
    final dayStart = DateTime(date.year, date.month, date.day);

    final patterns = await (_db.select(_db.adultRoleBlocks)
          ..where((b) =>
              b.weekday.equals(date.weekday) &
              b.startMinute.isSmallerOrEqualValue(minuteOfDay) &
              b.endMinute.isBiggerThanValue(minuteOfDay)))
        .get();

    final overrides = await (_db.select(_db.adultRoleBlockOverrides)
          ..where((o) =>
              o.date.equals(dayStart) &
              o.startMinute.isSmallerOrEqualValue(minuteOfDay) &
              o.endMinute.isBiggerThanValue(minuteOfDay)))
        .get();

    // Resolve per-adult: an override with replaces=true beats a
    // pattern; an override with replaces=false adds on top.
    final assignments = <_Assignment>[];

    final replacedAdults = <String>{};
    for (final o in overrides) {
      if (o.replaces) replacedAdults.add(o.adultId);
    }

    for (final p in patterns) {
      if (replacedAdults.contains(p.adultId)) continue;
      assignments.add(_Assignment(
        adultId: p.adultId,
        kind: RoleBlockKind.fromValue(p.kind),
        groupId: p.groupId,
      ));
    }
    for (final o in overrides) {
      assignments.add(_Assignment(
        adultId: o.adultId,
        kind: RoleBlockKind.fromValue(o.kind),
        groupId: o.groupId,
      ));
    }

    // Group by group id. In-room kinds only.
    final byGroup = <String, List<_Assignment>>{};
    for (final a in assignments) {
      if (!a.kind.isInRoom) continue;
      final gid = a.groupId;
      if (gid == null) continue;
      (byGroup[gid] ??= []).add(a);
    }

    // Pull adult names + group names for display.
    final allGroups = await _db.select(_db.groups).get();
    final adultIds = byGroup.values
        .expand((list) => list.map((a) => a.adultId))
        .toSet()
        .toList();
    final adults = adultIds.isEmpty
        ? <Adult>[]
        : await (_db.select(_db.adults)
              ..where((a) => a.id.isIn(adultIds)))
            .get();
    final adultById = {for (final a in adults) a.id: a};

    // Walk groups in display order (alphabetical). Empty rooms
    // still show up so the UI can surface "0 in this group" — a
    // valid coverage state during full-program off-time.
    final out = <GroupCoverage>[];
    for (final g in allGroups) {
      final list = byGroup[g.id] ?? const <_Assignment>[];
      final adultsInRoom = <CoverageAdult>[
        for (final a in list)
          CoverageAdult(
            adultId: a.adultId,
            name: _displayName(adultById[a.adultId]),
            kind: a.kind,
          ),
      ];
      out.add(GroupCoverage(
        groupId: g.id,
        groupName: g.name,
        adults: adultsInRoom,
      ));
    }
    out.sort((a, b) => a.groupName.compareTo(b.groupName));
    return out;
  }

  static String _displayName(Adult? a) {
    if (a == null) return '(unknown)';
    final raw = a.name.trim();
    if (raw.isEmpty) return '(unnamed)';
    // Compact "First L." form so the coverage strip can list 2-3
    // names per group without overflowing on a phone. If the name
    // is single-word, just return it as-is.
    final parts = raw.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first;
    return '${parts.first} ${parts.last[0]}.';
  }
}

/// Coverage for one classroom at the queried moment.
class GroupCoverage {
  const GroupCoverage({
    required this.groupId,
    required this.groupName,
    required this.adults,
  });

  final String groupId;
  final String groupName;
  final List<CoverageAdult> adults;

  int get count => adults.length;
}

class CoverageAdult {
  const CoverageAdult({
    required this.adultId,
    required this.name,
    required this.kind,
  });

  final String adultId;
  final String name;
  final RoleBlockKind kind;
}

class _Assignment {
  const _Assignment({
    required this.adultId,
    required this.kind,
    required this.groupId,
  });

  final String adultId;
  final RoleBlockKind kind;
  final String? groupId;
}

final coverageRepositoryProvider = Provider<CoverageRepository>((ref) {
  return CoverageRepository(ref.watch(databaseProvider), ref);
});

/// "Coverage right now." Watches the active program so changes
/// to membership / role blocks invalidate the result. Used by
/// the coverage strip on the Today screen.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final coverageNowProvider =
    FutureProvider.autoDispose<List<GroupCoverage>>((ref) async {
  ref.watch(activeProgramIdProvider);
  final now = DateTime.now();
  final minute = now.hour * 60 + now.minute;
  return ref
      .read(coverageRepositoryProvider)
      .coverageAt(date: now, minuteOfDay: minute);
});
