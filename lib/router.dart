import 'package:basecamp/features/activity_library/activity_library_screen.dart';
import 'package:basecamp/features/adults/adult_detail_screen.dart';
import 'package:basecamp/features/adults/adults_screen.dart';
import 'package:basecamp/features/adults/program_timeline_screen.dart';
import 'package:basecamp/features/ask/ask_screen.dart';
import 'package:basecamp/features/auth/auth_repository.dart';
import 'package:basecamp/features/auth/sign_in_screen.dart';
import 'package:basecamp/features/children/child_detail_screen.dart';
import 'package:basecamp/features/children/children_screen.dart';
import 'package:basecamp/features/curriculum/curriculum_hub_screen.dart';
import 'package:basecamp/features/curriculum/curriculum_screen.dart';
import 'package:basecamp/features/experiment/experiment_screen.dart';
import 'package:basecamp/features/experiment/monthly_plan_screen.dart';
import 'package:basecamp/features/experiment/survey/survey_screen.dart';
import 'package:basecamp/features/forms/forms_hub_screen.dart';
import 'package:basecamp/features/forms/polymorphic/definitions/parent_concern.dart';
import 'package:basecamp/features/forms/polymorphic/generic_form_list_screen.dart';
import 'package:basecamp/features/forms/polymorphic/generic_form_screen.dart';
import 'package:basecamp/features/forms/polymorphic/registry.dart';
import 'package:basecamp/features/lesson_sequences/lesson_sequence_detail_screen.dart';
import 'package:basecamp/features/lesson_sequences/lesson_sequences_screen.dart';
import 'package:basecamp/features/observations/observations_screen.dart';
import 'package:basecamp/features/parents/parent_detail_screen.dart';
import 'package:basecamp/features/parents/parents_screen.dart';
import 'package:basecamp/features/planning/week_plan_screen.dart';
import 'package:basecamp/features/programs/join_with_code_sheet.dart';
import 'package:basecamp/features/programs/program_bootstrap.dart';
import 'package:basecamp/features/programs/program_detail_screen.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/programs/programs_screen.dart';
import 'package:basecamp/features/programs/sync_diagnostics_screen.dart';
import 'package:basecamp/features/programs/welcome_screen.dart';
import 'package:basecamp/features/roles/roles_screen.dart';
import 'package:basecamp/features/rooms/rooms_screen.dart';
import 'package:basecamp/features/schedule/schedule_editor_screen.dart';
import 'package:basecamp/features/settings/program_settings_screen.dart';
import 'package:basecamp/features/setup/setup_hub_screen.dart';
import 'package:basecamp/features/surveys/survey_list_screen.dart';
import 'package:basecamp/features/surveys/survey_results_screen.dart';
import 'package:basecamp/features/surveys/survey_setup_screen.dart';
import 'package:basecamp/features/sync/sync_audit_screen.dart';
import 'package:basecamp/features/themes/themes_screen.dart';
import 'package:basecamp/features/today/today_screen.dart';
import 'package:basecamp/features/trips/trip_detail_screen.dart';
import 'package:basecamp/features/trips/trips_screen.dart';
import 'package:basecamp/features/vehicles/vehicles_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Drops any open keyboard/focus whenever a route transitions. Fixes
/// a long-standing bug where, e.g., closing the Observe composer and
/// swiping to Today left the keyboard open — and any accidental
/// keystroke landed back in the hidden text field on the previous
/// page. Covers push, pop, replace, and remove.
class _UnfocusOnTransition extends NavigatorObserver {
  void _dropFocus() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _dropFocus();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _dropFocus();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _dropFocus();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _dropFocus();
}

