import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits `DateTime.now()` once immediately, then every time a wall-clock
/// minute boundary crosses. Widgets that need to feel alive (countdowns,
/// "NOW" chips, "ends in N min" badges) watch this so they rebuild at
/// the moment the displayed time would change — not on an arbitrary
/// 60-second schedule that could drift by up to a minute.
///
/// The stream aligns to the next minute boundary each tick, so over
/// hours it never skews from the system clock. Cancelled via Riverpod's
/// onDispose when the last listener goes away.
final nowTickProvider = StreamProvider<DateTime>((ref) {
  final controller = StreamController<DateTime>();
  Timer? timer;

  void scheduleNext() {
    final now = DateTime.now();
    final msUntilNextMinute =
        60000 - now.second * 1000 - now.millisecond;
    timer = Timer(Duration(milliseconds: msUntilNextMinute), () {
      if (controller.isClosed) return;
      controller.add(DateTime.now());
      scheduleNext();
    });
  }

  controller.add(DateTime.now());
  scheduleNext();

  ref.onDispose(() async {
    timer?.cancel();
    await controller.close();
  });

  return controller.stream;
});
