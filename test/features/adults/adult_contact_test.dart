import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/parents/parents_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

/// v40 coverage for the adult-contact + staff↔parent bridge.
///
/// Lives alongside the existing adult tests since the surface is
/// small — phone/email persist on create, update can clear them via
/// `Value(null)`, and the reverse-lookup stream surfaces the staff
/// row paired to a parent.
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late AdultsRepository adults;
  late ParentsRepository parents;

  setUp(() {
    db = createTestDatabase();
    container = createTestContainer(database: db);
    adults = AdultsRepository(db, fakeRef(container));
    parents = ParentsRepository(db, fakeRef(container));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('addAdult persists phone + email', () async {
    final id = await adults.addAdult(
      name: 'Sarah',
      phone: '555-0100',
      email: 'sarah@example.com',
    );
    final row = await adults.getAdult(id);
    expect(row, isNotNull);
    expect(row!.phone, '555-0100');
    expect(row.email, 'sarah@example.com');
  });

  test('updateAdult clears phone via Value(null)', () async {
    final id = await adults.addAdult(
      name: 'Sarah',
      phone: '555-0100',
      email: 'sarah@example.com',
    );
    await adults.updateAdult(
      id: id,
      name: 'Sarah',
      phone: const Value<String?>(null),
    );
    final row = await adults.getAdult(id);
    expect(row!.phone, isNull);
    // Email untouched when caller leaves it Value.absent() (default).
    expect(row.email, 'sarah@example.com');
  });

  test('watchAdultLinkedToParent returns the paired adult', () async {
    final parentId = await parents.addParent(firstName: 'Pat');
    // Adult not linked yet → stream emits null.
    final adultId = await adults.addAdult(name: 'Pat Staff');
    expect(
      await adults.watchAdultLinkedToParent(parentId).first,
      isNull,
    );

    await adults.updateAdult(
      id: adultId,
      name: 'Pat Staff',
      parentId: Value(parentId),
    );
    final linked = await adults.watchAdultLinkedToParent(parentId).first;
    expect(linked, isNotNull);
    expect(linked!.id, adultId);

    // Unlinking via Value(null) drops the stream back to null.
    await adults.updateAdult(
      id: adultId,
      name: 'Pat Staff',
      parentId: const Value<String?>(null),
    );
    expect(
      await adults.watchAdultLinkedToParent(parentId).first,
      isNull,
    );
  });
}
