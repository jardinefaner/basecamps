import 'dart:async';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:basecamp/features/sync/sync_specs.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Repository for the lesson-sequence tables (v40).
///
/// Schema-only this round — no UI consumes these methods yet. Round 4
/// builds the week-planner on top. Kept deliberately thin so the later
/// round can grow the API without renaming what's here.
class LessonSequencesRepository {
  LessonSequencesRepository(this._db, this._ref);

  final AppDatabase _db;
  final Ref _ref;

  /// See ObservationsRepository._programId for why we read this on
  /// every insert rather than caching at construction time.
  String? get _programId => _ref.read(activeProgramIdProvider);

  SyncEngine get _sync => _ref.read(syncEngineProvider);

  // -------- Sequences --------

  Stream<List<LessonSequence>> watchAll() {
    final query = _db.select(_db.lessonSequences)
      ..orderBy([(s) => OrderingTerm.asc(s.name)]);
    return query.watch();
  }

  Future<LessonSequence?> getSequence(String id) {
    return (_db.select(_db.lessonSequences)..where((s) => s.id.equals(id)))
        .getSingleOrNull();
  }

  Future<String> addSequence({
    required String name,
    String? description,
    String? themeId,
    String? coreQuestion,
  }) async {
    final id = newId();
    await _db.into(_db.lessonSequences).insert(
          LessonSequencesCompanion.insert(
            id: id,
            name: name,
            description: Value(description),
            themeId: Value(themeId),
            coreQuestion: Value(coreQuestion),
            programId: Value(_programId),
          ),
        );
    unawaited(_sync.pushRow(lessonSequencesSpec, id));
    return id;
  }

  Future<void> updateSequence({
    required String id,
    String? name,
    Value<String?> description = const Value.absent(),
    Value<String?> themeId = const Value.absent(),
    Value<String?> coreQuestion = const Value.absent(),
  }) async {
    await (_db.update(_db.lessonSequences)..where((s) => s.id.equals(id)))
        .write(
      LessonSequencesCompanion(
        name: name == null ? const Value.absent() : Value(name),
        description: description,
        themeId: themeId,
        coreQuestion: coreQuestion,
        updatedAt: Value(DateTime.now()),
      ),
    );
    unawaited(_sync.pushRow(lessonSequencesSpec, id));
  }

  /// Sequences attached to [themeId], sorted by name (which by
  /// convention encodes the week number — "Week 1: …", "Week 2: …" —
  /// so alphabetical ordering matches week order). The curriculum
  /// view consumes this stream to render the week strip.
  Stream<List<LessonSequence>> watchSequencesForTheme(String themeId) {
    final query = _db.select(_db.lessonSequences)
      ..where((s) => s.themeId.equals(themeId))
      ..orderBy([(s) => OrderingTerm.asc(s.name)]);
    return query.watch();
  }

  Future<void> deleteSequence(String id) async {
    final row = await (_db.select(_db.lessonSequences)
          ..where((s) => s.id.equals(id)))
        .getSingleOrNull();
    final programId = row?.programId;
    await (_db.delete(_db.lessonSequences)..where((s) => s.id.equals(id)))
        .go();
    if (programId != null) {
      unawaited(
        _sync.pushDelete(
          spec: lessonSequencesSpec,
          id: id,
          programId: programId,
        ),
      );
    }
  }

  // -------- Items --------

  /// Ordered items in a sequence. Sorted by `position` ascending so
  /// the planner can render them as a list without re-sorting.
  Stream<List<LessonSequenceItem>> watchItemsFor(String sequenceId) {
    final query = _db.select(_db.lessonSequenceItems)
      ..where((i) => i.sequenceId.equals(sequenceId))
      ..orderBy([(i) => OrderingTerm.asc(i.position)]);
    return query.watch();
  }

