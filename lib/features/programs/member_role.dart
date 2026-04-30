/// Role enum for `program_members.role`. Cloud stores the dbValue
/// as plain text (no PG enum type) so future roles like 'viewer'
/// or 'parent' can land without a migration; the Dart enum is
/// exhaustive and gives every callsite a typed comparison.
///
/// The audit found 6+ string-literal `member.role == 'admin'`
/// comparisons scattered across the program detail screen. A typo
/// (or a future rename to "owner") would silently grant nothing
/// without any compiler signal. Use [ProgramMemberRole] / the
/// `isAdmin` extension instead.
library;

import 'package:basecamp/database/database.dart';

enum ProgramMemberRole {
  admin('admin'),
  teacher('teacher');

  const ProgramMemberRole(this.dbValue);

  final String dbValue;

  /// Map a stored db string to an enum value. Anything unknown
  /// falls back to [teacher] — the safer default for an
  /// unrecognized role string (no admin-only powers).
  static ProgramMemberRole fromDb(String? raw) {
    if (raw == null) return teacher;
    for (final r in ProgramMemberRole.values) {
      if (r.dbValue == raw) return r;
    }
    return teacher;
  }
}

extension ProgramMemberRoleX on ProgramMember {
  /// Typed accessor — replaces ad-hoc `member.role == 'admin'`
  /// comparisons.
  ProgramMemberRole get typedRole => ProgramMemberRole.fromDb(role);

  /// One-liner for the most common gate. Same shape every UI
  /// callsite was open-coding.
  bool get isAdmin => typedRole == ProgramMemberRole.admin;
}
