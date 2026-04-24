import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/roles/roles_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late RolesRepository repo;

  setUp(() {
    db = createTestDatabase();
    repo = RolesRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('addRole + watchAll returns rows alphabetically', () async {
    await repo.addRole(name: 'Director');
    await repo.addRole(name: 'Art teacher');
    await repo.addRole(name: 'Head cook');

    final list = await repo.watchAll().first;
    expect(list.map((r) => r.name), ['Art teacher', 'Director', 'Head cook']);
  });

  test('updateRole renames an existing role', () async {
    final id = await repo.addRole(name: 'Art Teacher');
    await repo.updateRole(id: id, name: 'Art teacher');
    final r = await repo.getRole(id);
    expect(r!.name, 'Art teacher');
  });

  test('deleteRole removes the row', () async {
    final id = await repo.addRole(name: 'Floater');
    await repo.deleteRole(id);
    final r = await repo.getRole(id);
    expect(r, isNull);
  });

  test('restoreRole re-inserts after delete (undo support)', () async {
    final id = await repo.addRole(name: 'Visiting artist');
    final before = await repo.getRole(id);
    expect(before, isNotNull);

    await repo.deleteRole(id);
    expect(await repo.getRole(id), isNull);

    await repo.restoreRole(before!);
    final restored = await repo.getRole(id);
    expect(restored, isNotNull);
    expect(restored!.name, 'Visiting artist');
  });
}
