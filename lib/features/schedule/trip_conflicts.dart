import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';

/// Why a trip is flagged on the day grid — either it collides with a
/// regular scheduled activity that targets a group on the trip, or
/// two trips on the same day both take the same group.
enum TripConflictKind {
  /// A trip overlaps a scheduled activity that targets a group on the
  /// trip.
  tripOverlapsActivity,

  /// Two trips on the same day share a group.
  tripOverlapsTrip,
}

/// One trip-based conflict. Two flavors — see [TripConflictKind] — but
/// the shape is identical so callers can render both through one row
/// widget in the conflict sheet.
class TripConflict {
  const TripConflict({
    required this.kind,
    required this.reason,
    required this.counterpartId,
  });

  final TripConflictKind kind;
  final String reason;

  /// The *other* side of the clash. For [TripConflictKind.tripOverlapsActivity]
  /// this is the trip id when keyed by activity (or the activity
  /// schedule-item id when keyed by trip). For
  /// [TripConflictKind.tripOverlapsTrip] this is the other trip's id.
  final String counterpartId;
}

/// Two-map result so callers can light up activity cards and trip
/// entries separately without tagging every entry with "which side am
/// I on".
class TripConflictResult {
  const TripConflictResult({
    required this.byActivityId,
    required this.byTripId,
  });

  final Map<String, List<TripConflict>> byActivityId;
  final Map<String, List<TripConflict>> byTripId;

  static const empty = TripConflictResult(
    byActivityId: <String, List<TripConflict>>{},
    byTripId: <String, List<TripConflict>>{},
  );
}

