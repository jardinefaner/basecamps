-- Enable Supabase Realtime on every program-scoped table.
--
-- Supabase ships a publication named `supabase_realtime` that the
-- realtime worker subscribes to. Tables only stream change events
-- to clients when they're members of that publication. By default
-- nothing is published, so even after Slice C's tables exist,
-- realtime channels see zero events until we add them here.
--
-- Adding a table is cheap (no row-level cost — just enrolls the
-- table in WAL streaming for change events). Removing later is
-- also one statement. Realtime delivers events through the same
-- WebSocket Supabase already keeps open for auth — no new
-- connection per table.
--
-- Cascade tables join too — when an observation_attachments row
-- changes, clients with the parent observation in scope want to
-- know. RLS still gates what each client actually sees.

alter publication supabase_realtime add table public.observations;
alter publication supabase_realtime add table public.observation_children;
alter publication supabase_realtime add table public.observation_attachments;
alter publication supabase_realtime add table public.observation_domain_tags;

alter publication supabase_realtime add table public.groups;
alter publication supabase_realtime add table public.rooms;
alter publication supabase_realtime add table public.roles;
alter publication supabase_realtime add table public.parents;
alter publication supabase_realtime add table public.parent_children;
alter publication supabase_realtime add table public.children;
alter publication supabase_realtime add table public.child_schedule_overrides;
alter publication supabase_realtime add table public.attendance;
alter publication supabase_realtime add table public.adults;
alter publication supabase_realtime add table public.adult_availability;
alter publication supabase_realtime add table public.adult_day_blocks;
alter publication supabase_realtime add table public.vehicles;
alter publication supabase_realtime add table public.trips;
alter publication supabase_realtime add table public.trip_groups;
alter publication supabase_realtime add table public.activity_library;
alter publication supabase_realtime add table public.activity_library_domain_tags;
alter publication supabase_realtime add table public.activity_library_usages;
alter publication supabase_realtime add table public.lesson_sequences;
alter publication supabase_realtime add table public.lesson_sequence_items;
alter publication supabase_realtime add table public.themes;
alter publication supabase_realtime add table public.schedule_templates;
alter publication supabase_realtime add table public.template_groups;
alter publication supabase_realtime add table public.schedule_entries;
alter publication supabase_realtime add table public.entry_groups;
alter publication supabase_realtime add table public.parent_concern_notes;
alter publication supabase_realtime add table public.parent_concern_children;
alter publication supabase_realtime add table public.form_submissions;
