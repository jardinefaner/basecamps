import 'package:basecamp/features/activity_library/activity_library_screen.dart';
import 'package:basecamp/features/adults/adult_detail_screen.dart';
import 'package:basecamp/features/adults/adults_screen.dart';
import 'package:basecamp/features/adults/program_timeline_screen.dart';
import 'package:basecamp/features/auth/auth_repository.dart';
import 'package:basecamp/features/auth/sign_in_screen.dart';
import 'package:basecamp/features/children/child_detail_screen.dart';
import 'package:basecamp/features/children/children_screen.dart';
import 'package:basecamp/features/curriculum/curriculum_screen.dart';
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
import 'package:basecamp/features/programs/programs_screen.dart';
import 'package:basecamp/features/roles/roles_screen.dart';
import 'package:basecamp/features/rooms/rooms_screen.dart';
import 'package:basecamp/features/schedule/schedule_editor_screen.dart';
import 'package:basecamp/features/settings/program_settings_screen.dart';
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
    _sub = ref.listen<AsyncValue<AuthState>>(
      authStateProvider,
      (_, _) => notifyListeners(),
    );
  }

  late final ProviderSubscription<AsyncValue<AuthState>> _sub;

  @override
  void dispose() {
    _sub.close();
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
      if (session == null && !goingToSignIn) return '/sign-in';
      if (session != null && goingToSignIn) return '/today';
      return null;
    },
    routes: [
      GoRoute(
        path: '/sign-in',
        builder: (_, _) => const SignInScreen(),
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
      ),
      GoRoute(
        path: '/week-plan',
        builder: (_, _) => const WeekPlanScreen(),
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
