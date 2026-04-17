import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stable ids of quick-action tiles the teacher has pinned to the top
/// of the launcher. Stored as a SharedPreferences string list so the
/// order survives restarts and doesn't need a DB migration — this is
/// UI preference, not app data.
class PinnedActionsNotifier extends Notifier<List<String>> {
  static const _prefsKey = 'launcher.pinned_action_ids';

  @override
  List<String> build() {
    // Empty until SharedPreferences resolves; then the post-load
    // setter replaces state and any watchers rebuild.
    unawaited(Future.microtask(_load));
    return const <String>[];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefsKey);
    if (stored != null) {
      state = List<String>.unmodifiable(stored);
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, state);
  }

  Future<void> pin(String id) async {
    if (state.contains(id)) return;
    state = List<String>.unmodifiable([...state, id]);
    await _save();
  }

  Future<void> unpin(String id) async {
    if (!state.contains(id)) return;
    state = List<String>.unmodifiable(
      state.where((x) => x != id),
    );
    await _save();
  }

  /// Replace the pinned list in one go — used when the teacher
  /// reorders via drag. Values not in [next] are dropped; values not
  /// previously pinned but present in [next] are added.
  Future<void> setOrder(List<String> next) async {
    state = List<String>.unmodifiable(next);
    await _save();
  }
}

final pinnedActionsProvider =
    NotifierProvider<PinnedActionsNotifier, List<String>>(
  PinnedActionsNotifier.new,
);
