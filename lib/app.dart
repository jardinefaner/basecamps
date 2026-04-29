import 'dart:async';

import 'package:basecamp/features/auth/auth_repository.dart';
import 'package:basecamp/features/forms/polymorphic/form_submission_repository.dart';
import 'package:basecamp/features/launcher/launcher_screen.dart';
import 'package:basecamp/features/observations/observation_media_store.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/features/programs/program_bootstrap.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:basecamp/features/sync/sync_specs.dart';
import 'package:basecamp/router.dart';
import 'package:basecamp/theme/theme.dart';
import 'package:basecamp/ui/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Global ScaffoldMessenger key. Lets out-of-tree code (sync
/// engine's conflict stream, future background tasks, etc.) reach
/// `ScaffoldMessenger.of(ctx)` without holding a BuildContext.
/// Wired into [MaterialApp.router]'s `scaffoldMessengerKey` below.
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

class BasecampApp extends ConsumerStatefulWidget {
  const BasecampApp({super.key});

  @override
  ConsumerState<BasecampApp> createState() => _BasecampAppState();
}

class _BasecampAppState extends ConsumerState<BasecampApp>
    with WidgetsBindingObserver {
  ProviderSubscription<Session?>? _programBootstrapSub;
  StreamSubscription<SyncConflict>? _conflictsSub;
  StreamSubscription<SyncPushError>? _pushErrorsSub;
  DateTime? _lastPushErrorToastAt;

  /// Safety-net periodic pull. Realtime is the primary fast path
  /// (postgres-changes events fire within ~50ms of an INSERT on
  /// another device), but the channel can silently drop on flaky
  /// networks, browser-tab-throttling, mobile-radio-sleep, etc.
  /// without surfacing an error. The periodic pull catches every
  /// missed event within at most one [_kPullInterval] window.
  ///
  /// 45s is a reasonable trade between freshness and bandwidth —
  /// pull-with-watermark is cheap when nothing's changed (one
  /// HEAD-shaped query per table that returns zero rows), so the
  /// cost on a quiet program is negligible.
  Timer? _periodicPullTimer;
  static const _kPullInterval = Duration(seconds: 45);

  /// Tracks whether we're foregrounded — when paused/inactive we
  /// stop the timer to save battery and avoid background-task
  /// throttling penalties on iOS / Android.
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPeriodicPull();
    // Subscribe the program bootstrap to auth state. On every
    // sign-in this ensures the user has a default program and
    // pumps the active program id into Riverpod for the rest of
    // the app to consume. Runs once per sign-in (idempotent —
    // existing programs are reused, not re-created).
    _programBootstrapSub =
        ref.read(programAuthBootstrapProvider).start();

    // Conflict-detection: when sync overwrites a local row that
    // had unsynced edits, surface a snackbar so the teacher
    // knows their work was shadowed by another device. The toast
    // groups the table + row id and is short — last-write-wins
    // is the semantic; this just adds visibility.
    _conflictsSub = ref.read(syncEngineProvider).conflicts.listen((c) {
      final messenger = scaffoldMessengerKey.currentState;
      if (messenger == null) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'A change from another device overwrote a local edit '
              'on ${c.table}. (Last write wins.)',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
    });

    // Push-error toast. Without this, RLS rejections / network
    // failures only landed in `debugPrint` and gave the user the
    // false impression that their save worked when really nothing
    // reached the cloud. Throttled so a burst of failures (one
    // per row in a multi-row save) collapses into a single
    // snackbar — bombarding the user with a dozen error toasts
    // helps no one.
    _pushErrorsSub =
        ref.read(syncEngineProvider).pushErrors.listen((err) {
      final now = DateTime.now();
      final last = _lastPushErrorToastAt;
      if (last != null && now.difference(last).inSeconds < 5) {
        return;
      }
      _lastPushErrorToastAt = now;
      final messenger = scaffoldMessengerKey.currentState;
      if (messenger == null) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(err.summary),
            duration: const Duration(seconds: 6),
          ),
        );
    });

    // Orphan-attachment sweep on startup. Reaps files in the app-
    // owned observation-media dir that no attachment row points at
    // — left behind when an undo-enabled delete ages past the 5-
    // second snackbar window. Fire-and-forget: never blocks the
    // first frame, never surfaces failures.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_sweepOrphans());
      unawaited(_backfillIncidentChildIds());
      // The legacy parent_concern_migration was folded into the v45
      // schema upgrade itself (see _migrateParentConcernRowsToFormSubmissions
      // in database.dart). Migration runs in onUpgrade, before any
      // app code reads the DB, so by the time we get here the rows
      // are already in form_submissions and the bespoke tables are
      // gone.
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodicPullTimer?.cancel();
    _programBootstrapSub?.close();
    unawaited(_conflictsSub?.cancel());
    unawaited(_pushErrorsSub?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _foreground;
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && !wasForeground) {
      // Coming back from background — pull immediately and make
      // sure realtime is healthy. Realtime channels can drop
      // without notification while the tab/app was paused; this
      // is the recovery path so the user doesn't miss a beat.
      unawaited(_pullNow());
      unawaited(_resubscribeRealtime());
      _startPeriodicPull();
    } else if (!_foreground && wasForeground) {
      _periodicPullTimer?.cancel();
      _periodicPullTimer = null;
    }
  }

  void _startPeriodicPull() {
    _periodicPullTimer?.cancel();
    _periodicPullTimer = Timer.periodic(_kPullInterval, (_) {
      unawaited(_pullNow());
    });
  }

  /// Watermarked pull across every spec. Cheap when nothing's
  /// changed (the watermark filters server-side, returns empty
  /// pages), so 45s polling is fine even on a quiet program. Bails
  /// silently when there's no signed-in user or no active program
  /// — both are normal states (sign-in screen, program-create
  /// flow) where the timer might still be running.
  Future<void> _pullNow() async {
    final activeId = ref.read(activeProgramIdProvider);
    if (activeId == null) return;
    final session = ref.read(currentSessionProvider);
    if (session == null) return;
    final engine = ref.read(syncEngineProvider);
    for (final spec in kAllSpecs) {
      try {
        await engine.pullTable(spec: spec, programId: activeId);
      } on Object catch (e) {
        // Single-table failure shouldn't kill the rest of the
        // sweep — RLS blip on one entity, transient network
        // hiccup, etc. Log and continue.
        debugPrint('Periodic pull of ${spec.table} failed: $e');
      }
    }
  }

  /// Force a realtime reconnect. The engine's normal subscribe is
  /// idempotent — it bails early when the program matches and a
  /// channel handle exists — but a silently-dead channel still
  /// satisfies that check. Resume from background is the most
  /// likely moment for a dropped channel (mobile radio sleep, web
  /// tab throttle, network change), so always force a rebuild
  /// here. The cost is ~100ms of handshake; the win is recovering
  /// from a dead channel without user intervention.
  Future<void> _resubscribeRealtime() async {
    final activeId = ref.read(activeProgramIdProvider);
    if (activeId == null) return;
    final session = ref.read(currentSessionProvider);
    if (session == null) return;
    try {
      await ref.read(syncEngineProvider).subscribeToRealtime(
            programId: activeId,
            specs: kAllSpecs,
            force: true,
          );
    } on Object catch (e) {
      debugPrint('Realtime resubscribe failed: $e');
    }
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
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: lightTheme(),
      darkTheme: darkTheme(),
      routerConfig: router,
      // Web / desktop windows can be a thousand pixels wider than a
      // phone screen. Without a clamp every list, hero card, and
      // form field stretches edge-to-edge and looks wrong. Wrap
      // every route in a max-width box so on wide windows content
      // sits in a centered column with the surface color filling
      // the gutters. Mobile screens (width below the cap) see no
      // effect.
      builder: (context, child) => _ResponsiveShell(child: child),
    );
  }
}

