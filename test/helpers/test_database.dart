import 'package:basecamp/database/database.dart';
import 'package:drift/native.dart';

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
