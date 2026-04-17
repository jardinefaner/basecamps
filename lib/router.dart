import 'package:basecamp/features/activity_library/activity_library_screen.dart';
import 'package:basecamp/features/forms/forms_hub_screen.dart';
import 'package:basecamp/features/forms/parent_concern/parent_concern_form_screen.dart';
import 'package:basecamp/features/forms/parent_concern/parent_concern_notes_screen.dart';
import 'package:basecamp/features/kids/kid_detail_screen.dart';
import 'package:basecamp/features/kids/kids_screen.dart';
import 'package:basecamp/features/launcher/launcher_screen.dart';
import 'package:basecamp/features/more/more_screen.dart';
import 'package:basecamp/features/observations/observations_screen.dart';
import 'package:basecamp/features/schedule/schedule_editor_screen.dart';
import 'package:basecamp/features/specialists/specialist_detail_screen.dart';
import 'package:basecamp/features/specialists/specialists_screen.dart';
import 'package:basecamp/features/today/today_screen.dart';
import 'package:basecamp/features/trips/trip_detail_screen.dart';
import 'package:basecamp/features/trips/trips_screen.dart';
import 'package:basecamp/ui/app_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/today',
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
                path: '/kids',
                builder: (_, _) => const KidsScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (_, state) => KidDetailScreen(
                      kidId: state.pathParameters['id']!,
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
                    path: 'specialists',
                    builder: (_, _) => const SpecialistsScreen(),
                    routes: [
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
                    path: 'forms',
                    builder: (_, _) => const FormsHubScreen(),
                    routes: [
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