  /// Appends [libraryItemId] to the end of [sequenceId]. Position
  /// comes from the max existing position + 1; for an empty sequence
  /// that's 0.
  ///
  /// [dayOfWeek] / [kind] are optional curriculum-arc metadata
  /// (v46). Pass `dayOfWeek: 1..7` (`DateTime.weekday`) and
  /// `kind: 'milestone'` to mark a weekly capstone — leave both off
  /// for legacy free-floating sequence items, which the v46 default
  /// stamps as `kind = 'daily'` with no day.
  Future<String> addItem({
    required String sequenceId,
    required String libraryItemId,
    int? dayOfWeek,
    String? kind,
  }) async {
    final existing = await (_db.select(_db.lessonSequenceItems)
          ..where((i) => i.sequenceId.equals(sequenceId))
          ..orderBy([(i) => OrderingTerm.desc(i.position)])
          ..limit(1))
        .getSingleOrNull();
    final nextPosition = (existing?.position ?? -1) + 1;
    final id = newId();
    await _db.into(_db.lessonSequenceItems).insert(
          LessonSequenceItemsCompanion.insert(
            id: id,
            sequenceId: sequenceId,
            libraryItemId: libraryItemId,
            position: nextPosition,
            dayOfWeek: Value(dayOfWeek),
            // The Drift column has a `Constant('daily')` default so
            // omitting `kind` here lets SQLite write the default; we
            // only override when the caller explicitly asks for one.
            kind: kind == null ? const Value.absent() : Value(kind),
          ),
        );
    // Cascade write — push the parent sequence so the new
    // lesson_sequence_items row is mirrored to cloud.
    unawaited(_sync.pushRow(lessonSequencesSpec, sequenceId));
    return id;
  }

