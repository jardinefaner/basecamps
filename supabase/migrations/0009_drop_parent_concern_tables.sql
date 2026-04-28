-- Drop the bespoke parent_concern_notes + parent_concern_children
-- tables now that the polymorphic form_submissions row with
-- form_type='parent_concern' replaces them (commit 3784201, with the
-- bespoke screens retired in 8cc3d68).
--
-- Sync state for these tables in the local sync_state table will go
-- stale next pull — the engine no longer has a TableSpec for either,
-- so the row is just dead weight. Cleanup of leftover sync_state
-- watermarks would require a per-program iteration; the rows are tiny
-- and the per-program count is one, so leaving them as historical
-- markers is fine.
--
-- The local Drift schema's v45 onUpgrade does its own DROP TABLE
-- after carrying the data forward into form_submissions. This file
-- handles the cloud side.

drop table if exists public.parent_concern_children;
drop table if exists public.parent_concern_notes;
