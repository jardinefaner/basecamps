import 'dart:async';
import 'dart:io';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:basecamp/features/sync/sync_specs.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  ///
  /// Fire-and-forget. Errors logged via debugPrint so they don't
  /// surface to the caller.
  Future<void> uploadObservationAttachment(String attachmentId) async {
    final client = _client;
    if (client == null) return;
    if (client.auth.currentSession == null) return;

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
      // The lint suggests existsSync() but we don't want to
      // block on disk I/O during a fire-and-forget upload.
      // ignore: avoid_slow_async_io
      if (!await file.exists()) {
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
    } on Object catch (e, st) {
      debugPrint('Observation attachment upload failed: $e\n$st');
    }
  }

  /// Uploads the avatar file for [childId] to the bucket and
  /// stamps `avatar_storage_path`. Same fire-and-forget shape as
  /// [uploadObservationAttachment]. Idempotent — a re-upload only
  /// fires when the local avatar path changed (caller checks).
  ///
  /// On success, marks `avatar_storage_path` dirty so the next
  /// pushRow propagates it to cloud — without that, the storage
  /// path stays local-only and other devices pulling the row see
  /// a useless cross-device file path with no cloud handle.
  Future<void> uploadChildAvatar(String childId) async {
    await _uploadPersonAvatar(
      kind: 'children',
      table: 'children',
      rowId: childId,
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
  Future<void> uploadAdultAvatar(String adultId) async {
    await _uploadPersonAvatar(
      kind: 'adults',
      table: 'adults',
      rowId: adultId,
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

  /// Heal pass — scan every children + adults row for "has
  /// avatar_path locally but no avatar_storage_path" and re-fire
  /// the upload. Idempotent (uploadXAvatar checks for an existing
  /// storage path and skips), so re-running on every bootstrap +
  /// foreground is cheap on the steady state. Catches any avatar
  /// whose first upload silently failed or whose stamp never
  /// reached cloud (the bug this method fixes — pre-Phase-4
  /// uploads stamped storage_path but never marked it dirty, so
  /// it stayed local-only forever).
  Future<int> healMissingAvatarUploads() async {
    final client = _client;
    if (client == null) return 0;
    if (client.auth.currentSession == null) return 0;
    var triggered = 0;
    try {
      final children = await (_db.select(_db.children)
            ..where((c) =>
                c.avatarPath.isNotNull() & c.avatarStoragePath.isNull()))
          .get();
      for (final c in children) {
        unawaited(uploadChildAvatar(c.id));
        triggered++;
      }
    } on Object catch (e) {
      debugPrint('healMissingAvatarUploads (children) failed: $e');
    }
    try {
      final adults = await (_db.select(_db.adults)
            ..where((a) =>
                a.avatarPath.isNotNull() & a.avatarStoragePath.isNull()))
          .get();
      for (final a in adults) {
        unawaited(uploadAdultAvatar(a.id));
        triggered++;
      }
    } on Object catch (e) {
      debugPrint('healMissingAvatarUploads (adults) failed: $e');
    }
    if (triggered > 0) {
      debugPrint('healMissingAvatarUploads queued $triggered upload(s).');
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
  }) async {
    final client = _client;
    if (client == null) return;
    if (client.auth.currentSession == null) return;

    try {
      final row = await tableSelect();
      if (row == null) return;
      final programId = row.programId;
      final localPath = row.localPath;
      if (programId == null || localPath == null) return;
      if (row.storagePath != null) return; // already uploaded

      final file = File(localPath);
      // ignore: avoid_slow_async_io — see uploadObservationAttachment
      if (!await file.exists()) return;

      final ext = p.extension(localPath);
      final storagePath = '${bucketKey(programId)}$ext';
      await client.storage.from(_bucket).uploadBinary(
            storagePath,
            await file.readAsBytes(),
            fileOptions: FileOptions(
              upsert: true,
              contentType: _contentTypeFor(ext, 'photo'),
            ),
          );
      await stampStoragePath(storagePath);
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

    try {
      final file = File(localPath);
      // ignore: avoid_slow_async_io — fire-and-forget; see siblings.
      if (!await file.exists()) {
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

  /// Signed download URL for [storagePath], used by web (which
  /// can't use the local-file cache because there's no filesystem).
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
  Future<String> ensureLocalFile(String storagePath) async {
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
    // ignore: avoid_slow_async_io — same reason as upload paths.
    if (await cacheFile.exists()) return cacheFile.path;

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
