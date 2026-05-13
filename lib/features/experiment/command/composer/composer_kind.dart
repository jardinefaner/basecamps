// Composer kinds — the domains the Spotlight-style picker can spawn
// a structured composer card for. Today only `observation` is
// wired; the rest are placeholders so the picker can list them but
// fall through to the existing LLM dispatch path on tap (until
// dedicated composers ship).
//
// Why an enum instead of stringly-typed: the picker UI, the
// active-composer state, and the matcher all key off the same
// value — a typed enum keeps the surface small and lets dart
// switches catch missing cases when we add a new composer.

import 'package:flutter/material.dart';

/// One entry in the domain-pick list shown above the command bar.
enum ComposerKind {
  observation(
    label: 'Observation',
    description: 'Quick note + photos for a child or group',
    icon: Icons.edit_note_rounded,
    keywords: ['observation', 'observations', 'note', 'notes', 'obs', 'ob'],
    routesToComposer: true,
  ),
  // The remaining entries are listed so the user discovers them in
  // the picker, but tapping them today funnels back through the
  // existing LLM dispatch (one-shot tool calls). When each domain
  // gets its own structured card, flip `routesToComposer` to true.
  calendar(
    label: 'Calendar tile',
    description: 'Trip, event, room change',
    icon: Icons.event_outlined,
    keywords: ['calendar', 'trip', 'event', 'cal', 'tile'],
    routesToComposer: false,
  ),
  latePickup(
    label: 'Late pickup',
    description: 'Log a pickup-time exception',
    icon: Icons.access_time_outlined,
    keywords: ['late', 'pickup', 'lp'],
    routesToComposer: false,
  );

  const ComposerKind({
    required this.label,
    required this.description,
    required this.icon,
    required this.keywords,
    required this.routesToComposer,
  });

  /// Title shown in the picker row.
  final String label;

  /// One-line subtitle to disambiguate the row.
  final String description;

  /// Leading glyph in the row.
  final IconData icon;

  /// Prefix-match keywords. The matcher is case-insensitive and
  /// uses substring containment so a user typing "obs" finds
  /// "observation". Order matters: the first matching kind wins
  /// when multiple keywords overlap (rare; today none do).
  final List<String> keywords;

  /// When true, picking this row spawns a dedicated composer card
  /// inside the Command Center. When false, the typed query is
  /// forwarded to the existing LLM dispatcher (so the older flow
  /// still works while we migrate one domain at a time).
  final bool routesToComposer;
}

/// Filter the kinds down to those whose keyword list matches
/// [query] by prefix. Empty query → ALL kinds (Spotlight-style:
/// focus the bar with nothing typed and you still see what's
/// available). One-character queries match if any keyword starts
/// with that letter — the friction of typing 2+ chars before any
/// suggestion appears was confusing in testing.
List<ComposerKind> matchComposerKinds(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return ComposerKind.values.toList();
  final firstWord = q.split(RegExp(r'\s+')).first;
  if (firstWord.isEmpty) return ComposerKind.values.toList();
  final out = <ComposerKind>[];
  for (final kind in ComposerKind.values) {
    for (final k in kind.keywords) {
      if (k.startsWith(firstWord) || firstWord.startsWith(k)) {
        out.add(kind);
        break;
      }
    }
  }
  return out;
}