  /// Update curriculum-arc metadata on an existing item (v46).
  /// Used by the curriculum editor to assign / move a card to a
  /// different weekday or convert it from a daily ritual to a
  /// weekly milestone.
  Future<void> updateItemMetadata({
    required String id,
    Value<int?> dayOfWeek = const Value.absent(),
    Value<String> kind = const Value.absent(),
  }) async {
    final row = await (_db.select(_db.lessonSequenceItems)
          ..where((i) => i.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    await (_db.update(_db.lessonSequenceItems)..where((i) => i.id.equals(id)))
        .write(
      LessonSequenceItemsCompanion(
        dayOfWeek: dayOfWeek,
        kind: kind,
      ),
    );
    unawaited(_sync.pushRow(lessonSequencesSpec, row.sequenceId));
  }

  Future<void> deleteItem(String id) async {
    final row = await (_db.select(_db.lessonSequenceItems)
          ..where((i) => i.id.equals(id)))
        .getSingleOrNull();
    await (_db.delete(_db.lessonSequenceItems)..where((i) => i.id.equals(id)))
        .go();
    final sequenceId = row?.sequenceId;
    if (sequenceId != null) {
      unawaited(_sync.pushRow(lessonSequencesSpec, sequenceId));
    }
  }

  /// Fetch a single item by id — used by the undo path on remove.
  Future<LessonSequenceItem?> getItem(String id) {
    return (_db.select(_db.lessonSequenceItems)..where((i) => i.id.equals(id)))
        .getSingleOrNull();
  }

  /// Re-insert a previously-deleted item. Used by confirmDeleteWithUndo
  /// so removals have a 5-second take-back window.
  Future<void> restoreItem(LessonSequenceItem row) async {
    await _db.into(_db.lessonSequenceItems).insertOnConflictUpdate(row);
    unawaited(_sync.pushRow(lessonSequencesSpec, row.sequenceId));
  }

  /// Rewrite `position` for every item in [sequenceId] so the order
  /// matches [itemIdsInNewOrder]. Done in one transaction — positions
  /// land 0..N-1 matching the passed list. Unlisted ids are ignored
  /// (caller is responsible for passing every item).
  Future<void> reorderItems(
    String sequenceId,
    List<String> itemIdsInNewOrder,
  ) async {
    await _db.transaction(() async {
      for (var i = 0; i < itemIdsInNewOrder.length; i++) {
        final itemId = itemIdsInNewOrder[i];
        await (_db.update(_db.lessonSequenceItems)
              ..where((row) =>
                  row.id.equals(itemId) &
                  row.sequenceId.equals(sequenceId)))
            .write(LessonSequenceItemsCompanion(position: Value(i)));
      }
    });
    // Cascade rewrite — push the parent sequence so cloud's
    // cascade table reflects the new ordering.
    unawaited(_sync.pushRow(lessonSequencesSpec, sequenceId));
  }

  /// Stream every (item, libraryItem) pair for a sequence, ordered by
  /// position. The detail screen needs the joined library row so it
  /// can render real titles / durations without a second per-row
  /// FutureProvider lookup.
  Stream<List<SequenceItemWithLibrary>> watchItemsJoined(String sequenceId) {
    final query = _db.select(_db.lessonSequenceItems).join([
      innerJoin(
        _db.activityLibrary,
        _db.activityLibrary.id.equalsExp(_db.lessonSequenceItems.libraryItemId),
      ),
    ])
      ..where(_db.lessonSequenceItems.sequenceId.equals(sequenceId))
      ..orderBy([OrderingTerm.asc(_db.lessonSequenceItems.position)]);

    return query.watch().map((rows) {
      return [
        for (final row in rows)
          SequenceItemWithLibrary(
            item: row.readTable(_db.lessonSequenceItems),
            library: row.readTable(_db.activityLibrary),
          ),
      ];
    });
  }

  /// Curriculum-arc shape (v46) — the joined items in [sequenceId]
  /// grouped into a 5-day weekday plan plus a milestone bucket.
  /// `dailyByWeekday` keys are 1..5 (Mon..Fri); items with no
  /// `dayOfWeek` get tucked into `dailyUnscheduled` (rendered as
  /// "anytime this week" by the curriculum view). Items with
  /// `kind == 'milestone'` go into `milestones`.
  ///
  /// Why a derived shape instead of multiple watchers: the
  /// curriculum view needs all four slots together to render a
  /// single week card, and pulling once + grouping in Dart is
  /// cheaper than 6 separate streams that all rebuild the same UI.
  Stream<WeekArc> watchWeekArc(String sequenceId) {
    return watchItemsJoined(sequenceId).map(WeekArc.fromItems);
  }
}

/// Curriculum-arc projection of one sequence's items.
class WeekArc {
  const WeekArc({
    required this.dailyByWeekday,
    required this.dailyUnscheduled,
    required this.milestones,
  });

  /// Project a flat joined-item list into the curriculum-arc shape:
  /// items grouped by weekday, milestones split off, and any daily
  /// item without a weekday assignment bucketed into "unscheduled".
  factory WeekArc.fromItems(List<SequenceItemWithLibrary> items) {
    final byDay = <int, List<SequenceItemWithLibrary>>{};
    final unscheduled = <SequenceItemWithLibrary>[];
    final milestones = <SequenceItemWithLibrary>[];
    for (final entry in items) {
      if (entry.item.kind == 'milestone') {
        milestones.add(entry);
        continue;
      }
      final day = entry.item.dayOfWeek;
      if (day == null) {
        unscheduled.add(entry);
      } else {
        (byDay[day] ??= []).add(entry);
      }
    }
    return WeekArc(
      dailyByWeekday: byDay,
      dailyUnscheduled: unscheduled,
      milestones: milestones,
    );
  }

  /// 1=Mon … 5=Fri → ordered list of activities for that day.
  final Map<int, List<SequenceItemWithLibrary>> dailyByWeekday;

  /// Daily items the curriculum author hasn't pinned to a weekday.
  final List<SequenceItemWithLibrary> dailyUnscheduled;

  /// `kind == 'milestone'` items — the weekly capstone share-out.
  final List<SequenceItemWithLibrary> milestones;
}

/// Joined sequence-item + library-row pair used by the detail screen
/// so it can render each row with its real title / duration without
/// a separate lookup per row.
class SequenceItemWithLibrary {
  const SequenceItemWithLibrary({required this.item, required this.library});

  final LessonSequenceItem item;
  final ActivityLibraryData library;
}

final lessonSequencesRepositoryProvider =
    Provider<LessonSequencesRepository>((ref) {
  return LessonSequencesRepository(ref.watch(databaseProvider), ref);
});

final lessonSequencesProvider =
    StreamProvider<List<LessonSequence>>((ref) {
  return ref.watch(lessonSequencesRepositoryProvider).watchAll();
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final lessonSequenceItemsProvider =
    StreamProvider.family<List<LessonSequenceItem>, String>(
  (ref, sequenceId) {
    return ref
        .watch(lessonSequencesRepositoryProvider)
        .watchItemsFor(sequenceId);
  },
);

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final lessonSequenceItemsJoinedProvider =
    StreamProvider.family<List<SequenceItemWithLibrary>, String>(
  (ref, sequenceId) {
    return ref
        .watch(lessonSequencesRepositoryProvider)
        .watchItemsJoined(sequenceId);
  },
);

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final lessonSequenceProvider =
    FutureProvider.family<LessonSequence?, String>(
  (ref, id) {
    return ref.watch(lessonSequencesRepositoryProvider).getSequence(id);
  },
);

/// Sequences belonging to a theme — drives the curriculum view's
/// week strip (each sequence is one "week" in the multi-week arc).
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final lessonSequencesForThemeProvider =
    StreamProvider.family<List<LessonSequence>, String>(
  (ref, themeId) {
    return ref
        .watch(lessonSequencesRepositoryProvider)
        .watchSequencesForTheme(themeId);
  },
);

/// Curriculum-arc projection — daily/milestone-grouped items for
/// one sequence (one "week" in the curriculum view).
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final weekArcProvider = StreamProvider.family<WeekArc, String>(
  (ref, sequenceId) {
    return ref.watch(lessonSequencesRepositoryProvider).watchWeekArc(sequenceId);
  },
);
