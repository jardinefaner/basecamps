import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which group card on Today was most recently expanded. Teachers
/// open the app, tap into "their" group; we remember that choice and
/// expand the same card next launch. No configuration screen — it
/// self-trains from use (see option B, "skip pinning").
///
/// Null = no group has been expanded yet (new install, or the user
/// explicitly collapsed the only expanded card). In that state all
/// group cards render collapsed.
class LastExpandedGroupNotifier extends Notifier<String?> {
  static const _prefsKey = 'today.last_expanded_group_id';

  /// Legacy SharedPreferences key from when this feature was called
  /// "pod". Read once on first load so teachers running the dev build
  /// through the rename don't lose their last-expanded state; written
  /// only under [_prefsKey] going forward.
  static const _legacyPrefsKey = 'today.last_expanded_pod_id';

  @override
  String? build() {
    // SharedPreferences is async; load on the next microtask and push
    // the value into state once it's back. Until then the screen just
    // renders with no group expanded, which is the right empty default.
    unawaited(Future.microtask(_load));
    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefsKey);
    // One-shot migration: read the legacy pod key and re-write under
    // the group key so the value survives the rename across the first
    // launch that ships this change.
    if (id == null) {
      final legacy = prefs.getString(_legacyPrefsKey);
      if (legacy != null && legacy.isNotEmpty) {
        await prefs.setString(_prefsKey, legacy);
        await prefs.remove(_legacyPrefsKey);
        id = legacy;
      }
    }
    if (id != null && id.isNotEmpty) state = id;
  }

  /// Expand a group. Passing the same id twice collapses it (classic
  /// single-open accordion behavior — tap the header to toggle).
  Future<void> toggle(String groupId) async {
    state = state == groupId ? null : groupId;
    final prefs = await SharedPreferences.getInstance();
    if (state == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, state!);
    }
  }
}

final lastExpandedGroupProvider =
    NotifierProvider<LastExpandedGroupNotifier, String?>(
  LastExpandedGroupNotifier.new,
);
