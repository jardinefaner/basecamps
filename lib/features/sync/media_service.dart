import 'dart:async';
import 'dart:io';

import 'package:basecamp/database/database.dart';
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
  MediaService(this._db);

  final AppDatabase _db;

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
  Future<void> uploadChildAvatar(String childId) async {
    await _uploadPersonAvatar(
      kind: 'children',
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

  Future<void> _uploadPersonAvatar({
    required String kind,
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
    } on Object catch (e, st) {
      debugPrint('$kind avatar upload failed: $e\n$st');
    }
  }

  // -- Download ----------------------------------------------------

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

final mediaServiceProvider = Provider<MediaService>((ref) {
  return MediaService(ref.read(databaseProvider));
});
