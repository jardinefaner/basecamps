import 'dart:async';

import 'package:basecamp/features/observations/observation_media_store.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/router.dart';
import 'package:basecamp/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