/// Adaptive shell that pivots between phone and web layouts.
///
/// Signed-out routes (just /sign-in for now) skip the shell entirely
/// — there's no point rendering a sidebar full of destinations the
/// user can't navigate to yet, and the sign-in page wants the full
/// viewport for its centered card.
///
/// Phones (width below [Breakpoints.sidebarThreshold]): unchanged.
/// The route's own Scaffold + slide-in Drawer pattern handles
/// everything.
///
/// Wide windows (web, desktop, tablet landscape): renders the
/// launcher as a permanent left sidebar + the route content in the
/// right column. Reads like a real web app — fixed nav rail on the
/// left, working pane on the right. Routes also drop their slide-in
/// Drawer + hamburger on this layout (see Today's Scaffold) so the
/// menu doesn't sit redundantly next to a sidebar that's already
/// showing the same content.
class _ResponsiveShell extends ConsumerWidget {
  const _ResponsiveShell({required this.child});

  final Widget? child;

  /// Width of the persistent sidebar on wide layouts. 320dp matches
  /// the Material navigation drawer default; the launcher's rows
  /// were already designed for that footprint.
  static const double _kSidebarWidth = 320;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (child == null) return const SizedBox.shrink();
    // Signed-out routes (Sign in) own their full layout; we're not
    // wrapping them in a sidebar that points nowhere.
    final session = ref.watch(currentSessionProvider);
    if (session == null) return child!;
    if (!Breakpoints.hasPersistentSidebar(context)) return child!;
    final theme = Theme.of(context);
    return Row(
      children: [
        // Left rail — the launcher in its own Material container so
        // it picks up the surface color stack and shows its own
        // elevation against the route. SizedBox + Material gives
        // it a clean stop without the slide-in animation overhead
        // a Drawer would carry.
        SizedBox(
          width: _kSidebarWidth,
          child: Material(
            color: theme.colorScheme.surfaceContainerLow,
            // SafeArea so the launcher's search pill doesn't slide
            // under desktop chrome on browsers that expose a top
            // inset.
            //
            // The local Overlay is required: LauncherScreen wraps
            // pinnable tiles in LongPressDraggable, which renders
            // its drag feedback into an Overlay ancestor. Inside a
            // Drawer route (mobile) the Navigator supplies one; here
            // we're a plain Row child with no route, so we add our
            // own. Navigation taps still bubble to the root
            // navigator via go_router — this Overlay only hosts
            // local floating widgets (drag feedback, future
            // tooltips, etc.).
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  // Positioned.fill is required: the Overlay's
                  // _Theatre lays out children with loose
                  // constraints, so a SafeArea+LauncherScreen
                  // without explicit sizing trips a "RenderBox
                  // was not laid out" assertion the first time
                  // focus traversal walks the tree.
                  builder: (_) => const Positioned.fill(
                    child: SafeArea(
                      child: LauncherScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Hairline separator. VerticalDivider inherits the theme's
        // outlineVariant — looks right against surface tiers.
        const VerticalDivider(width: 1, thickness: 1),
        // Route pane. Fills whatever the sidebar doesn't claim. No
        // max-width clamp here — teachers on a 27-inch monitor see
        // the full pane, week-plan grids breathe, etc.
        Expanded(child: child!),
      ],
    );
  }
}
