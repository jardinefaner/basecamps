import 'package:basecamp/features/schedule/conflicts.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';

/// One entry the "Use this sequence" spread would write if it proceeds
/// without further input. Mirrors the fields `addOneOffEntry` cares
/// about so we can faithfully simulate the resulting [ScheduleItem]
/// for the conflict detector.
class ProposedSequenceEntry {
  const ProposedSequenceEntry({
    required this.position,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.title,
    this.adultId,
    this.location,
    this.notes,
    this.sourceLibraryItemId,
    this.sourceUrl,
  });

  /// 1-based day index in the sequence (Day 1, Day 2, …). Used in the
  /// dialog copy so teachers can map bullets back to their list.
  final int position;
  final DateTime date;
  final String startTime;
  final String endTime;
  final String title;
  final String? adultId;
  final String? location;
  final String? notes;
  final String? sourceLibraryItemId;
  final String? sourceUrl;

  /// Synthesize a [ScheduleItem] for conflict detection. The id is a
  /// transient `proposed-<n>` marker so clashes against real items
  /// are keyed distinctly from each other.
  ScheduleItem toScheduleItem() {
    return ScheduleItem(
      id: 'proposed-$position',
      date: date,
      startTime: startTime,
      endTime: endTime,
      isFullDay: false,
      title: title,
      groupIds: const [],
      // Sequence entries inherit the library card's audience model —
      // no explicit groups, broadcast to "all groups". Matches how
      // the live writer emits them via `addOneOffEntry`.
      allGroups: true,
      adultId: adultId,
      location: location,
      notes: notes,
      isFromTemplate: false,
      sourceLibraryItemId: sourceLibraryItemId,
      sourceUrl: sourceUrl,
    );
  }
}

/// Human-readable conflicts detected for one proposed entry.
class SequenceConflict {
  const SequenceConflict({
    required this.position,
    required this.title,
    required this.reasons,
  });

  final int position;
  final String title;

  /// Reason fragments phrased to drop into the dialog's bullet
  /// template: `Day 2: 'Circle Time' <reason>`. Example reason:
  /// "conflicts with existing 'Morning Stretch' on Ms. Park".
  final List<String> reasons;
}

/// Runs the activity-vs-activity conflict detector for each proposed
/// entry against the existing schedule on that date. Returns only the
/// proposals that have at least one conflict, with reasons already
/// rendered as human-readable strings.
List<SequenceConflict> detectSequenceConflicts({
  required List<ProposedSequenceEntry> proposals,
  required Map<DateTime, List<ScheduleItem>> existingByDate,
}) {
  final out = <SequenceConflict>[];
  for (final p in proposals) {
    final proposed = p.toScheduleItem();
    final existing = existingByDate[p.date] ?? const <ScheduleItem>[];
    final combined = <ScheduleItem>[...existing, proposed];
    final map = conflictsByItemId(combined);
    final infos = map[proposed.id];
    if (infos == null || infos.isEmpty) continue;
    final reasons = <String>[
      for (final info in infos) _reasonFor(info),
    ];
    out.add(
      SequenceConflict(
        position: p.position,
        title: p.title,
        reasons: reasons,
      ),
    );
  }
  return out;
}

String _reasonFor(ConflictInfo info) {
  final other = info.other;
  final parts = <String>[];
  if (info.adultClash) {
    // We don't have an adult display name here — the dialog stays
    // title-only, which is enough for teachers to recognise the
    // clash. Name lookup would pull adults_repository in; keep the
    // pre-check dependency-light.
    parts.add('shares the same adult');
  }
  if (info.roomClash) {
    parts.add('same room');
  }
  if (info.groupClash && !info.adultClash && !info.roomClash) {
    parts.add('overlaps the same groups');
  }
  final qualifier = parts.isEmpty ? '' : ' (${parts.join(', ')})';
  return "conflicts with existing '${other.title}'$qualifier";
}
