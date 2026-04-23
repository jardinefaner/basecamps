import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Program-wide knobs the teacher can tune — late-arrival grace,
/// overdue-pickup grace. Kept small on purpose: the default values
/// work for most programs, and a ten-field settings screen is the
/// wrong place for single-value tuning. Extra knobs earn their spot
/// when they have a concrete "I wish this were different" driving
/// them, not before.
///
/// Backed by SharedPreferences so values survive a cold start without
/// requiring a Drift migration on every UX tweak.
class ProgramSettings {
  const ProgramSettings({
    required this.latenessGraceMinutes,
    required this.pickupGraceMinutes,
  });

  /// Minutes past a child's expected arrival before the flag fires.
  /// A bus 8 minutes late in traffic shouldn't page the teacher; 20+
  /// minutes usually does. Defaults to 15.
  final int latenessGraceMinutes;

  /// Minutes past a child's expected pickup before the overdue flag
  /// fires. Parents running 5 minutes late at pickup is routine, so
  /// this tends to get tuned up in practice. Defaults to 15.
  final int pickupGraceMinutes;

  static const defaults = ProgramSettings(
    latenessGraceMinutes: 15,
    pickupGraceMinutes: 15,
  );

  ProgramSettings copyWith({
    int? latenessGraceMinutes,
    int? pickupGraceMinutes,
  }) =>
      ProgramSettings(
        latenessGraceMinutes:
            latenessGraceMinutes ?? this.latenessGraceMinutes,
        pickupGraceMinutes:
            pickupGraceMinutes ?? this.pickupGraceMinutes,
      );
}

/// Notifier that loads + saves [ProgramSettings] against
/// SharedPreferences. Starts at [ProgramSettings.defaults] while the
/// first load is in flight — that's the right "empty" behavior, and
/// it matches the values a brand-new install would see anyway.
class ProgramSettingsNotifier extends Notifier<ProgramSettings> {
  static const _kLatenessGrace = 'settings.lateness_grace_minutes';
  static const _kPickupGrace = 'settings.pickup_grace_minutes';

  @override
  ProgramSettings build() {
    unawaited(Future.microtask(_load));
    return ProgramSettings.defaults;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final lateness = prefs.getInt(_kLatenessGrace);
    final pickup = prefs.getInt(_kPickupGrace);
    if (lateness == null && pickup == null) return;
    state = ProgramSettings(
      latenessGraceMinutes:
          lateness ?? ProgramSettings.defaults.latenessGraceMinutes,
      pickupGraceMinutes:
          pickup ?? ProgramSettings.defaults.pickupGraceMinutes,
    );
  }

  Future<void> setLatenessGrace(int minutes) async {
    state = state.copyWith(latenessGraceMinutes: minutes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLatenessGrace, minutes);
  }

  Future<void> setPickupGrace(int minutes) async {
    state = state.copyWith(pickupGraceMinutes: minutes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPickupGrace, minutes);
  }
}

final programSettingsProvider =
    NotifierProvider<ProgramSettingsNotifier, ProgramSettings>(
  ProgramSettingsNotifier.new,
);
