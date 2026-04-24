import 'dart:async';

import 'package:basecamp/features/forms/polymorphic/form_submission_repository.dart';
import 'package:basecamp/features/observations/observation_media_store.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/router.dart';
import 'package:basecamp/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BasecampApp extends ConsumerStatefulWidget {
  const BasecampApp({super.key});

  @override
  ConsumerState<BasecampApp> createState() => _BasecampAppState();
}

class _BasecampAppState extends ConsumerState<BasecampApp> {
  @override
  void initState() {
    super.initState();
    // Orphan-attachment sweep on startup. Reaps files in the app-
    // owned observation-media dir that no attachment row points at
    // — left behind when an undo-enabled delete ages past the 5-
    // second snackbar window. Fire-and-forget: never blocks the
    // first frame, never surfaces failures.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_sweepOrphans());
      unawaited(_backfillIncidentChildIds());
    });
  }

  Future<void> _sweepOrphans() async {
    try {
      final dir = await ref.read(observationMediaDirProvider.future);
      if (dir == null) return;
      await ref
          .read(observationsRepositoryProvider)
          .sweepOrphanedAttachmentFiles(mediaDir: dir);
    } on Object {
      // Startup sweep isn't critical — silently ignore any IO error,
      // permission issue, or missing-dir edge case. We'll try again
      // next launch.
    }
  }

  /// One-time back-fill: pre-picker incident submissions stored the
  /// child as a free-text `child_name`. After the FormChildPickerField
  /// slice, new submissions stamp the typed child_id FK column. This
  /// walks the historical rows once per install, matching by name
  /// (first+last, case-insensitive) and setting child_id when the
  /// match is unambiguous. Guarded by a SharedPreferences flag so we
  /// don't re-scan every launch; safe to run again if the flag is
  /// cleared (idempotent — already-linked rows filter out).
  Future<void> _backfillIncidentChildIds() async {
    const flagKey = 'incident_child_backfill_v1_done';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(flagKey) ?? false) return;
      final linked = await ref
          .read(formSubmissionRepositoryProvider)
          .backfillIncidentChildIds();
      await prefs.setBool(flagKey, true);
      // Intentionally quiet — teachers don't need a snackbar for a
      // migration they didn't ask for. `linked` is still logged to
      // debug output so a developer checking on first launch can
      // see whether rows matched.
      debugPrint('Back-filled $linked historical incident child links.');
    } on Object {
      // Don't mark the flag on failure — we'll retry next launch.
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Basecamp',
      theme: lightTheme(),
      darkTheme: darkTheme(),
      routerConfig: router,
    );
  }
}
