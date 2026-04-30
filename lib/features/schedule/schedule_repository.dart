import 'dart:async';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/core/now_tick.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/program_scope.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/schedule/week_days.dart';
import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:basecamp/features/sync/sync_specs.dart';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A resolved schedule item for a given day, sourced either from a template
/// or from a per-date entry (addition or override).
class ScheduleItem {
  const ScheduleItem({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.isFullDay,
    required this.title,
    required this.isFromTemplate,
    required this.groupIds,
    required this.allGroups,
    required this.date,
    this.rangeStart,
    this.rangeEnd,
    this.adultId,
    this.location,
    this.notes,
    this.templateId,
    this.entryId,
    this.sourceLibraryItemId,
    this.roomId,
    this.sourceUrl,
    this.sourceTripId,
  });

  final String id;
  final String startTime;
  final String endTime;
  final bool isFullDay;
  final String title;
  final List<String> groupIds;

  /// True when the teacher meant "this is for everyone"; false when
  /// they either picked specific groups or explicitly picked none (staff
  /// prep, etc). Only meaningful when [groupIds] is empty — non-empty
  /// always narrows to those groups regardless.
  final bool allGroups;
  final String? adultId;
  final String? location;
  final String? notes;
  final bool isFromTemplate;
  final String? templateId;
  final String? entryId;

  /// When the teacher created this activity via "From library", this
  /// holds the library row's id so the Today detail sheet can link
  /// back to the full activity card (hook / summary / key points /
  /// learning goals / source URL). Null for activities typed from
  /// scratch.
  final String? sourceLibraryItemId;

  /// Tracked-room reference (v28). When set, this is the authoritative
  /// location — the free-form [location] string is a display fallback
  /// and ad-hoc note escape hatch. Room conflict detection fires when
  /// two items share the same [roomId] at overlapping times.
  final String? roomId;

  /// v40: per-occurrence reference link (recipe URL, lesson plan,
  /// article). Rendered tappably on the detail sheet when set.
  /// Independent of any library-card back-reference.
  final String? sourceUrl;

  /// Set on schedule entries that mirror a trip — when a teacher
  /// creates a trip we also write a `schedule_entries` row with
  /// `source_trip_id` pointing back at the trip. Without this
  /// flag flowing through to [ScheduleItem], the today-agenda
  /// rendered the trip twice (once from `trips`, once from the
  /// mirrored schedule entry). Today agenda filters mirror entries
  /// out so the trip card from `trips` is the canonical one;
  /// schedule editor / week views still show them so the row is
  /// editable in the schedule context too.
  final String? sourceTripId;

  /// The concrete calendar date this item renders on. Set by the
  /// repository while expanding templates and entries into day-
  /// specific slots, so tap handlers can tell "Art on April 21" from
  /// "Art on April 23" when the same template produces both.
  final DateTime date;

  /// For multi-day entries: the entry's original start / end dates.
  /// Both null for templates and for single-day entries. When set the
  /// detail sheet shows a "spans N days" pill and the delete flow
  /// warns that removing the row drops every day in the range.
  final DateTime? rangeStart;
  final DateTime? rangeEnd;

  bool get isMultiDay => rangeEnd != null && rangeStart != null;

  bool get isOneOff => !isFromTemplate;

  /// Resolved audience flag. When specific groups are picked those take
  /// precedence; otherwise respect the explicit "all groups" choice.
  bool get isAllGroups => groupIds.isEmpty && allGroups;

  /// Intentionally empty audience — the teacher picked no groups and
  /// turned off "All groups". Used by readers to show "no children" instead
  /// of falling back to everyone.
  bool get isNoGroups => groupIds.isEmpty && !allGroups;

  TimeOfDay get startTimeOfDay => _parseTime(startTime);
  TimeOfDay get endTimeOfDay => _parseTime(endTime);
  int get startMinutes => startTimeOfDay.hour * 60 + startTimeOfDay.minute;
  int get endMinutes => endTimeOfDay.hour * 60 + endTimeOfDay.minute;

  static TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
  }
}

class ScheduleRepository {
  ScheduleRepository(this._db, this._ref);

  final AppDatabase _db;
  final Ref _ref;

  /// See ObservationsRepository._programId for why we read this on
  /// every insert rather than caching at construction time.
  String? get _programId => _ref.read(activeProgramIdProvider);

  SyncEngine get _sync => _ref.read(syncEngineProvider);

  Stream<List<ScheduleTemplate>> watchTemplates() {
    final query = _db.select(_db.scheduleTemplates)
      ..where((t) => matchesActiveProgram(t.programId, _programId))
      ..orderBy([
        (t) => OrderingTerm.asc(t.dayOfWeek),
        (t) => OrderingTerm.asc(t.startTime),
      ]);
    return query.watch();
  }

  /// Templates assigned to one adult, weekly-ordered. Feeds the
  /// "What they run" section on the adult detail screen.
  Stream<List<ScheduleTemplate>> watchTemplatesForAdult(
    String adultId,
  ) {
    final query = _db.select(_db.scheduleTemplates)
      ..where((t) =>
          t.adultId.equals(adultId) &
          matchesActiveProgram(t.programId, _programId))
      ..orderBy([
        (t) => OrderingTerm.asc(t.dayOfWeek),
        (t) => OrderingTerm.asc(t.startTime),
      ]);
    return query.watch();
  }

  Future<List<ScheduleTemplate>> templatesForDay(int dayOfWeek) {
    final query = _db.select(_db.scheduleTemplates)
      ..where((t) =>
          t.dayOfWeek.equals(dayOfWeek) &
          matchesActiveProgram(t.programId, _programId))
      ..orderBy([(t) => OrderingTerm.asc(t.startTime)]);
    return query.get();
  }

