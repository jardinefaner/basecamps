/// Display-name extensions for the three people entity types.
///
/// The audit found this composition repeated 15+ times in
/// divergent forms — "First L" vs "First L." vs "First Last" —
/// already drifted in production code. Same child rendered
/// "Sarah J." in one place and "Sarah Johnson" in another. This
/// file is the one source of truth so future surfaces all read
/// the same shape.
library;

import 'package:basecamp/core/format/text.dart';
import 'package:basecamp/database/database.dart';

extension ChildDisplay on Child {
  /// "Sarah Johnson" — full name when last is set, just first
  /// when not. Used on detail screens, attendance rows, and
  /// anywhere there's room.
  String get fullName {
    final last = lastName?.trim();
    if (last == null || last.isEmpty) return firstName;
    return '$firstName $last';
  }

  /// "Sarah J." — first name + last initial. Used in dense
  /// pickers, chips, and grids where space is tight. Period
  /// included after the initial (the audit found three
  /// variations; standardizing on the period form because
  /// it reads as a name rather than a typo).
  String get shortName {
    final last = lastName?.trim();
    if (last == null || last.isEmpty) return firstName;
    return '$firstName ${last.initial}.';
  }

  /// Avatar fallback initial. Wraps [StringInitial.initial] for
  /// callsite ergonomics.
  String get displayInitial => firstName.initial;
}

extension AdultDisplay on Adult {
  /// "Sarah Johnson" or "Sarah" — Adult.name is already a single
  /// field today, so this is mostly a future-proof seam if we
  /// ever split it.
  String get fullName => name;

  /// "Sarah J." style. Splits on whitespace; if there's no
  /// surname, returns the single-token name as-is.
  String get shortName {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return name;
    return '${parts.first} ${parts.last.initial}.';
  }

  String get displayInitial => name.initial;
}

extension ParentDisplay on Parent {
  /// "Sarah Johnson" or "Sarah" — handles parents stored as
  /// first-name only.
  String get fullName {
    final last = lastName?.trim();
    if (last == null || last.isEmpty) return firstName;
    return '$firstName $last';
  }

  String get shortName {
    final last = lastName?.trim();
    if (last == null || last.isEmpty) return firstName;
    return '$firstName ${last.initial}.';
  }

  String get displayInitial => firstName.initial;
}