/// Bridges the Riverpod auth-state stream into a [Listenable] so
/// GoRouter's `refreshListenable` can rebuild the route tree on
/// sign-in / sign-out without us reaching into the auth singletons
/// from inside the router.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    // ref.listen fires once per auth-state event; notifyListeners
    // tells GoRouter to re-evaluate `redirect` for the current
    // location. Without this the user signs in but stays parked on
    // /sign-in until they manually navigate.
    _authSub = ref.listen<AsyncValue<AuthState>>(
      authStateProvider,
      (_, _) => notifyListeners(),
    );
    // Also re-evaluate `redirect` whenever the active program
    // changes — slice 3 sends signed-in users with no program to
    // /welcome, and the redirect needs to fire when bootstrap
    // first decides "no program here" *and* when the user later
    // joins/creates one (so they bounce off /welcome to /today).
    _activeProgramSub = ref.listen<String?>(
      activeProgramIdProvider,
      (_, _) => notifyListeners(),
    );
    // Re-evaluate redirects when the bootstrap finishes — the
    // user signs in, the auth state flips, but the active-program
    // id stays null until we hydrate cloud + decide a default. The
    // redirect needs to wake up at *both* edges (auth flip AND
    // bootstrap settle) or it'll race the bootstrap and bounce the
    // user to /welcome for the half-second hydrate window.
    _bootstrapSub = ref.listen<bool>(
      programBootstrapInProgressProvider,
      (_, _) => notifyListeners(),
    );
  }

  late final ProviderSubscription<AsyncValue<AuthState>> _authSub;
  late final ProviderSubscription<String?> _activeProgramSub;
  late final ProviderSubscription<bool> _bootstrapSub;

  @override
  void dispose() {
    _authSub.close();
    _activeProgramSub.close();
    _bootstrapSub.close();
    super.dispose();
  }
}

