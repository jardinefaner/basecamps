import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which pod card on Today was most recently expanded. Teachers opened
/// the app, tapped into "their" pod; we remember that choice and
/// expand the same card next launch. No configuration screen — it
/// self-trains from use (see /loop plan: option B, "skip pinning").
///
/// Null = no pod has been expanded yet (new install, or the user
/// explicitly collapsed the only expanded card). In that state all
/// pod cards render collapsed.
class LastExpandedPodNotifier extends Notifier<String?> {
  static const _prefsKey = 'today.last_expanded_pod_id';

  @override
  String? build() {
    // SharedPreferences is async; load on the next microtask and push
    // the value into state once it's back. Until then the screen just
    // renders with no pod expanded, which is the right empty default.
    unawaited(Future.microtask(_load));
    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_prefsKey);
    if (id != null && id.isNotEmpty) state = id;
  }

  /// Expand a pod. Passing the same id twice collapses it (classic
  /// single-open accordion behavior — tap the header to toggle).
  Future<void> toggle(String podId) async {
    state = state == podId ? null : podId;
    final prefs = await SharedPreferences.getInstance();
    if (state == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, state!);
    }
  }
}

final lastExpandedPodProvider =
    NotifierProvider<LastExpandedPodNotifier, String?>(
  LastExpandedPodNotifier.new,
);
