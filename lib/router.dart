import 'package:basecamp/features/activity_library/activity_library_screen.dart';
import 'package:basecamp/features/children/child_detail_screen.dart';
import 'package:basecamp/features/children/children_screen.dart';
import 'package:basecamp/features/forms/forms_hub_screen.dart';
import 'package:basecamp/features/forms/parent_concern/parent_concern_form_screen.dart';
import 'package:basecamp/features/forms/parent_concern/parent_concern_notes_screen.dart';
import 'package:basecamp/features/forms/polymorphic/generic_form_list_screen.dart';
import 'package:basecamp/features/forms/polymorphic/registry.dart';
import 'package:basecamp/features/launcher/launcher_screen.dart';
import 'package:basecamp/features/more/more_screen.dart';
import 'package:basecamp/features/observations/observations_screen.dart';
import 'package:basecamp/features/rooms/rooms_screen.dart';
import 'package:basecamp/features/schedule/schedule_editor_screen.dart';
import 'package:basecamp/features/settings/program_settings_screen.dart';
import 'package:basecamp/features/specialists/program_timeline_screen.dart';
import 'package:basecamp/features/specialists/specialist_detail_screen.dart';
import 'package:basecamp/features/specialists/specialists_screen.dart';
import 'package:basecamp/features/today/today_screen.dart';
import 'package:basecamp/features/trips/trip_detail_screen.dart';
import 'package:basecamp/features/trips/trips_screen.dart';
import 'package:basecamp/ui/app_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/today',
    observers: [_UnfocusOnTransition()],
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppScaffold(navigationShell: navigationShell);
        },
        branches: [
          // Hidden "launcher" branch — reached by swiping right from
          // Today. No nav-bar tile; the scaffold drops the indicator
          // when this branch is active.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/launcher',
                builder: (_, _) => const LauncherScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
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
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/observations',
                builder: (_, _) => const ObservationsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
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
            ],
          ),
          StatefulShellBranch(
            routes: [
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
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/more',
                builder: (_, _) => const MoreScreen(),
                routes: [
                  GoRoute(
                    // Route renamed from 'specialists' to 'adults' in
                    // the v28 refactor — the feature now covers leads,
                    // specialists, AND ambient staff. Table names and
                    // Dart class names stay as-is (backwards compat +
                    // not user-visible); the URL is.
                    path: 'adults',
                    builder: (_, _) => const SpecialistsScreen(),
                    routes: [
                      GoRoute(
                        path: 'timeline',
                        builder: (_, _) =>
                            const ProgramTimelineScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (_, state) => SpecialistDetailScreen(
                          specialistId: state.pathParameters['id']!,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'library',
                    builder: (_, _) => const ActivityLibraryScreen(),
                  ),
                  GoRoute(
                    path: 'rooms',
                    builder: (_, _) => const RoomsScreen(),
                  ),
                  GoRoute(
                    path: 'settings',
                    builder: (_, _) => const ProgramSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'forms',
                    builder: (_, _) => const FormsHubScreen(),
                    routes: [
                      GoRoute(
                        path: 'type/:typeKey',
                        builder: (_, state) {
                          final typeKey =
                              state.pathParameters['typeKey']!;
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
                          return GenericFormListScreen(
                            definition: def,
                          );
                        },
                      ),
                      GoRoute(
                        path: 'parent-concern',
                        builder: (_, _) =>
                            const ParentConcernNotesScreen(),
                        routes: [
                          GoRoute(
                            path: 'new',
                            // Creation flows through the step wizard so
                            // first-timers aren't faced with seven
                            // sections at once; editing keeps the
                            // scroll layout.
                            builder: (_, _) => const ParentConcernFormScreen(
                              presentation: ConcernFormPresentation.wizard,
                            ),
                          ),
                          GoRoute(
                            path: ':id',
                            builder: (_, state) =>
                                ParentConcernFormScreen(
                              noteId: state.pathParameters['id'],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
