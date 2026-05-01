import 'dart:async';
import 'dart:convert';

import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/program_scope.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:basecamp/features/sync/sync_specs.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ActivityLibraryRepository {
  ActivityLibraryRepository(this._db, this._ref);

  final AppDatabase _db;
  final Ref _ref;

  /// See ObservationsRepository._programId for why we read this on
  /// every insert rather than caching at construction time.
  String? get _programId => _ref.read(activeProgramIdProvider);

  SyncEngine get _sync => _ref.read(syncEngineProvider);

  Stream<List<ActivityLibraryData>> watchAll() {
    // Newest first — the user's spec for the creation flow ends with
    // the freshly-generated card appearing at the top of the bucket,
    // and that's the intuitive order for a bucket anyway.
    final query = _db.select(_db.activityLibrary)
      ..where((a) => matchesActiveProgram(a.programId, _programId))
      ..orderBy([(a) => OrderingTerm.desc(a.createdAt)]);
    return query.watch();
  }

  Future<ActivityLibraryData?> getItem(String id) {
    return (_db.select(_db.activityLibrary)..where((a) => a.id.equals(id)))
        .getSingleOrNull();
  }

  Future<String> addItem({
    required String title,
    int? defaultDurationMin,
    String? adultId,
    String? location,
    String? notes,
    // Rich card fields — all optional so legacy "just a preset" rows
    // (title + duration etc.) still work through the same API.
    int? audienceMinAge,
    int? audienceMaxAge,
    String? hook,
    String? summary,
    String? keyPoints,
    String? learningGoals,
    int? engagementTimeMin,
    String? sourceUrl,
    String? sourceAttribution,
    String? materials,
    Map<int, AgeVariant>? ageVariants,
  }) async {
    final id = newId();
    await _db.into(_db.activityLibrary).insert(
          ActivityLibraryCompanion.insert(
            id: id,
            title: title,
            defaultDurationMin: Value(defaultDurationMin),
            adultId: Value(adultId),
            location: Value(location),
            notes: Value(notes),
            audienceMinAge: Value(audienceMinAge),
            audienceMaxAge: Value(audienceMaxAge),
            hook: Value(hook),
            summary: Value(summary),
            keyPoints: Value(keyPoints),
            learningGoals: Value(learningGoals),
            engagementTimeMin: Value(engagementTimeMin),
            sourceUrl: Value(sourceUrl),
            sourceAttribution: Value(sourceAttribution),
            materials: Value(materials),
            ageVariants: Value(_encodeAgeVariants(ageVariants)),
            programId: Value(_programId),
          ),
        );
    unawaited(_sync.pushRow(activityLibrarySpec, id));
    return id;
  }

  /// Updates ONLY the fields explicitly provided. Uses Drift's
  /// `Value.absent()` for anything not passed so a caller that only
  /// touches preset fields (title/duration/location/…) doesn't
  /// accidentally null out the rich-card columns (audience, summary,
  /// hook, etc.) just by virtue of not mentioning them.
  ///
  /// Regression fixed here: the edit sheet was calling updateItem with
  /// positional `null`s for rich fields, which got written to the DB
  /// and wiped every AI-generated card on its first edit.
  Future<void> updateItem({
    required String id,
    String? title,
    // Each field uses a `Value<T>` wrapper so callers can distinguish
    // "leave this alone" (absent) from "set it to null" (Value(null)).
    Value<int?> defaultDurationMin = const Value.absent(),
    Value<String?> adultId = const Value.absent(),
    Value<String?> location = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<int?> audienceMinAge = const Value.absent(),
    Value<int?> audienceMaxAge = const Value.absent(),
    Value<String?> hook = const Value.absent(),
    Value<String?> summary = const Value.absent(),
    Value<String?> keyPoints = const Value.absent(),
    Value<String?> learningGoals = const Value.absent(),
    Value<int?> engagementTimeMin = const Value.absent(),
    Value<String?> sourceUrl = const Value.absent(),
    Value<String?> sourceAttribution = const Value.absent(),
    Value<String?> materials = const Value.absent(),
    Value<Map<int, AgeVariant>?> ageVariants = const Value.absent(),
  }) async {
    await (_db.update(_db.activityLibrary)..where((a) => a.id.equals(id)))
        .write(
      ActivityLibraryCompanion(
        title: title == null ? const Value.absent() : Value(title),
        defaultDurationMin: defaultDurationMin,
        adultId: adultId,
        location: location,
        notes: notes,
        audienceMinAge: audienceMinAge,
        audienceMaxAge: audienceMaxAge,
        hook: hook,
        summary: summary,
        keyPoints: keyPoints,
        learningGoals: learningGoals,
        engagementTimeMin: engagementTimeMin,
        sourceUrl: sourceUrl,
        sourceAttribution: sourceAttribution,
        materials: materials,
        ageVariants: ageVariants.present
            ? Value(_encodeAgeVariants(ageVariants.value))
            : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _db.markDirty('activity_library', id, [
      if (title != null) 'title',
      if (defaultDurationMin.present) 'default_duration_min',
      if (adultId.present) 'adult_id',
      if (location.present) 'location',
      if (notes.present) 'notes',
      if (audienceMinAge.present) 'audience_min_age',
      if (audienceMaxAge.present) 'audience_max_age',
      if (hook.present) 'hook',
      if (summary.present) 'summary',
      if (keyPoints.present) 'key_points',
      if (learningGoals.present) 'learning_goals',
      if (engagementTimeMin.present) 'engagement_time_min',
      if (sourceUrl.present) 'source_url',
      if (sourceAttribution.present) 'source_attribution',
      if (materials.present) 'materials',
      if (ageVariants.present) 'age_variants',
    ]);
    unawaited(_sync.pushRow(activityLibrarySpec, id));

    // Title write-through to every linked schedule_template. The
    // library card is the source of truth for an activity's content;
    // a rename here should rename every place that activity is
    // scheduled. Other field changes (summary, materials, etc.) stay
    // on the library row only — they're not mirrored onto templates.
    if (title != null) {
      await _propagateTitleToTemplates(id, title);
    }
  }

  /// Mirror a library card's title onto every schedule_template that
  /// references it. Writes directly via `_db` so we don't pull in the
  /// schedule repo (would create a circular import). Each template
  /// gets its title column marked dirty + pushed so the cloud row
  /// updates too.
  Future<void> _propagateTitleToTemplates(
    String libraryItemId,
    String newTitle,
  ) async {
    final templates = await (_db.select(_db.scheduleTemplates)
          ..where((t) => t.sourceLibraryItemId.equals(libraryItemId)))
        .get();
    if (templates.isEmpty) return;
    final now = DateTime.now();
    for (final t in templates) {
      if (t.title == newTitle) continue;
      await (_db.update(_db.scheduleTemplates)
            ..where((row) => row.id.equals(t.id)))
          .write(
        ScheduleTemplatesCompanion(
          title: Value(newTitle),
          updatedAt: Value(now),
        ),
      );
      await _db.markDirty('schedule_templates', t.id, ['title']);
      unawaited(_sync.pushRow(scheduleTemplatesSpec, t.id));
    }
  }

  Future<void> deleteItem(String id) async {
    final row = await (_db.select(_db.activityLibrary)
          ..where((a) => a.id.equals(id)))
        .getSingleOrNull();
    final programId = row?.programId;
    await (_db.delete(_db.activityLibrary)..where((a) => a.id.equals(id)))
        .go();
    if (programId != null) {
      unawaited(
        _sync.pushDelete(
          spec: activityLibrarySpec,
          id: id,
          programId: programId,
        ),
      );
    }
  }

  Future<void> deleteItems(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final rows = await (_db.select(_db.activityLibrary)
          ..where((a) => a.id.isIn(list)))
        .get();
    await (_db.delete(_db.activityLibrary)..where((a) => a.id.isIn(list)))
        .go();
    for (final r in rows) {
      final programId = r.programId;
      if (programId != null) {
        unawaited(
          _sync.pushDelete(
            spec: activityLibrarySpec,
            id: r.id,
            programId: programId,
          ),
        );
      }
    }
  }

  /// Restore helpers for the undo snackbar — re-insert with the
  /// original id. Cascaded schedule-entry / template source links
  /// (source_library_item_id) are already null from the delete
  /// cascade and don't come back.
  Future<void> restoreItem(ActivityLibraryData row) async {
    await _db.into(_db.activityLibrary).insertOnConflictUpdate(row);
    unawaited(_sync.pushRow(activityLibrarySpec, row.id));
  }

  Future<void> restoreItems(Iterable<ActivityLibraryData> rows) async {
    await _db.transaction(() async {
      for (final row in rows) {
        await _db.into(_db.activityLibrary).insertOnConflictUpdate(row);
      }
    });
    for (final row in rows) {
      unawaited(_sync.pushRow(activityLibrarySpec, row.id));
    }
  }

  // ---- v40: free-text domain tags per library item ----

  /// Adds [domain] to [libraryItemId]. Idempotent — the composite
  /// PK on (library_item_id, domain) collapses duplicate adds.
  Future<void> addDomainTag(String libraryItemId, String domain) async {
    await _db.into(_db.activityLibraryDomainTags).insertOnConflictUpdate(
          ActivityLibraryDomainTagsCompanion.insert(
            libraryItemId: libraryItemId,
            domain: domain,
          ),
        );
    unawaited(_sync.pushRow(activityLibrarySpec, libraryItemId));
  }

  Future<void> removeDomainTag(
    String libraryItemId,
    String domain,
  ) async {
    await (_db.delete(_db.activityLibraryDomainTags)
          ..where((t) =>
              t.libraryItemId.equals(libraryItemId) &
              t.domain.equals(domain)))
        .go();
    unawaited(_sync.pushRow(activityLibrarySpec, libraryItemId));
  }

  /// All domains attached to [libraryItemId], alphabetically. Streamed
  /// so the future picker UI updates live on add/remove.
  Stream<List<String>> watchDomainsFor(String libraryItemId) {
    final query = _db.select(_db.activityLibraryDomainTags)
      ..where((t) => t.libraryItemId.equals(libraryItemId))
      ..orderBy([(t) => OrderingTerm.asc(t.domain)]);
    return query.watch().map((rows) => [for (final r in rows) r.domain]);
  }

  /// One-shot read of the domain tags for [libraryItemId] — the
  /// duplicate flow needs the current snapshot without subscribing.
  Future<List<String>> domainsFor(String libraryItemId) async {
    final rows = await (_db.select(_db.activityLibraryDomainTags)
          ..where((t) => t.libraryItemId.equals(libraryItemId)))
        .get();
    return [for (final r in rows) r.domain];
  }

  /// Stream of `itemId -> set(domain)` for every library row. Used by
  /// the library screen's domain-tag filter chip so the predicate can
  /// consult each card's current tag set without running N per-card
  /// subscriptions. Alphabetical order on the inner set is irrelevant
  /// (it's a membership check).
  Stream<Map<String, Set<String>>> watchAllDomainTags() {
    // Scope through the parent table: domain tags are a cascade
    // (no programId column of their own), so we join to
    // activity_library and filter on its programId.
    final query = _db.select(_db.activityLibraryDomainTags).join([
      innerJoin(
        _db.activityLibrary,
        _db.activityLibrary.id
            .equalsExp(_db.activityLibraryDomainTags.libraryItemId),
      ),
    ])
      ..where(matchesActiveProgram(
        _db.activityLibrary.programId,
        _programId,
      ));
    return query.watch().map((rows) {
      final map = <String, Set<String>>{};
      for (final r in rows) {
        final tag = r.readTable(_db.activityLibraryDomainTags);
        map.putIfAbsent(tag.libraryItemId, () => <String>{}).add(tag.domain);
      }
      return map;
    });
  }

  /// Promote a schedule item's fields into a fresh library card,
  /// returning the new library item id. Copies title, notes →
  /// `summary` (library cards don't have a free-form notes field;
  /// notes is the closest semantic match), `sourceUrl`,
  /// duration (endMinutes - startMinutes → `defaultDurationMin`),
  /// location, adultId. Fields the schedule item doesn't carry stay
  /// null — the teacher can fill them in after.
  ///
  /// Does NOT mutate the source schedule row; the caller is expected
  /// to follow up with updateTemplate/updateEntry to wire the new
  /// sourceLibraryItemId link.
  Future<String> createFromScheduleItem(ScheduleItem item) async {
    final duration = item.endMinutes - item.startMinutes;
    return addItem(
      title: item.title,
      // Full-day items have a bogus 0-minute span; don't persist a
      // useless default. Negative is defensive against a malformed row.
      defaultDurationMin:
          (item.isFullDay || duration <= 0) ? null : duration,
      adultId: item.adultId,
      location: item.location,
      summary: item.notes,
      sourceUrl: item.sourceUrl,
    );
  }

  /// Clones [sourceId] into a fresh row with a suffixed title. Rich-
  /// card fields, audience, materials, etc. are copied verbatim so the
  /// teacher can tweak one detail without rebuilding the whole card.
  /// Domain tags are copied too — a duplicate of a "SSD3 / Empathy"
  /// card should still be taxonomically findable. Returns the new id
  /// so callers can immediately open the copy in the edit sheet.
  Future<String> duplicate(String sourceId) async {
    final source = await getItem(sourceId);
    if (source == null) {
      throw StateError('No library item with id $sourceId');
    }
    final newIdValue = newId();
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db.into(_db.activityLibrary).insert(
            ActivityLibraryCompanion.insert(
              id: newIdValue,
              title: '${source.title} (copy)',
              defaultDurationMin: Value(source.defaultDurationMin),
              adultId: Value(source.adultId),
              location: Value(source.location),
              notes: Value(source.notes),
              audienceMinAge: Value(source.audienceMinAge),
              audienceMaxAge: Value(source.audienceMaxAge),
              hook: Value(source.hook),
              summary: Value(source.summary),
              keyPoints: Value(source.keyPoints),
              learningGoals: Value(source.learningGoals),
              engagementTimeMin: Value(source.engagementTimeMin),
              sourceUrl: Value(source.sourceUrl),
              sourceAttribution: Value(source.sourceAttribution),
              materials: Value(source.materials),
              createdAt: Value(now),
              updatedAt: Value(now),
              programId: Value(_programId),
            ),
          );
      final sourceDomains = await (_db.select(_db.activityLibraryDomainTags)
            ..where((t) => t.libraryItemId.equals(sourceId)))
          .get();
      for (final tag in sourceDomains) {
        await _db.into(_db.activityLibraryDomainTags).insertOnConflictUpdate(
              ActivityLibraryDomainTagsCompanion.insert(
                libraryItemId: newIdValue,
                domain: tag.domain,
              ),
            );
      }
    });
    unawaited(_sync.pushRow(activityLibrarySpec, newIdValue));
    return newIdValue;
  }

  /// A small "nudge" recommender for the card detail sheet's Similar
  /// Activities section. Not a precise ranker — ordered by: shared
  /// domain count desc, then age-range overlap, then whether a
  /// meaningful title token matches. Source item is excluded; results
  /// capped at [limit].
  Future<List<ActivityLibraryData>> similarItems(
    String sourceId, {
    int limit = 5,
  }) async {
    final source = await getItem(sourceId);
    if (source == null) return const [];
    final sourceDomains = (await domainsFor(sourceId)).toSet();
    // Preload domain tags for every row in one shot — keeps this a
    // simple in-memory rank rather than per-item round-trips. Scoped
    // through the parent library table so we don't pull tags from
    // other programs' rows.
    final tagJoin = _db.select(_db.activityLibraryDomainTags).join([
      innerJoin(
        _db.activityLibrary,
        _db.activityLibrary.id
            .equalsExp(_db.activityLibraryDomainTags.libraryItemId),
      ),
    ])
      ..where(matchesActiveProgram(
        _db.activityLibrary.programId,
        _programId,
      ));
    final allTagRows = await tagJoin
        .map((r) => r.readTable(_db.activityLibraryDomainTags))
        .get();
    final tagsByItem = <String, Set<String>>{};
    for (final r in allTagRows) {
      tagsByItem.putIfAbsent(r.libraryItemId, () => <String>{}).add(r.domain);
    }
    final sourceTitleTokens = _titleTokens(source.title);
    final candidates = await (_db.select(_db.activityLibrary)
          ..where((a) =>
              a.id.equals(sourceId).not() &
              matchesActiveProgram(a.programId, _programId)))
        .get();
    final scored = <_SimilarScored>[];
    for (final cand in candidates) {
      final candDomains = tagsByItem[cand.id] ?? const <String>{};
      final sharedDomains = candDomains.intersection(sourceDomains).length;
      final ageOverlap = _agesOverlap(
        source.audienceMinAge,
        source.audienceMaxAge,
        cand.audienceMinAge,
        cand.audienceMaxAge,
      );
      final candTokens = _titleTokens(cand.title);
      final tokenOverlap =
          sourceTitleTokens.intersection(candTokens).isNotEmpty;
      // Skip cards that share nothing — otherwise "similar" would just
      // be "everything else".
      if (sharedDomains == 0 && !ageOverlap && !tokenOverlap) continue;
      scored.add(_SimilarScored(
        item: cand,
        sharedDomains: sharedDomains,
        ageOverlap: ageOverlap,
        tokenOverlap: tokenOverlap,
      ));
    }
    scored.sort((a, b) {
      final byDomain = b.sharedDomains.compareTo(a.sharedDomains);
      if (byDomain != 0) return byDomain;
      final byAge = (b.ageOverlap ? 1 : 0) - (a.ageOverlap ? 1 : 0);
      if (byAge != 0) return byAge;
      final byTitle = (b.tokenOverlap ? 1 : 0) - (a.tokenOverlap ? 1 : 0);
      return byTitle;
    });
    return [for (final s in scored.take(limit)) s.item];
  }

  static Set<String> _titleTokens(String title) {
    // Strip common words so "Morning circle" vs "Circle time" still
    // matches on "circle" without being polluted by stopwords.
    const stop = {
      'a', 'an', 'and', 'the', 'of', 'for', 'to', 'in', 'on', 'with',
      'time', 'activity', 'circle', // ironic, but too generic across cards
    };
    final tokens = title
        .toLowerCase()
        .split(RegExp('[^a-z0-9]+'))
        .where((t) => t.length > 2 && !stop.contains(t))
        .toSet();
    // Keep "circle" in if it's the only token left — "Morning circle"
    // would otherwise match nothing.
    if (tokens.isEmpty) {
      return title
          .toLowerCase()
          .split(RegExp('[^a-z0-9]+'))
          .where((t) => t.isNotEmpty)
          .toSet();
    }
    return tokens;
  }

  static bool _agesOverlap(int? aMin, int? aMax, int? bMin, int? bMax) {
    if ((aMin == null && aMax == null) || (bMin == null && bMax == null)) {
      return false;
    }
    final aLo = aMin ?? 0;
    final aHi = aMax ?? 999;
    final bLo = bMin ?? 0;
    final bHi = bMax ?? 999;
    return aLo <= bHi && aHi >= bLo;
  }

  // ---- v46: age-scaled rendering helpers ----

  /// Returns the row's text rendered for [age]. If
  /// `ActivityLibrary.ageVariants` has a key matching [age], that
  /// variant's `summary` / `keyPoints` / `learningGoals` win;
  /// otherwise we fall back to the unscaled columns. Used by the
  /// curriculum view's "show age scaling" toggle.
  ScaledActivityCard scaleForAge(ActivityLibraryData row, int age) {
    final variants = decodeAgeVariants(row.ageVariants);
    final variant = variants[age];
    return ScaledActivityCard(
      title: row.title,
      hook: row.hook,
      summary: variant?.summary ?? row.summary,
      keyPoints: variant?.keyPoints ?? row.keyPoints,
      learningGoals: variant?.learningGoals ?? row.learningGoals,
      // Materials / source / engagement time aren't age-scaled:
      // they describe the activity logistics, not the framing.
      materials: row.materials,
      sourceAttribution: row.sourceAttribution,
      sourceUrl: row.sourceUrl,
      engagementTimeMin: row.engagementTimeMin,
      // True when at least one variant is defined — drives the
      // curriculum view's toggle visibility.
      hasAgeVariants: variants.isNotEmpty,
    );
  }

  // ---- Internal: age_variants JSON shape ----

  static String? _encodeAgeVariants(Map<int, AgeVariant>? variants) {
    if (variants == null || variants.isEmpty) return null;
    return jsonEncode({
      for (final e in variants.entries) e.key.toString(): e.value.toJson(),
    });
  }

  /// Public so the curriculum view can decode straight off a row
  /// without reaching back into a method on the repository.
  static Map<int, AgeVariant> decodeAgeVariants(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <int, AgeVariant>{};
      decoded.forEach((key, value) {
        final age = int.tryParse(key.toString());
        if (age == null || value is! Map) return;
        out[age] = AgeVariant.fromJson(Map<String, dynamic>.from(value));
      });
      return out;
    } on FormatException {
      // Malformed JSON shouldn't crash the renderer; just fall back
      // to no variants so the unscaled columns are used.
      return const {};
    } on Object {
      return const {};
    }
  }
}

