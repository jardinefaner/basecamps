import 'dart:async';
import 'dart:io' show Directory, File;

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:basecamp/features/sync/sync_specs.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cloud-backed media storage for observation attachments + child
/// and adult avatars. Each row's `storage_path` (or
/// `avatar_storage_path`) is the bucket-relative key in Supabase
/// Storage's `media` bucket. Local files keep their existing path
/// for fast access on the device that captured them; other devices
/// resolve through Storage on demand.
///
/// Three operations:
///   - [uploadObservationAttachment]: called after a row is
///     inserted. Reads the local file, uploads to bucket, stamps
///     the row with `storage_path`. Fire-and-forget — failure
///     leaves the row "local-only" until the next attempt.
///   - [uploadChildAvatar] / [uploadAdultAvatar]: same shape for
///     people-photo rows.
///   - [ensureLocalFile]: called when a UI wants to display a
///     remote-only attachment. If the local file is present,
///     returns its path; otherwise downloads from Storage to a
///     persistent cache dir and returns the cache path.
///
/// Bucket layout:
///   `<programId>/observation_attachments/<rowId>.<ext>`
///   `<programId>/avatars/children/<rowId>.<ext>`
///   `<programId>/avatars/adults/<rowId>.<ext>`
///
/// Path keying with the row id keeps lookups deterministic — no
/// per-device file naming, no collisions across teachers.
///
/// **Web parity:** `dart:io.File` throws on web (no filesystem),
/// so every code path that touches bytes goes through [XFile]
/// (which on web wraps a `blob:` URL and returns bytes via its
/// own platform-aware reader). The capture device passes the
/// freshly-picked [XFile] in directly; heal passes for cloud-only
/// rows are skipped on web because there's no local file to
/// recover from.
class MediaService {
  MediaService(this._db, [this._ref]);

  final AppDatabase _db;

  /// Riverpod Ref for reading the sync engine on demand. Optional
  /// so existing constructions (tests) that don't provide one
  /// keep working — they just won't auto-push storage-path stamps,
  /// which is fine in a test harness with no real Supabase.
  final Ref? _ref;