/// Global key on the GoRouter's root Navigator. Sidebar widgets
/// (the launcher) live as siblings of the route's Navigator rather
/// than descendants — so `Navigator.of(context, rootNavigator: true)`
/// from inside the sidebar can't find the route navigator and any
/// route push (`showDialog`, `showMenu`, `Navigator.push`) silently
/// no-ops there. This key lets sidebar code reach the root navigator
/// directly: `rootNavigatorKey.currentState?.push(...)`.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Flat top-level route tree. Today is the root — every other screen is
/// a pushed route accessible from Today's drawer (or deep-linked). The
/// old StatefulShell with its launcher + five-tab setup is gone; the
/// launcher is rendered inside Today's drawer instead of as its own
/// route.
///
/// Auth gate: every route requires a session except `/sign-in`. The
/// `redirect` callback below funnels signed-out users to /sign-in and
/// bounces signed-in users away from /sign-in back to /today. The
/// `refreshListenable` rebuilds the redirect on every auth-state
/// change so sign-in immediately routes the teacher into the app.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);
  return GoRouter(
    initialLocation: '/today',
    navigatorKey: rootNavigatorKey,
    observers: [_UnfocusOnTransition()],
    refreshListenable: refresh,
    redirect: (context, state) {
      // Custom-scheme URIs (e.g. com.example.basecamps://login-
      // callback/?code=...) are OAuth deep links that supabase-
      // flutter handles directly via its own AppLinks listener.
      // The router shouldn't try to match them as routes — they
      // aren't routes, and matching throws "no routes for
      // location ...". When we see one, deflect to /sign-in (a
      // known route) and let supabase's session listener flip
      // the auth state once the code exchange completes; the
      // router will rebuild and route the user onward.
      final scheme = state.uri.scheme;
      if (scheme.isNotEmpty && scheme != 'http' && scheme != 'https') {
        return '/sign-in';
      }
      // Auth round-trip: if the URL still carries an auth callback
      // param, Supabase is mid-exchange and the session hasn't
      // landed yet. Don't push the user to /sign-in during that
      // window — main() awaits the exchange explicitly before
      // runApp, so by the time we get here without one of these
      // present, the session reflects reality. This guard is belt-
      // and-suspenders against any future flow where the param
      // lingers a tick longer than the first frame.
      //
      // `code` covers PKCE OAuth + magic-link in PKCE mode;
      // `token_hash` covers older / non-PKCE magic-link callbacks.
      final qp = state.uri.queryParameters;
      if (qp.containsKey('code') || qp.containsKey('token_hash')) {
        return null;
      }
      final session = ref.read(authRepositoryProvider).currentSession;
      final goingToSignIn = state.matchedLocation == '/sign-in';
      final goingToWelcome = state.matchedLocation == '/welcome';
      // Diagnostics has to stay reachable from the welcome
      // screen, even when there's no active program — that's
      // the exact state the user is in when they need it most.
      // Without this exemption the no-active-program gate
      // bounces /more/programs/diagnostics back to /welcome.
      final goingToDiagnostics =
          state.matchedLocation == '/more/programs/diagnostics';
      // Deep-link redeem path (/redeem/:code) is the landing page for
      // someone tapping a shared invite link — they're explicitly
      // joining their first program, so the no-active-program gate
      // below must not bounce them off it.
      final goingToRedeem = state.matchedLocation.startsWith('/redeem/');
      // Bounce-back across sign-in: when a signed-out user lands on
      // a deep link (e.g. /redeem/:code from an invite email), we
      // tuck the original location into a `?next=` query param so
      // the post-sign-in branch below can route them straight there
      // instead of dumping them on /today (and losing the code).
      if (session == null && !goingToSignIn) {
        if (state.matchedLocation == '/sign-in') return null;
        final next = Uri.encodeComponent(state.uri.toString());
        return '/sign-in?next=$next';
      }
      if (session != null && goingToSignIn) {
        final next = state.uri.queryParameters['next'];
        if (next != null && next.isNotEmpty) {
          // Don't trust query params blindly — only bounce to
          // app-internal paths, never an external URL someone
          // could have appended.
          if (next.startsWith('/')) return next;
        }
        return '/today';
      }
      // No-active-program gate (Slice 3): a signed-in user without
      // a current program belongs on /welcome, where they pick
      // Create-vs-Join. Skip the redirect when they're already
      // there (avoids a redirect loop), still on /sign-in (auth
      // callback flow), or in the diagnostics route (debugging
      // the no-program state itself).
      //
      // Also skip while the bootstrap is hydrating cloud programs.
      // On a fresh sign-in the auth flip happens before
      // ProgramAuthBootstrap finishes deciding a default program;
      // checking activeProgramIdProvider during that window gives
      // us null and bounces the user to /welcome, which then
      // bounces back to /today the moment bootstrap settles. The
      // visible result is a half-second flash of the welcome page
      // every login. Holding the redirect open until bootstrap
      // settles fixes it; refreshListenable wakes the redirect
      // back up when the in-progress flag flips to false.
      if (session != null &&
          !goingToSignIn &&
          !goingToWelcome &&
          !goingToDiagnostics &&
          !goingToRedeem) {
        final bootstrapping =
            ref.read(programBootstrapInProgressProvider);
        if (!bootstrapping) {
          final activeId = ref.read(activeProgramIdProvider);
          if (activeId == null) return '/welcome';
        }
      }
      // And the inverse: if the user landed on /welcome but
      // they DO have an active program (e.g. they joined and the
      // bootstrap finished), bounce them to /today.
      if (session != null && goingToWelcome) {
        final activeId = ref.read(activeProgramIdProvider);
        if (activeId != null) return '/today';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/sign-in',
        builder: (_, _) => const SignInScreen(),
      ),
      GoRoute(
        path: '/welcome',
        builder: (_, _) => const WelcomeScreen(),
      ),
      // Deep-link landing for shared invite codes
      // (`https://basecamp.app/redeem/ABCD1234`). Renders the same
      // JoinWithCodeSheet the welcome screen + programs screen open,
      // but pre-filled with the path code and hosted in a full-screen
      // Scaffold so it works as a top-level route. On success the
      // sheet pops with a RedeemResult — but since this isn't a modal,
      // pop just goes back; the program switch already fired inside
      // redeemAndSwitch, so the bootstrap will route the user onward.
      GoRoute(
        path: '/redeem/:code',
        builder: (_, state) => Scaffold(
          appBar: AppBar(title: const Text('Join program')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: JoinWithCodeSheet(
                  initialCode: state.pathParameters['code'],
                ),
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/today',
        builder: (_, _) => const TodayScreen(),
        routes: [
          GoRoute(
            path: 'schedule',
            builder: (_, _) => const ScheduleEditorScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/ask',
        builder: (_, _) => const AskScreen(),
      ),
      GoRoute(
        path: '/observations',
        builder: (_, state) => ObservationsScreen(
          // Tag chips on observation cards push `/observations?tag=ssd3`
          // to scope the archive to one domain. Null = unfiltered.
          initialTagFilter: state.uri.queryParameters['tag'],
        ),
      ),
      GoRoute(
        path: '/children',
        builder: (_, _) => const ChildrenScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) => ChildDetailScreen(
              childId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/trips',
        builder: (_, _) => const TripsScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) => TripDetailScreen(
              tripId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),
      // /more/* URLs stay stable even though the /more landing page is
      // gone — every context.push('/more/settings') etc. across the
      // codebase still resolves. The "more" prefix is now purely a
      // grouping convention, not a navigable parent.
      GoRoute(
        path: '/more/adults',
        builder: (_, _) => const AdultsScreen(),
        routes: [
          GoRoute(
            path: 'timeline',
            builder: (_, _) => const ProgramTimelineScreen(),
          ),
          GoRoute(
            path: ':id',
            builder: (_, state) => AdultDetailScreen(
              adultId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/more/library',
        builder: (_, _) => const ActivityLibraryScreen(),
      ),
      // Curriculum hub — single tabbed surface that consolidates the
      // previously-scattered Themes / Lesson sequences / Templates
      // entry-points. The deeper detail routes (/more/themes,
      // /more/sequences) are still resolvable for deep links and the
      // existing detail screens keep working — this hub is a
      // launcher-level streamlining, not a model change.
      GoRoute(
        path: '/more/curriculum',
        builder: (_, _) => const CurriculumHubScreen(),
      ),
      // Setup hub — index page for the rarely-revisited program-config
      // screens (Rooms, Vehicles, Roles, Forms, Trips). Like the
      // curriculum hub, this is a launcher rollup; the underlying
      // screens stay reachable directly.
      GoRoute(
        path: '/more/setup',
        builder: (_, _) => const SetupHubScreen(),
      ),
      GoRoute(
        path: '/more/roles',
        builder: (_, _) => const RolesScreen(),
      ),
      GoRoute(
        path: '/more/rooms',
        builder: (_, _) => const RoomsScreen(),
      ),
      GoRoute(
        path: '/more/vehicles',
        builder: (_, _) => const VehiclesScreen(),
      ),
      GoRoute(
        path: '/more/parents',
        builder: (_, _) => const ParentsScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) => ParentDetailScreen(
              parentId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/more/settings',
        builder: (_, _) => const ProgramSettingsScreen(),
      ),
      GoRoute(
        path: '/more/programs',
        builder: (_, _) => const ProgramsScreen(),
        routes: [
          GoRoute(
            path: 'diagnostics',
            builder: (_, _) => const SyncDiagnosticsScreen(),
          ),
          GoRoute(
            path: 'audit',
            builder: (_, _) => const SyncAuditScreen(),
          ),
          GoRoute(
            path: ':id',
            builder: (_, state) => ProgramDetailScreen(
              programId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/week-plan',
        builder: (_, _) => const WeekPlanScreen(),
      ),
      // Sandbox surface — blank canvas for trying out new ideas before
      // they earn their own feature directory + route. Reachable from
      // the launcher under the "Lab" category.
      GoRoute(
        path: '/experiment',
        builder: (_, _) => const ExperimentScreen(),
        routes: [
          // v60.7 — Chibi-character sandbox. The activity-based
          // experiment screen's FAB has a "New Survey" entry that
          // pushes here. Self-contained Flame game; no shared state
          // with the rest of the experiment surface.
          GoRoute(
            path: 'survey',
            builder: (_, _) => const SurveyScreen(),
          ),
        ],
      ),
      // BASECamp Student Survey tool — graduated from the
      // experiment lab to a top-level destination. Reachable
      // from the launcher's Surveys tile under People.
      //   /surveys           — list of saved surveys
      //   /surveys/new       — teacher setup form
      //   /surveys/:id       — results sheet (default landing)
      //   /surveys/:id/play  — locked-down kiosk for the kids
      GoRoute(
        path: '/surveys',
        builder: (_, _) => const SurveyListScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (_, _) => const SurveySetupScreen(),
          ),
          GoRoute(
            path: ':id',
            builder: (_, state) => SurveyResultsScreen(
              surveyId: state.pathParameters['id']!,
            ),
            routes: [
              GoRoute(
                path: 'play',
                builder: (_, state) => SurveyScreen(
                  surveyId: state.pathParameters['id'],
                  // Optional ?resume=<sessionId> — when present,
                  // the kiosk re-opens that session and continues
                  // from the first unanswered question.
                  resumeSessionId: state.uri.queryParameters['resume'],
                ),
              ),
            ],
          ),
        ],
      ),
      // Monthly plan sandbox — Mon–Fri grid, one activity per cell,
      // no time-of-day. Different mental model from the week plan;
      // we're trying it out before deciding whether it graduates.
      GoRoute(
        path: '/monthly-plan',
        builder: (_, _) => const MonthlyPlanScreen(),
      ),
      GoRoute(
        path: '/more/sequences',
        builder: (_, _) => const LessonSequencesScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) => LessonSequenceDetailScreen(
              sequenceId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/more/themes',
        builder: (_, _) => const ThemesScreen(),
        routes: [
          // Built-in curriculum templates. Now consolidated into the
          // Curriculum hub's Templates tab — this route still resolves
          // (deep links / old context.push references) but renders the
          // hub directly so there's just one place to author / import
          // curricula.
          GoRoute(
            path: 'templates',
            builder: (_, _) => const CurriculumHubScreen(),
          ),
          // Curriculum-arc view (v46) — multi-week phase/week/day
          // arc rendered from the theme's LessonSequences. Lives
          // under /more/themes/:id/curriculum so the URL reads as
          // "this theme's curriculum" and the existing CRUD screen
          // stays at the parent path.
          GoRoute(
            path: ':themeId/curriculum',
            builder: (_, state) => CurriculumScreen(
              themeId: state.pathParameters['themeId']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/more/forms',
        builder: (_, _) => const FormsHubScreen(),
        routes: [
          GoRoute(
            path: 'type/:typeKey',
            builder: (_, state) {
              final typeKey = state.pathParameters['typeKey']!;
              final def = formDefinitionFor(typeKey);
              if (def == null) {
                return Scaffold(
                  appBar: AppBar(
                    title: const Text('Forms'),
                  ),
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Unknown form type: $typeKey',
                      ),
                    ),
                  ),
                );
              }
              return GenericFormListScreen(definition: def);
            },
          ),
          // Legacy /more/forms/parent-concern[/<sub>] routes — kept as
          // entry-points so every existing context.push still resolves,
          // but now backed by the polymorphic generic screen + the
          // parent_concern FormDefinition. The bespoke
          // ParentConcernFormScreen + ParentConcernNotesScreen widgets
          // are deleted; the polymorphic surface handles every field
          // shape they used (multi-child picker + signature pad, both
          // landed in commit eb82aa3).
          GoRoute(
            path: 'parent-concern',
            builder: (_, _) =>
                const GenericFormListScreen(definition: parentConcernForm),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, _) =>
                    const GenericFormScreen(definition: parentConcernForm),
              ),
              GoRoute(
                path: ':id',
                builder: (_, state) => GenericFormScreen(
                  definition: parentConcernForm,
                  submissionId: state.pathParameters['id'],
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
