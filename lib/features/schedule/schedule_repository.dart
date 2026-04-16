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
    required this.title,
    required this.isFromTemplate,
    this.podId,
    this.specialistName,
    this.location,
    this.notes,
    this.templateId,
    this.entryId,
  });

  final String id;
  final String startTime; // "HH:mm"
  final String endTime;
  final String title;
  final String? podId;
  final String? specialistName;
  final String? location;
  final String? notes;

  /// True when this item came from a recurring template (possibly overridden).
  final bool isFromTemplate;

  /// The source template id (set if this item came from a template, or if
  /// a per-date entry overrides/cancels a template).
  final String? templateId;

  /// The per-date entry id (set when an override or addition produced this item).
  final String? entryId;

  TimeOfDay get startTimeOfDay => _parseTime(startTime);
  TimeOfDay get endTimeOfDay => _parseTime(endTime);

  int get startMinutes => startTimeOfDay.hour * 60 + startTimeOfDay.minute;

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

  // -- Templates --

  Stream<List<ScheduleTemplate>> watchTemplates() {
    final query = _db.select(_db.scheduleTemplates)
      ..orderBy([
        (t) => OrderingTerm.asc(t.dayOfWeek),
        (t) => OrderingTerm.asc(t.startTime),
      ]);
    return query.watch();
  }

  Future<String> addTemplate({
    required int dayOfWeek,
    required String startTime,
    required String endTime,
    required String title,
    String? podId,
    String? specialistName,
    String? location,
    String? notes,
  }) async {
    final id = newId();
    await _db.into(_db.scheduleTemplates).insert(
          ScheduleTemplatesCompanion.insert(
            id: id,
            dayOfWeek: dayOfWeek,
            startTime: startTime,
            endTime: endTime,
            title: title,
            podId: Value(podId),
            specialistName: Value(specialistName),
            location: Value(location),
            notes: Value(notes),
          ),
        );
    return id;
  }

  Future<void> updateTemplate({
    required String id,
    required int dayOfWeek,
    required String startTime,
    required String endTime,
    required String title,
    String? podId,
    String? specialistName,
    String? location,
    String? notes,
  }) async {
    await (_db.update(_db.scheduleTemplates)..where((t) => t.id.equals(id)))
        .write(
      ScheduleTemplatesCompanion(
        dayOfWeek: Value(dayOfWeek),
        startTime: Value(startTime),
        endTime: Value(endTime),
        title: Value(title),
        podId: Value(podId),
        specialistName: Value(specialistName),
        location: Value(location),
        notes: Value(notes),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteTemplate(String id) async {
    await (_db.delete(_db.scheduleTemplates)..where((t) => t.id.equals(id)))
        .go();
  }

  // -- Entries (per-date overrides/additions/cancellations) --

  Future<String> addOneOffEntry({
    required DateTime date,
    required String startTime,
    required String endTime,
    required String title,
    String? podId,
    String? specialistName,
    String? location,
    String? notes,
  }) async {
    final id = newId();
    await _db.into(_db.scheduleEntries).insert(
          ScheduleEntriesCompanion.insert(
            id: id,
            date: _dayOnly(date),
            startTime: startTime,
            endTime: endTime,
            title: title,
            podId: Value(podId),
            specialistName: Value(specialistName),
            location: Value(location),
            notes: Value(notes),
            kind: 'addition',
          ),
        );
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

  // -- Merged view for a date --

  Stream<List<ScheduleItem>> watchScheduleForDate(DateTime date) {
    final day = _dayOnly(date);
    final dayOfWeek = date.weekday; // ISO 1..7
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
      return _merge(templates: templates, entries: entries);
    });
  }

  List<ScheduleItem> _merge({
    required List<ScheduleTemplate> templates,
    required List<ScheduleEntry> entries,
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
            title: override.title,
            podId: override.podId,
            specialistName: override.specialistName,
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
            title: t.title,
            podId: t.podId,
            specialistName: t.specialistName,
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
            title: e.title,
            podId: e.podId,
            specialistName: e.specialistName,
            location: e.location,
            notes: e.notes,
            isFromTemplate: false,
            entryId: e.id,
          ),
        );
      }
    }

    items.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return items;
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  return ScheduleRepository(ref.watch(databaseProvider));
});

final templatesProvider = StreamProvider<List<ScheduleTemplate>>((ref) {
  return ref.watch(scheduleRepositoryProvider).watchTemplates();
});

final todayScheduleProvider = StreamProvider<List<ScheduleItem>>((ref) {
  return ref
      .watch(scheduleRepositoryProvider)
      .watchScheduleForDate(DateTime.now());
});
