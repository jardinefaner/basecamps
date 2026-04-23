import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/rooms/rooms_repository.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A "pod" bundles the three things that together describe one
/// self-contained classroom unit:
///
///   - the [Group] of kids that live in it (Butterflies, Ladybycs…)
///   - the lead adults anchored to that group (0, 1, or 2 leads —
///     pods start with two leads at open, and usually one rotates off
///     into the specialist pool mid-morning)
///   - the default room that group calls home (nullable — a newly
///     seeded group doesn't have one yet)
///
/// This is the pivot for the pod-centric Today view. Data-wise nothing
/// new is stored; every link already exists in the DB. Pod just joins
/// them so the UI doesn't have to three-way-correlate lists on every
/// rebuild.
class Pod {
  const Pod({
    required this.group,
    required this.anchorLeads,
    required this.childCount,
    this.defaultRoom,
  });

  /// The group record — source of name, color, id.
  final Group group;

  /// Specialists whose `anchoredGroupId` points at this group AND whose
  /// `adultRole` is `AdultRole.lead`. Sorted by name for stable UI.
  /// Usually 1 or 2; can be 0 (a just-created group waiting for a lead
  /// assignment) or rarely 3+ (multi-lead pods during transitions).
  final List<Specialist> anchorLeads;

  /// The room the group calls home, if any. Derived from
  /// `rooms.defaultForGroupId`; returning it here saves every pod card
  /// from running its own lookup.
  final Room? defaultRoom;

  /// How many children are currently assigned to this group. Shown in
  /// the collapsed pod card ("12 kids") without having to re-filter the
  /// global children list per render.
  final int childCount;

  String get id => group.id;
  String get name => group.name;
}

/// All pods currently on file, sorted by group creation order (same
/// as `groupsProvider` — keeps the existing UI ordering intact so
/// screens that adopt pods don't accidentally reshuffle the world).
///
/// This is a **derived** provider: it watches the existing
/// group/specialist/room/children streams and joins them into a
/// `List<Pod>`. It doesn't need its own schema or table; every link is
/// already represented elsewhere.
///
/// The provider stays in `AsyncData` when all four upstreams are
/// ready; reports `AsyncLoading` while any are still loading;
/// surfaces an `AsyncError` on the first upstream error.
final podsProvider = Provider<AsyncValue<List<Pod>>>((ref) {
  final groupsAsync = ref.watch(groupsProvider);
  final specialistsAsync = ref.watch(specialistsProvider);
  final roomsAsync = ref.watch(roomsProvider);
  final childrenAsync = ref.watch(childrenProvider);

  // First error wins — matches how `AsyncValue.when` handles it.
  // Avoid stuffing heterogeneous AsyncValue<T>s into a shared list
  // (generic inference balks); a direct scan is clearer anyway.
  for (final a in <AsyncValue<Object>>[
    groupsAsync,
    specialistsAsync,
    roomsAsync,
    childrenAsync,
  ]) {
    if (a.hasError) {
      return AsyncError(a.error!, a.stackTrace ?? StackTrace.current);
    }
  }

  final groups = groupsAsync.asData?.value;
  final specialists = specialistsAsync.asData?.value;
  final rooms = roomsAsync.asData?.value;
  final children = childrenAsync.asData?.value;
  if (groups == null ||
      specialists == null ||
      rooms == null ||
      children == null) {
    return const AsyncLoading();
  }

  // Index up front so the join is O(n+m) instead of O(n·m) per pod.
  // Matters once there are 6+ pods and 40+ kids.
  final leadsByGroup = <String, List<Specialist>>{};
  for (final s in specialists) {
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

  final pods = [
    for (final g in groups)
      Pod(
        group: g,
        anchorLeads: leadsByGroup[g.id] ?? const [],
        defaultRoom: defaultRoomByGroup[g.id],
        childCount: childCountByGroup[g.id] ?? 0,
      ),
  ];
  return AsyncData(pods);
});

/// A single pod by group id. Thin wrapper over [podsProvider]; falls
/// back to `null` when the id doesn't match (group was just deleted,
/// stale route param, etc.) so callers don't have to filter manually.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final podProvider = Provider.family<AsyncValue<Pod?>, String>((ref, groupId) {
  final allAsync = ref.watch(podsProvider);
  return allAsync.whenData((pods) {
    for (final p in pods) {
      if (p.id == groupId) return p;
    }
    return null;
  });
});