/// Given today's activity items and today's trips (with their group
/// memberships), flag conflicts in both directions.
///
/// Rules:
/// - Trips with no groups (program-wide / "everyone") don't flag
///   activities — conservative default so a blanket trip doesn't
///   scream about every regular activity on the day.
/// - A timed trip without explicit times (`departureTime` /
///   `returnTime` both null) is treated as 00:00–23:59.
/// - Activity-vs-trip: time ranges overlap AND (activity targets
///   "all groups" OR the activity's groups intersect the trip's
///   groups).
/// - Trip-vs-trip: both land on the day, share at least one group,
///   time ranges overlap.
TripConflictResult detectTripConflicts({
  required List<ScheduleItem> scheduleItems,
  required List<Trip> todayTrips,
  required Map<String, List<String>> groupsByTrip,
  required Map<String, Group> groupsById,
}) {
  if (todayTrips.isEmpty) return TripConflictResult.empty;

  final byActivityId = <String, List<TripConflict>>{};
  final byTripId = <String, List<TripConflict>>{};

  // Trip ↔ activity.
  for (final trip in todayTrips) {
    final tripGroups = groupsByTrip[trip.id] ?? const <String>[];
    // Program-wide trips: conservative — don't flag activities. (The
    // user can explicitly add groups to a trip if they want the
    // conflict machinery to fire.)
    if (tripGroups.isEmpty) continue;
    final tripGroupSet = tripGroups.toSet();

    final tripStart = _minutesFromHhmm(trip.departureTime ?? '00:00');
    final tripEnd = _minutesFromHhmm(trip.returnTime ?? '23:59');

    for (final item in scheduleItems) {
      // Skip the schedule entry that's the trip's mirrored row — the
      // trips repo creates a ScheduleEntry for each trip. Matching
      // title + covers the same time window would otherwise double-
      // flag. We approximate by skipping entries whose title equals
      // the trip name AND whose group set matches — good enough;
      // worst case we miss a self-flag.
      if (item.title == trip.name &&
          _groupSetsMatch(item, tripGroupSet)) {
        continue;
      }

      if (item.isNoGroups) continue;

      // Activity's audience overlap with trip groups. All-groups
      // activities match anything; specific groups need an
      // intersection.
      final shares = item.isAllGroups ||
          item.groupIds.toSet().intersection(tripGroupSet).isNotEmpty;
      if (!shares) continue;

      final itemStart = item.isFullDay ? 0 : item.startMinutes;
      final itemEnd = item.isFullDay ? 24 * 60 : item.endMinutes;
      final overlaps = itemStart < tripEnd && tripStart < itemEnd;
      if (!overlaps) continue;

      final sharedNames = item.isAllGroups
          ? tripGroups
              .map((g) => groupsById[g]?.name ?? 'Group')
              .toList()
          : item.groupIds
              .toSet()
              .intersection(tripGroupSet)
              .map((g) => groupsById[g]?.name ?? 'Group')
              .toList();
      final groupLabel = sharedNames.isEmpty
          ? 'shared group'
          : sharedNames.join(', ');
      final range = (trip.departureTime != null && trip.returnTime != null)
          ? '${_fmt(tripStart)}–${_fmt(tripEnd)}'
          : 'all day';
      final reason =
          'Trip "${trip.name}" runs $range covering $groupLabel';

      (byActivityId[item.id] ??= <TripConflict>[]).add(
        TripConflict(
          kind: TripConflictKind.tripOverlapsActivity,
          reason: reason,
          counterpartId: trip.id,
        ),
      );
      // Mirror on the trip side so tap-a-trip also reveals the
      // activity it collides with.
      (byTripId[trip.id] ??= <TripConflict>[]).add(
        TripConflict(
          kind: TripConflictKind.tripOverlapsActivity,
          reason: 'Overlaps "${item.title}" '
              '(${item.isFullDay ? "all day" : "${_fmt(item.startMinutes)}–${_fmt(item.endMinutes)}"})',
          counterpartId: item.id,
        ),
      );
    }
  }

  // Trip ↔ trip.
  for (var i = 0; i < todayTrips.length; i++) {
    for (var j = i + 1; j < todayTrips.length; j++) {
      final a = todayTrips[i];
      final b = todayTrips[j];
      final ag = (groupsByTrip[a.id] ?? const <String>[]).toSet();
      final bg = (groupsByTrip[b.id] ?? const <String>[]).toSet();
      if (ag.isEmpty || bg.isEmpty) continue;
      final shared = ag.intersection(bg);
      if (shared.isEmpty) continue;

      final aStart = _minutesFromHhmm(a.departureTime ?? '00:00');
      final aEnd = _minutesFromHhmm(a.returnTime ?? '23:59');
      final bStart = _minutesFromHhmm(b.departureTime ?? '00:00');
      final bEnd = _minutesFromHhmm(b.returnTime ?? '23:59');
      final overlaps = aStart < bEnd && bStart < aEnd;
      if (!overlaps) continue;

      final groupLabel = shared
          .map((g) => groupsById[g]?.name ?? 'Group')
          .join(', ');
      (byTripId[a.id] ??= <TripConflict>[]).add(
        TripConflict(
          kind: TripConflictKind.tripOverlapsTrip,
          reason:
              'Trip "${a.name}" and "${b.name}" both take $groupLabel',
          counterpartId: b.id,
        ),
      );
      (byTripId[b.id] ??= <TripConflict>[]).add(
        TripConflict(
          kind: TripConflictKind.tripOverlapsTrip,
          reason:
              'Trip "${b.name}" and "${a.name}" both take $groupLabel',
          counterpartId: a.id,
        ),
      );
    }
  }

  return TripConflictResult(
    byActivityId: byActivityId,
    byTripId: byTripId,
  );
}

bool _groupSetsMatch(ScheduleItem item, Set<String> tripGroups) {
  final a = item.groupIds.toSet();
  if (a.length != tripGroups.length) return false;
  return a.containsAll(tripGroups);
}

int _minutesFromHhmm(String hhmm) {
  final parts = hhmm.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

String _fmt(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
  final period = h < 12 ? 'a' : 'p';
  final mm = m == 0 ? '' : ':${m.toString().padLeft(2, '0')}';
  return '$hour12$mm$period';
}
