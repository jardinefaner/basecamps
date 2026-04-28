import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Staff job titles / roles (v39). Promoted from the free-text
/// `Adults.role` column — "Art teacher", "Director", "Head cook" —
/// into a first-class picklist so teachers stop re-typing the same
/// labels. `adults.role` still exists as a display fallback for
/// legacy rows; new rows populate `adults.role_id` via this entity.
///
/// Deleting a role just nulls out any adult's `role_id` (FK set
/// null) — the adult keeps existing, with their legacy free-text
/// string as the display fallback if present.
class RolesRepository {
  RolesRepository(this._db, this._ref);

  final AppDatabase _db;
  final Ref _ref;

  /// See ObservationsRepository._programId for why we read this on
  /// every insert rather than caching at construction time.
  String? get _programId => _ref.read(activeProgramIdProvider);

  Stream<List<Role>> watchAll() {
    final query = _db.select(_db.roles)
      ..orderBy([(r) => OrderingTerm.asc(r.name)]);
    return query.watch();
  }

  Future<List<Role>> getAll() {
    final query = _db.select(_db.roles)
      ..orderBy([(r) => OrderingTerm.asc(r.name)]);
    return query.get();
  }

  Future<Role?> getRole(String id) {
    return (_db.select(_db.roles)..where((r) => r.id.equals(id)))
        .getSingleOrNull();
  }

  Stream<Role?> watchRole(String id) {
    return (_db.select(_db.roles)..where((r) => r.id.equals(id)))
        .watchSingleOrNull();
  }

  Future<String> addRole({required String name}) async {
    final id = newId();
    await _db.into(_db.roles).insert(
          RolesCompanion.insert(
            id: id,
            name: name,
            programId: Value(_programId),
          ),
        );
    return id;
  }

  Future<void> updateRole({
    required String id,
    String? name,
  }) async {
    await (_db.update(_db.roles)..where((r) => r.id.equals(id))).write(
      RolesCompanion(
        name: name == null ? const Value.absent() : Value(name),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteRole(String id) async {
    await (_db.delete(_db.roles)..where((r) => r.id.equals(id))).go();
  }

  /// Re-insert a previously-deleted role row for the undo snackbar.
  /// Cascaded nulls on `adults.role_id` aren't re-linked — adults
  /// that pointed here keep their legacy free-text `role` as the
  /// display fallback.
  Future<void> restoreRole(Role row) async {
    await _db.into(_db.roles).insertOnConflictUpdate(row);
  }
}

final rolesRepositoryProvider = Provider<RolesRepository>((ref) {
  return RolesRepository(ref.watch(databaseProvider), ref);
});

final rolesProvider = StreamProvider<List<Role>>((ref) {
  return ref.watch(rolesRepositoryProvider).watchAll();
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final roleProvider =
    StreamProvider.family<Role?, String>((ref, id) {
  return ref.watch(rolesRepositoryProvider).watchRole(id);
});