  /// Bucket name. Created via the cloud SQL migration; RLS scopes
  /// reads/writes to program members.
  static const _bucket = 'media';

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } on Object {
      return null;
    }
  }

  // -- Upload ------------------------------------------------------

  /// Uploads the local file for [attachmentId] to the `media`
  /// bucket and stamps the row's `storage_path` with the bucket
  /// key. No-op if:
  ///   - Supabase isn't initialized / signed in
  ///   - the row is gone (deleted between mutation and upload)
  ///   - the row already has a non-null `storage_path` (idempotent)
  ///   - the local file no longer exists (e.g. user cleared cache)
  ///   - the device is web (no filesystem to read from)
  ///
  /// Fire-and-forget. Errors logged via debugPrint so they don't
  /// surface to the caller.
  Future<void> uploadObservationAttachment(String attachmentId) async {
    final client = _client;
    if (client == null) return;
    if (client.auth.currentSession == null) return;
    // Web has no filesystem — observation attachments stamped on
    // a phone get pulled here as cloud rows; the upload pass is a
    // no-op.
    if (kIsWeb) return;

    try {
      final row = await (_db.select(_db.observationAttachments)
            ..where((a) => a.id.equals(attachmentId)))
          .getSingleOrNull();
      if (row == null) return;
      if (row.storagePath != null) return; // already uploaded

      // Find the parent observation to discover the program_id —
      // bucket key uses program_id as the first segment for
      // RLS scoping.
      final obs = await (_db.select(_db.observations)
            ..where((o) => o.id.equals(row.observationId)))
          .getSingleOrNull();
      final programId = obs?.programId;
      if (programId == null) return;

      final file = File(row.localPath);
      // existsSync — heal-path I/O is OK to be sync; tripping the
      // slow-async-io lint matters less than avoiding a needless
      // event-loop hop, and we already gated on kIsWeb above.
      if (!file.existsSync()) {
        debugPrint(
          'Media upload skipped — local file missing for $attachmentId',
        );
        return;
      }

      final ext = p.extension(row.localPath);
      final storagePath = '$programId/observation_attachments/'
          '$attachmentId$ext';
      await client.storage.from(_bucket).uploadBinary(
            storagePath,
            await file.readAsBytes(),
            fileOptions: FileOptions(
              upsert: true,
              contentType: _contentTypeFor(ext, row.kind),
            ),
          );

      await (_db.update(_db.observationAttachments)
            ..where((a) => a.id.equals(attachmentId)))
          .write(
        ObservationAttachmentsCompanion(
          storagePath: Value(storagePath),
        ),
      );
      // observation_attachments is a cascade of observations —
      // it travels to cloud via the parent's pushRow + cascade
      // replace. Trigger a push of the parent observation so the
      // cascade rebuilds with the freshly-stamped storage_path
      // included; otherwise the storage_path lingers local-only
      // until the next observation edit happens to fire a push.
      final ref = _ref;
      if (ref != null) {
        unawaited(
          ref
              .read(syncEngineProvider)
              .pushRow(observationsSpec, row.observationId),
        );
      }
    } on Object catch (e, st) {
      debugPrint('Observation attachment upload failed: $e\n$st');
    }
  }

  /// Uploads an avatar for [childId] to the bucket and stamps
  /// `avatar_storage_path`. Two callers:
  ///
  ///   * **Picker (fresh capture):** pass [source] — the [XFile]
  ///     returned by `image_picker`. Bytes are read via
  ///     `XFile.readAsBytes()`, which works on every platform
  ///     including web (where `XFile.path` is a useless `blob:`
  ///     URL but the bytes are still readable). Always uploads,
  ///     overwriting any prior photo for this row.
  ///
  ///   * **Heal pass (no [source]):** native-only. Reads the row's
  ///     `avatar_path`, verifies the file is still on disk, and
  ///     uploads. No-op when `avatar_storage_path` is already set
  ///     (idempotent).
  ///
  /// On success, marks `avatar_storage_path` dirty so the next
  /// pushRow propagates it to cloud — without that, the storage
  /// path stays local-only and other devices pulling the row see
  /// a useless cross-device file path with no cloud handle.
  Future<void> uploadChildAvatar(
    String childId, {
    XFile? source,
  }) async {
    await _uploadPersonAvatar(
      kind: 'children',
      table: 'children',
      rowId: childId,
      source: source,
      tableSelect: () => (_db.select(_db.children)
            ..where((c) => c.id.equals(childId)))
          .getSingleOrNull()
          .then((row) => row == null
              ? null
              : _AvatarPullback(
                  programId: row.programId,
                  localPath: row.avatarPath,
                  storagePath: row.avatarStoragePath,
                )),
      stampStoragePath: (path) async {
        await (_db.update(_db.children)
              ..where((c) => c.id.equals(childId)))
            .write(ChildrenCompanion(
          avatarStoragePath: Value(path),
        ));
      },
      bucketKey: (programId) =>
          '$programId/avatars/children/$childId',
    );
  }

  /// Same as [uploadChildAvatar] for adults.
  Future<void> uploadAdultAvatar(
    String adultId, {
    XFile? source,
  }) async {
    await _uploadPersonAvatar(
      kind: 'adults',
      table: 'adults',
      rowId: adultId,
      source: source,
      tableSelect: () => (_db.select(_db.adults)
            ..where((a) => a.id.equals(adultId)))
          .getSingleOrNull()
          .then((row) => row == null
              ? null
              : _AvatarPullback(
                  programId: row.programId,
                  localPath: row.avatarPath,
                  storagePath: row.avatarStoragePath,
                )),
      stampStoragePath: (path) async {
        await (_db.update(_db.adults)
              ..where((a) => a.id.equals(adultId)))
            .write(AdultsCompanion(
          avatarStoragePath: Value(path),
        ));
      },
      bucketKey: (programId) =>
          '$programId/avatars/adults/$adultId',
    );
  }

  /// Heal pass — scan every media-bearing table for "has a local
  /// path but no cloud storage path" and re-fire the upload.
  /// Covers children + adults avatars and observation attachments.
  /// Idempotent (each upload method short-circuits when storage
  /// path is already set), so re-running on every bootstrap +
  /// foreground tick is cheap at steady state.
  ///
  /// **Native-only.** Heal exists to recover the device that
  /// captured the photo from a prior upload failure. Web devices
  /// never carry the local file — running heal there would just
  /// silently fail every cycle and waste cloud round-trips.
  /// (Pre-T1 the heal pass _did_ run on web, where File()
  /// construction threw `UnsupportedError` for every row.)
  Future<int> healMissingAvatarUploads() async {
    final client = _client;
    if (client == null) return 0;
    if (client.auth.currentSession == null) return 0;
    if (kIsWeb) return 0;

    var triggered = 0;
    try {
      final children = await (_db.select(_db.children)
            ..where((c) =>
                c.avatarPath.isNotNull() & c.avatarStoragePath.isNull()))
          .get();
      for (final c in children) {
        // Extra guard — only fire if the file is actually on this
        // device's disk. The avatar_path column is local-only
        // (Phase 6 / T1.1) so it should already correspond to
        // *this* device, but a stale value can survive across
        // wipe/import.
        final local = c.avatarPath;
        if (local == null) continue;
        if (!File(local).existsSync()) continue;
        unawaited(uploadChildAvatar(c.id));
        triggered++;
      }
    } on Object catch (e) {
      debugPrint('heal (children avatars) failed: $e');
    }
    try {
      final adults = await (_db.select(_db.adults)
            ..where((a) =>
                a.avatarPath.isNotNull() & a.avatarStoragePath.isNull()))
          .get();
      for (final a in adults) {
        final local = a.avatarPath;
        if (local == null) continue;
        if (!File(local).existsSync()) continue;
        unawaited(uploadAdultAvatar(a.id));
        triggered++;
      }
    } on Object catch (e) {
      debugPrint('heal (adults avatars) failed: $e');
    }
    try {
      // observation_attachments.localPath is non-nullable, so
      // every row has one — the gap to heal is "no storagePath
      // yet."
      final attachments = await (_db.select(_db.observationAttachments)
            ..where((a) => a.storagePath.isNull()))
          .get();
      for (final a in attachments) {
        if (!File(a.localPath).existsSync()) continue;
        unawaited(uploadObservationAttachment(a.id));
        triggered++;
      }
    } on Object catch (e) {
      debugPrint('heal (obs attachments) failed: $e');
    }
    if (triggered > 0) {
      debugPrint('Media heal queued $triggered upload(s).');
    }
    return triggered;
  }

  Future<void> _uploadPersonAvatar({
    required String kind,
    required String table,
    required String rowId,
    required Future<_AvatarPullback?> Function() tableSelect,
    required Future<void> Function(String storagePath) stampStoragePath,
    required String Function(String programId) bucketKey,
    XFile? source,
  }) async {
    final client = _client;
    if (client == null) return;
    if (client.auth.currentSession == null) return;

    try {
      final row = await tableSelect();
      if (row == null) return;
      final programId = row.programId;
      if (programId == null) return;

      // Resolve bytes. Two paths:
      //   1. Fresh capture: read straight from the picker's XFile.
      //      Works on every platform — XFile abstracts the
      //      file-vs-blob distinction.
      //   2. Heal: read from the row's local path. Native-only;
      //      web has no FS, so we'd never have a local file to
      //      recover from.
      final Uint8List bytes;
      final String ext;
      if (source != null) {
        bytes = await source.readAsBytes();
        ext = _extensionFromXFile(source);
      } else {
        if (kIsWeb) return; // web heal is a no-op, see comments above.
        if (row.storagePath != null) return; // already uploaded
        final localPath = row.localPath;
        if (localPath == null) return;
        final file = File(localPath);
        if (!file.existsSync()) return;
        bytes = await file.readAsBytes();
        ext = p.extension(localPath).isEmpty
            ? '.jpg'
            : p.extension(localPath);
      }

      final storagePath = '${bucketKey(programId)}$ext';
      await client.storage.from(_bucket).uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: _contentTypeFor(ext, 'photo'),
            ),
          );
      await stampStoragePath(storagePath);
      // Replace any stale bytes the drift cache may have for the
      // same storage_path. The bucket key is stable per row id, so
      // a re-upload (teacher picked a new photo for the same row)
      // overwrites the cloud object — but our local cache would
      // keep serving the old bytes until eviction. Stamp the new
      // bytes directly so the next render is correct.
      await _db.into(_db.mediaCache).insertOnConflictUpdate(
            MediaCacheCompanion.insert(
              storagePath: storagePath,
              bytes: bytes,
              contentType:
                  Value(_contentTypeFor(ext, 'photo')),
              cachedAt: Value(DateTime.now()),
            ),
          );
      // Mark the column dirty + nudge a push so the storage path
      // actually reaches cloud. Without these two lines the stamp
      // sits in local Drift forever and other devices can never
      // download the file. The pushRow goes through the standard
      // 250ms debounce + Phase-2 partial-UPDATE path, so the row's
      // other fields aren't disturbed.
      await _db.markDirty(table, rowId, ['avatar_storage_path']);
      // syncEngineProvider is read lazily because MediaService is
      // constructed before the sync engine is wired up at app
      // startup; reading it eagerly in the constructor would
      // create a circular dependency. The Riverpod container is
      // a singleton — read-on-demand is cheap.
      final ref = _ref;
      if (ref != null) {
        unawaited(
          ref.read(syncEngineProvider).pushRow(_specFor(table), rowId),
        );
      }
    } on Object catch (e, st) {
      debugPrint('$kind avatar upload failed: $e\n$st');
    }
  }

  /// Best-effort file extension from an [XFile]. On native the
  /// `name` always carries the original extension; on web some
  /// browsers omit it (the `blob:` URL has none). Falls back to
  /// the MIME type, then to `.jpg` so the bucket key is always
  /// well-formed.
  String _extensionFromXFile(XFile source) {
    final fromName = p.extension(source.name);
    if (fromName.isNotEmpty) return fromName;
    final mime = source.mimeType;
    if (mime != null) {
      switch (mime) {
        case 'image/jpeg':
          return '.jpg';
        case 'image/png':
          return '.png';
        case 'image/heic':
          return '.heic';
        case 'image/gif':
          return '.gif';
        case 'image/webp':
          return '.webp';
      }
    }
    return '.jpg';
  }

  /// Map a table name to its TableSpec. Avatars are pushed via
  /// the children / adults specs; observation attachments live on
  /// observations' cascade list (caller pushes the parent row).
  TableSpec _specFor(String table) {
    switch (table) {
      case 'children':
        return childrenSpec;
      case 'adults':
        return adultsSpec;
    }
    throw ArgumentError('No spec known for $table');
  }

  /// Uploads a form image-field's local file to the bucket under
  /// `<programId>/forms/<submissionId>/<fieldKey>.<ext>`. Returns the
  /// bucket key on success so the caller can stamp it onto the
  /// submission's `data` blob (the renderer reads it back when
  /// re-opening the form on another device).
  ///
  /// Same fire-and-forget shape as [uploadObservationAttachment]:
  /// no-ops (returns null) when Supabase isn't ready, the local file
  /// is gone, or the upload throws — never re-raises.
  Future<String?> uploadFormImage({
    required String submissionId,
    required String fieldKey,
    required String localPath,
    required String programId,
  }) async {
    final client = _client;
    if (client == null) return null;
    if (client.auth.currentSession == null) return null;
    // Form images come from the same image_picker plumbing as
    // avatars — but this entry point still takes a string path,
    // which on web is a `blob:` URL that File() can't open. The
    // forms surface should migrate to XFile too; until it does,
    // skip the upload on web rather than throw.
    if (kIsWeb) return null;

    try {
      final file = File(localPath);
      if (!file.existsSync()) {
        debugPrint(
          'Form image upload skipped — local file missing for '
          '$submissionId/$fieldKey',
        );
        return null;
      }
      final ext = p.extension(localPath);
      final storagePath = '$programId/forms/$submissionId/$fieldKey$ext';
      await client.storage.from(_bucket).uploadBinary(
            storagePath,
            await file.readAsBytes(),
            fileOptions: FileOptions(
              upsert: true,
              contentType: _contentTypeFor(ext, 'photo'),
            ),
          );
      return storagePath;
    } on Object catch (e, st) {
      debugPrint('Form image upload failed: $e\n$st');
      return null;
    }
  }

  // -- Download ----------------------------------------------------

  /// Drift-first byte fetch for [storagePath]. The media-cache
  /// table (`media_cache`) acts as a content-addressed blob store
  /// keyed by the bucket-relative path. Resolution order:
  ///
  ///   1. **Drift hit** → return cached bytes immediately. No
  ///      network round-trip, no signed-URL mint, no Supabase
  ///      transfer. Survives app restarts; on web survives page
  ///      reloads (drift_flutter persists to IndexedDB).
  ///   2. **Drift miss** → download bytes from Supabase Storage
  ///      via the storage client's `download(...)`, stamp into
  ///      Drift, return bytes.
  ///
  /// In-flight de-duplication: simultaneous requests for the same
  /// path (e.g. two SmallAvatars rendering at once) share a single
  /// Future via [_inFlightBytes] so we only hit Supabase once per
  /// path per app session.
  ///
  /// Returns null when:
  ///   * Supabase isn't initialized / signed in (cache miss has
  ///     no recovery path)
  ///   * Download throws (RLS deny, network, missing object) —
  ///     error logged via debugPrint, caller renders the fallback
  ///     initial.
  Future<Uint8List?> ensureBytes(String storagePath) async {
    if (storagePath.isEmpty) return null;
    // Drift hit → done.
    final cached = await (_db.select(_db.mediaCache)
          ..where((c) => c.storagePath.equals(storagePath)))
        .getSingleOrNull();
    if (cached != null) return Uint8List.fromList(cached.bytes);

    // Coalesce concurrent misses for the same path.
    final inFlight = _inFlightBytes[storagePath];
    if (inFlight != null) return inFlight;

    final future = _downloadAndCache(storagePath);
    _inFlightBytes[storagePath] = future;
    try {
      return await future;
    } finally {
      // Map.remove returns the removed value (a Future here),
      // which the lint mistakes for an unawaited Future. We've
      // already awaited it via `future` above.
      // ignore: unawaited_futures
      _inFlightBytes.remove(storagePath);
    }
  }

  Future<Uint8List?> _downloadAndCache(String storagePath) async {
    final client = _client;
    if (client == null) return null;
    if (client.auth.currentSession == null) return null;
    try {
      final bytes = await client.storage.from(_bucket).download(storagePath);
      // Stamp the cache so the next read (this device, this or a
      // later session) skips the download. INSERT … ON CONFLICT
      // updates an existing row in case the bucket key was
      // overwritten with new bytes for the same id.
      await _db.into(_db.mediaCache).insertOnConflictUpdate(
            MediaCacheCompanion.insert(
              storagePath: storagePath,
              bytes: bytes,
              contentType: Value(_guessContentType(storagePath)),
              cachedAt: Value(DateTime.now()),
            ),
          );
      return bytes;
    } on Object catch (e) {
      debugPrint('Media download failed for $storagePath: $e');
      return null;
    }
  }

  /// Best-guess MIME from the storage_path extension. Used purely
  /// for the cache row's metadata column; the actual decoder
  /// sniffs magic bytes itself.
  String? _guessContentType(String storagePath) {
    final ext = p.extension(storagePath).toLowerCase();
    if (ext.isEmpty) return null;
    return _contentTypeFor(ext, 'photo');
  }

  /// Inflight de-duplication map. Keyed by storage_path.
  final Map<String, Future<Uint8List?>> _inFlightBytes = {};

  /// Drop the cached bytes for [storagePath] — used after the
  /// teacher uploads a new photo for the same row id (the bucket
  /// key is the same, but the bytes are new). Caller is the
  /// upload pipeline, not UI.
  Future<void> evictCachedBytes(String storagePath) async {
    await (_db.delete(_db.mediaCache)
          ..where((c) => c.storagePath.equals(storagePath)))
        .go();
  }

  /// Signed download URL for [storagePath]. Kept for callers that
  /// genuinely need a URL (e.g. legacy `<img src=...>` pipelines).
  /// New code should prefer [ensureBytes] which goes through the
  /// drift cache and returns ready-to-render bytes.
  ///
  /// Cached in memory keyed by storage path; expires ~5 minutes
  /// before the actual signed-URL TTL so a long-render doesn't
  /// show a 401-ed image when the URL flips just-expired.
  /// Returns null when:
  ///   * Supabase isn't initialized / signed in.
  ///   * The signed-URL request fails (RLS, network, deleted).
  ///
  /// The `media` bucket is private (migrations 0008 / 0021), so a
  /// vanilla public URL won't work — every request has to be
  /// signed with the user's session.
  Future<String?> signedUrlFor(String storagePath) async {
    final cached = _signedUrlCache[storagePath];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.url;
    }
    final client = _client;
    if (client == null) return null;
    if (client.auth.currentSession == null) return null;
    try {
      // 1-hour signed URL — long enough that a session-of-use
      // re-renders all hit cache, short enough that a leaked URL
      // self-expires quickly.
      final url = await client.storage
          .from(_bucket)
          .createSignedUrl(storagePath, 3600);
      _signedUrlCache[storagePath] = _SignedUrl(
        url: url,
        expiresAt: DateTime.now().add(const Duration(minutes: 55)),
      );
      return url;
    } on Object catch (e) {
      debugPrint('Signed URL failed for $storagePath: $e');
      return null;
    }
  }

  final Map<String, _SignedUrl> _signedUrlCache = {};

  /// Returns a local file path for the given [storagePath]. If
  /// the file is already cached, returns the cache path
  /// immediately. Otherwise downloads from Storage into the cache
  /// and returns the new path. Throws on transport failure — UI
  /// should show a retry affordance.
  ///
  /// Cache lives in the app's documents directory under
  /// `media-cache/`. Files are named by their storage path with
  /// path separators replaced — guaranteed unique without needing
  /// per-row mapping.
  ///
  /// Native-only: web has no filesystem; web callers route through
  /// [signedUrlFor] + NetworkImage instead.
  Future<String> ensureLocalFile(String storagePath) async {
    if (kIsWeb) {
      throw const MediaUnavailableException(
        'ensureLocalFile is native-only; use signedUrlFor on web',
      );
    }
    final client = _client;
    if (client == null) {
      throw const MediaUnavailableException(
        'Supabase not initialized',
      );
    }
    if (client.auth.currentSession == null) {
      throw const MediaUnavailableException('Sign in to load media');
    }

    final cacheDir = await _cacheDirectory();
    final cacheKey = storagePath.replaceAll('/', '__');
    final cacheFile = File(p.join(cacheDir.path, cacheKey));
    if (cacheFile.existsSync()) return cacheFile.path;

    final bytes = await client.storage.from(_bucket).download(storagePath);
    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsBytes(bytes);
    return cacheFile.path;
  }

  /// Where downloaded files live. Persistent across launches —
  /// the cache survives app restarts so we don't re-download every
  /// time. Caller doesn't have to await; it's cheap to recompute.
  Future<Directory> _cacheDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'media-cache'));
  }

  String _contentTypeFor(String ext, String kind) {
    final lower = ext.toLowerCase();
    if (lower == '.jpg' || lower == '.jpeg') return 'image/jpeg';
    if (lower == '.png') return 'image/png';
    if (lower == '.heic') return 'image/heic';
    if (lower == '.gif') return 'image/gif';
    if (lower == '.webp') return 'image/webp';
    if (lower == '.mp4') return 'video/mp4';
    if (lower == '.mov') return 'video/quicktime';
    return kind == 'video'
        ? 'application/octet-stream'
        : 'application/octet-stream';
  }
}

/// Internal value object so `_uploadPersonAvatar` can read the
/// fields it needs from either Children or Adults without two
/// nearly-identical inline functions.
class _AvatarPullback {
  const _AvatarPullback({
    required this.programId,
    required this.localPath,
    required this.storagePath,
  });

  final String? programId;
  final String? localPath;
  final String? storagePath;
}

/// Thrown when a media operation can't proceed (no Supabase, no
/// session). Caller surfaces a UI affordance — typically a retry
/// button next to a placeholder thumbnail.
class MediaUnavailableException implements Exception {
  const MediaUnavailableException(this.message);
  final String message;

  @override
  String toString() => 'MediaUnavailableException: $message';
}

/// Memory-cached signed URL with an expiry timestamp. Kept private
/// — callers always go through [MediaService.signedUrlFor] which
/// invalidates expired entries.
class _SignedUrl {
  const _SignedUrl({required this.url, required this.expiresAt});
  final String url;
  final DateTime expiresAt;
}

final mediaServiceProvider = Provider<MediaService>((ref) {
  return MediaService(ref.read(databaseProvider), ref);
});
