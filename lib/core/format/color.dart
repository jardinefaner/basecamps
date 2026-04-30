/// Shared color helpers. The audit found 9+ private copies of the
/// same hex-to-Color parser scattered across today / curriculum /
/// groups / themes screens. This file is the one source of truth
/// — re-export `parseHex` from here, delete the locals.
library;

import 'package:flutter/material.dart';

/// Parse `#RRGGBB` / `#AARRGGBB` (with or without leading `#`)
/// into a [Color]. Returns null when the string is empty, the
/// wrong length, or contains non-hex characters.
///
/// 6-digit values are treated as opaque (alpha forced to FF).
/// 8-digit values use the explicit alpha channel.
///
/// Drift stores hex as plain text. Every UI surface that tints
/// from a row's `colorHex` should pipe through this so a
/// malformed value renders as "no color" everywhere identically
/// instead of one screen's parser being slightly more lenient.
Color? parseHex(String? hex) {
  if (hex == null) return null;
  final trimmed = hex.trim();
  if (trimmed.isEmpty) return null;
  final clean = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
  if (clean.length != 6 && clean.length != 8) return null;
  final n = int.tryParse(clean, radix: 16);
  if (n == null) return null;
  return Color(clean.length == 6 ? 0xFF000000 | n : n);
}
