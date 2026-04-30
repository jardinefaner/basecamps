/// Shared text-formatting helpers. The audit found 25+ open-coded
/// implementations of "first character of a name, uppercase, with
/// a fallback for empty" — and four of them (`name[0].toUpperCase()`)
/// crash on names containing emoji or composed glyphs because they
/// index by code unit instead of grapheme cluster. This file is the
/// one source of truth.
library;

// `characters` extension on String is re-exported from
// flutter/widgets, which is already a transitive dep everywhere
// in the app. Avoids adding a direct dependency on the package.
import 'package:flutter/widgets.dart';

extension StringInitial on String? {
  /// First grapheme of the string, uppercased — for avatar circle
  /// fallbacks. Returns `'?'` for null / empty / whitespace-only,
  /// so callsites don't have to repeat the empty check.
  ///
  /// Grapheme-aware: 'José'.initial → 'J', '🎉Sarah'.initial → '🎉',
  /// '😀'.initial → '😀'. Open-coded `name[0]` would break the
  /// emoji/composed-glyph case (returns half a code point).
  String get initial {
    final s = this;
    if (s == null || s.trim().isEmpty) return '?';
    final cs = s.trim().characters;
    if (cs.isEmpty) return '?';
    return cs.first.toUpperCase();
  }
}
