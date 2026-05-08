// Late-pickup entry store — Riverpod-backed in-memory state for
// the late-pickup lab. Lifted out of the screen so the Command
// Center can write rows the screen will see.
//
// In-memory only. Lab proof. Same shape as
// `calendar_tile_store.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LateEntry {
  LateEntry({
    required this.id,
    required this.date,
    required this.pickupTime,
    required this.childId,
    required this.childName,
    required this.parentName,
    required this.reminderCardGiven,
    required this.staffName,
    required this.notes,
  });

  final String id;
  DateTime date;
  TimeOfDay pickupTime;
  String? childId;
  String childName;
  String parentName;
  bool reminderCardGiven;
  String staffName;
  String notes;
}

/// Holds late-pickup entries newest-first. Same notifier shape
/// as `calendarTilesProvider` — `add` puts at the head, `remove`
/// pulls by id, `touch` re-emits identity for in-place edits.
class LateEntriesNotifier extends Notifier<List<LateEntry>> {
  @override
  List<LateEntry> build() => <LateEntry>[];

  void add(LateEntry e) {
    state = <LateEntry>[e, ...state];
  }

  /// In-place edits to a row's mutable fields (`reminderCardGiven`,
  /// `notes`) only trigger watchers if we re-emit a new list. Call
  /// after mutating an entry directly.
  void touch() {
    state = <LateEntry>[...state];
  }

  void remove(String id) {
    state = state.where((e) => e.id != id).toList();
  }
}

final lateEntriesProvider =
    NotifierProvider<LateEntriesNotifier, List<LateEntry>>(
  LateEntriesNotifier.new,
);
