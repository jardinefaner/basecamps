import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adult_timeline_repository.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/rooms/rooms_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A "group summary" bundles the three things that together describe
/// one self-contained classroom unit:
///
///   - the [Group] of kids that live in it (Butterflies, Ladybugs…)
///   - the lead adults anchored to that group (0, 1, or 2 leads —
///     groups start with two leads at open, and usually one rotates
///     off into the adult pool mid-morning)
///   - the default room that group calls home (nullable — a newly
///     seeded group doesn't have one yet)
///
/// This is the pivot for the group-centric Today view. Data-wise
/// nothing new is stored; every link already exists in the DB.
/// [GroupSummary] just joins them so the UI doesn't have to three-way-
/// correlate lists on every rebuild.
///
/// Named `GroupSummary` (not just `Group`) because Drift's row
/// dataclass for the `groups` table already owns that name.
class GroupSummary {
  const GroupSummary({
    required this.group,
    required this.anchorLeads,
    required this.childCount,
    this.defaultRoom,
  });

  /// The group record — source of name, color, id.
  final Group group;

  /// Adults whose `anchoredGroupId` points at this group AND whose
  /// `adultRole` is `AdultRole.lead`. Sorted by name for stable UI.
  /// Usually 1 or 2; can be 0 (a just-created group waiting for a lead
  /// assignment) or rarely 3+ (multi-lead groups during transitions).
  final List<Adult> anchorLeads;

  /// The room the group calls home, if any. Derived from
  /// `rooms.defaultForGroupId`; returning it here saves every group
  /// card from running its own lookup.
  final Room? defaultRoom;

  /// How many children are currently assigned to this group. Shown in
  /// the collapsed group card ("12 kids") without having to re-filter
  /// the global children list per render.
  final int childCount;

  String get id => group.id;
  String get name => group.name;
}

/// All group summaries currently on file, sorted by group creation
/// order (same as `groupsProvider` — keeps the existing UI ordering
/// intact so screens that adopt summaries don't accidentally
/// reshuffle the world).
///
/// This is a **derived** provider: it watches the existing
/// group/adult/room/children streams and joins them into a
/// `List<GroupSummary>`. It doesn't need its own schema or table;
/// every link is already represented elsewhere.
///
/// The provider stays in `AsyncData` when all four upstreams are
/// ready; reports `AsyncLoading` while any are still loading;
/// surfaces an `AsyncError` on the first upstream error.
final groupSummariesProvider =
    Provider<AsyncValue<List<GroupSummary>>>((ref) {
  final groupsAsync = ref.watch(groupsProvider);
  final adultsAsync = ref.watch(adultsProvider);
  final roomsAsync = ref.watch(roomsProvider);
  final childrenAsync = ref.watch(childrenProvider);

  // First error wins — matches how `AsyncValue.when` handles it.
  // Avoid stuffing heterogeneous AsyncValue<T>s into a shared list
  // (generic inference balks); a direct scan is clearer anyway.
  for (final a in <AsyncValue<Object>>[
    groupsAsync,
    adultsAsync,
    roomsAsync,
    childrenAsync,
  ]) {
    if (a.hasError) {
      return AsyncError(a.error!, a.stackTrace ?? StackTrace.current);
    }
  }

  final groups = groupsAsync.asData?.value;
  final adults = adultsAsync.asData?.value;
  final rooms = roomsAsync.asData?.value;
  final children = childrenAsync.asData?.value;
  if (groups == null ||
      adults == null ||
      rooms == null ||
      children == null) {
    return const AsyncLoading();
  }

  // Index up front so the join is O(n+m) instead of O(n·m) per
  // group. Matters once there are 6+ groups and 40+ kids.
  final leadsByGroup = <String, List<Adult>>{};
  for (final s in adults) {
    if (AdultRole.fromDb(s.adultRole) != AdultRole.lead) continue;
    final anchor = s.anchoredGroupId;
    if (anchor == null) continue;
    (leadsByGroup[anchor] ??= []).add(s);
  }
  for (final list in leadsByGroup.values) {
    list.sort((a, b) => a.name.compareTo(b.name));
  }

  final defaultRoomByGroup = <String, Room>{};
  for (final r in rooms) {
    final g = r.defaultForGroupId;
    if (g == null) continue;
    // If somehow two rooms both claim to be default for the same
    // group, the first one (by room name order — that's how
    // `roomsProvider` sorts) wins. Not great, but "two defaults" is
    // a data-entry bug we'd rather surface in the room editor than
    // paper over silently here.
    defaultRoomByGroup.putIfAbsent(g, () => r);
  }

  final childCountByGroup = <String, int>{};
  for (final k in children) {
    final g = k.groupId;
    if (g == null) continue;
    childCountByGroup[g] = (childCountByGroup[g] ?? 0) + 1;
  }

  final summaries = [
    for (final g in groups)
      GroupSummary(
        group: g,
        anchorLeads: leadsByGroup[g.id] ?? const [],
        defaultRoom: defaultRoomByGroup[g.id],
        childCount: childCountByGroup[g.id] ?? 0,
      ),
  ];
  return AsyncData(summaries);
});

/// Pure check: is [groupId] actually staffed by a lead on [weekday]?
///
/// "Staffed" means at least one adult for whom ALL are true:
///   - they count as a lead for this group today — either statically
///     anchored (role `lead` + anchoredGroupId == groupId) OR have a
///     per-day block ([AdultDayBlock] with role `lead` + groupId
///     matching) for [weekday]
///   - they have at least one [AdultAvailabilityData] row for [weekday]
///     (an anchored lead with zero availability on that day is absent)
///
/// Pure function: no providers, no Drift — easy to unit test and drop
/// straight into a widget that already watches these lists.
bool isGroupStaffedToday({
  required String groupId,
  required int weekday,
  required List<Adult> adults,
  required List<AdultDayBlock> todayDayBlocks,
  required List<AdultAvailabilityData> availability,
}) {
  // Who has availability today? Any single row for this weekday
  // counts — we're answering "is the adult on the clock at all today?"
  // not "are they on the clock right now." The latter is a Today-
  // surface concern.
  final adultsWithAvailabilityToday = <String>{
    for (final a in availability)
      if (a.dayOfWeek == weekday) a.adultId,
  };
  if (adultsWithAvailabilityToday.isEmpty) return false;

  // Adults leading this group today via a per-day block.
  final leadsByBlockToday = <String>{
    for (final b in todayDayBlocks)
      if (b.dayOfWeek == weekday &&
          b.role == AdultBlockRole.lead.dbValue &&
          b.groupId == groupId)
        b.adultId,
  };

  for (final a in adults) {
    final anchorsHere = AdultRole.fromDb(a.adultRole) == AdultRole.lead &&
        a.anchoredGroupId == groupId;
    final leadsHereToday = anchorsHere || leadsByBlockToday.contains(a.id);
    if (!leadsHereToday) continue;
    if (adultsWithAvailabilityToday.contains(a.id)) return true;
  }
  return false;
}

/// A single group summary by group id. Thin wrapper over
/// [groupSummariesProvider]; falls back to `null` when the id doesn't
/// match (group was just deleted, stale route param, etc.) so callers
/// don't have to filter manually.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final groupSummaryProvider =
    Provider.family<AsyncValue<GroupSummary?>, String>((ref, groupId) {
  final allAsync = ref.watch(groupSummariesProvider);
  return allAsync.whenData((summaries) {
    for (final s in summaries) {
      if (s.id == groupId) return s;
    }
    return null;
  });
});