  Future<ScheduleTemplate?> getTemplate(String id) {
    return (_db.select(_db.scheduleTemplates)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Stream of all templates mapped to [ScheduleItem]s (with their group ids
  /// resolved) grouped by weekday. Used by the editor for display and for
  /// conflict detection.
  Stream<Map<int, List<ScheduleItem>>> watchTemplateItemsByDay() {
    return watchTemplates().asyncMap((templates) async {
      final byDay = <int, List<ScheduleItem>>{};
      for (final t in templates) {
        final groups = await groupsForTemplate(t.id);
        // Date is meaningless for the weekly-template view — callers
        // that care about concrete dates use `watchScheduleForWeek` or
        // `watchScheduleForDate`. Sentinel keeps the field non-null.
        final item = ScheduleItem(
          id: t.id,
          date: DateTime(1970),
          startTime: t.startTime,
          endTime: t.endTime,
          isFullDay: t.isFullDay,
          title: t.title,
          groupIds: groups,
          allGroups: t.allGroups,
          adultId: t.adultId,
          location: t.location,
          notes: t.notes,
          isFromTemplate: true,
          templateId: t.id,
          sourceLibraryItemId: t.sourceLibraryItemId,
          roomId: t.roomId,
          sourceUrl: t.sourceUrl,
        );
        byDay.putIfAbsent(t.dayOfWeek, () => []).add(item);
      }
      for (final list in byDay.values) {
        list.sort((a, b) {
          if (a.isFullDay != b.isFullDay) return a.isFullDay ? -1 : 1;
          return a.startMinutes.compareTo(b.startMinutes);
        });
      }
      return byDay;
    });
  }

  Future<List<String>> groupsForTemplate(String templateId) async {
    final rows = await (_db.select(_db.templateGroups)
          ..where((p) => p.templateId.equals(templateId)))
        .get();
    return rows.map((r) => r.groupId).toList();
  }

  /// Stream of [groupsForTemplate] for [templateId]. Lets the
  /// schedule editor and any group-chip rendering refresh on
  /// cross-device pivots without polling. Equivalent to the old
  /// FutureProvider but driven by Drift's table-watch.
  Stream<List<String>> watchGroupsForTemplate(String templateId) {
    return (_db.select(_db.templateGroups)
          ..where((p) => p.templateId.equals(templateId)))
        .watch()
        .map((rows) => rows.map((r) => r.groupId).toList());
  }

  Future<List<String>> groupsForEntry(String entryId) async {
    final rows = await (_db.select(_db.entryGroups)
          ..where((p) => p.entryId.equals(entryId)))
        .get();
    return rows.map((r) => r.groupId).toList();
  }

  Future<String?> latestEndTimeForDay(int dayOfWeek) async {
    final templates = await templatesForDay(dayOfWeek);
    final timed = templates.where((t) => !t.isFullDay).toList();
    if (timed.isEmpty) return null;
    timed.sort((a, b) => _compareTime(b.endTime, a.endTime));
    return timed.first.endTime;
  }

  Future<String> addTemplate({
    required int dayOfWeek,
    required String startTime,
    required String endTime,
    required String title,
    List<String> groupIds = const [],
    bool allGroups = true,
    bool isFullDay = false,
    String? adultId,
    String? location,
    String? notes,
    DateTime? startDate,
    DateTime? endDate,
    // Series id for "delete every occurrence" — wizard stamps one per
    // multi-day create pass. Renamed from `groupId` in schema v25
    // because that name now refers to the people-group reference.
    String? seriesId,
    // Back-reference to the activity library row (when the teacher
    // picked "From library"). Null for typed-from-scratch activities.
    String? sourceLibraryItemId,
    // Tracked-room FK (v28). When set, drives room conflict detection
    // and overrides the free-form [location] string for display.
    String? roomId,
    // v40: free-text reference URL (recipe, lesson plan, article).
    // Persists alongside the other display fields; the detail sheet
    // renders it tappably via url_launcher when set.
    String? sourceUrl,
  }) async {
    final id = newId();
    await _db.transaction(() async {
      await _db.into(_db.scheduleTemplates).insert(
            ScheduleTemplatesCompanion.insert(
              id: id,
              dayOfWeek: dayOfWeek,
              startTime: startTime,
              endTime: endTime,
              isFullDay: Value(isFullDay),
              title: title,
              allGroups: Value(allGroups),
              adultId: Value(adultId),
              location: Value(location),
              notes: Value(notes),
              startDate: Value(startDate == null ? null : _dayOnly(startDate)),
              endDate: Value(endDate == null ? null : _dayOnly(endDate)),
              seriesId: Value(seriesId),
              sourceLibraryItemId: Value(sourceLibraryItemId),
              roomId: Value(roomId),
              sourceUrl: Value(sourceUrl),
              programId: Value(_programId),
            ),
          );
      for (final groupId in groupIds) {
        await _db.into(_db.templateGroups).insert(
              TemplateGroupsCompanion.insert(templateId: id, groupId: groupId),
            );
      }
    });
    unawaited(_sync.pushRow(scheduleTemplatesSpec, id));
    return id;
  }

  Future<void> updateTemplate({
    required String id,
    required int dayOfWeek,
    required String startTime,
    required String endTime,
    required String title,
    List<String> groupIds = const [],
    bool allGroups = true,
    bool isFullDay = false,
    String? adultId,
    String? location,
    String? notes,
    DateTime? startDate,
    DateTime? endDate,
    // Value.absent() so the existing edit sheet (which doesn't know
    // about rooms yet) doesn't accidentally clear roomId on save.
    Value<String?> roomId = const Value.absent(),
    // Same absent-unless-set pattern — the library-promotion flow
    // rewrites this to wire a one-off template up to a freshly
    // created library card, but every other edit leaves it alone.
    Value<String?> sourceLibraryItemId = const Value.absent(),
  }) async {
    await _db.transaction(() async {
      await (_db.update(_db.scheduleTemplates)
            ..where((t) => t.id.equals(id)))
          .write(
        ScheduleTemplatesCompanion(
          dayOfWeek: Value(dayOfWeek),
          startTime: Value(startTime),
          endTime: Value(endTime),
          isFullDay: Value(isFullDay),
          title: Value(title),
          allGroups: Value(allGroups),
          adultId: Value(adultId),
          location: Value(location),
          notes: Value(notes),
          startDate: Value(startDate == null ? null : _dayOnly(startDate)),
          endDate: Value(endDate == null ? null : _dayOnly(endDate)),
          roomId: roomId,
          sourceLibraryItemId: sourceLibraryItemId,
          updatedAt: Value(DateTime.now()),
        ),
      );
      await (_db.delete(_db.templateGroups)
            ..where((p) => p.templateId.equals(id)))
          .go();
      for (final groupId in groupIds) {
        await _db.into(_db.templateGroups).insert(
              TemplateGroupsCompanion.insert(templateId: id, groupId: groupId),
            );
      }
    });
    // updateTemplate is a wholesale edit — the form sheet always
    // passes every visible field — so mark them all dirty. The
    // partial-UPDATE path still pushes only the marked columns
    // (no surprise extra fields), and methods that set just one
    // column (e.g. setTemplateSourceLibraryItem) get tighter
    // partial pushes that don't disturb other fields.
    await _db.markDirty('schedule_templates', id, [
      'day_of_week',
      'start_time',
      'end_time',
      'is_full_day',
      'title',
      'all_groups',
      'adult_id',
      'location',
      'notes',
      'start_date',
      'end_date',
      if (roomId.present) 'room_id',
      if (sourceLibraryItemId.present) 'source_library_item_id',
    ]);
    unawaited(_sync.pushRow(scheduleTemplatesSpec, id));
  }

  /// Wire an existing template row to a library card without touching
  /// any of its other fields. Used by the "Save to library" promotion
  /// flow on activity detail: we create a fresh card from the
  /// template's data, then rewire the back-link so the title tap on
  /// the detail sheet routes to the new card.
  Future<void> setTemplateSourceLibraryItem({
    required String templateId,
    required String? libraryItemId,
  }) async {
    await (_db.update(_db.scheduleTemplates)
          ..where((t) => t.id.equals(templateId)))
        .write(
      ScheduleTemplatesCompanion(
        sourceLibraryItemId: Value(libraryItemId),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _db.markDirty('schedule_templates', templateId,
        ['source_library_item_id']);
    unawaited(_sync.pushRow(scheduleTemplatesSpec, templateId));
  }

  /// Mirror of [setTemplateSourceLibraryItem] for one-off entries.
  Future<void> setEntrySourceLibraryItem({
    required String entryId,
    required String? libraryItemId,
  }) async {
    await (_db.update(_db.scheduleEntries)
          ..where((e) => e.id.equals(entryId)))
        .write(
      ScheduleEntriesCompanion(
        sourceLibraryItemId: Value(libraryItemId),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _db.markDirty('schedule_entries', entryId,
        ['source_library_item_id']);
    unawaited(_sync.pushRow(scheduleEntriesSpec, entryId));
  }

  Future<void> deleteTemplate(String id) async {
    final row = await (_db.select(_db.scheduleTemplates)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    final programId = row?.programId;
    await (_db.delete(_db.scheduleTemplates)..where((t) => t.id.equals(id)))
        .go();
    if (programId != null) {
      unawaited(
        _sync.pushDelete(
          spec: scheduleTemplatesSpec,
          id: id,
          programId: programId,
        ),
      );
    }
  }

  /// Deletes every template that represents the same activity as the
  /// one with this id — i.e. every weekday-row of the "Mon + Wed + Fri
  /// Art" set the wizard created together. New rows use the explicit
  /// `groupId` column; legacy rows (created before group tracking was
  /// added, and single-day templates) fall back to a shape match on
  /// title + startTime + endTime.
  Future<int> deleteTemplateGroupFor(String id) async {
    final siblings = await _siblingTemplatesFor(id);
    if (siblings.isEmpty) return 0;
    final count = await (_db.delete(_db.scheduleTemplates)
          ..where((t) => t.id.isIn(siblings.map((r) => r.id))))
        .go();
    for (final r in siblings) {
      final programId = r.programId;
      if (programId != null) {
        unawaited(
          _sync.pushDelete(
            spec: scheduleTemplatesSpec,
            id: r.id,
            programId: programId,
          ),
        );
      }
    }
    return count;
  }

  /// Count of templates the "delete every occurrence" confirmation
  /// will actually remove — the shape-aware group size.
  Future<int> countTemplatesInGroupFor(String id) async {
    final siblings = await _siblingTemplatesFor(id);
    return siblings.length;
  }

  /// Returns every template that belongs to the same activity group
  /// as the row with this id. Series identity is:
  ///   - `seriesId` when set (authoritative; wizard stamps a fresh one
  ///     per create pass),
  ///   - otherwise same (title, startTime, endTime) pre-migration.
  /// The tapped row is always included in the result.
  /// Public wrapper — used by the undo snackbar to snapshot the
  /// sibling set BEFORE `deleteTemplateGroupFor` drops them, so the
  /// whole recurring pattern can be restored in one transaction.
  Future<List<ScheduleTemplate>> siblingTemplatesFor(String id) =>
      _siblingTemplatesFor(id);

  Future<List<ScheduleTemplate>> _siblingTemplatesFor(String id) async {
    final row = await (_db.select(_db.scheduleTemplates)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return const [];
    final series = row.seriesId;
    if (series != null) {
      return (_db.select(_db.scheduleTemplates)
            ..where((t) => t.seriesId.equals(series)))
          .get();
    }
    // Legacy fallback — shape match on the three fields a teacher
    // would recognise as "same activity, different day".
    return (_db.select(_db.scheduleTemplates)
          ..where(
            (t) =>
                t.title.equals(row.title) &
                t.startTime.equals(row.startTime) &
                t.endTime.equals(row.endTime),
          ))
        .get();
  }

  /// Duplicates all templates from [sourceDay] into each of [targetDays].
  /// Copies group assignments. Returns the count of templates copied per day
  /// (same count for every target day).
  Future<int> copyDayTemplates({
    required int sourceDay,
    required Set<int> targetDays,
  }) async {
    if (targetDays.isEmpty) return 0;
    final sources = await templatesForDay(sourceDay);
    if (sources.isEmpty) return 0;

    final newIds = <String>[];
    await _db.transaction(() async {
      for (final target in targetDays) {
        if (target == sourceDay) continue;
        for (final src in sources) {
          final newTemplateId = newId();
          newIds.add(newTemplateId);
          await _db.into(_db.scheduleTemplates).insert(
                ScheduleTemplatesCompanion.insert(
                  id: newTemplateId,
                  dayOfWeek: target,
                  startTime: src.startTime,
                  endTime: src.endTime,
                  isFullDay: Value(src.isFullDay),
                  title: src.title,
                  allGroups: Value(src.allGroups),
                  adultId: Value(src.adultId),
                  location: Value(src.location),
                  notes: Value(src.notes),
                  startDate: Value(src.startDate),
                  endDate: Value(src.endDate),
                  programId: Value(_programId),
                ),
              );
          final groupIds = await groupsForTemplate(src.id);
          for (final groupId in groupIds) {
            await _db.into(_db.templateGroups).insert(
                  TemplateGroupsCompanion.insert(
                    templateId: newTemplateId,
                    groupId: groupId,
                  ),
                );
          }
        }
      }
    });
    for (final newTemplateId in newIds) {
      unawaited(_sync.pushRow(scheduleTemplatesSpec, newTemplateId));
    }
    return sources.length;
  }

  Future<String> addOneOffEntry({
    required DateTime date,
    required String startTime,
    required String endTime,
    required String title,
    List<String> groupIds = const [],
    bool allGroups = true,
    bool isFullDay = false,
    DateTime? endDate,
    String? adultId,
    String? location,
    String? notes,
    String? sourceLibraryItemId,
    String? roomId,
    String? sourceUrl,
  }) async {
    final id = newId();
    // Normalize bounds so the range is always [start, end] with
    // date-only values — upstream callers are careless about time-of-day.
    final start = _dayOnly(date);
    final normalizedEnd = endDate == null ? null : _dayOnly(endDate);
    final end = (normalizedEnd != null && normalizedEnd.isBefore(start))
        ? null
        : normalizedEnd;
    await _db.transaction(() async {
      await _db.into(_db.scheduleEntries).insert(
            ScheduleEntriesCompanion.insert(
              id: id,
              date: start,
              endDate: Value(end),
              startTime: startTime,
              endTime: endTime,
              isFullDay: Value(isFullDay),
              title: title,
              allGroups: Value(allGroups),
              adultId: Value(adultId),
              location: Value(location),
              notes: Value(notes),
              sourceLibraryItemId: Value(sourceLibraryItemId),
              roomId: Value(roomId),
              sourceUrl: Value(sourceUrl),
              kind: 'addition',
              programId: Value(_programId),
            ),
          );
      for (final groupId in groupIds) {
        await _db.into(_db.entryGroups).insert(
              EntryGroupsCompanion.insert(entryId: id, groupId: groupId),
            );
      }
    });
    unawaited(_sync.pushRow(scheduleEntriesSpec, id));
    return id;
  }

  /// Shifts a template's start/end times just for [date] by inserting
  /// an `override` schedule entry. The override carries every other
  /// field forward unchanged (groups, adult, location, notes,
  /// isFullDay), so readers that see the merged schedule get a single
  /// row with the new times and the same audience.
  ///
  /// If a prior override already exists for this (templateId, date),
  /// it's replaced — shifting is idempotent, no stacking.
  Future<void> shiftTemplateForDate({
    required String templateId,
    required DateTime date,
    required String startTime,
    required String endTime,
  }) async {
    final template = await (_db.select(_db.scheduleTemplates)
          ..where((t) => t.id.equals(templateId)))
        .getSingle();
    final templateGroups = await groupsForTemplate(templateId);
    final dayOnly = _dayOnly(date);
    final nextDay = dayOnly.add(const Duration(days: 1));

    final overrideId = newId();
    await _db.transaction(() async {
      // Drop any prior override for this day so we don't stack rows.
      await (_db.delete(_db.scheduleEntries)
            ..where(
              (e) =>
                  e.overridesTemplateId.equals(templateId) &
                  e.kind.equals('override') &
                  e.date.isBiggerOrEqualValue(dayOnly) &
                  e.date.isSmallerThanValue(nextDay),
            ))
          .go();

      await _db.into(_db.scheduleEntries).insert(
            ScheduleEntriesCompanion.insert(
              id: overrideId,
              date: dayOnly,
              startTime: startTime,
              endTime: endTime,
              isFullDay: Value(template.isFullDay),
              title: template.title,
              allGroups: Value(template.allGroups),
              adultId: Value(template.adultId),
              location: Value(template.location),
              notes: Value(template.notes),
              kind: 'override',
              overridesTemplateId: Value(templateId),
              programId: Value(_programId),
            ),
          );
      for (final groupId in templateGroups) {
        await _db.into(_db.entryGroups).insert(
              EntryGroupsCompanion.insert(
                entryId: overrideId,
                groupId: groupId,
              ),
            );
      }
    });
    unawaited(_sync.pushRow(scheduleEntriesSpec, overrideId));
  }

  /// Move a weekly template to a different day-of-week. Affects all
  /// future occurrences of that recurring activity. For one-off
  /// date-scoped changes the teacher should use `addEntry` with an
  /// override / cancellation instead.
  Future<void> moveTemplateToDay({
    required String templateId,
    required int newDayOfWeek,
  }) async {
    await (_db.update(_db.scheduleTemplates)
          ..where((t) => t.id.equals(templateId)))
        .write(
      ScheduleTemplatesCompanion(
        dayOfWeek: Value(newDayOfWeek),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _db.markDirty('schedule_templates', templateId, ['day_of_week']);
    unawaited(_sync.pushRow(scheduleTemplatesSpec, templateId));
  }

  /// Clone an existing template onto another weekday. Group
  /// assignments come along. The new row gets a fresh id and is
  /// treated as independent — no `seriesId` is propagated, so the
  /// "delete every occurrence" wizard rule won't touch the original
  /// when the copy is later deleted (or vice versa). Returns the
  /// new template id.
  ///
  /// Used by the week-plan drag-to-duplicate path. Cancellation /
  /// override entries (which the drop handler rejects upstream) never
  /// reach this method.
  Future<String> copyTemplateToDay({
    required String templateId,
    required int targetDay,
  }) async {
    final src = await getTemplate(templateId);
    if (src == null) {
      throw StateError('Template $templateId no longer exists');
    }
    final newTemplateId = newId();
    await _db.transaction(() async {
      await _db.into(_db.scheduleTemplates).insert(
            ScheduleTemplatesCompanion.insert(
              id: newTemplateId,
              dayOfWeek: targetDay,
              startTime: src.startTime,
              endTime: src.endTime,
              isFullDay: Value(src.isFullDay),
              title: src.title,
              allGroups: Value(src.allGroups),
              adultId: Value(src.adultId),
              location: Value(src.location),
              notes: Value(src.notes),
              startDate: Value(src.startDate),
              endDate: Value(src.endDate),
              sourceLibraryItemId: Value(src.sourceLibraryItemId),
              roomId: Value(src.roomId),
              sourceUrl: Value(src.sourceUrl),
              programId: Value(_programId),
            ),
          );
      final groupIds = await groupsForTemplate(templateId);
      for (final groupId in groupIds) {
        await _db.into(_db.templateGroups).insert(
              TemplateGroupsCompanion.insert(
                templateId: newTemplateId,
                groupId: groupId,
              ),
            );
      }
    });
    unawaited(_sync.pushRow(scheduleTemplatesSpec, newTemplateId));
    return newTemplateId;
  }

  /// Clone a one-off entry onto a new date. Multi-day spans preserve
  /// their length (endDate shifts by the same delta). Group
  /// assignments come along. The new row is always written as
  /// `kind: 'addition'` — override / cancellation entries never reach
  /// this method because the drop handler rejects them. Returns the
  /// new entry id.
  Future<String> copyEntryToDate({
    required String entryId,
    required DateTime newDate,
  }) async {
    final row = await (_db.select(_db.scheduleEntries)
          ..where((e) => e.id.equals(entryId)))
        .getSingle();
    final oldStart = _dayOnly(row.date);
    final newStart = _dayOnly(newDate);
    final deltaDays = newStart.difference(oldStart).inDays;
    final newEnd = row.endDate == null
        ? null
        : _dayOnly(row.endDate!).add(Duration(days: deltaDays));
    final newEntryId = newId();
    await _db.transaction(() async {
      await _db.into(_db.scheduleEntries).insert(
            ScheduleEntriesCompanion.insert(
              id: newEntryId,
              date: newStart,
              endDate: Value(newEnd),
              startTime: row.startTime,
              endTime: row.endTime,
              isFullDay: Value(row.isFullDay),
              title: row.title,
              allGroups: Value(row.allGroups),
              adultId: Value(row.adultId),
              location: Value(row.location),
              notes: Value(row.notes),
              sourceLibraryItemId: Value(row.sourceLibraryItemId),
              roomId: Value(row.roomId),
              sourceUrl: Value(row.sourceUrl),
              kind: 'addition',
              programId: Value(_programId),
            ),
          );
      final groupIds = await groupsForEntry(entryId);
      for (final groupId in groupIds) {
        await _db.into(_db.entryGroups).insert(
              EntryGroupsCompanion.insert(
                entryId: newEntryId,
                groupId: groupId,
              ),
            );
      }
    });
    unawaited(_sync.pushRow(scheduleEntriesSpec, newEntryId));
    return newEntryId;
  }

  /// Move a one-off entry's date. Updates `date` + `endDate` when the
  /// entry is multi-day (the endDate shifts by the same delta so the
  /// range length is preserved).
  Future<void> moveEntryToDate({
    required String entryId,
    required DateTime newDate,
  }) async {
    final row = await (_db.select(_db.scheduleEntries)
          ..where((e) => e.id.equals(entryId)))
        .getSingle();
    final oldStart = _dayOnly(row.date);
    final newStart = _dayOnly(newDate);
    final deltaDays = newStart.difference(oldStart).inDays;
    final oldEnd = row.endDate;
    final newEnd = oldEnd == null
        ? null
        : _dayOnly(oldEnd).add(Duration(days: deltaDays));
    await (_db.update(_db.scheduleEntries)
          ..where((e) => e.id.equals(entryId)))
        .write(
      ScheduleEntriesCompanion(
        date: Value(newStart),
        endDate: Value(newEnd),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _db.markDirty('schedule_entries', entryId, ['date', 'end_date']);
    unawaited(_sync.pushRow(scheduleEntriesSpec, entryId));
  }

  /// Updates the start/end times of a single one-off entry. Used by
  /// "Shift today" on activities that aren't template-sourced.
  Future<void> shiftEntryTimes({
    required String entryId,
    required String startTime,
    required String endTime,
  }) async {
    await (_db.update(_db.scheduleEntries)
          ..where((e) => e.id.equals(entryId)))
        .write(
      ScheduleEntriesCompanion(
        startTime: Value(startTime),
        endTime: Value(endTime),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _db.markDirty('schedule_entries', entryId,
        ['start_time', 'end_time']);
    unawaited(_sync.pushRow(scheduleEntriesSpec, entryId));
  }

  Future<void> cancelTemplateForDate({
    required String templateId,
    required DateTime date,
  }) async {
    final template = await (_db.select(_db.scheduleTemplates)
          ..where((t) => t.id.equals(templateId)))
        .getSingle();
    final cancellationId = newId();
    await _db.into(_db.scheduleEntries).insert(
          ScheduleEntriesCompanion.insert(
            id: cancellationId,
            date: _dayOnly(date),
            startTime: template.startTime,
            endTime: template.endTime,
            isFullDay: Value(template.isFullDay),
            title: template.title,
            allGroups: Value(template.allGroups),
            kind: 'cancellation',
            overridesTemplateId: Value(templateId),
            programId: Value(_programId),
          ),
        );
    unawaited(_sync.pushRow(scheduleEntriesSpec, cancellationId));
  }

  Future<void> deleteEntry(String id) async {
    final row = await (_db.select(_db.scheduleEntries)
          ..where((e) => e.id.equals(id)))
        .getSingleOrNull();
    final programId = row?.programId;
    await (_db.delete(_db.scheduleEntries)..where((e) => e.id.equals(id)))
        .go();
    if (programId != null) {
      unawaited(
        _sync.pushDelete(
          spec: scheduleEntriesSpec,
          id: id,
          programId: programId,
        ),
      );
    }
  }

  /// Restore helper for the undo snackbar — re-insert the entry row
  /// with its original id. Cascaded entry_groups join rows aren't
  /// restored (same 5-second-window tradeoff as other restores); the
  /// entry comes back but without its group multi-select.
  Future<void> restoreEntry(ScheduleEntry row) async {
    await _db.into(_db.scheduleEntries).insertOnConflictUpdate(row);
    unawaited(_sync.pushRow(scheduleEntriesSpec, row.id));
  }

  /// Restore helpers for template deletes. `restoreTemplates` takes
  /// a list so the "delete this weekday's whole recurring pattern"
  /// flow (deleteTemplateGroupFor) can undo the whole sibling set
  /// in one snackbar.
  Future<void> restoreTemplate(ScheduleTemplate row) async {
    await _db.into(_db.scheduleTemplates).insertOnConflictUpdate(row);
    unawaited(_sync.pushRow(scheduleTemplatesSpec, row.id));
  }

  Future<void> restoreTemplates(Iterable<ScheduleTemplate> rows) async {
    await _db.transaction(() async {
      for (final row in rows) {
        await _db.into(_db.scheduleTemplates).insertOnConflictUpdate(row);
      }
    });
    for (final row in rows) {
      unawaited(_sync.pushRow(scheduleTemplatesSpec, row.id));
    }
  }

  Future<ScheduleEntry?> getEntry(String id) {
    return (_db.select(_db.scheduleEntries)..where((e) => e.id.equals(id)))
        .getSingleOrNull();
  }

  /// Edit an existing one-off entry (full-day events, trips, etc.).
  /// Mirrors [addOneOffEntry] for shape normalization, and replaces the
  /// entry's group join rows wholesale — same pattern as
  /// [updateTemplate].
  Future<void> updateEntry({
    required String id,
    required DateTime date,
    required String startTime,
    required String endTime,
    required String title,
    List<String> groupIds = const [],
    bool allGroups = true,
    bool isFullDay = false,
    DateTime? endDate,
    String? adultId,
    String? location,
    String? notes,
    // Same absent-unless-set pattern as updateTemplate.
    Value<String?> roomId = const Value.absent(),
    Value<String?> sourceLibraryItemId = const Value.absent(),
  }) async {
    final start = _dayOnly(date);
    final normalizedEnd = endDate == null ? null : _dayOnly(endDate);
    final end = (normalizedEnd != null && normalizedEnd.isBefore(start))
        ? null
        : normalizedEnd;
    await _db.transaction(() async {
      await (_db.update(_db.scheduleEntries)..where((e) => e.id.equals(id)))
          .write(
        ScheduleEntriesCompanion(
          date: Value(start),
          endDate: Value(end),
          startTime: Value(startTime),
          endTime: Value(endTime),
          isFullDay: Value(isFullDay),
          title: Value(title),
          allGroups: Value(allGroups),
          adultId: Value(adultId),
          location: Value(location),
          notes: Value(notes),
          roomId: roomId,
          sourceLibraryItemId: sourceLibraryItemId,
          updatedAt: Value(DateTime.now()),
        ),
      );
      await (_db.delete(_db.entryGroups)
            ..where((g) => g.entryId.equals(id)))
          .go();
      for (final groupId in groupIds) {
        await _db.into(_db.entryGroups).insert(
              EntryGroupsCompanion.insert(
                entryId: id,
                groupId: groupId,
              ),
            );
      }
    });
    // Wholesale entry edit — every visible field on the form is
    // re-set. Mark them all dirty so the partial-UPDATE path
    // pushes the same set; cascade rows (entry_groups) are
    // already replaced wholesale by _pushCascades.
    await _db.markDirty('schedule_entries', id, [
      'date',
      'end_date',
      'start_time',
      'end_time',
      'is_full_day',
      'title',
      'all_groups',
      'adult_id',
      'location',
      'notes',
      if (roomId.present) 'room_id',
      if (sourceLibraryItemId.present) 'source_library_item_id',
    ]);
    unawaited(_sync.pushRow(scheduleEntriesSpec, id));
  }

  /// Copy every one-off `addition` entry from the Mon..Fri span starting
  /// at [sourceMonday] into the matching weekday in the week starting at
  /// [destMonday]. Templates aren't touched — they already recur, so
  /// duplicating them would double-book next week.
  ///
  /// MVP scope: entries-only. Cancellations and overrides are skipped —
  /// they only make sense relative to a specific template on a specific
  /// date, and copying them forward would silently neuter next week's
  /// templates in surprising ways.
  ///
  /// Returns the number of entries copied. Single-day entries get mirrored
  /// onto the same weekday; multi-day entries (with endDate) land on the
  /// destination week with their range preserved — endDate shifts by the
  /// same week delta so the entry's length is unchanged.
  Future<int> duplicateWeekTemplates({
    required DateTime sourceMonday,
    required DateTime destMonday,
  }) async {
    final sourceStart = _dayOnly(sourceMonday);
    final sourceEnd = sourceStart.add(const Duration(days: 5));
    final destStart = _dayOnly(destMonday);
    // Delta in days — lets multi-day entry endDates shift by the same
    // offset as their start, preserving the range length.
    final deltaDays = destStart.difference(sourceStart).inDays;

    final sources = await (_db.select(_db.scheduleEntries)
          ..where((e) =>
              e.kind.equals('addition') &
              e.date.isBiggerOrEqualValue(sourceStart) &
              e.date.isSmallerThanValue(sourceEnd) &
              matchesActiveProgram(e.programId, _programId)))
        .get();

    if (sources.isEmpty) return 0;

    var copied = 0;
    final newIds = <String>[];
    await _db.transaction(() async {
      for (final src in sources) {
        final newEntryId = newId();
        newIds.add(newEntryId);
        final newDate = src.date.add(Duration(days: deltaDays));
        final newEndDate = src.endDate?.add(Duration(days: deltaDays));
        await _db.into(_db.scheduleEntries).insert(
              ScheduleEntriesCompanion.insert(
                id: newEntryId,
                date: _dayOnly(newDate),
                endDate: Value(newEndDate == null ? null : _dayOnly(newEndDate)),
                startTime: src.startTime,
                endTime: src.endTime,
                isFullDay: Value(src.isFullDay),
                title: src.title,
                allGroups: Value(src.allGroups),
                adultId: Value(src.adultId),
                location: Value(src.location),
                notes: Value(src.notes),
                sourceLibraryItemId: Value(src.sourceLibraryItemId),
                roomId: Value(src.roomId),
                sourceUrl: Value(src.sourceUrl),
                kind: 'addition',
                programId: Value(_programId),
              ),
            );
        final groupIds = await groupsForEntry(src.id);
        for (final groupId in groupIds) {
          await _db.into(_db.entryGroups).insert(
                EntryGroupsCompanion.insert(
                  entryId: newEntryId,
                  groupId: groupId,
                ),
              );
        }
        copied += 1;
      }
    });
    for (final newEntryId in newIds) {
      unawaited(_sync.pushRow(scheduleEntriesSpec, newEntryId));
    }
    return copied;
  }

  /// Merged schedule stream for every day in the week starting at the given
  /// Monday. Returns a map keyed by ISO day-of-week (1..7).
  Stream<Map<int, List<ScheduleItem>>> watchScheduleForWeek(
    DateTime weekStart,
  ) {
    final monday = _dayOnly(weekStart);
    final nextMonday = monday.add(const Duration(days: 7));

    final templatesStream = (_db.select(_db.scheduleTemplates)
          ..where((t) => matchesActiveProgram(t.programId, _programId)))
        .watch();
    // Entries can span a range — include any row whose [date, endDate]
    // touches this week, not just ones whose start date falls inside.
    // An entry with no endDate is treated as a single-day match.
    final entriesStream = (_db.select(_db.scheduleEntries)
          ..where(
            (e) =>
                e.date.isSmallerThanValue(nextMonday) &
                ((e.endDate.isNull() &
                        e.date.isBiggerOrEqualValue(monday)) |
                    (e.endDate.isNotNull() &
                        e.endDate.isBiggerOrEqualValue(monday))) &
                matchesActiveProgram(e.programId, _programId),
          ))
        .watch();

    return Stream<Map<int, List<ScheduleItem>>>.multi((controller) {
      List<ScheduleTemplate>? templates;
      List<ScheduleEntry>? entries;

      Future<void> recompute() async {
        final t = templates;
        final e = entries;
        if (t == null || e == null) return;
        try {
          final templateGroupMap = <String, List<String>>{};
          for (final tpl in t) {
            templateGroupMap[tpl.id] = await groupsForTemplate(tpl.id);
          }
          final entryGroupMap = <String, List<String>>{};
          for (final en in e) {
            entryGroupMap[en.id] = await groupsForEntry(en.id);
          }

          final result = <int, List<ScheduleItem>>{};
          // Monday..Friday only — the program doesn't run weekends, so we
          // skip Sat/Sun in the iteration entirely. Any templates/entries
          // still dated on those days are simply dropped here and never
          // surface in the UI.
          for (var offset = 0; offset < scheduleDayCount; offset++) {
            final date = monday.add(Duration(days: offset));
            final dayOfWeek = date.weekday;

            final dayTemplates = t.where((tpl) {
              if (tpl.dayOfWeek != dayOfWeek) return false;
              final s = tpl.startDate;
              final en = tpl.endDate;
              if (s != null && s.isAfter(date)) return false;
              if (en != null && en.isBefore(date)) return false;
              return true;
            }).toList();

            final dayEntries = e.where((en) => _entryCoversDate(en, date))
                .toList();

            result[dayOfWeek] = _merge(
              date: date,
              templates: dayTemplates,
              entries: dayEntries,
              templateGroups: templateGroupMap,
              entryGroups: entryGroupMap,
            );
          }
          if (!controller.isClosed) controller.add(result);
        } on Object catch (err, st) {
          if (!controller.isClosed) controller.addError(err, st);
        }
      }

      final sub1 = templatesStream.listen((val) {
        templates = val;
        unawaited(recompute());
      }, onError: controller.addError);
      final sub2 = entriesStream.listen((val) {
        entries = val;
        unawaited(recompute());
      }, onError: controller.addError);

      controller.onCancel = () async {
        await sub1.cancel();
        await sub2.cancel();
      };
    });
  }

  /// Merged schedule stream for a specific date. Re-emits whenever either
  /// the templates table OR the entries table changes — so a newly added
  /// full-day event (which lives in entries) correctly triggers an update.
  Stream<List<ScheduleItem>> watchScheduleForDate(DateTime date) {
    final day = _dayOnly(date);
    final dayOfWeek = date.weekday;
    final nextDay = day.add(const Duration(days: 1));

    final templatesStream = (_db.select(_db.scheduleTemplates)
          ..where((t) =>
              t.dayOfWeek.equals(dayOfWeek) &
              matchesActiveProgram(t.programId, _programId)))
        .watch();
    // Include any entry whose [date, endDate] overlaps `day`. Single-
    // day entries (endDate null) match when date == day; multi-day
    // entries match when date <= day <= endDate.
    final entriesStream = (_db.select(_db.scheduleEntries)
          ..where(
            (e) =>
                e.date.isSmallerThanValue(nextDay) &
                ((e.endDate.isNull() &
                        e.date.isBiggerOrEqualValue(day)) |
                    (e.endDate.isNotNull() &
                        e.endDate.isBiggerOrEqualValue(day))) &
                matchesActiveProgram(e.programId, _programId),
          ))
        .watch();

    return Stream<List<ScheduleItem>>.multi((controller) {
      List<ScheduleTemplate>? templates;
      List<ScheduleEntry>? entries;

      Future<void> recompute() async {
        final t = templates;
        final e = entries;
        if (t == null || e == null) return;

        // Date-range filter in Dart — null-safe and unambiguous.
        final filteredTemplates = t.where((tpl) {
          final start = tpl.startDate;
          final end = tpl.endDate;
          if (start != null && start.isAfter(day)) return false;
          if (end != null && end.isBefore(day)) return false;
          return true;
        }).toList();

        try {
          final templateGroupMap = <String, List<String>>{};
          for (final tpl in filteredTemplates) {
            templateGroupMap[tpl.id] = await groupsForTemplate(tpl.id);
          }
          final entryGroupMap = <String, List<String>>{};
          for (final en in e) {
            entryGroupMap[en.id] = await groupsForEntry(en.id);
          }
          final merged = _merge(
            date: day,
            templates: filteredTemplates,
            entries: e,
            templateGroups: templateGroupMap,
            entryGroups: entryGroupMap,
          );
          if (!controller.isClosed) controller.add(merged);
        } on Object catch (err, st) {
          if (!controller.isClosed) controller.addError(err, st);
        }
      }

      final sub1 = templatesStream.listen((val) {
        templates = val;
        unawaited(recompute());
      }, onError: controller.addError);
      final sub2 = entriesStream.listen((val) {
        entries = val;
        unawaited(recompute());
      }, onError: controller.addError);

      controller.onCancel = () async {
        await sub1.cancel();
        await sub2.cancel();
      };
    });
  }

  /// True when an entry's date span covers [day]. Single-day entries
  /// (endDate null) match only when their start date equals [day];
  /// multi-day entries match any day in [date, endDate] inclusive.
  bool _entryCoversDate(ScheduleEntry e, DateTime day) {
    final target = _dayOnly(day);
    final start = _dayOnly(e.date);
    if (start.isAfter(target)) return false;
    final end = e.endDate;
    if (end == null) {
      return start.isAtSameMomentAs(target);
    }
    final endOnly = _dayOnly(end);
    return !endOnly.isBefore(target);
  }

  List<ScheduleItem> _merge({
    required DateTime date,
    required List<ScheduleTemplate> templates,
    required List<ScheduleEntry> entries,
    required Map<String, List<String>> templateGroups,
    required Map<String, List<String>> entryGroups,
  }) {
    final cancelledTemplateIds = <String>{
      for (final e in entries)
        if (e.kind == 'cancellation' && e.overridesTemplateId != null)
          e.overridesTemplateId!,
    };
    final overrides = <String, ScheduleEntry>{
      for (final e in entries)
        if (e.kind == 'override' && e.overridesTemplateId != null)
          e.overridesTemplateId!: e,
    };

    final items = <ScheduleItem>[];

    for (final t in templates) {
      if (cancelledTemplateIds.contains(t.id)) continue;
      final override = overrides[t.id];
      if (override != null) {
        items.add(
          ScheduleItem(
            id: override.id,
            date: date,
            startTime: override.startTime,
            endTime: override.endTime,
            isFullDay: override.isFullDay,
            title: override.title,
            groupIds: entryGroups[override.id] ?? const [],
            allGroups: override.allGroups,
            adultId: override.adultId,
            location: override.location,
            notes: override.notes,
            isFromTemplate: true,
            templateId: t.id,
            entryId: override.id,
            // Attribution follows the template — the override only
            // shifts time/groups/etc. for a single day.
            sourceLibraryItemId: t.sourceLibraryItemId,
            // Room: prefer the override's room when set, else inherit
            // the template's. Lets a "just for today" move to a
            // different room show up correctly on the day.
            roomId: override.roomId ?? t.roomId,
            // Reference URL (v40): same rule as room — override wins
            // when set, else inherit the template's link.
            sourceUrl: override.sourceUrl ?? t.sourceUrl,
          ),
        );
      } else {
        items.add(
          ScheduleItem(
            id: t.id,
            date: date,
            startTime: t.startTime,
            endTime: t.endTime,
            isFullDay: t.isFullDay,
            title: t.title,
            groupIds: templateGroups[t.id] ?? const [],
            allGroups: t.allGroups,
            adultId: t.adultId,
            location: t.location,
            notes: t.notes,
            isFromTemplate: true,
            templateId: t.id,
            sourceLibraryItemId: t.sourceLibraryItemId,
            roomId: t.roomId,
            sourceUrl: t.sourceUrl,
          ),
        );
      }
    }

    for (final e in entries) {
      if (e.kind == 'addition') {
        final isMulti = e.endDate != null;
        items.add(
          ScheduleItem(
            id: e.id,
            date: date,
            rangeStart: isMulti ? _dayOnly(e.date) : null,
            rangeEnd: isMulti ? _dayOnly(e.endDate!) : null,
            startTime: e.startTime,
            endTime: e.endTime,
            isFullDay: e.isFullDay,
            title: e.title,
            groupIds: entryGroups[e.id] ?? const [],
            allGroups: e.allGroups,
            adultId: e.adultId,
            location: e.location,
            notes: e.notes,
            isFromTemplate: false,
            entryId: e.id,
            sourceLibraryItemId: e.sourceLibraryItemId,
            roomId: e.roomId,
            sourceUrl: e.sourceUrl,
            sourceTripId: e.sourceTripId,
          ),
        );
      }
    }

    items.sort((a, b) {
      if (a.isFullDay != b.isFullDay) return a.isFullDay ? -1 : 1;
      return a.startMinutes.compareTo(b.startMinutes);
    });
    return items;
  }

  int _compareTime(String a, String b) {
    final aParts = a.split(':').map(int.parse).toList();
    final bParts = b.split(':').map(int.parse).toList();
    return (aParts[0] * 60 + aParts[1]).compareTo(bParts[0] * 60 + bParts[1]);
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  return ScheduleRepository(ref.watch(databaseProvider), ref);
});

final templatesProvider = StreamProvider<List<ScheduleTemplate>>((ref) {
  ref.watch(activeProgramIdProvider);
  return ref.watch(scheduleRepositoryProvider).watchTemplates();
});

final templateItemsByDayProvider =
    StreamProvider<Map<int, List<ScheduleItem>>>((ref) {
  ref.watch(activeProgramIdProvider);
  return ref.watch(scheduleRepositoryProvider).watchTemplateItemsByDay();
});

/// Stream of the effective schedule for the week starting at a given Monday
/// midnight. Each entry in the returned map keys on the ISO day-of-week
/// (1..7) and carries the merged schedule for that specific date — templates
/// filtered by date bounds plus any per-date entries.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final scheduleForWeekProvider =
    StreamProvider.family<Map<int, List<ScheduleItem>>, DateTime>(
  (ref, weekStart) {
    ref.watch(activeProgramIdProvider);
    return ref
        .watch(scheduleRepositoryProvider)
        .watchScheduleForWeek(weekStart);
  },
);

/// Watches `nowTickProvider` so a session left running past
/// midnight advances to the new day automatically. Within the
/// same day every minute tick yields the same anchor so the
/// inner stream is reused.
final todayScheduleProvider = StreamProvider<List<ScheduleItem>>((ref) {
  ref.watch(activeProgramIdProvider);
  final now = ref.watch(nowTickProvider).value ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return ref
      .watch(scheduleRepositoryProvider)
      .watchScheduleForDate(today);
});

/// Schedule rows (templates + one-offs) resolved against an arbitrary
/// date. Backs the Today screen's prev/next day cycling — the same
/// stream that [todayScheduleProvider] wraps, but parameterized by
/// date so a teacher can browse yesterday / tomorrow without leaving
/// the Today surface. Other callers that only ever need today's rows
/// (child_detail, observation composer) stay on [todayScheduleProvider].
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final scheduleForDateProvider =
    StreamProvider.family<List<ScheduleItem>, DateTime>((ref, date) {
  ref.watch(activeProgramIdProvider);
  return ref.watch(scheduleRepositoryProvider).watchScheduleForDate(date);
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final templatesByAdultProvider =
    StreamProvider.family<List<ScheduleTemplate>, String>(
  (ref, adultId) {
    ref.watch(activeProgramIdProvider);
    return ref
        .watch(scheduleRepositoryProvider)
        .watchTemplatesForAdult(adultId);
  },
);

/// Stream-backed (T2.2) so a colleague pivoting a template's
/// group set on another device re-paints group chips without a
/// manual refresh. Was a FutureProvider — every consumer would
/// stick on the first read until the route remounted.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final templateGroupsProvider =
    StreamProvider.family<List<String>, String>((ref, templateId) {
  return ref
      .watch(scheduleRepositoryProvider)
      .watchGroupsForTemplate(templateId);
});
