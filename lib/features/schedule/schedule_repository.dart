import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
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
        final item = ScheduleItem(
          id: t.id,
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
    String? specialistId,
    String? location,
    String? notes,
  }) async {
    final id = newId();
    await _db.transaction(() async {
      await _db.into(_db.scheduleEntries).insert(
            ScheduleEntriesCompanion.insert(
              id: id,
              date: _dayOnly(date),
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

  Stream<List<ScheduleItem>> watchScheduleForDate(DateTime date) {
    final day = _dayOnly(date);
    final dayOfWeek = date.weekday;
    final nextDay = day.add(const Duration(days: 1));

    final templatesQuery = _db.select(_db.scheduleTemplates)
      ..where((t) => t.dayOfWeek.equals(dayOfWeek));
    final entriesQuery = _db.select(_db.scheduleEntries)
      ..where(
        (e) =>
            e.date.isBiggerOrEqualValue(day) &
            e.date.isSmallerThanValue(nextDay),
      );

    return templatesQuery.watch().asyncMap((templates) async {
      final entries = await entriesQuery.get();
      final templatePodMap = <String, List<String>>{};
      for (final t in templates) {
        templatePodMap[t.id] = await podsForTemplate(t.id);
      }
      final entryPodMap = <String, List<String>>{};
      for (final e in entries) {
        entryPodMap[e.id] = await podsForEntry(e.id);
      }
      return _merge(
        templates: templates,
        entries: entries,
        templatePods: templatePodMap,
        entryPods: entryPodMap,
      );
    });
  }

  List<ScheduleItem> _merge({
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
        items.add(
          ScheduleItem(
            id: e.id,
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

final todayScheduleProvider = StreamProvider<List<ScheduleItem>>((ref) {
  return ref
      .watch(scheduleRepositoryProvider)
      .watchScheduleForDate(DateTime.now());
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final templatePodsProvider =
    FutureProvider.family<List<String>, String>((ref, templateId) {
  return ref.watch(scheduleRepositoryProvider).podsForTemplate(templateId);
});
