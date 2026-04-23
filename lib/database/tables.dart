import 'package:drift/drift.dart';

@DataClassName('Group')
class Groups extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get colorHex => text().nullable()();
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

  // Standing expected drop-off / pickup time for this child, stored
  // as "HH:mm" strings (matches how schedule times are stored in
  // ScheduleTemplates). Nullable — a child with no expected time
  // never triggers lateness flags, which is the right default for
  // drop-in / flexible-schedule kids. Daily variations go through
  // [ChildScheduleOverrides] below.
  TextColumn get expectedArrival => text().nullable()();
  TextColumn get expectedPickup => text().nullable()();

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
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Reusable activity definitions. Originally a set of scheduling
/// presets (title + duration + location + specialist) — the original
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
  TextColumn get specialistId => text()
      .nullable()
      .references(Specialists, #id, onDelete: KeyAction.setNull)();
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

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One block of "I'm available to work" for a specialist — e.g. "Mon
/// 9:00–17:00". Any given specialist can have multiple rows (Mon 9–12,
/// Mon 13–17) to model split shifts, and each row can be bounded by
/// [startDate]/[endDate] to model seasonal work or time off. Same ISO
/// day-of-week convention (1..7) the schedule uses everywhere else.
///
/// v28: added [breakStart]/[breakEnd] + [lunchStart]/[lunchEnd] to
/// encode each adult's daily break + lunch inside their shift, so the
/// Today view can show "on lunch until 1:00" and the conflict layer
/// can warn when activities are scheduled on top of breaks.
class SpecialistAvailability extends Table {
  TextColumn get id => text()();
  TextColumn get specialistId => text()
      .references(Specialists, #id, onDelete: KeyAction.cascade)();
  IntColumn get dayOfWeek => integer()();
  TextColumn get startTime => text()();
  TextColumn get endTime => text()();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  TextColumn get breakStart => text().nullable()();
  TextColumn get breakEnd => text().nullable()();
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
/// into labeled blocks. Models the "pod lead 8:30-11, then specialist
/// rotator 11-12, then back to pod lead 12-3" pattern that the static
/// `Specialist.adultRole` alone can't express.
///
/// Gaps between blocks on a given day are implied "off". Adults with
/// NO blocks for a day fall back to `Specialist.adultRole` interpreted
/// as a single shift-long block (so the existing specialist-as-rotator
/// behavior keeps working for the simple case).
///
/// Break + lunch remain on the specialist_availability row for the
/// MVP; they layer ON TOP of this timeline — a specialist block
/// running 11-12 with a lunch 11:30-12:00 just means the specialist
/// is rotating 11-11:30 and at lunch 11:30-12. Duplicating break /
/// lunch into this table would be noise for the common case.
///
/// `role` values:
///   - 'lead'       — anchored to a pod (requires `pod_id`)
///   - 'specialist' — rotating, no pod
@DataClassName('AdultDayBlock')
class AdultDayBlocks extends Table {
  TextColumn get id => text()();
  TextColumn get specialistId => text()
      .references(Specialists, #id, onDelete: KeyAction.cascade)();

  /// ISO day of week (1 = Mon, 7 = Sun). Program runs M-F so values
  /// are almost always 1..5, but no CHECK constraint — weekend is
  /// legal data, just unused for now.
  IntColumn get dayOfWeek => integer()();

  /// HH:mm wall-clock strings, same format as schedule templates and
  /// availability. Half-open: `[startTime, endTime)` is the span of
  /// the block.
  TextColumn get startTime => text()();
  TextColumn get endTime => text()();

  /// 'lead' or 'specialist'. Bad values fall back to 'specialist' at
  /// read time — matches how `AdultRole.fromDb` handles the similar
  /// field on Specialists.
  TextColumn get role => text()();

  /// For lead blocks — which pod (group) the adult is anchoring
  /// during this span. Null for specialist blocks. FK to groups
  /// with setNull on delete so deleting a pod silently detaches any
  /// legacy lead blocks rather than cascading-deleting the whole
  /// timeline.
  TextColumn get podId => text()
      .nullable()
      .references(Groups, #id, onDelete: KeyAction.setNull)();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Adults in the program — teachers, specialists, directors, kitchen,
/// nurse, etc. Table name stays "specialists" for backwards compat with
/// pre-v28 rows and existing foreign keys. The UI surfaces these as
/// "Adults."
///
/// Structural role (v28) governs how the adult participates in the
/// schedule:
///   - 'lead'       → anchored to a single group all day, in that
///                     group's home room by default
///   - 'specialist' → rover who rotates between activities (existing
///                     behavior)
///   - 'ambient'    → present in the building but not on the activity
///                     grid (director, nurse, kitchen, front desk)
///
/// [role] (the free-form text) stays as the job-title blurb
/// ("Art teacher", "Head cook"). [adultRole] is the structural one.
class Specialists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get role => text().nullable()();
  TextColumn get notes => text().nullable()();
  // Local file path for the specialist's photo. Remote upload comes later.
  TextColumn get avatarPath => text().nullable()();

  // -- v28: adult roles --

  /// 'lead' | 'specialist' | 'ambient'. Null-defaults to 'specialist'
  /// on existing rows (matches current behavior — every adult was
  /// treated as a rover).
  TextColumn get adultRole =>
      text().withDefault(const Constant('specialist'))();

  /// For leads: the single group they're anchored to all day. For
  /// specialists and ambient staff: null. FK setNull on delete so
  /// removing a group doesn't orphan the adult.
  TextColumn get anchoredGroupId => text()
      .nullable()
      .references(Groups, #id, onDelete: KeyAction.setNull)();

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
  // Deprecated: use specialistId instead. Retained for migration backfill only.
  TextColumn get specialistName => text().nullable()();
  TextColumn get specialistId => text()
      .nullable()
      .references(Specialists, #id, onDelete: KeyAction.setNull)();
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

/// Parent concern notes — the first form type. Staff fill one out when a
/// parent raises a concern; the form is broken into sections and can be
/// saved mid-fill and returned to. Most fields are optional (and default
/// to empty strings / nulls) so partial drafts save cleanly.
class ParentConcernNotes extends Table {
  TextColumn get id => text()();

  // Header
  TextColumn get childNames => text().withDefault(const Constant(''))();
  TextColumn get parentName => text().withDefault(const Constant(''))();
  DateTimeColumn get concernDate => dateTime().nullable()();
  TextColumn get staffReceiving => text().withDefault(const Constant(''))();
  TextColumn get supervisorNotified => text().nullable()();

  // Method of communication — a concern can come in through more than
  // one channel in the same conversation, so these are independent
  // flags rather than a single enum.
  BoolColumn get methodInPerson =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get methodPhone => boolean().withDefault(const Constant(false))();
  BoolColumn get methodEmail => boolean().withDefault(const Constant(false))();
  TextColumn get methodOther => text().nullable()();

  // Narrative
  TextColumn get concernDescription =>
      text().withDefault(const Constant(''))();
  TextColumn get immediateResponse =>
      text().withDefault(const Constant(''))();

  // Follow-up plan — same shape as method of communication.
  BoolColumn get followUpMonitor =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get followUpStaffCheckIns =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get followUpSupervisorReview =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get followUpParentConversation =>
      boolean().withDefault(const Constant(false))();
  TextColumn get followUpOther => text().nullable()();
  DateTimeColumn get followUpDate => dateTime().nullable()();

  TextColumn get additionalNotes => text().nullable()();

  // Signatures. [staffSignature] / [supervisorSignature] hold the
  // typed printed name; the *Path columns hold a local PNG exported
  // from the in-form signature pad. Both can be set independently —
  // printed name without drawing is "typed signature", drawing alone
  // is anonymous, and both is the full paper-form equivalent.
  TextColumn get staffSignature => text().nullable()();
  TextColumn get staffSignaturePath => text().nullable()();
  DateTimeColumn get staffSignatureDate => dateTime().nullable()();
  TextColumn get supervisorSignature => text().nullable()();
  TextColumn get supervisorSignaturePath => text().nullable()();
  DateTimeColumn get supervisorSignatureDate => dateTime().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

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

/// Structured link between a parent concern note and each child it
/// mentions. Replaces a lossy substring-match against the free-text
/// `childNames` column — the Today screen uses this join to show
/// "an active concern mentions a child in this group" on the right
/// activity card, and opens the specific concern on tap.
///
/// `childNames` is still kept on the concern row for display/export
/// purposes (the parent's words), but this table is the source of
/// truth for "which children are involved".
class ParentConcernChildren extends Table {
  TextColumn get concernId => text().references(
        ParentConcernNotes,
        #id,
        onDelete: KeyAction.cascade,
      )();
  TextColumn get childId =>
      text().references(Children, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {concernId, childId};
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
  // Deprecated: use specialistId instead. Retained for migration backfill only.
  TextColumn get specialistName => text().nullable()();
  TextColumn get specialistId => text()
      .nullable()
      .references(Specialists, #id, onDelete: KeyAction.setNull)();
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
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
