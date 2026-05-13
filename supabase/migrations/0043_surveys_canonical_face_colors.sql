-- 0043 — surveys.canonical_face_colors (teacher display toggle)
--
-- The basket kiosk normally rotates a random color palette across
-- the 5 face slots per question — same expressions, different
-- colors — to keep kids from pattern-matching ("tap the green
-- one"). Some classrooms / age bands need the canonical mapping
-- (red sad → green happy) for legibility. This flag lets the
-- teacher pick per-survey at setup time.
--
-- Default FALSE so existing surveys keep their anti-bias rotation
-- unchanged. The marble-jar kiosk ignores this column.

alter table public.surveys
  add column if not exists canonical_face_colors boolean not null default false;
