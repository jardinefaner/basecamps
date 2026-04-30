import 'package:drift/drift.dart';

@DataClassName('Group')
class Groups extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get colorHex => text().nullable()();

  /// Owning program (v42). Nullable so the schema migration can
  /// land additively — a one-shot backfill on first sign-in stamps
  /// existing rows with the user's default program. Repositories
  /// pass `activeProgramIdProvider` on every insert from then on.
  TextColumn get programId => text().nullable()();

  /// v52: hide-but-keep. Pickers filter `archivedAt IS NULL`;
  /// detail screens / historical observations still resolve a
  /// reference. Toggle via the row-detail menu.
  DateTimeColumn get archivedAt => dateTime().nullable()();

  /// v52: user-orderable display order on the launcher / Today.
  /// Nullable so existing rows fall back to alpha-by-name; once
  /// the teacher reorders, every group in the program gets a
  /// stable integer.
  IntColumn get position => integer().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  // `group` / `groups` are SQL reserved words; pin the SQL name here
  // so Drift quotes it consistently in every generated statement.
  @override
  String? get tableName => 'groups';
}

@DataClassName('Child')
class Children extends Table {
  TextColumn get id => text()();
  TextColumn get firstName => text()();
  TextColumn get lastName => text().nullable()();
  TextColumn get groupId =>
      text().nullable().references(Groups, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get birthDate => dateTime().nullable()();
  TextColumn get pin => text().nullable()();
  TextColumn get notes => text().nullable()();
  // Primary parent/guardian name, used to pre-fill the parent concern
  // note form when a child is selected. Free-form for now; if we add
  // formal Parent records later these children can be joined against
  // them.
  TextColumn get parentName => text().nullable()();
  // Local file path for the child's photo. Remote upload comes later.
  TextColumn get avatarPath => text().nullable()();

  /// v44: bucket-relative path of the avatar in the `media`
  /// bucket. Set by MediaService.upload once the avatar's been
  /// uploaded to cloud. Other devices use this to lazy-download
  /// the avatar when the child first appears in their UI.
  TextColumn get avatarStoragePath => text().nullable()();

  /// v51: per-upload content tag. The bucket key
  /// (`avatarStoragePath`) is stable per row id, so re-picking a
  /// photo overwrites bytes at the same key — invisible to other
  /// devices' caches without a signal. Each upload stamps a fresh
  /// random etag; the avatar resolver uses
  /// `(storage_path, etag)` as its cache key, so any change here
  /// flows through realtime and forces a re-fetch on every other
  /// device. Null on rows uploaded before v51 — the resolver
  /// treats null-etag-vs-null-etag as a match (backwards-compat).
  TextColumn get avatarEtag => text().nullable()();

  // Standing expected drop-off / pickup time for this child, stored
  // as "HH:mm" strings (matches how schedule times are stored in
  // ScheduleTemplates). Nullable — a child with no expected time
  // never triggers lateness flags, which is the right default for
  // drop-in / flexible-schedule kids. Daily variations go through
  // [ChildScheduleOverrides] below.
  TextColumn get expectedArrival => text().nullable()();
  TextColumn get expectedPickup => text().nullable()();

  /// Owning program (v42). See [Groups.programId] for nullability
  /// rationale.
  TextColumn get programId => text().nullable()();

  /// v52: hide-but-keep for alumni / withdrawn children. Same
  /// pattern as [Groups.archivedAt].
  DateTimeColumn get archivedAt => dateTime().nullable()();

  /// v52: user-orderable line-up order within a group.
  IntColumn get position => integer().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Per-child, per-day override for the standing [Children.expectedArrival]
/// / [Children.expectedPickup] times. Row exists iff the teacher logged
/// an exception for today ("mom texted, Noah's running late; expect him
/// at 9:30 instead of 8:30"). Absence = use standing times.
///
/// Date-scoped: one row per (child, date). Repository ON CONFLICT-
/// replaces on save so editing the override is idempotent.
@DataClassName('ChildScheduleOverride')
class ChildScheduleOverrides extends Table {
  TextColumn get id => text()();
  TextColumn get childId => text()
      .references(Children, #id, onDelete: KeyAction.cascade)();

  /// Calendar date the override applies to. Time-of-day is ignored
  /// at read time — the repository normalizes to local midnight
  /// when querying.
  DateTimeColumn get date => dateTime()();

  // Both nullable even though the row exists: the teacher might
  // override just arrival ("mom running late") without touching
  // pickup, and vice versa. Null here means "use the standing value
  // for this half of the day."
  TextColumn get expectedArrivalOverride => text().nullable()();
  TextColumn get expectedPickupOverride => text().nullable()();

  /// Free-form context on why this override exists. Shown in the
  /// child detail / flags list when the teacher taps to see "why is
  /// Noah late" — "running late, mom texting" answers that.
  TextColumn get note => text().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Program-owned vehicles (v37). A named vehicle carries the two
/// fields teachers retype on every trip — make/model + plate — so
/// the vehicle-check form picks from a list instead of making
/// drivers spell out "Ford Transit 350" every morning. One row per
/// vehicle the program operates.
@DataClassName('Vehicle')
class Vehicles extends Table {
  TextColumn get id => text()();

  /// Short display name — "Big Bus", "Blue Van", or just a copy of
  /// the make/model when there's only one. Shows up on list tiles
  /// and the picker chip.
  TextColumn get name => text()();

  /// "Ford Transit 350" — free text so teachers can match whatever
  /// they see on the registration.
  TextColumn get makeModel => text().withDefault(const Constant(''))();

  /// License plate — free text for the same reason. Stored exactly
  /// as entered so the vehicle check form reads it back verbatim.
  TextColumn get licensePlate =>
      text().withDefault(const Constant(''))();

  /// Optional free-form notes — VIN, parking spot, owner, insurance
  /// contact, whatever the program wants tied to the vehicle.
  TextColumn get notes => text().nullable()();

  /// Owning program (v42). See [Groups.programId] for the rule.
  TextColumn get programId => text().nullable()();

  /// v52: archive retired vehicles without losing their trip
  /// history. Pickers filter `archivedAt IS NULL`.
  DateTimeColumn get archivedAt => dateTime().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Trips extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get date => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  TextColumn get location => text().nullable()();
  TextColumn get notes => text().nullable()();
  // Optional "HH:mm" times bounding the trip within its date. Nullable means
  // the trip is considered full-day.
  TextColumn get departureTime => text().nullable()();
  TextColumn get returnTime => text().nullable()();

  /// Owning program (v42). See [Groups.programId] for the rule.
  TextColumn get programId => text().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Groups going on a given trip. Empty set is interpreted as "all groups".
class TripGroups extends Table {
  TextColumn get tripId =>
      text().references(Trips, #id, onDelete: KeyAction.cascade)();
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {tripId, groupId};
}

class Captures extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get caption => text().nullable()();
  TextColumn get imagePath => text().nullable()();
  TextColumn get tripId =>
      text().nullable().references(Trips, #id, onDelete: KeyAction.setNull)();
  TextColumn get authorName => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CaptureChildren extends Table {
  TextColumn get captureId =>
      text().references(Captures, #id, onDelete: KeyAction.cascade)();
  TextColumn get childId =>
      text().references(Children, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {captureId, childId};
}

/// Photos, videos, and other media attached to an observation. Stored as
/// local filesystem paths for now; [remoteUrl] will be filled in once a
/// cloud storage sync exists.
class ObservationAttachments extends Table {
  TextColumn get id => text()();
  TextColumn get observationId => text()
      .references(Observations, #id, onDelete: KeyAction.cascade)();
  // 'photo' | 'video'
  TextColumn get kind => text()();
  TextColumn get localPath => text()();
  TextColumn get remoteUrl => text().nullable()();

  /// v44: bucket-relative path in Supabase Storage's `media`
  /// bucket. Set by MediaService.upload after the file lands in
  /// cloud. On other devices (where localPath points at a file
  /// that doesn't exist), readers fall back to fetching this
  /// path through the bucket. Null for legacy rows + for
  /// uploads that haven't completed yet.
  TextColumn get storagePath => text().nullable()();
  TextColumn get thumbnailPath => text().nullable()();
  IntColumn get durationMs => integer().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Maps an observation to 0..N children. Observations primarily target
/// children via this join table; the legacy single
/// [Observations.childId] column is kept for older rows.
class ObservationChildren extends Table {
  TextColumn get observationId => text()
      .references(Observations, #id, onDelete: KeyAction.cascade)();
  TextColumn get childId =>
      text().references(Children, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {observationId, childId};
}

/// One row per (observation, domain) pair. Observations can span several
/// curriculum domains — a "shared with a friend" moment touches SSD3
/// (empathy), SSD8 (friendship), and sometimes SSD9 (conflict). The
/// legacy single [Observations.domain] column is still written as the
/// "primary" (first-selected) domain so older queries keep working.
///
/// Named `Tags` (not just `Domains`) so Drift's generated row dataclass
/// `ObservationDomainTag` doesn't collide with the `ObservationDomain`
/// enum in observations_repository.dart.
class ObservationDomainTags extends Table {
  TextColumn get observationId => text()
      .references(Observations, #id, onDelete: KeyAction.cascade)();
  TextColumn get domain => text()();

  @override
  Set<Column<Object>> get primaryKey => {observationId, domain};
}

class Observations extends Table {
  TextColumn get id => text()();
  TextColumn get targetKind => text()();
  TextColumn get childId => text()
      .nullable()
      .references(Children, #id, onDelete: KeyAction.setNull)();
  TextColumn get groupId =>
      text().nullable().references(Groups, #id, onDelete: KeyAction.setNull)();
  TextColumn get activityLabel => text().nullable()();
  TextColumn get domain => text()();
  TextColumn get sentiment => text()();
  TextColumn get note => text()();
  // When a teacher ran AI refine and saved the refined version, the
  // pre-refine text lives here so the edit sheet can flip back to it
  // later. Null for observations that were never refined — most of them.
  TextColumn get noteOriginal => text().nullable()();
  TextColumn get tripId =>
      text().nullable().references(Trips, #id, onDelete: KeyAction.setNull)();
  TextColumn get authorName => text().nullable()();

  /// v33: structural link to the activity occurrence this observation
  /// was captured during. activityLabel remains the display fallback
  /// (and the only link for observations typed outside any scheduled
  /// activity); these three columns together identify "Morning Circle
  /// on April 23, Butterflies instance" unambiguously so reports can
  /// ask precise questions.
  ///
  /// scheduleSourceKind is 'template' or 'entry'. Null across all
  /// three = no structural link (impromptu observation).
  TextColumn get scheduleSourceKind => text().nullable()();
  TextColumn get scheduleSourceId => text().nullable()();
  DateTimeColumn get activityDate => dateTime().nullable()();

  /// Optional room the observation happened in. Useful for
  /// program-wide activities that split across rooms (Morning Circle
  /// in Butterflies Room vs Ladybugs Room) — the room pinpoints
  /// which pod's instance even when activityLabel is the same.
  TextColumn get roomId => text().nullable().references(
        Rooms,
        #id,
        onDelete: KeyAction.setNull,
      )();

  /// Owning program (v42). See [Groups.programId] for the rule.
  TextColumn get programId => text().nullable()();

  /// v52: auth user id of whoever logged the observation. Lets
  /// the UI render "Logged by Sarah" with a real link to the
  /// member instead of relying on the free-text [authorName]
  /// (which stays as a fallback for legacy rows). Repos
  /// populate from `currentSessionProvider.user.id` on insert;
  /// nullable for pre-v52 rows.
  TextColumn get createdBy => text().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Reusable activity definitions. Originally a set of scheduling
/// presets (title + duration + location + adult) — the original
/// columns stay for backwards compatibility with existing rows and the
/// library picker used by the schedule wizards.
///
/// As of schema v26 the table also holds rich "activity cards" — AI-
/// generated learning-activity summaries scoped to an audience age or
/// age range, sourced from a URL the teacher pasted into the creation
/// wizard. All the new fields are nullable so legacy preset rows and
/// fresh rich cards coexist in the same table.
class ActivityLibrary extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  IntColumn get defaultDurationMin => integer().nullable()();
  TextColumn get adultId => text()
      .nullable()
      .references(Adults, #id, onDelete: KeyAction.setNull)();
  TextColumn get location => text().nullable()();
  TextColumn get notes => text().nullable()();

  // -- Rich "activity card" fields (v26) --

  /// Inclusive lower bound of the intended audience age. When
  /// [audienceMaxAge] equals this, the card is for a single age; when
  /// it's bigger, the card targets a range. When both are null, the
  /// row is a legacy preset / untargeted item.
  IntColumn get audienceMinAge => integer().nullable()();
  IntColumn get audienceMaxAge => integer().nullable()();

  /// One-line hook that teasers the card.
  TextColumn get hook => text().nullable()();

  /// 2-4 sentence summary at the audience's reading level.
  TextColumn get summary => text().nullable()();

  /// Key points, one per line (newline-joined). Rendered as a bulleted
  /// list. Using a single text column instead of a join table keeps
  /// the schema tight — these are short, display-only, and never
  /// queried for.
  TextColumn get keyPoints => text().nullable()();

  /// Suggested learning goals, newline-joined. Same rationale as
  /// [keyPoints].
  TextColumn get learningGoals => text().nullable()();

  /// Rough "how long this'll hold the kid's attention" in minutes.
  IntColumn get engagementTimeMin => integer().nullable()();

  /// The URL the teacher pasted. Preserved so we can link back to the
  /// source and re-generate from it later if needed.
  TextColumn get sourceUrl => text().nullable()();

  /// Human-readable attribution — e.g. "via BBC.com" — derived from
  /// the scraped page's title or host during generation.
  TextColumn get sourceAttribution => text().nullable()();

  /// Comma- or newline-separated list of materials — free-text for
  /// now. A future filter can parse this into chips.
  TextColumn get materials => text().nullable()();

  /// Optional age-scaled rewrites of [summary] / [keyPoints] /
  /// [learningGoals] for adjacent ages, stored as a single JSON blob
  /// (v46). Shape:
  ///
  /// ```json
  /// {
  ///   "5":  { "summary": "...", "keyPoints": "...", "goals": "..." },
  ///   "6":  { "summary": "...", ... }
  /// }
  /// ```
  ///
  /// Rendered by the curriculum view's age-scaling toggle. Stored as
  /// a JSON string instead of a side table because the rewrites are
  /// always read together with the parent row and never queried for.
  /// Null on legacy rows; the renderer falls back to the unscaled
  /// [summary] / [keyPoints] / [learningGoals] when no variant for the
  /// requested age exists.
  TextColumn get ageVariants => text().nullable()();

  /// Owning program (v42). See [Groups.programId] for the rule.
  TextColumn get programId => text().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Free-form curriculum-domain tags for activity library items
/// (v40). A library item can live in multiple domains ("Music",
/// "Movement") and the join lets the library screen filter by any
/// subset without storing a denormalized list-string. Values are
/// free text for now; a future picker can normalize them.
class ActivityLibraryDomainTags extends Table {
  TextColumn get libraryItemId => text()
      .references(ActivityLibrary, #id, onDelete: KeyAction.cascade)();
  TextColumn get domain => text()();

  @override
  Set<Column<Object>> get primaryKey => {libraryItemId, domain};
}

/// Log row recorded each time a library card is instantiated into a
/// schedule (template or entry). Drives "recently used" sort and the
/// "last used at" affordance on library cards. Both template_id and
/// entry_id are nullable so a usage can record just one side — e.g.
/// a template created from the card sets template_id; when that
/// template expands into a per-date entry through the override flow,
/// that entry's usage row can point at entry_id instead.
class ActivityLibraryUsages extends Table {
  TextColumn get id => text()();
  TextColumn get libraryItemId => text()
      .references(ActivityLibrary, #id, onDelete: KeyAction.cascade)();
  TextColumn get templateId => text().nullable().references(
        ScheduleTemplates,
        #id,
        onDelete: KeyAction.setNull,
      )();
  TextColumn get entryId => text().nullable().references(
        ScheduleEntries,
        #id,
        onDelete: KeyAction.setNull,
      )();

  /// The date the card was instantiated for — i.e. the date the
  /// schedule row lives on. Used for "used this week" aggregations.
  DateTimeColumn get usedOn => dateTime()();

  /// When the usage row itself was recorded.
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Named ordered sequences of library activities — "this week's
/// plan", "fall unit 3", "Bug Week lessons". Each sequence owns an
/// ordered list of library items via [LessonSequenceItems]. No UI
/// this round; schema lands so Round 4 can build on top.
class LessonSequences extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();

  /// Owning theme (v46). When non-null, the sequence is one "week"
  /// (or arc) inside a 10-week / multi-week theme, and the
  /// curriculum view groups sequences by phase under their theme.
  /// Nullable so legacy free-floating sequences (lesson plans not
  /// tied to a theme) keep working unchanged.
  TextColumn get themeId => text()
      .nullable()
      .references(Themes, #id, onDelete: KeyAction.setNull)();

  /// One-line "essential question" for the week — the prompt the
  /// teacher returns to during morning meeting and the milestone
  /// recap (v46). E.g. "What if everything was upside-down?".
  /// Optional.
  TextColumn get coreQuestion => text().nullable()();

  /// Phase grouping (v47) — sequences with the same `phase` value
  /// render under one phase header in the curriculum view, e.g.
  /// "ALL ABOUT ME" spans weeks 1–2. Free-text so curriculum
  /// authors can name phases however they want without a schema
  /// migration. Null for sequences that aren't part of a phased
  /// arc (legacy, or single-week lesson plans).
  TextColumn get phase => text().nullable()();

  /// Per-week accent color override (v47). Hex string like
  /// `#ff6b6b`. The curriculum view uses this to tint that week's
  /// chip, callout, and milestone star — falling back to
  /// `themes.colorHex` when null. Lets a 10-week theme have a
  /// gradient of colors across its phases (week 1 reddish, week 2
  /// orange-red, etc.) without mutating the theme color.
  TextColumn get colorHex => text().nullable()();

  /// Pedagogical / "under the hood" notes per week (v47). Free-
  /// form text the curriculum author writes for themselves /
  /// other teachers — what concepts the week is meant to surface,
  /// what behaviors to watch for. Surfaced behind a toggle in the
  /// curriculum view (admins / teachers see it; could later be
  /// gated to admin-only via UI).
  TextColumn get engineNotes => text().nullable()();

  /// Owning program (v42). See [Groups.programId] for the rule.
  TextColumn get programId => text().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Ordered join from [LessonSequences] to [ActivityLibrary]. A single
/// library item can appear multiple times in a sequence (the same
/// activity running twice), hence the dedicated id instead of a
/// composite PK. `position` is 0-based; reorder flows rewrite it.
class LessonSequenceItems extends Table {
  TextColumn get id => text()();
  TextColumn get sequenceId => text()
      .references(LessonSequences, #id, onDelete: KeyAction.cascade)();
  TextColumn get libraryItemId => text()
      .references(ActivityLibrary, #id, onDelete: KeyAction.cascade)();

  /// 0-based position inside the sequence. Sort is authoritative on
  /// read, and inserts / reorders rewrite this column.
  IntColumn get position => integer()();

  /// Day-of-week the item runs on (v46). 1=Mon … 7=Sun, matching
  /// `DateTime.weekday`. Nullable: legacy free-floating items have
  /// no calendar slot, and `kind = 'milestone'` items also leave it
  /// null because they span the whole week.
  IntColumn get dayOfWeek => integer().nullable()();

  /// What role this item plays inside the sequence (v46). Today's
  /// known values:
  ///
  /// - `daily` — a per-day ritual (morning meeting, lunch ritual,
  ///   afternoon investigation). Pairs with [dayOfWeek].
  /// - `milestone` — the weekly capstone / Friday share-out.
  ///   [dayOfWeek] is left null.
  ///
  /// Stored as free text (no enum table) so curriculum authors can
  /// add ad-hoc kinds without a migration. Defaults to `daily` on
  /// legacy rows via the v46 migration.
  TextColumn get kind => text().withDefault(const Constant('daily'))();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Program-level themes — "Bug week", "Kindness week". A theme spans
/// a date range and colors the Today / planning surfaces without
/// mandating which activities run. No UI this round; schema lands so
/// later rounds (plan-a-week / PDF export) can consume it.
///
/// Data class is named `ProgramTheme` to avoid clashing with
/// Flutter's `Theme` widget — callers already importing
/// `flutter/material.dart` need a disambiguated symbol.
@DataClassName('ProgramTheme')
class Themes extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get colorHex => text().nullable()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  TextColumn get notes => text().nullable()();

  /// Owning program (v42). See [Groups.programId] for the rule.
  TextColumn get programId => text().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One block of "I'm available to work" for an adult — e.g. "Mon
/// 9:00–17:00". Any given adult can have multiple rows (Mon 9–12,
/// Mon 13–17) to model split shifts, and each row can be bounded by
/// [startDate]/[endDate] to model seasonal work or time off. Same ISO
/// day-of-week convention (1..7) the schedule uses everywhere else.
///
/// v28: added [breakStart]/[breakEnd] + [lunchStart]/[lunchEnd] to
/// encode each adult's daily break + lunch inside their shift, so the
/// Today view can show "on lunch until 1:00" and the conflict layer
/// can warn when activities are scheduled on top of breaks.
class AdultAvailability extends Table {
  TextColumn get id => text()();
  TextColumn get adultId => text()
      .references(Adults, #id, onDelete: KeyAction.cascade)();
  IntColumn get dayOfWeek => integer()();
  TextColumn get startTime => text()();
  TextColumn get endTime => text()();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  // v28 added a single break window. v35 added a second break so
  // programs that run morning + afternoon breaks can record both.
  // `break2Start/End` are the second window; both nullable so any
  // combination of "no breaks / one break / two breaks" is valid.
  TextColumn get breakStart => text().nullable()();
  TextColumn get breakEnd => text().nullable()();
  TextColumn get break2Start => text().nullable()();
  TextColumn get break2End => text().nullable()();
  TextColumn get lunchStart => text().nullable()();
  TextColumn get lunchEnd => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Per-adult, per-day role timeline — subdivides an adult's shift
/// into labeled blocks. Models the "group lead 8:30-11, then
/// adult rotator 11-12, then back to group lead 12-3" pattern
/// that the static `Adult.adultRole` alone can't express.
///
/// Gaps between blocks on a given day are implied "off". Adults with
/// NO blocks for a day fall back to `Adult.adultRole` interpreted
/// as a single shift-long block (so the existing adult-as-rotator
/// behavior keeps working for the simple case).
///
/// Break + lunch remain on the adult_availability row for the
/// MVP; they layer ON TOP of this timeline — a adult block
/// running 11-12 with a lunch 11:30-12:00 just means the adult
/// is rotating 11-11:30 and at lunch 11:30-12. Duplicating break /
/// lunch into this table would be noise for the common case.
///
/// `role` values:
///   - 'lead'       — anchored to a group (requires `group_id`)
///   - 'adult' — rotating, no group
@DataClassName('AdultDayBlock')
class AdultDayBlocks extends Table {
  TextColumn get id => text()();
  TextColumn get adultId => text()
      .references(Adults, #id, onDelete: KeyAction.cascade)();

  /// ISO day of week (1 = Mon, 7 = Sun). Program runs M-F so values
  /// are almost always 1..5, but no CHECK constraint — weekend is
  /// legal data, just unused for now.
  IntColumn get dayOfWeek => integer()();

  /// HH:mm wall-clock strings, same format as schedule templates and
  /// availability. Half-open: `[startTime, endTime)` is the span of
  /// the block.
  TextColumn get startTime => text()();
  TextColumn get endTime => text()();

  /// 'lead' or 'adult'. Bad values fall back to 'adult' at
  /// read time — matches how `AdultRole.fromDb` handles the similar
  /// field on Adults.
  TextColumn get role => text()();

  /// For lead blocks — which group the adult is anchoring during
  /// this span. Null for adult blocks. FK to groups with
  /// setNull on delete so deleting a group silently detaches any
  /// legacy lead blocks rather than cascading-deleting the whole
  /// timeline.
  TextColumn get groupId => text()
      .nullable()
      .references(Groups, #id, onDelete: KeyAction.setNull)();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Per-weekday "what role am I in right now" timeline (v48).
/// Models classroom-rotation patterns — the typical shape:
///
///   Mon 8:00-9:30   anchor      Lions
///   Mon 9:30-10:30  specialist  Lions       (specialist warm-up)
///   Mon 10:30-11:30 specialist  Bears       (rotation away)
///   Mon 11:30-12:30 anchor      Lions
///   Mon 12:30-13:00 break       null
///
/// Roles (stored as the `kind` text but typed via `RoleBlockKind`
/// in Dart):
///   - `anchor`     — anchored to a `groupId`. Two anchors per
///                    classroom is the typical baseline.
///   - `specialist` — teaching a subject across rooms. `subject`
///                    set when known. `groupId` is the room
///                    they're CURRENTLY in for this slot (which
///                    may not be their home room).
///   - `break`      — off-duty. `groupId` null.
///   - `lunch`      — same as break, separately labeled for
///                    payroll / scheduling clarity.
///   - `admin`      — non-classroom work (planning, paperwork,
///                    parent meetings). `groupId` null.
///   - `sub`        — covering for an absent teacher. `groupId`
///                    is the room they're subbing in.
///
/// One-off changes (Sarah's home from Lions but covering Bears
/// today) live in [AdultRoleBlockOverrides]. The resolver layers
/// pattern → overrides for a given date.
@DataClassName('AdultRoleBlock')
class AdultRoleBlocks extends Table {
  TextColumn get id => text()();
  TextColumn get adultId => text()
      .references(Adults, #id, onDelete: KeyAction.cascade)();

  /// 1 = Mon … 7 = Sun. Same convention as
  /// `DateTime.weekday` and the rest of the app.
  IntColumn get weekday => integer()();

  /// Minutes from midnight. Half-open `[start, end)`. Storing as
  /// minutes (not HH:mm strings) keeps overlap math straight in
  /// the resolver — no parsing per comparison.
  IntColumn get startMinute => integer()();
  IntColumn get endMinute => integer()();

  /// Stored as text. Validated client-side via the
  /// `RoleBlockKind` enum in
  /// `lib/features/adults/role_blocks_repository.dart`. Cloud
  /// has a CHECK constraint enumerating the allowed values
  /// (see migration 0018) so a typo in raw SQL doesn't sneak in.
  TextColumn get kind => text()();

  /// Specialist subject — "Art", "Music", "Movement". Set only
  /// when `kind = 'specialist'` (and even then it's optional —
  /// floor specialists exist who teach mixed content). Null
  /// otherwise.
  TextColumn get subject => text().nullable()();

  /// Which classroom the adult is in during this block. Required
  /// for `anchor` / `specialist` / `sub`; null for break/lunch/
  /// admin (the adult isn't in any room).
  TextColumn get groupId => text()
      .nullable()
      .references(Groups, #id, onDelete: KeyAction.setNull)();

  /// Owning program. Same rule as everywhere else.
  TextColumn get programId => text().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Date-specific override on the role-block timeline (v48). Two
/// modes:
///   - `replaces = true`  — wipes any pattern blocks that overlap
///     this time on this date and substitutes this one. Use for
///     "Sarah is out today, Marcus subs in 9-10."
///   - `replaces = false` — adds a one-off block on top of the
///     pattern. Use for "extra music session 3-4 today" without
///     touching the regular pattern.
///
/// Resolver semantics: given a date D, the day plan = pattern
/// blocks for `D.weekday` minus anything with a `replaces`
/// override for D, plus all overrides for D. Layer order matters
/// only when overrides and pattern collide; `replaces` wins.
@DataClassName('AdultRoleBlockOverride')
class AdultRoleBlockOverrides extends Table {
  TextColumn get id => text()();
  TextColumn get adultId => text()
      .references(Adults, #id, onDelete: KeyAction.cascade)();

  /// Calendar date the override applies to. Day-only granularity
  /// (time component ignored) — matches `Trips.date` and other
  /// date-only fields in the schema.
  DateTimeColumn get date => dateTime()();

  IntColumn get startMinute => integer()();
  IntColumn get endMinute => integer()();
  TextColumn get kind => text()();
  TextColumn get subject => text().nullable()();
  TextColumn get groupId => text()
      .nullable()
      .references(Groups, #id, onDelete: KeyAction.setNull)();

  /// True when this override blocks any overlapping pattern row
  /// for this date. False when it's additive (extra block on top
  /// of the pattern). Default false — additive is the safer
  /// guess if the author forgets to flip it.
  BoolColumn get replaces =>
      boolean().withDefault(const Constant(false))();

  TextColumn get programId => text().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Staff job titles / roles (v39). Promotes the free-text
/// [Adults.role] blurb into a shared picklist so "Art teacher" is
/// typed once, picked thereafter. Legacy string still lives on the
/// adult row as a display fallback for pre-v39 entries.
@DataClassName('Role')
class Roles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// Owning program (v42). See [Groups.programId] for the rule.
  TextColumn get programId => text().nullable()();

  /// v52: archive without losing historical attribution. A role
  /// used last year stays on past observations / staff records
  /// even after the program rotates curriculum.
  DateTimeColumn get archivedAt => dateTime().nullable()();

  /// v52: user-orderable display order in the role picker.
  IntColumn get position => integer().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Adults in the program — teachers, adults, directors, kitchen,
/// nurse, etc. The UI surfaces these as "Adults."
///
/// Structural role (v28) governs how the adult participates in the
/// schedule:
///   - 'lead'       → anchored to a single group all day, in that
///                     group's home room by default
///   - 'adult' → rover who rotates between activities (existing
///                     behavior)
///   - 'ambient'    → present in the building but not on the activity
///                     grid (director, nurse, kitchen, front desk)
///
/// [role] (the free-form text) stays as the job-title blurb
/// ("Art teacher", "Head cook"). [adultRole] is the structural one.
@DataClassName('Adult')
class Adults extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get role => text().nullable()();
  /// FK to Roles (v39). The legacy free-text `role` column above stays
  /// as a display fallback for adults created before the promotion —
  /// new rows can leave it null once the picker populates `roleId`.
  TextColumn get roleId => text()
      .nullable()
      .references(Roles, #id, onDelete: KeyAction.setNull)();
  TextColumn get notes => text().nullable()();
  // Local file path for the adult's photo. Remote upload comes later.
  TextColumn get avatarPath => text().nullable()();

  /// v44: bucket-relative path of the avatar in the `media`
  /// bucket. See Children.avatarStoragePath for the same role.
  TextColumn get avatarStoragePath => text().nullable()();

  /// v51: per-upload content tag. See Children.avatarEtag for the
  /// rationale — same fix for the same staleness gap.
  TextColumn get avatarEtag => text().nullable()();

  /// v40: direct contact columns on the adult row itself. Both
  /// nullable — programs that don't capture staff phone/email yet
  /// leave them blank. Validation is lenient (match Parents' shape),
  /// and tap-to-call / tap-to-email on the detail screen keys off
  /// the raw strings.
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();

  /// Set when this staff member is also a parent of a child in the
  /// program. The Parents row carries phone/email /
  /// pickup-authorization; the Adults row carries shift + role.
  /// Both can be true simultaneously.
  TextColumn get parentId => text()
      .nullable()
      .references(Parents, #id, onDelete: KeyAction.setNull)();

  // -- v28: adult roles --

  /// 'lead' | 'specialist' | 'ambient'. v52 normalizes the
  /// historical 'adult' default to 'specialist' (cloud migration
  /// 0027 + Drift v52 onUpgrade do the in-place UPDATE) to match
  /// the AdultRole enum's dbValues. New rows default to
  /// 'specialist'; legacy 'adult' rows are migrated.
  TextColumn get adultRole =>
      text().withDefault(const Constant('specialist'))();

  /// For leads: the single group they're anchored to all day. For
  /// adults and ambient staff: null. FK setNull on delete so
  /// removing a group doesn't orphan the adult.
  TextColumn get anchoredGroupId => text()
      .nullable()
      .references(Groups, #id, onDelete: KeyAction.setNull)();

  /// Owning program (v42). See [Groups.programId] for the rule.
  TextColumn get programId => text().nullable()();

  /// v52: archive ex-staff without losing observation/audit
  /// attribution.
  DateTimeColumn get archivedAt => dateTime().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Physical rooms / zones in the building where activities happen.
/// Named entities (v28) instead of free-form location strings, so the
/// conflict layer can catch "two rovers in the same room at once"
/// reliably. Playground, Outdoor Field, Main Room — all rooms.
///
/// Off-site addresses (field trips to the zoo) are NOT rooms; those
/// stay as free-form text on the trip / entry row with a Google Maps
/// tap-to-open affordance, and aren't subject to room conflict rules.
class Rooms extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// Optional soft cap on headcount. Used by the conflict layer's
  /// future "this room is oversubscribed" rule; no hard enforcement.
  IntColumn get capacity => integer().nullable()();

  TextColumn get notes => text().nullable()();

  /// When set, this is a group's "home room" — the default location
  /// for any activity with that group. Auto-fills the room picker in
  /// the activity form. Nullable: shared rooms (the gym) have no
  /// default group. FK setNull so deleting a group leaves the room in
  /// place, just un-anchored.
  TextColumn get defaultForGroupId => text()
      .nullable()
      .references(Groups, #id, onDelete: KeyAction.setNull)();

  /// Owning program (v42). See [Groups.programId] for the rule.
  TextColumn get programId => text().nullable()();

  /// v52: archive renovated / closed rooms without breaking
  /// historical schedule rows that reference them.
  DateTimeColumn get archivedAt => dateTime().nullable()();

  /// v52: user-orderable display order in the room picker.
  IntColumn get position => integer().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Recurring weekly schedule items. `dayOfWeek` uses ISO 1..7 (Mon..Sun).
/// Times are stored as "HH:mm" strings so they survive timezone shifts.
///
/// [startDate] / [endDate] are optional inclusive date bounds. When set, the
/// template only applies on dates within that range.
class ScheduleTemplates extends Table {
  TextColumn get id => text()();
  IntColumn get dayOfWeek => integer()();
  TextColumn get startTime => text()();
  TextColumn get endTime => text()();
  BoolColumn get isFullDay => boolean().withDefault(const Constant(false))();
  TextColumn get title => text()();
  // Shared id for templates created together in the same wizard pass
  // (one row per picked day). Used by "delete every occurrence" to
  // wipe every weekday's instance of the same activity at once, not
  // just the one row the teacher happened to tap. Null for legacy
  // rows predating the column and for single-day templates; deletion
  // semantics fall back to a row-by-row delete in that case.
  //
  // Named [seriesId] since schema v25 — the word "group" now refers to
  // the user-facing people-grouping (formerly "group") on every other
  // column.
  TextColumn get seriesId => text().nullable()();
  TextColumn get groupId =>
      text().nullable().references(Groups, #id, onDelete: KeyAction.setNull)();
  // True when this activity is intentionally for every group (no
  // restriction); false when the teacher picked specific groups or
  // explicitly picked nobody (staff meeting, prep block, etc).
  // Pre-schema-22 we inferred "all groups" from an empty
  // template_groups list, which conflated "for everyone" with "for
  // nobody yet chosen".
  BoolColumn get allGroups => boolean().withDefault(const Constant(true))();
  // Deprecated: use adultId instead. Retained for migration backfill only.
  TextColumn get adultName => text().nullable()();
  TextColumn get adultId => text()
      .nullable()
      .references(Adults, #id, onDelete: KeyAction.setNull)();
  TextColumn get location => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  // Back-reference to the activity library row this template was created
  // from (via "From library" in the wizard). Null when the teacher
  // typed the activity from scratch. Used by the Today detail sheet to
  // offer a "view activity card" link back to the rich library content
  // (hook / summary / key points / learning goals). setNull on delete
  // so removing the library entry doesn't nuke the scheduled row.
  TextColumn get sourceLibraryItemId => text().nullable().references(
        ActivityLibrary,
        #id,
        onDelete: KeyAction.setNull,
      )();
  /// Optional reference to a tracked room (v28). When set, this is the
  /// authoritative location and participates in room conflict detection.
  /// The free-form [location] string stays for ad-hoc notes ("north
  /// corner of the gym") and for backwards compat with pre-v28 rows.
  TextColumn get roomId => text()
      .nullable()
      .references(Rooms, #id, onDelete: KeyAction.setNull)();

  /// v40: optional reference link the teacher pasted when creating
  /// the activity. Rendered tappably on the detail sheet so teachers
  /// can jump to the source page (recipe, lesson plan, article).
  /// Independent of the rich library-card `sourceUrl` — this is per-
  /// occurrence metadata.
  TextColumn get sourceUrl => text().nullable()();

  /// Owning program (v42). See [Groups.programId] for the rule.
  TextColumn get programId => text().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Maps a schedule template to 0..N groups. Empty set = "all groups".
class TemplateGroups extends Table {
  TextColumn get templateId => text().references(
        ScheduleTemplates,
        #id,
        onDelete: KeyAction.cascade,
      )();
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {templateId, groupId};
}

/// Maps a per-date schedule entry to 0..N groups. Empty set = "all groups".
class EntryGroups extends Table {
  TextColumn get entryId => text().references(
        ScheduleEntries,
        #id,
        onDelete: KeyAction.cascade,
      )();
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {entryId, groupId};
}

// ParentConcernNotes table — REMOVED in schema v45. The form
// migrated to the polymorphic form_submissions architecture
// (commit 3784201). The v45 onUpgrade block carried any remaining
// rows forward + dropped the bespoke table. Left this marker so
// the absence is intentional, not accidental.

/// One row per (child, date) with the day's attendance status.
/// `status` is a string so new values (e.g. "excused") can be added
/// without migrations — the enum lives on the Dart side.
///
/// Rows only exist for days where someone explicitly set a status;
/// an absent row means "not yet checked in" rather than "present by
/// default", so the UI can show a neutral pending state.
class Attendance extends Table {
  TextColumn get childId => text().references(
        Children,
        #id,
        onDelete: KeyAction.cascade,
      )();
  DateTimeColumn get date => dateTime()();

  /// One of AttendanceStatus.name values: 'present', 'absent', 'late',
  /// 'leftEarly'. Stored as text so adding a new status later is just
  /// a Dart enum change plus UI, not a migration.
  TextColumn get status => text()();

  /// Clock time the child was checked in / out, HH:mm. Populated for
  /// late / leftEarly; optional for present.
  TextColumn get clockTime => text().nullable()();

  /// Short free-text note — e.g. "picked up early by Dad, out at 2pm".
  TextColumn get notes => text().nullable()();

  /// v30: pickup tracking. Row stays in the 'present' status; a
  /// non-null [pickupTime] marks the child as collected for the day.
  /// That's enough to drive the "still here past expected pickup"
  /// overdue flag on Today — we don't move them out of 'present' so
  /// the day's roll count ("12/14 present") stays meaningful even
  /// after everyone goes home.
  TextColumn get pickupTime => text().nullable()();

  /// Who picked the child up — free-form so it covers dad / grandma /
  /// named friend / "backup contact" without needing a structured
  /// caregivers table yet. Shown on the pickup row + in future
  /// reports.
  TextColumn get pickedUpBy => text().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {childId, date};
}

// ParentConcernChildren cascade table — REMOVED in v45 alongside
// ParentConcernNotes. The polymorphic form_submissions row stores
// the multi-child link as a JSON array under `data.child_ids`.

/// Generic submission row for the polymorphic forms system (v34). A
/// single row represents one filled-in form of any type — vehicle
/// check, behavior monitoring, future custom forms. The
/// form-type-specific fields live in the `data` JSON blob keyed by
/// the field's key; the columns here are just the axes
/// the UI and reports query on (type, context, status, dates).
///
/// Why hybrid (typed columns + JSON blob):
///   - Indexable columns for the common question axes (child, group,
///     trip, type, status, due-at) — Today's flags-strip scan and
///     "every concern for Noah" lookups stay fast.
///   - JSON `data` for the form-type-specific fields — new forms
///     don't require a migration, and we're not on the hook for
///     maintaining 200 bespoke columns as new forms land.
///
/// ParentConcernNotes stays as-is (bespoke table) for compatibility;
/// new forms go through this table from day one. Migrating the old
/// concern rows over is a later slice.
@DataClassName('FormSubmission')
class FormSubmissions extends Table {
  TextColumn get id => text()();

  /// Short string that identifies the form type — e.g. 'vehicle_check',
  /// 'behavior_monitoring'. Resolved to a `FormDefinition` in Dart.
  /// Values stay stable forever (they're the on-disk encoding); new
  /// form types are new strings, not renames.
  TextColumn get formType => text()();

  /// Lifecycle state. 'draft' is the default for a just-opened form;
  /// 'active', 'completed', 'archived' are form-type-specific phase
  /// labels — the monitoring form moves through active → completed;
  /// simpler forms jump straight to completed on save.
  TextColumn get status =>
      text().withDefault(const Constant('draft'))();

  /// Stamped when the teacher hits Save on a finished submission.
  /// Null while still being edited.
  DateTimeColumn get submittedAt => dateTime().nullable()();

  /// Free-text author for now. Becomes a logged-in-user FK later
  /// without a schema change.
  TextColumn get authorName => text().nullable()();

  // -- Indexed context links. Nullable because not every form scopes
  //    to every kind of subject. The form definition declares which
  //    subject kind it expects.
  TextColumn get childId =>
      text().nullable().references(Children, #id, onDelete: KeyAction.setNull)();
  TextColumn get groupId =>
      text().nullable().references(Groups, #id, onDelete: KeyAction.setNull)();
  TextColumn get tripId =>
      text().nullable().references(Trips, #id, onDelete: KeyAction.setNull)();

  /// Self-reference — a Behavior Monitoring submission points at the
  /// Parent Concern it follows up on. Generalizable to any
  /// follow-up-style form linking to a parent form.
  TextColumn get parentSubmissionId =>
      text().nullable().references(FormSubmissions, #id, onDelete: KeyAction.setNull)();

  /// Optional review / follow-up deadline. Today's flags strip scans
  /// this column across all form types to surface "monitoring review
  /// due" and future "incident report overdue" signals with one
  /// query. Null = no deadline.
  DateTimeColumn get reviewDueAt => dateTime().nullable()();

  /// JSON-encoded map of answers keyed by FormField.key. Defaults to
  /// an empty object so a fresh draft row is valid.
  TextColumn get data =>
      text().withDefault(const Constant('{}'))();

  /// Owning program (v42). See [Groups.programId] for the rule.
  TextColumn get programId => text().nullable()();

  /// v52: auth user id of whoever submitted the form. Same role
  /// as [Observations.createdBy] — lets the UI render "Vehicle
  /// check completed by Marcus" with a stable link to the
  /// member, while [authorName] stays as a fallback for legacy
  /// rows.
  TextColumn get createdBy => text().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Per-date schedule entries. `kind` is 'addition' | 'override' | 'cancellation'.
/// When 'override' or 'cancellation', `overridesTemplateId` points to the template
/// that this entry modifies for the given `date`.
class ScheduleEntries extends Table {
  TextColumn get id => text()();
  DateTimeColumn get date => dateTime()();
  // Optional end of a multi-day range. When null, the entry applies
  // only to `date` (original behaviour). When set, the entry applies
  // to every date in `[date, endDate]` inclusive — used by multi-day
  // events and notes.
  DateTimeColumn get endDate => dateTime().nullable()();
  TextColumn get startTime => text()();
  TextColumn get endTime => text()();
  BoolColumn get isFullDay => boolean().withDefault(const Constant(false))();
  TextColumn get title => text()();
  TextColumn get groupId =>
      text().nullable().references(Groups, #id, onDelete: KeyAction.setNull)();
  // Mirror of ScheduleTemplates.allGroups — see the comment there.
  BoolColumn get allGroups => boolean().withDefault(const Constant(true))();
  // Deprecated: use adultId instead. Retained for migration backfill only.
  TextColumn get adultName => text().nullable()();
  TextColumn get adultId => text()
      .nullable()
      .references(Adults, #id, onDelete: KeyAction.setNull)();
  TextColumn get location => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get kind => text()();
  // Backreference to a Trip that spawned this entry. When set, deleting the
  // trip cascades and removes the entry, keeping the calendar in sync.
  TextColumn get sourceTripId =>
      text().nullable().references(Trips, #id, onDelete: KeyAction.cascade)();
  TextColumn get overridesTemplateId => text().nullable().references(
        ScheduleTemplates,
        #id,
        onDelete: KeyAction.setNull,
      )();
  // Mirror of [ScheduleTemplates.sourceLibraryItemId]. Same rules:
  // null when created from scratch; setNull on library delete so the
  // entry survives.
  TextColumn get sourceLibraryItemId => text().nullable().references(
        ActivityLibrary,
        #id,
        onDelete: KeyAction.setNull,
      )();
  /// Mirror of [ScheduleTemplates.roomId]. Participates in room
  /// conflict detection. Null for off-site / free-form locations
  /// (field trips — those keep their address in [location]).
  TextColumn get roomId => text()
      .nullable()
      .references(Rooms, #id, onDelete: KeyAction.setNull)();

  /// Mirror of [ScheduleTemplates.sourceUrl] (v40). Per-occurrence
  /// reference link, independent of any library-card source.
  TextColumn get sourceUrl => text().nullable()();

  /// Owning program (v42). See [Groups.programId] for the rule.
  TextColumn get programId => text().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Parents / guardians (v38). Promotes the free-text `parentName`
/// on Children into a real entity so siblings share a single row
/// and contact info lives in one place. Nothing else in the schema
/// FKs into this table yet; the parent-concern form still keeps
/// its own free-text `parent_name` for back-compat, but a follow-up
/// can swap it over to a picker the same way vehicle_check swapped
/// make/model for a vehicle id.
///
/// Relationship is free-form text ("mom", "dad", "grandmother",
/// "guardian", "auntie") — programs use whatever label they
/// actually use, no enum. Phone/email are both nullable so "name
/// only" rows are fine for programs that don't want to capture
/// contact methods yet.
@DataClassName('Parent')
class Parents extends Table {
  TextColumn get id => text()();
  TextColumn get firstName => text()();
  TextColumn get lastName => text().nullable()();

  /// Free-text relationship label. "Mom", "Dad", "Grandmother",
  /// "Guardian", "Auntie" — programs decide. Shown next to the name
  /// on child-detail cards.
  TextColumn get relationship => text().nullable()();

  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get notes => text().nullable()();

  /// Owning program (v42). See [Groups.programId] for the rule.
  TextColumn get programId => text().nullable()();

  /// v52: archive former families without losing the link to
  /// historical observations / attendance.
  DateTimeColumn get archivedAt => dateTime().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Many-to-many join between [Parents] and [Children]. Siblings
/// sharing a parent = one parent row with multiple join rows. A
/// child can have multiple parent rows too (two moms, mom + step-
/// dad, etc).
///
/// `isPrimary` marks the default pickup contact for a child. At
/// most one primary per child is the UX convention, enforced at
/// the repository layer (setting one clears any other) — SQLite
/// has no partial-unique constraint that would enforce it
/// server-side without dialect tricks.
/// Per-table sync watermark. Tracks the most recent `updated_at`
/// pulled from cloud for each (program, table) pair so the next
/// pull-on-launch only fetches deltas. Slice C populates this on
/// every successful pull; pre-Slice-C tables don't have rows here
/// and use a sentinel of `1970-01-01` on first read.
@DataClassName('SyncWatermark')
class SyncState extends Table {
  TextColumn get programId => text()();

  /// SQL table this watermark applies to (e.g. `observations`).
  /// Named `targetTable` because Drift's TableInfo mixin already
  /// uses `tableName` and `entityName` for its own metadata, so a
  /// collision-free Dart name is needed. Drift maps the snake-case
  /// SQL column to `target_table` automatically.
  TextColumn get targetTable => text()();

  /// Latest `updated_at` we've seen from the cloud for this
  /// (program, table). Stored UTC; the cloud column is timestamptz
  /// so timezone is unambiguous.
  DateTimeColumn get lastPulledAt => dateTime()();

  /// Stamped on every successful pull so a developer can tell at a
  /// glance when the last sync ran.
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {programId, targetTable};
}

class ParentChildren extends Table {
  TextColumn get parentId =>
      text().references(Parents, #id, onDelete: KeyAction.cascade)();
  TextColumn get childId =>
      text().references(Children, #id, onDelete: KeyAction.cascade)();

  /// Primary pickup contact for this child. At most one primary
  /// per child (repository-enforced, not FK-enforced).
  BoolColumn get isPrimary =>
      boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// v52: stamped on every UPDATE (cloud-side touch trigger,
  /// local-side via repo writes) so the watermarked pull picks
  /// up isPrimary toggles. Without this column the pull never
  /// noticed primary-flag flips since the row's natural-PK was
  /// stable.
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {parentId, childId};
}

/// A program (school, after-school site, classroom, neighborhood
/// circle — eventually any "room" in the First Mate frame). Every
/// data table will eventually carry a `program_id` so a single
/// Supabase database can host many programs without leaking data
/// across them. Multiple users can be members of one program — the
/// program is the unit of sharing.
///
/// Created locally on first sign-in (the user becomes the lone
/// admin of a default "My Program") and pushed up to Supabase via
/// the Slice C sync. The `createdBy` column stores the Supabase
/// `auth.users.id` (UUID as text) of whichever user kicked it off.
@DataClassName('Program')
class Programs extends Table {
  TextColumn get id => text()();

  /// Display name shown in the program switcher and on the launcher
  /// chip. Editable after creation.
  TextColumn get name => text()();

  /// Supabase auth user id (UUID as string) of the member who
  /// created the program. Stays as a text reference rather than a
  /// real FK because Drift has no row in auth.users to link to —
  /// the FK lives in Supabase only, not locally.
  TextColumn get createdBy => text()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Many-to-many membership join: which Supabase users belong to
/// which Program, and at what role. The composite PK
/// (programId, userId) is what RLS policies will eventually scope
/// against on the cloud side.
///
/// Roles for v1: `'admin'` and `'teacher'`. Admins can rename the
/// program and invite/remove other members; teachers can write
/// program data but not change membership. The string is
/// intentionally not enum-typed so we can grow it (`viewer`,
/// `parent`, etc.) without a schema migration.
class ProgramMembers extends Table {
  TextColumn get programId =>
      text().references(Programs, #id, onDelete: KeyAction.cascade)();

  /// Supabase auth user id (UUID as string). No FK — see
  /// [Programs.createdBy] for the same reasoning.
  TextColumn get userId => text()();

  /// Free-text role label. Conventional values right now: `admin`,
  /// `teacher`. Surfaced in the (future) member-list UI. Defaulted
  /// to `teacher` so manual inserts don't leave it null.
  TextColumn get role => text().withDefault(const Constant('teacher'))();

  /// v52: human-readable display name for the members card.
  /// Populated by the bootstrap from `auth.users.raw_user_meta_data`
  /// on every membership upsert. Falls back to a UUID prefix when
  /// null. Editable later (a "what should everyone call you"
  /// settings flow can swap it).
  TextColumn get displayName => text().nullable()();

  DateTimeColumn get joinedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {programId, userId};
}

/// Local-only blob cache for Supabase Storage objects (avatar
/// photos, observation thumbnails, etc.). Keyed by the bucket-
/// relative `storage_path`, the same string the cloud row carries
/// in its `avatar_storage_path` / `storage_path` column. Bytes
/// are populated on first signed-URL fetch; later reads come
/// straight from Drift without hitting the network.
///
/// Why a Drift blob instead of an FS-only cache:
///   * Web has no filesystem — every cross-device avatar would
///     re-mint a signed URL on every page reload + re-download
///     bytes from Supabase. With Drift (IndexedDB on web), one
///     download per device per photo, persistent across reloads.
///   * Native still uses the file-system cache
///     (`MediaService.ensureLocalFile`) for read-by-path APIs
///     like `Image.file`; this table is the web equivalent. The
///     two coexist — `ensureLocalFile` is a no-op on web; the
///     blob cache is queried first on web only.
///
/// Local-only: `MediaCache` is **not** in `kSyncedTableNames`
/// (the sync engine never pushes or pulls it). Each device
/// downloads its own copy on demand. A wipe of local data clears
/// the cache; the next render re-fetches from Supabase Storage.
class MediaCache extends Table {
  /// Bucket-relative key, e.g.
  /// `<programId>/avatars/children/<id>.jpg`.
  TextColumn get storagePath => text()();

  /// Raw bytes from Supabase Storage. Photos are typically
  /// 30–150 KB after the picker's 1000px / 85% JPEG re-encode,
  /// so a program with 50 children + 20 adults caches well under
  /// 10 MB total.
  BlobColumn get bytes => blob()();

  /// Optional MIME hint so the renderer can pick the right
  /// decoder. We always store the bytes verbatim — Flutter's
  /// image codecs sniff the magic bytes themselves — but having
  /// the type written down helps debugging.
  TextColumn get contentType => text().nullable()();

  /// v51: which content version these bytes are. Mirrors the
  /// owning row's `avatar_etag` (or other etag-bearing column).
  /// Reads compare the cache row's etag against the requested
  /// etag — any mismatch evicts and re-fetches. Null is treated
  /// as a wildcard match for backwards compatibility with rows
  /// that don't carry an etag yet (legacy or non-versioned media
  /// like observation attachments).
  TextColumn get etag => text().nullable()();

  /// Stamped on every successful fetch / refresh. Used to drive
  /// future TTL-based expiration if a photo is updated cloud-side
  /// (today the row's `avatar_storage_path` includes a stable id;
  /// when we eventually rotate keys, this column is the lever).
  DateTimeColumn get cachedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {storagePath};

  @override
  String? get tableName => 'media_cache';
}
