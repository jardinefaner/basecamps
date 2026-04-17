import 'package:basecamp/database/database.dart';
import 'package:basecamp/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_database.dart';

/// Mounts [child] inside a ProviderScope + MaterialApp + Scaffold
/// wired for widget tests. The `databaseProvider` is overridden with
/// an in-memory test AppDatabase so any stream/provider the widget
/// watches (e.g. `childrenProvider`) resolves without touching
/// drift_flutter's real native DB — that native path kicks off a
/// background Timer that flutter_test's `!timersPending` invariant
/// can't handle.
///
/// Teardown: an empty widget is pumped + settled so Material
/// ripples, Tickers, and the overridden DB all drain.
Future<void> pumpWithHost(
  WidgetTester tester,
  Widget child, {
  AppDatabase? database,
}) async {
  final db = database ?? createTestDatabase();
  final container = ProviderContainer(
    overrides: [databaseProvider.overrideWithValue(db)],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: lightTheme(),
        home: Scaffold(body: child),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    container.dispose();
    await db.close();
  });
}
