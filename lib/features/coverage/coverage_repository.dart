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

// ────────────────────────────────────────────────────────────
// Day-wide coverage timeline
// ────────────────────────────────────────────────────────────

extension CoverageTimeline on CoverageRepository {
  /// Sample [coverageAt] across the whole day in [stepMinutes]-
  /// minute increments and return a structure the timeline
  /// widget can paint without further math: per-group, a list of
  /// `(minuteOfDay → adultCount)` samples.
  ///
  /// Default sample interval = 30 min, default span 7am–6pm —
  /// matches the program day. Caller can override both for a
  /// shorter strip on a phone.
  ///
  /// Cost: one role-block read per sample. With 30-min steps over
  /// 11 hours that's 22 reads per day. The role-block tables are
  /// small; this is fine. Future optimization: query once for the
  /// full day, walk in Dart.
  Future<DayCoverage> dayCoverage({
    required DateTime date,
    int startMinute = 7 * 60,
    int endMinute = 18 * 60,
    int stepMinutes = 30,
  }) async {
    final samples = <int>[];
    for (var m = startMinute; m <= endMinute; m += stepMinutes) {
      samples.add(m);
    }

    // Pre-fetch group list so each sample doesn't re-load it.
    // The CoverageRepository itself does that today; for a 22-
    // sample sweep we'll just call it sequentially. The DB cost
    // dominates the JS overhead.
    final perSample = <List<GroupCoverage>>[];
    for (final m in samples) {
      perSample.add(await coverageAt(date: date, minuteOfDay: m));
    }

    // Pivot from sample-major to group-major.
    final byGroup = <String, _GroupTimelineBuilder>{};
    for (var i = 0; i < samples.length; i++) {
      for (final g in perSample[i]) {
        final builder = byGroup.putIfAbsent(
          g.groupId,
          () => _GroupTimelineBuilder(
            groupId: g.groupId,
            groupName: g.groupName,
          ),
        );
        builder.samples.add(CoverageSample(
          minuteOfDay: samples[i],
          count: g.count,
        ));
      }
    }

    final groups = byGroup.values
        .map((b) => GroupCoverageTimeline(
              groupId: b.groupId,
              groupName: b.groupName,
              samples: b.samples,
            ))
        .toList()
      ..sort((a, b) => a.groupName.compareTo(b.groupName));

    return DayCoverage(
      startMinute: startMinute,
      endMinute: endMinute,
      stepMinutes: stepMinutes,
      groups: groups,
    );
  }
}

class _GroupTimelineBuilder {
  _GroupTimelineBuilder({
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;
  final List<CoverageSample> samples = [];
}

class DayCoverage {
  const DayCoverage({
    required this.startMinute,
    required this.endMinute,
    required this.stepMinutes,
    required this.groups,
  });

  final int startMinute;
  final int endMinute;
  final int stepMinutes;
  final List<GroupCoverageTimeline> groups;
}

class GroupCoverageTimeline {
  const GroupCoverageTimeline({
    required this.groupId,
    required this.groupName,
    required this.samples,
  });

  final String groupId;
  final String groupName;
  final List<CoverageSample> samples;
}

class CoverageSample {
  const CoverageSample({
    required this.minuteOfDay,
    required this.count,
  });

  final int minuteOfDay;
  final int count;
}

/// Day-wide coverage for today. autoDispose so a quick swipe
/// away tears it down — coverage data is point-in-time and
/// shouldn't outlive the screen that asked for it.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final coverageDayProvider =
    FutureProvider.autoDispose<DayCoverage>((ref) async {
  ref.watch(activeProgramIdProvider);
  return ref.read(coverageRepositoryProvider).dayCoverage(
        date: DateTime.now(),
      );
});