/// One age slot inside `ActivityLibrary.ageVariants` (v46).
class AgeVariant {
  const AgeVariant({this.summary, this.keyPoints, this.learningGoals});

  factory AgeVariant.fromJson(Map<String, dynamic> json) => AgeVariant(
        summary: json['summary'] as String?,
        keyPoints: json['keyPoints'] as String?,
        learningGoals: json['goals'] as String? ??
            json['learningGoals'] as String?,
      );

  final String? summary;
  final String? keyPoints;
  final String? learningGoals;

  Map<String, String?> toJson() => {
        'summary': summary,
        'keyPoints': keyPoints,
        'goals': learningGoals,
      };
}

/// Render-ready card text after age scaling has been applied.
/// The curriculum view consumes this directly — no further fallback
/// logic on the widget side.
class ScaledActivityCard {
  const ScaledActivityCard({
    required this.title,
    required this.hook,
    required this.summary,
    required this.keyPoints,
    required this.learningGoals,
    required this.materials,
    required this.sourceAttribution,
    required this.sourceUrl,
    required this.engagementTimeMin,
    required this.hasAgeVariants,
  });

  final String title;
  final String? hook;
  final String? summary;
  final String? keyPoints;
  final String? learningGoals;
  final String? materials;
  final String? sourceAttribution;
  final String? sourceUrl;
  final int? engagementTimeMin;
  final bool hasAgeVariants;
}

