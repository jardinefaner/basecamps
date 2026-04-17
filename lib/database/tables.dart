import 'package:drift/drift.dart';

class Pods extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get colorHex => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Kids extends Table {
  TextColumn get id => text()();
  TextColumn get firstName => text()();
  TextColumn get lastName => text().nullable()();
  TextColumn get podId =>
      text().nullable().references(Pods, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get birthDate => dateTime().nullable()();
  TextColumn get pin => text().nullable()();
  TextColumn get notes => text().nullable()();
  // Primary parent/guardian name, used to pre-fill the parent concern
  // note form when a kid is selected. Free-form for now; if we add
  // formal Parent records later these kids can be joined against them.
  TextColumn get parentName => text().nullable()();
  // Local file path for the kid's photo. Remote upload comes later.
  TextColumn get avatarPath => text().nullable()();
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

/// Pods going on a given trip. Empty set is interpreted as "all pods".
class TripPods extends Table {
  TextColumn get tripId =>
      text().references(Trips, #id, onDelete: KeyAction.cascade)();
  TextColumn get podId =>
      text().references(Pods, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {tripId, podId};
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

class CaptureKids extends Table {
  TextColumn get captureId =>
      text().references(Captures, #id, onDelete: KeyAction.cascade)();
  TextColumn get kidId =>
      text().references(Kids, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {captureId, kidId};
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

/// Maps an observation to 0..N kids. Observations primarily target kids
/// via this join table; the legacy single [Observations.kidId] column is
/// kept for older rows.
class ObservationKids extends Table {
  TextColumn get observationId => text()
      .references(Observations, #id, onDelete: KeyAction.cascade)();
  TextColumn get kidId =>
      text().references(Kids, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {observationId, kidId};
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
  TextColumn get kidId =>
      text().nullable().references(Kids, #id, onDelete: KeyAction.setNull)();
  TextColumn get podId =>
      text().nullable().references(Pods, #id, onDelete: KeyAction.setNull)();
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

/// Reusable activity definitions. Picking one from the library during
/// schedule creation prefills the title, default duration, specialist,
/// location and notes.
class ActivityLibrary extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  IntColumn get defaultDurationMin => integer().nullable()();
  TextColumn get specialistId => text()
      .nullable()
      .references(Specialists, #id, onDelete: KeyAction.setNull)();
  TextColumn get location => text().nullable()();
  TextColumn get notes => text().nullable()();
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
class SpecialistAvailability extends Table {
  TextColumn get id => text()();
  TextColumn get specialistId => text()
      .references(Specialists, #id, onDelete: KeyAction.cascade)();
  IntColumn get dayOfWeek => integer()();
  TextColumn get startTime => text()();
  TextColumn get endTime => text()();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Named people who run activities (art teacher, swim instructor, etc.).
/// Not user accounts yet — just named entities linked from schedule items.
class Specialists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get role => text().nullable()();
  TextColumn get notes => text().nullable()();
  // Local file path for the specialist's photo. Remote upload comes later.
  TextColumn get avatarPath => text().nullable()();
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
  TextColumn get groupId => text().nullable()();
  TextColumn get podId =>
      text().nullable().references(Pods, #id, onDelete: KeyAction.setNull)();
  // Deprecated: use specialistId instead. Retained for migration backfill only.
  TextColumn get specialistName => text().nullable()();
  TextColumn get specialistId => text()
      .nullable()
      .references(Specialists, #id, onDelete: KeyAction.setNull)();
  TextColumn get location => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Maps a schedule template to 0..N pods. Empty set = "all pods".
class TemplatePods extends Table {
  TextColumn get templateId => text().references(
        ScheduleTemplates,
        #id,
        onDelete: KeyAction.cascade,
      )();
  TextColumn get podId =>
      text().references(Pods, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {templateId, podId};
}

/// Maps a per-date schedule entry to 0..N pods. Empty set = "all pods".
class EntryPods extends Table {
  TextColumn get entryId => text().references(
        ScheduleEntries,
        #id,
        onDelete: KeyAction.cascade,
      )();
  TextColumn get podId =>
      text().references(Pods, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {entryId, podId};
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
  TextColumn get podId =>
      text().nullable().references(Pods, #id, onDelete: KeyAction.setNull)();
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
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
