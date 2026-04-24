import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adult_timeline_repository.dart';
import 'package:basecamp/features/adults/adults_repository.dart';

/// What an adult is doing right at a given moment — derived from
/// their timeline blocks for today, falling back to the static
/// `Adult.adultRole` + anchor when no blocks exist.
///
/// Value is null in two cases:
///   - No blocks and no static role / shift info could be resolved.
///   - Inside a gap between blocks (implied "off").
/// UI surfaces can show those adults as idle / off-shift.
class AdultCurrentState {
  const AdultCurrentState({
    required this.adultId,
    required this.role,
    this.groupId,
    this.blockStartMinutes,
    this.blockEndMinutes,
  });

  final String adultId;
  final AdultBlockRole role;

  /// For lead state — which group (group) they're anchoring right now.
  /// Null for adult / rotator blocks.
  final String? groupId;

  /// Useful for surfaces that want to show "until 11:00" alongside
  /// the current state. Null when derived from static role (no block
  /// bounds are known).
  final int? blockStartMinutes;
  final int? blockEndMinutes;
}

/// Splits `rows` into a per-adult list keyed by adult id.
/// Used by the derivation pass below to answer per-adult questions
/// without re-scanning the full list each time.
Map<String, List<AdultTimelineBlock>> groupBlocksByAdult(
  List<AdultDayBlock> rows,
) {
  final out = <String, List<AdultTimelineBlock>>{};
  for (final r in rows) {
    (out[r.adultId] ??= []).add(AdultTimelineBlock.fromRow(r));
  }
  // Sort each list by start time so the "first block that straddles
  // now" scan is deterministic (matters for overlapping edits).
  for (final list in out.values) {
    list.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
  }
  return out;
}

/// Resolves [adult]'s current state at [nowMinutes] on a day
/// that has [blocksForAdult] (possibly empty).
///
/// Rules (in order):
///   1. If any block straddles now, it wins — use its role + groupId.
///   2. If blocks exist for today but none straddles now, the adult
///      is between blocks (implied off) → return null.
///   3. If no blocks exist, fall back to the static
///      `Adult.adultRole`:
///        - lead + anchoredGroupId → lead block covering the whole
///          day (so Today can still show them as anchoring their group)
///        - adult → rotating adult state
///        - ambient → null (ambient adults aren't on the group grid)
AdultCurrentState? resolveCurrentState({
  required Adult adult,
  required List<AdultTimelineBlock> blocksForAdult,
  required int nowMinutes,
}) {
  if (blocksForAdult.isNotEmpty) {
    for (final b in blocksForAdult) {
      if (nowMinutes >= b.startMinutes && nowMinutes < b.endMinutes) {
        return AdultCurrentState(
          adultId: adult.id,
          role: b.role,
          groupId: b.groupId,
          blockStartMinutes: b.startMinutes,
          blockEndMinutes: b.endMinutes,
        );
      }
    }
    // Blocks exist but none covers now → in a gap → off.
    return null;
  }

  // Legacy fallback: no timeline set, interpret the static role.
  final staticRole = AdultRole.fromDb(adult.adultRole);
  switch (staticRole) {
    case AdultRole.lead:
      if (adult.anchoredGroupId == null) return null;
      return AdultCurrentState(
        adultId: adult.id,
        role: AdultBlockRole.lead,
        groupId: adult.anchoredGroupId,
      );
    case AdultRole.specialist:
      return AdultCurrentState(
        adultId: adult.id,
        role: AdultBlockRole.specialist,
      );
    case AdultRole.ambient:
      return null;
  }
}

/// Which adults are currently leading [groupId]? Combines timeline
/// resolution with the static anchor fallback so groups with a mix of
/// "scheduled via timeline" and "just a static anchor" leads both
/// show up in the same list.
///
/// Returns adult ids; caller joins with the full adults
/// list for display.
Set<String> leadsInGroupNow({
  required String groupId,
  required int nowMinutes,
  required List<Adult> adults,
  required Map<String, List<AdultTimelineBlock>> blocksByAdult,
}) {
  final ids = <String>{};
  for (final s in adults) {
    final blocks = blocksByAdult[s.id] ?? const <AdultTimelineBlock>[];
    final state = resolveCurrentState(
      adult: s,
      blocksForAdult: blocks,
      nowMinutes: nowMinutes,
    );
    if (state == null) continue;
    if (state.role != AdultBlockRole.lead) continue;
    if (state.groupId != groupId) continue;
    ids.add(s.id);
  }
  return ids;
}
