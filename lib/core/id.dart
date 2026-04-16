import 'dart:math';

final Random _random = Random.secure();

String newId() {
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rand = _random.nextInt(1 << 32).toRadixString(36);
  return '$ts$rand';
}
