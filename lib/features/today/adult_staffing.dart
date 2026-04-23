import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/specialists/adult_timeline_repository.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';

/// What an adult is doing right at a given moment — derived from
/// their timeline blocks for today, falling back to the static
/// `Specialist.adultRole` + anchor when no blocks exist.
///
/// Value is null in two cases:
///   - No blocks and no static role / shift info could be resolved.
///   - Inside a gap between blocks (implied "off").
/// UI surfaces can show those adults as idle / off-shift.
class AdultCurrentState {
  const AdultCurrentState({
    required this.specialistId,
    required this.role,
    this.podId,
    this.blockStartMinutes,
    this.blockEndMinutes,
  });

  final String specialistId;
  final AdultBlockRole role;

  /// For lead state — which pod (group) they're anchoring right now.
  /// Null for specialist / rotator blocks.
  final String? podId;

  /// Useful for surfaces that want to show "until 11:00" alongside
  /// the current state. Null when derived from static role (no block
  /// bounds are known).
  final int? blockStartMinutes;
  final int? blockEndMinutes;
}

/// Splits `rows` into a per-adult list keyed by specialist id.
/// Used by the derivation pass below to answer per-adult questions
/// without re-scanning the full list each time.
Map<String, List<AdultTimelineBlock>> groupBlocksBySpecialist(
  List<AdultDayBlock> rows,
) {
  final out = <String, List<AdultTimelineBlock>>{};
  for (final r in rows) {
    (out[r.specialistId] ??= []).add(AdultTimelineBlock.fromRow(r));
  }
  // Sort each list by start time so the "first block that straddles
  // now" scan is deterministic (matters for overlapping edits).
  for (final list in out.values) {
    list.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
  }
  return out;
}

/// Resolves [specialist]'s current state at [nowMinutes] on a day
/// that has [blocksForAdult] (possibly empty).
///
/// Rules (in order):
///   1. If any block straddles now, it wins — use its role + podId.
///   2. If blocks exist for today but none straddles now, the adult
///      is between blocks (implied off) → return null.
///   3. If no blocks exist, fall back to the static
///      `Specialist.adultRole`:
///        - lead + anchoredGroupId → lead block covering the whole
///          day (so Today can still show them as anchoring their pod)
///        - specialist → rotating specialist state
///        - ambient → null (ambient adults aren't on the pod grid)
AdultCurrentState? resolveCurrentState({
  required Specialist specialist,
  required List<AdultTimelineBlock> blocksForAdult,
  required int nowMinutes,
}) {
  if (blocksForAdult.isNotEmpty) {
    for (final b in blocksForAdult) {
      if (nowMinutes >= b.startMinutes && nowMinutes < b.endMinutes) {
        return AdultCurrentState(
          specialistId: specialist.id,
          role: b.role,
          podId: b.podId,
          blockStartMinutes: b.startMinutes,
          blockEndMinutes: b.endMinutes,
        );
      }
    }
    // Blocks exist but none covers now → in a gap → off.
    return null;
  }

  // Legacy fallback: no timeline set, interpret the static role.
  final staticRole = AdultRole.fromDb(specialist.adultRole);
  switch (staticRole) {
    case AdultRole.lead:
      if (specialist.anchoredGroupId == null) return null;
      return AdultCurrentState(
        specialistId: specialist.id,
        role: AdultBlockRole.lead,
        podId: specialist.anchoredGroupId,
      );
    case AdultRole.specialist:
      return AdultCurrentState(
        specialistId: specialist.id,
        role: AdultBlockRole.specialist,
      );
    case AdultRole.ambient:
      return null;
  }
}

/// Which adults are currently leading [podId]? Combines timeline
/// resolution with the static anchor fallback so pods with a mix of
/// "scheduled via timeline" and "just a static anchor" leads both
/// show up in the same list.
///
/// Returns specialist ids; caller joins with the full specialists
/// list for display.
Set<String> leadsInPodNow({
  required String podId,
  required int nowMinutes,
  required List<Specialist> specialists,
  required Map<String, List<AdultTimelineBlock>> blocksBySpecialist,
}) {
  final ids = <String>{};
  for (final s in specialists) {
    final blocks = blocksBySpecialist[s.id] ?? const <AdultTimelineBlock>[];
    final state = resolveCurrentState(
      specialist: s,
      blocksForAdult: blocks,
      nowMinutes: nowMinutes,
    );
    if (state == null) continue;
    if (state.role != AdultBlockRole.lead) continue;
    if (state.podId != podId) continue;
    ids.add(s.id);
  }
  return ids;
}
