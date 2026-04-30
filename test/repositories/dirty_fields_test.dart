import 'dart:convert';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/rooms/rooms_repository.dart';
import 'package:drift/drift.dart' show UpdateKind, Value, Variable;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

/// Phase 1 (markDirty / readDirtyFields / clearDirtyFields) +
/// Phase 4 (repos calling markDirty) coverage. Doesn't exercise
/// the cloud-side push path — that needs a Supabase fake; see
/// the integration tests for that. Here we verify:
///
///   * markDirty stamps the column names on the row.
///   * Repeated markDirty merges (no duplicates, deterministic
///     ordering).
///   * readDirtyFields returns the list; empty when clean.
///   * clearDirtyFields resets the column to null.
///   * Repository update methods call markDirty for the columns
///     they actually changed (canary: rooms.updateRoom).
void main() {
  late AppDatabase db;
  setUp(() async {
    db = createTestDatabase();
  });
  tearDown(() async {
    await db.close();
  });

  group('markDirty / readDirtyFields / clearDirtyFields', () {
    test('clean row reports empty dirty list', () async {
      final id = await db.into(db.rooms).insert(
            RoomsCompanion.insert(id: 'room-1', name: 'Art Room'),
          );
      expect(id, isPositive);
      final dirty = await db.readDirtyFields('rooms', 'room-1');
      expect(dirty, isEmpty);
    });

    test('markDirty stamps the listed columns', () async {
      await db.into(db.rooms).insert(
            RoomsCompanion.insert(id: 'room-1', name: 'Art Room'),
          );
      await db.markDirty('rooms', 'room-1', ['name', 'capacity']);
      final dirty = await db.readDirtyFields('rooms', 'room-1');
      expect(dirty, containsAll(['name', 'capacity']));
      expect(dirty.length, 2);
    });

    test('repeated markDirty merges without duplicates', () async {
      await db.into(db.rooms).insert(
            RoomsCompanion.insert(id: 'room-1', name: 'Art Room'),
          );
      await db.markDirty('rooms', 'room-1', ['name']);
      await db.markDirty('rooms', 'room-1', ['capacity']);
      await db.markDirty('rooms', 'room-1', ['name', 'notes']);
      final dirty = await db.readDirtyFields('rooms', 'room-1');
      expect(dirty.toSet(), {'name', 'capacity', 'notes'});
    });

    test('clearDirtyFields nulls the column', () async {
      await db.into(db.rooms).insert(
            RoomsCompanion.insert(id: 'room-1', name: 'Art Room'),
          );
      await db.markDirty('rooms', 'room-1', ['name']);
      await db.clearDirtyFields('rooms', 'room-1');
      final dirty = await db.readDirtyFields('rooms', 'room-1');
      expect(dirty, isEmpty);

      // Direct SQL check that the column is genuinely NULL, not
      // just empty JSON.
      final raw = await db.customSelect(
        'SELECT "dirty_fields" FROM "rooms" WHERE id = ?',
        variables: [const Variable<String>('room-1')],
      ).getSingle();
      expect(raw.data['dirty_fields'], isNull);
    });

    test('readDirtyFields tolerates corrupt JSON', () async {
      await db.into(db.rooms).insert(
            RoomsCompanion.insert(id: 'room-1', name: 'Art Room'),
          );
      // Inject malformed JSON to simulate a partial-write or
      // hand-edited DB. Should not throw — the helper falls back
      // to "no dirty fields" rather than crashing.
      await db.customUpdate(
        'UPDATE "rooms" SET "dirty_fields" = ? WHERE id = ?',
        variables: [
          const Variable<String>('not-valid-json'),
          const Variable<String>('room-1'),
        ],
        updates: const {},
        updateKind: UpdateKind.update,
      );
      final dirty = await db.readDirtyFields('rooms', 'room-1');
      expect(dirty, isEmpty);
    });
  });

  group('rooms_repository.updateRoom marks dirty fields', () {
    test('only changed fields land in dirty_fields', () async {
      final container = createTestContainer(database: db);
      addTearDown(container.dispose);
      final repo = RoomsRepository(db, fakeRef(container));

      // Seed a room. addRoom does not call markDirty (full
      // upsert path on first push handles the insert), so the
      // row starts clean.
      final id = await repo.addRoom(name: 'Art Room', capacity: 12);
      expect(await db.readDirtyFields('rooms', id), isEmpty);

      // Update one field — only that one should be marked dirty.
      await repo.updateRoom(id: id, name: 'Studio');
      expect(
        await db.readDirtyFields('rooms', id),
        equals(['name']),
      );

      // Another update marks an additional field; the first
      // stays in the list (still un-pushed in this test).
      await repo.updateRoom(id: id, capacity: const Value(20));
      final after = await db.readDirtyFields('rooms', id);
      expect(after.toSet(), {'name', 'capacity'});
    });

    test('Value.absent params do not mark dirty', () async {
      final container = createTestContainer(database: db);
      addTearDown(container.dispose);
      final repo = RoomsRepository(db, fakeRef(container));

      final id = await repo.addRoom(name: 'Art Room');
      // Calling updateRoom with no field arguments stamps no
      // dirty fields — useful for callers that just want to
      // bump updated_at without changing semantics.
      await repo.updateRoom(id: id);
      expect(await db.readDirtyFields('rooms', id), isEmpty);
    });
  });

  group('JSON shape', () {
    test('dirty_fields stores a sorted JSON array', () async {
      await db.into(db.rooms).insert(
            RoomsCompanion.insert(id: 'room-1', name: 'Art Room'),
          );
      await db.markDirty('rooms', 'room-1', ['notes', 'capacity', 'name']);
      final raw = await db.customSelect(
        'SELECT "dirty_fields" FROM "rooms" WHERE id = ?',
        variables: [const Variable<String>('room-1')],
      ).getSingle();
      final encoded = raw.data['dirty_fields']! as String;
      final decoded = jsonDecode(encoded) as List<Object?>;
      // Sorted so the JSON shape is stable across machines and
      // doesn't churn even when the caller passes different
      // orderings of the same field set.
      expect(decoded, ['capacity', 'name', 'notes']);
    });
  });
}
