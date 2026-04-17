import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prefixes the Smart Shelf uses to distinguish pinned item types. The
/// shelf stores a flat list of strings like `action:new-activity` or
/// `child:abc123` in SharedPreferences, and the launcher resolves each
/// to a live tile by type.
///
/// Keep these values stable — they're the on-disk encoding. Changing
/// one drops every existing pin of that type.
class PinnedKinds {
  static const action = 'action';
  static const destination = 'dest';
  static const child = 'child';
  static const specialist = 'specialist';
  static const library = 'library';
}

String pinId(String kind, String id) => '$kind:$id';

/// Destructures a stored id like `action:new-activity` into its kind
/// and inner value. Returns null when the id is malformed.
({String kind, String id})? parsePinId(String stored) {
  final i = stored.indexOf(':');
  if (i <= 0 || i == stored.length - 1) return null;
  return (kind: stored.substring(0, i), id: stored.substring(i + 1));
}

/// Ordered list of pinned item ids (with type prefix). Stored as a
/// SharedPreferences string list so the shelf survives restarts and
/// doesn't need a DB migration — this is UI preference, not app data.
class PinnedItemsNotifier extends Notifier<List<String>> {
  static const _prefsKey = 'launcher.pinned_item_ids';

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

  bool isPinned(String id) => state.contains(id);

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

final pinnedItemsProvider =
    NotifierProvider<PinnedItemsNotifier, List<String>>(
  PinnedItemsNotifier.new,
);