class _SimilarScored {
  const _SimilarScored({
    required this.item,
    required this.sharedDomains,
    required this.ageOverlap,
    required this.tokenOverlap,
  });

  final ActivityLibraryData item;
  final int sharedDomains;
  final bool ageOverlap;
  final bool tokenOverlap;
}

final activityLibraryRepositoryProvider =
    Provider<ActivityLibraryRepository>((ref) {
  return ActivityLibraryRepository(ref.watch(databaseProvider), ref);
});

final activityLibraryProvider =
    StreamProvider<List<ActivityLibraryData>>((ref) {
  ref.watch(activeProgramIdProvider);
  return ref.watch(activityLibraryRepositoryProvider).watchAll();
});

/// Domains attached to a specific library item. Streamed so domain
/// pickers in a later round update live as the teacher adds / removes
/// tags.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final libraryDomainsForItemProvider =
    StreamProvider.family<List<String>, String>((ref, libraryItemId) {
  return ref
      .watch(activityLibraryRepositoryProvider)
      .watchDomainsFor(libraryItemId);
});

/// Screen-wide lookup of `itemId -> set(domain)` for every library
/// row. The library filter chip row consults this so the predicate
/// can check a domain match without spinning up a per-card stream.
final allLibraryDomainTagsProvider =
    StreamProvider<Map<String, Set<String>>>((ref) {
  ref.watch(activeProgramIdProvider);
  return ref.watch(activityLibraryRepositoryProvider).watchAllDomainTags();
});

/// Cached "similar activities" for a given library item. Recomputed
/// whenever the library table changes (via ref.watch on the list
/// provider) so newly added cards join / leave the results live.
// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final similarLibraryItemsProvider =
    FutureProvider.family<List<ActivityLibraryData>, String>(
  (ref, sourceId) async {
    // Re-run when program switches or the library list changes so
    // freshly added (and program-scoped) cards appear.
    ref
      ..watch(activeProgramIdProvider)
      ..watch(activityLibraryProvider)
      ..watch(allLibraryDomainTagsProvider);
    return ref
        .watch(activityLibraryRepositoryProvider)
        .similarItems(sourceId);
  },
);
