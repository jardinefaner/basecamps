import 'package:drift/drift.dart';

/// Build a Drift `where` predicate that scopes a query to rows
/// belonging to the active program — or the legacy "unscoped" pool
/// when [activeId] is null.
///
/// Used by every repository's read methods (Slice 1 of the multi-
/// program rollout). Without this, switching programs would do
/// nothing visible because every screen showed every row regardless
/// of `program_id`. The migration that added `program_id` columns
/// (v42) was additive-only; the read-side filter is what makes
/// switching meaningful.
///
/// The `IS NULL` arm covers two cases that aren't bugs:
/// 1. **Pre-program legacy rows.** Users who upgraded across v42
///    have rows with `program_id = NULL` until the one-shot
///    backfill stamps them. We want those visible regardless of
///    which program is active so a teacher who hasn't completed
///    the backfill (or whose backfill failed) doesn't see an
///    empty roster.
/// 2. **No active program yet.** During the first-frame window
///    after launch (before `activeProgramIdProvider` hydrates),
///    `activeId` is null. Falling back to "show legacy untagged
///    rows" prevents the brief flash of empty UI.
///
/// When [activeId] is non-null the predicate matches both that
/// program's rows and untagged rows. When it's null we restrict to
/// untagged rows only — anything else would leak data across
/// programs while we're booting.
Expression<bool> matchesActiveProgram(
  GeneratedColumn<String> programIdCol,
  String? activeId,
) {
  if (activeId == null) {
    return programIdCol.isNull();
  }
  return programIdCol.equals(activeId) | programIdCol.isNull();
}
