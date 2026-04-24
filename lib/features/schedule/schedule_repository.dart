import 'dart:async';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/schedule/week_days.dart';
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
  ScheduleRepository(this._db);

  final AppDatabase _db;

  Stream<List<ScheduleTemplate>> watchTemplates() {
    final query = _db.select(_db.scheduleTemplates)
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
      ..where((t) => t.adultId.equals(adultId))
      ..orderBy([
        (t) => OrderingTerm.asc(t.dayOfWeek),
        (t) => OrderingTerm.asc(t.startTime),
      ]);
    return query.watch();
  }

  Future<List<ScheduleTemplate>> templatesForDay(int dayOfWeek) {
    final query = _db.select(_db.scheduleTemplates)
      ..where((t) => t.dayOfWeek.equals(dayOfWeek))
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
            ),
          );
      for (final groupId in groupIds) {
        await _db.into(_db.templateGroups).insert(
              TemplateGroupsCompanion.insert(templateId: id, groupId: groupId),
            );
      }
    });
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
  }

  Future<void> deleteTemplate(String id) async {
    await (_db.delete(_db.scheduleTemplates)..where((t) => t.id.equals(id)))
        .go();
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
    return (_db.delete(_db.scheduleTemplates)
          ..where((t) => t.id.isIn(siblings.map((r) => r.id))))
        .go();
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

    await _db.transaction(() async {
      for (final target in targetDays) {
        if (target == sourceDay) continue;
        for (final src in sources) {
          final newTemplateId = newId();
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
            ),
          );
      for (final groupId in groupIds) {
        await _db.into(_db.entryGroups).insert(
              EntryGroupsCompanion.insert(entryId: id, groupId: groupId),
            );
      }
    });
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

      final overrideId = newId();
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
  }

  Future<void> cancelTemplateForDate({
    required String templateId,
    required DateTime date,
  }) async {
    final template = await (_db.select(_db.scheduleTemplates)
          ..where((t) => t.id.equals(templateId)))
        .getSingle();
    await _db.into(_db.scheduleEntries).insert(
          ScheduleEntriesCompanion.insert(
            id: newId(),
            date: _dayOnly(date),
            startTime: template.startTime,
            endTime: template.endTime,
            isFullDay: Value(template.isFullDay),
            title: template.title,
            allGroups: Value(template.allGroups),
            kind: 'cancellation',
            overridesTemplateId: Value(templateId),
          ),
        );
  }

  Future<void> deleteEntry(String id) async {
    await (_db.delete(_db.scheduleEntries)..where((e) => e.id.equals(id)))
        .go();
  }

  /// Restore helper for the undo snackbar — re-insert the entry row
  /// with its original id. Cascaded entry_groups join rows aren't
  /// restored (same 5-second-window tradeoff as other restores); the
  /// entry comes back but without its group multi-select.
  Future<void> restoreEntry(ScheduleEntry row) async {
    await _db.into(_db.scheduleEntries).insertOnConflictUpdate(row);
  }

  /// Restore helpers for template deletes. `restoreTemplates` takes
  /// a list so the "delete this weekday's whole recurring pattern"
  /// flow (deleteTemplateGroupFor) can undo the whole sibling set
  /// in one snackbar.
  Future<void> restoreTemplate(ScheduleTemplate row) async {
    await _db.into(_db.scheduleTemplates).insertOnConflictUpdate(row);
  }

  Future<void> restoreTemplates(Iterable<ScheduleTemplate> rows) async {
    await _db.transaction(() async {
      for (final row in rows) {
        await _db.into(_db.scheduleTemplates).insertOnConflictUpdate(row);
      }
    });
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
  }

  /// Merged schedule stream for every day in the week starting at the given
  /// Monday. Returns a map keyed by ISO day-of-week (1..7).
  Stream<Map<int, List<ScheduleItem>>> watchScheduleForWeek(
    DateTime weekStart,
  ) {
    final monday = _dayOnly(weekStart);
    final nextMonday = monday.add(const Duration(days: 7));

    final templatesStream = _db.select(_db.scheduleTemplates).watch();
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
                        e.endDate.isBiggerOrEqualValue(monday))),
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
          ..where((t) => t.dayOfWeek.equals(dayOfWeek)))
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
                        e.endDate.isBiggerOrEqualValue(day))),
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
  return ScheduleRepository(ref.watch(databaseProvider));
});

final templatesProvider = StreamProvider<List<ScheduleTemplate>>((ref) {
  return ref.watch(scheduleRepositoryProvider).watchTemplates();
});

final templateItemsByDayProvider =
    StreamProvider<Map<int, List<ScheduleItem>>>((ref) {
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
    return ref
        .watch(scheduleRepositoryProvider)
        .watchScheduleForWeek(weekStart);
  },
);

final todayScheduleProvider = StreamProvider<List<ScheduleItem>>((ref) {
  return ref
      .watch(scheduleRepositoryProvider)
      .watchScheduleForDate(DateTime.now());
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final templatesByAdultProvider =
    StreamProvider.family<List<ScheduleTemplate>, String>(
  (ref, adultId) {
    return ref
        .watch(scheduleRepositoryProvider)
        .watchTemplatesForAdult(adultId);
  },
);

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final templateGroupsProvider =
    FutureProvider.family<List<String>, String>((ref, templateId) {
  return ref.watch(scheduleRepositoryProvider).groupsForTemplate(templateId);
});
