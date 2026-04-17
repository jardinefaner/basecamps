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
    required this.podIds,
    required this.date,
    this.rangeStart,
    this.rangeEnd,
    this.specialistId,
    this.location,
    this.notes,
    this.templateId,
    this.entryId,
  });

  final String id;
  final String startTime;
  final String endTime;
  final bool isFullDay;
  final String title;
  final List<String> podIds;
  final String? specialistId;
  final String? location;
  final String? notes;
  final bool isFromTemplate;
  final String? templateId;
  final String? entryId;

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
  bool get isAllPods => podIds.isEmpty;

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

  /// Templates assigned to one specialist, weekly-ordered. Feeds the
  /// "What they run" section on the specialist detail screen.
  Stream<List<ScheduleTemplate>> watchTemplatesForSpecialist(
    String specialistId,
  ) {
    final query = _db.select(_db.scheduleTemplates)
      ..where((t) => t.specialistId.equals(specialistId))
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

  /// Stream of all templates mapped to [ScheduleItem]s (with their pod ids
  /// resolved) grouped by weekday. Used by the editor for display and for
  /// conflict detection.
  Stream<Map<int, List<ScheduleItem>>> watchTemplateItemsByDay() {
    return watchTemplates().asyncMap((templates) async {
      final byDay = <int, List<ScheduleItem>>{};
      for (final t in templates) {
        final pods = await podsForTemplate(t.id);
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
          podIds: pods,
          specialistId: t.specialistId,
          location: t.location,
          notes: t.notes,
          isFromTemplate: true,
          templateId: t.id,
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

  Future<List<String>> podsForTemplate(String templateId) async {
    final rows = await (_db.select(_db.templatePods)
          ..where((p) => p.templateId.equals(templateId)))
        .get();
    return rows.map((r) => r.podId).toList();
  }

  Future<List<String>> podsForEntry(String entryId) async {
    final rows = await (_db.select(_db.entryPods)
          ..where((p) => p.entryId.equals(entryId)))
        .get();
    return rows.map((r) => r.podId).toList();
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
    List<String> podIds = const [],
    bool isFullDay = false,
    String? specialistId,
    String? location,
    String? notes,
    DateTime? startDate,
    DateTime? endDate,
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
              specialistId: Value(specialistId),
              location: Value(location),
              notes: Value(notes),
              startDate: Value(startDate == null ? null : _dayOnly(startDate)),
              endDate: Value(endDate == null ? null : _dayOnly(endDate)),
            ),
          );
      for (final podId in podIds) {
        await _db.into(_db.templatePods).insert(
              TemplatePodsCompanion.insert(templateId: id, podId: podId),
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
    List<String> podIds = const [],
    bool isFullDay = false,
    String? specialistId,
    String? location,
    String? notes,
    DateTime? startDate,
    DateTime? endDate,
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
          specialistId: Value(specialistId),
          location: Value(location),
          notes: Value(notes),
          startDate: Value(startDate == null ? null : _dayOnly(startDate)),
          endDate: Value(endDate == null ? null : _dayOnly(endDate)),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await (_db.delete(_db.templatePods)
            ..where((p) => p.templateId.equals(id)))
          .go();
      for (final podId in podIds) {
        await _db.into(_db.templatePods).insert(
              TemplatePodsCompanion.insert(templateId: id, podId: podId),
            );
      }
    });
  }

  Future<void> deleteTemplate(String id) async {
    await (_db.delete(_db.scheduleTemplates)..where((t) => t.id.equals(id)))
        .go();
  }

  /// Duplicates all templates from [sourceDay] into each of [targetDays].
  /// Copies pod assignments. Returns the count of templates copied per day
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
                  specialistId: Value(src.specialistId),
                  location: Value(src.location),
                  notes: Value(src.notes),
                  startDate: Value(src.startDate),
                  endDate: Value(src.endDate),
                ),
              );
          final podIds = await podsForTemplate(src.id);
          for (final podId in podIds) {
            await _db.into(_db.templatePods).insert(
                  TemplatePodsCompanion.insert(
                    templateId: newTemplateId,
                    podId: podId,
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
    List<String> podIds = const [],
    bool isFullDay = false,
    DateTime? endDate,
    String? specialistId,
    String? location,
    String? notes,
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
              specialistId: Value(specialistId),
              location: Value(location),
              notes: Value(notes),
              kind: 'addition',
            ),
          );
      for (final podId in podIds) {
        await _db.into(_db.entryPods).insert(
              EntryPodsCompanion.insert(entryId: id, podId: podId),
            );
      }
    });
    return id;
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
            kind: 'cancellation',
            overridesTemplateId: Value(templateId),
          ),
        );
  }

  Future<void> deleteEntry(String id) async {
    await (_db.delete(_db.scheduleEntries)..where((e) => e.id.equals(id)))
        .go();
  }

  Future<ScheduleEntry?> getEntry(String id) {
    return (_db.select(_db.scheduleEntries)..where((e) => e.id.equals(id)))
        .getSingleOrNull();
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
          final templatePodMap = <String, List<String>>{};
          for (final tpl in t) {
            templatePodMap[tpl.id] = await podsForTemplate(tpl.id);
          }
          final entryPodMap = <String, List<String>>{};
          for (final en in e) {
            entryPodMap[en.id] = await podsForEntry(en.id);
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
              templatePods: templatePodMap,
              entryPods: entryPodMap,
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
          final templatePodMap = <String, List<String>>{};
          for (final tpl in filteredTemplates) {
            templatePodMap[tpl.id] = await podsForTemplate(tpl.id);
          }
          final entryPodMap = <String, List<String>>{};
          for (final en in e) {
            entryPodMap[en.id] = await podsForEntry(en.id);
          }
          final merged = _merge(
            date: day,
            templates: filteredTemplates,
            entries: e,
            templatePods: templatePodMap,
            entryPods: entryPodMap,
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
    required Map<String, List<String>> templatePods,
    required Map<String, List<String>> entryPods,
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
            podIds: entryPods[override.id] ?? const [],
            specialistId: override.specialistId,
            location: override.location,
            notes: override.notes,
            isFromTemplate: true,
            templateId: t.id,
            entryId: override.id,
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
            podIds: templatePods[t.id] ?? const [],
            specialistId: t.specialistId,
            location: t.location,
            notes: t.notes,
            isFromTemplate: true,
            templateId: t.id,
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
            podIds: entryPods[e.id] ?? const [],
            specialistId: e.specialistId,
            location: e.location,
            notes: e.notes,
            isFromTemplate: false,
            entryId: e.id,
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
final templatesBySpecialistProvider =
    StreamProvider.family<List<ScheduleTemplate>, String>(
  (ref, specialistId) {
    return ref
        .watch(scheduleRepositoryProvider)
        .watchTemplatesForSpecialist(specialistId);
  },
);

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final templatePodsProvider =
    FutureProvider.family<List<String>, String>((ref, templateId) {
  return ref.watch(scheduleRepositoryProvider).podsForTemplate(templateId);
});
