import 'dart:async';

import 'package:basecamp/features/auth/auth_repository.dart';
import 'package:basecamp/features/forms/polymorphic/form_submission_repository.dart';
import 'package:basecamp/features/launcher/launcher_screen.dart';
import 'package:basecamp/features/observations/observation_media_store.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/features/programs/program_bootstrap.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/sync/media_service.dart';
import 'package:basecamp/features/sync/sync_engine.dart';
import 'package:basecamp/features/sync/sync_specs.dart';
import 'package:basecamp/router.dart';
import 'package:basecamp/theme/theme.dart';
import 'package:basecamp/ui/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Global ScaffoldMessenger key. Lets out-of-tree code (the sync
/// engine's pushErrors stream, future background tasks, etc.)
/// reach `ScaffoldMessenger.of(ctx)` without holding a
/// BuildContext. Wired into [MaterialApp.router]'s
/// `scaffoldMessengerKey` below.
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
    //
    // Deferred to a post-frame callback because `start()` fires
    // its initial session check synchronously, which can call
    // `_BootstrapInProgressNotifier.set` — modifying a Riverpod
    // provider during initState/build raises an "unhandled
    // exception" assertion. Post-frame puts the first call
    // outside the build phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _programBootstrapSub =
          ref.read(programAuthBootstrapProvider).start();
    });

    // The "a change from another device overwrote a local edit"
    // toast lived here through Phase 5 of the sync work. Field-
    // level dirty tracking now preserves un-pushed local edits
    // across pulls and realtime events (the dirty-fields list is
    // filtered out of every incoming row before merge), so the
    // row-level timestamp comparison that powered the toast was
    // firing on overlap that didn't actually overwrite anything.
    // Toast removed; the conflict stream + SyncConflict class
    // + `_isConcurrentOverwrite` helper went with it.

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

    // Membership-out-of-sync banner. Bootstrap stamps this when
    // the cloud `program_members` upsert fails — without a UI
    // signal, every push silently 403s and the user wonders why
    // their work isn't reaching cloud. A snackbar with an action
    // lets them retry without digging through settings.
    ref.listenManual<String?>(
      membershipUpsertFailureProvider,
      (previous, next) {
        if (next == null || next == previous) return;
        final messenger = scaffoldMessengerKey.currentState;
        if (messenger == null) return;
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: const Text(
                'Membership out of sync. Saves may not reach cloud.',
              ),
              duration: const Duration(seconds: 12),
              action: SnackBarAction(
                label: 'Retry',
                onPressed: () {
                  final programId = ref.read(activeProgramIdProvider);
                  if (programId == null) return;
                  unawaited(
                    ref
                        .read(programAuthBootstrapProvider)
                        .reconnectMembership(programId),
                  );
                },
              ),
            ),
          );
      },
    );

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
      //
      // Plus: if we somehow have a session but no active program
      // (the bootstrap raced the network on cold launch), re-run
      // it now. The retry timer would also catch this, but
      // foreground is the moment the user is most likely to
      // notice — heal eagerly.
      unawaited(_pullNow());
      unawaited(_resubscribeRealtime());
      unawaited(_maybeRerunBootstrap());
      _startPeriodicPull();
    } else if (!_foreground && wasForeground) {
      _periodicPullTimer?.cancel();
      _periodicPullTimer = null;
      // Flush every pending debounced push BEFORE the system has
      // a chance to suspend us. Without this, the 250ms push
      // debounce can swallow recent edits when the user closes a
      // browser tab, switches away on iOS, etc.: the timer dies
      // with the page, the cloud never receives the write, and a
      // re-open finds only "bits and pieces" of the session's
      // edits. The drain runs synchronously through pushRowNow
      // (no debounce), so on web `inactive`/`paused` lifecycle
      // events kick this before unload.
      unawaited(
        ref.read(syncEngineProvider).flushPendingPushes(kAllSpecs),
      );
    }
  }

  /// When the app foregrounds with a session but no active program,
  /// the user is functionally stuck on /welcome despite having a
  /// real cloud membership. Re-fire the bootstrap so the device
  /// heals itself without forcing the user into the audit screen.
  Future<void> _maybeRerunBootstrap() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return;
    if (ref.read(activeProgramIdProvider) != null) return;
    try {
      await ref.read(programAuthBootstrapProvider).rerunBootstrap();
    } on Object catch (e) {
      debugPrint('Foreground bootstrap retry failed: $e');
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
    // Drain any rows whose previous push errored — dirty_fields
    // is the source of truth for "this row has un-pushed local
    // edits." The sweep is cheap when nothing's pending and
    // self-heals when something is. Goes after the pulls so the
    // freshly-merged local state is what gets re-pushed.
    await engine.drainPendingPushes(kAllSpecs);
    // Avatar heal — re-upload any avatars whose storage_path
    // never reached cloud. Catches legacy uploads (pre-Phase-4,
    // when stamp didn't markDirty) that stayed local-only.
    // Idempotent so it's safe to run on every foreground tick.
    unawaited(
      ref.read(mediaServiceProvider).healMissingAvatarUploads(),
    );
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

  /// Width the route gives up to the always-present icon rail.
  /// Mirrors `_HoverSidebar._kRailWidth` so the layout reservation
  /// matches what the rail's collapsed width will paint.
  static const double _kReservedRail = 64;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (child == null) return const SizedBox.shrink();
    // Signed-out routes (Sign in) own their full layout; we're not
    // wrapping them in a sidebar that points nowhere.
    final session = ref.watch(currentSessionProvider);
    if (session == null) return child!;
    if (!Breakpoints.hasPersistentSidebar(context)) return child!;
    // Stack lets the launcher EXPAND OVER the route content instead
    // of shrinking it. The Row in the bottom layer reserves a fixed
    // 64dp gutter on the left so the route never paints under the
    // collapsed icon rail; when the rail expands to 320dp, the
    // sidebar Positioned grows over the route's leftmost 256dp.
    // Route layout stays put — just the panel slides on top.
    return Stack(
      children: [
        // Bottom layer: 64dp left gutter + divider + route. Route
        // gets a stable width of (viewport - 64dp - divider 1dp).
        Row(
          children: [
            const SizedBox(width: _kReservedRail),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: child!),
          ],
        ),
        // Top layer: the hover sidebar itself. Pinned to the left
        // edge; animates its own width 64↔320 without disturbing
        // the Row below. Material elevation reinforces the
        // "panel sits over the route" perception when expanded.
        const Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: _HoverSidebar(),
        ),
      ],
    );
  }
}

