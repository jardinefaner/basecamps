import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-memory [AppDatabase] for repository / widget tests. The native
/// sqlite3 library needs foreign keys enabled manually for each
/// connection (same as the app does in `beforeOpen`) — tests that
/// exercise cascade / setNull rely on this.
AppDatabase createTestDatabase() {
  final native = NativeDatabase.memory(
    setup: (raw) {
      raw.execute('PRAGMA foreign_keys = ON;');
    },
  );
  return AppDatabase.forTesting(native);
}

/// A throwaway [Ref] suitable for repository tests. Repos read
/// `activeProgramIdProvider` on every insert to stamp `program_id`;
/// we override it to a constant `null` here so tests don't have to
/// stand up a SharedPreferences mock or wait for the auth-bootstrap
/// hydrate. Rows write fine with `program_id` null — the next-launch
/// backfill stamps them when a real program lands.
///
/// Caller is responsible for keeping the container alive for as long
/// as the repo is used. The simplest pattern: `late final container =
/// ProviderContainer(...); ... addTearDown(container.dispose);` in
/// `setUp`, then pass `fakeRef(container)` into the constructor.
Ref fakeRef(ProviderContainer container) {
  return container.read(_refProvider);
}

/// Builds a [ProviderContainer] with `activeProgramIdProvider` pinned
/// to null. Use this everywhere a test needs to construct a repo —
/// the alternative (real provider, default value) tries to hydrate
/// from SharedPreferences and crashes before the binding is set up.
ProviderContainer createTestContainer() {
  return ProviderContainer(
    overrides: [
      activeProgramIdProvider.overrideWith(_NullActiveProgramNotifier.new),
    ],
  );
}

final _refProvider = Provider<Ref>((ref) => ref);

class _NullActiveProgramNotifier extends ActiveProgramNotifier {
  @override
  String? build() => null;
}
