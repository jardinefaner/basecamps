import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which lens Today is showing — the group-chip focused view
/// (per-group NOW / NEXT / EARLIER) or the chronological agenda
/// feed that weaves activities, trips, and opt-in breaks across the
/// whole day.
///
/// Coexist by design. Teachers pick based on what they want to
/// answer: "what is my pod doing right now" (groups) vs "what's
/// happening overall today" (agenda).
enum TodayMode {
  groups,
  agenda;

  String get dbValue => name;

  static TodayMode fromDb(String? raw) {
    for (final m in TodayMode.values) {
      if (m.dbValue == raw) return m;
    }
    return TodayMode.groups;
  }
}

/// Notifier persisting the mode choice across launches — teachers
/// who prefer one lens stay in it without having to re-select every
/// time they open the app.
class TodayModeNotifier extends Notifier<TodayMode> {
  static const _prefsKey = 'today.mode';

  @override
  TodayMode build() {
    unawaited(Future.microtask(_load));
    return TodayMode.groups;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    state = TodayMode.fromDb(raw);
  }

  Future<void> set(TodayMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.dbValue);
  }
}

final todayModeProvider =
    NotifierProvider<TodayModeNotifier, TodayMode>(TodayModeNotifier.new);
