import 'dart:math';

final Random _random = Random.secure();

/// Random suffix bound. `1 << 32` looks correct but Dart-on-JS
/// overflows it to 0 (JS bitwise operators are 32-bit), and
/// `Random.nextInt(0)` then throws — every newId() call on web
/// blew up with "RangeError: max must be in range 0 < max ≤ 2^32,
/// was 0", which silently broke every wizard's save path. `1 << 30`
/// is unambiguously 2^30 on both native and web; ~1B values of
/// entropy combined with the microsecond timestamp prefix stays
/// collision-safe for any realistic per-user write rate.
const int _kRandomBound = 1 << 30;

String newId() {
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rand = _random.nextInt(_kRandomBound).toRadixString(36);
  return '$ts$rand';
}