/// Persistent launcher sidebar that defaults to a narrow icon rail
/// and expands to the full launcher panel on hover. Same container,
/// same Material surface — only the width animates; the inner
/// [MinimalLauncher] always lays out at the full panel width and
/// the surrounding ClipRect reveals more of it as the outer
/// AnimatedContainer grows.
///
/// **Why a width animation rather than an overlay:** the alternative
/// (panel slides over the route content) needs nested MouseRegion
/// gymnastics — when the overlay covers the rail, the rail's
/// MouseRegion fires onExit (its hit-test was lost to the overlay),
/// which collapses the panel, which uncovers the rail, which fires
/// onEnter, which expands the panel… ad infinitum. AnimatedContainer
/// + a single MouseRegion sidesteps all of that. The trade-off is
/// the route pane reflowing as the rail expands; for a 256px,
/// 200ms shift it reads as intentional.
class _HoverSidebar extends StatefulWidget {
  const _HoverSidebar();

  @override
  State<_HoverSidebar> createState() => _HoverSidebarState();
}

class _HoverSidebarState extends State<_HoverSidebar> {
  bool _expanded = false;

  /// True while any descendant of the launcher (search TextField,
  /// for now — destinations are stateless taps) holds focus. Pins
  /// the panel as expanded while the user is interacting, so a
  /// stray mouse drift outside the rail doesn't yank the panel
  /// away mid-keystroke and unmount the focused input.
  bool _hasInteractiveFocus = false;

  /// Permanent icon rail width. The rail is *always* rendered at this
  /// width — collapsed/expanded state only changes whether the detail
  /// panel slides in beside it. Icons in the rail therefore never
  /// move between states, which is the Slack / Notion / Linear
  /// pattern (and what fixes the "icons jump on expand" feel that
  /// AnimatedSwitcher between two distinct widgets produces).
  static const double _kRailWidth = 64;

  /// Total width when the detail panel is open (rail + panel).
  static const double _kPanelWidth = 320;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) {
        if (!_expanded) setState(() => _expanded = true);
      },
      onExit: (_) {
        // Don't collapse while the user is actively typing in the
        // search field (or any other launcher descendant has
        // focus) — collapsing would unmount the TextField, drop
        // the in-progress keystroke, and read as the search field
        // "not searching."
        if (_hasInteractiveFocus) return;
        if (_expanded) setState(() => _expanded = false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: _expanded ? _kPanelWidth : _kRailWidth,
        child: Material(
          color: theme.colorScheme.surfaceContainerLow,
          // Elevation only kicks in when expanded — the panel needs
          // to read as "floating over the route," not "in line with
          // it." Collapsed, the rail sits at elevation 0 (matches
          // the rest of the surface tier).
          elevation: _expanded ? 8 : 0,
          // The trick: lay MinimalLauncher out at the FULL panel
          // width even when the outer AnimatedContainer is narrower
          // (mid-animation or fully-collapsed). OverflowBox forces
          // that, ClipRect clips the overhang. Result: every row's
          // leading icon paints at exactly the same screen
          // coordinates regardless of expand state — labels just
          // appear/disappear as the clip window grows.
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: _kPanelWidth,
              maxWidth: _kPanelWidth,
              child: SafeArea(
                // Focus-listener wrapper. `Focus.hasFocus` is true
                // when this node OR any descendant holds focus —
                // exactly the signal we need to know "the user is
                // interacting; don't collapse the panel right now."
                // canRequestFocus:false so this Focus isn't itself
                // a focus stop in tab navigation; it's purely an
                // observer.
                child: Focus(
                  canRequestFocus: false,
                  onFocusChange: (hasFocus) {
                    if (hasFocus == _hasInteractiveFocus) return;
                    setState(() => _hasInteractiveFocus = hasFocus);
                  },
                  child: MinimalLauncher(expanded: _expanded),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
