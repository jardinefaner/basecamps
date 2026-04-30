-- Performance indexes surfaced by the post-launch audit.
--
-- All four tables are queried by columns that lack an index, so
-- every read sequence-scans. Symptoms today are subtle (low row
-- counts) but the cost grows linearly with program size + sibling
-- counts. RLS already scopes membership correctly via joins; this
-- migration is purely about read latency.
--
-- Idempotent (`if not exists`).

-- parent_children(child_id):
--   `watchForChild(childId)` (parents_repository.dart) renders the
--   "who is this child's parents" list on every child detail view.
--   The composite PK is (parent_id, child_id) and we already have
--   `idx_parent_children_parent`, but no index starts with
--   child_id — every render seq-scans the table. Add one.
create index if not exists idx_parent_children_child
  on public.parent_children (child_id);

-- adults(anchored_group_id):
--   "Which adults anchor this group?" runs on every group detail
--   render (group_detail_screen.dart:556+). Without an index it
--   seq-scans `adults` per render.
create index if not exists idx_adults_anchored_group
  on public.adults (anchored_group_id)
  where anchored_group_id is not null;

-- adults(parent_id):
--   `adultLinkedToParentProvider` (adults_repository.dart) runs
--   on every parent detail render. v40 added the column without
--   an index; partial index keeps it small (most adults are not
--   linked to a parent row).
create index if not exists idx_adults_parent
  on public.adults (parent_id)
  where parent_id is not null;

-- rooms(default_for_group_id):
--   `defaultRoomFor(groupId)` runs on every activity-form open.
--   Partial index — most rooms aren't a group default.
create index if not exists idx_rooms_default_for_group
  on public.rooms (default_for_group_id)
  where default_for_group_id is not null;
