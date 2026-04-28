import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Program-owned vehicles (v37). Promotes what used to be two free-
/// text fields on every vehicle-check form (make/model + license
/// plate) into a first-class picklist. Teachers pick "Big Bus" once;
/// the form stamps the identity automatically; per-vehicle history
/// (last 5 checks on Big Bus) becomes answerable by join.
///
/// No FKs point INTO this table from the polymorphic forms schema —
/// the vehicle-check form references by id inside its JSON data
/// blob, not by FK column, because the forms table intentionally
/// doesn't thread per-form columns. If the picked vehicle is later
/// deleted, historical submissions just read back the raw id; the
/// UI renders "(deleted vehicle)" in that case.
class VehiclesRepository {
  VehiclesRepository(this._db, this._ref);

  final AppDatabase _db;
  final Ref _ref;

  /// See ObservationsRepository._programId for why we read this on
  /// every insert rather than caching at construction time.
  String? get _programId => _ref.read(activeProgramIdProvider);

  Stream<List<Vehicle>> watchAll() {
    final query = _db.select(_db.vehicles)
      ..orderBy([(v) => OrderingTerm.asc(v.name)]);
    return query.watch();
  }

  Future<List<Vehicle>> getAll() {
    final query = _db.select(_db.vehicles)
      ..orderBy([(v) => OrderingTerm.asc(v.name)]);
    return query.get();
  }

  Future<Vehicle?> getVehicle(String id) {
    return (_db.select(_db.vehicles)..where((v) => v.id.equals(id)))
        .getSingleOrNull();
  }

  Stream<Vehicle?> watchVehicle(String id) {
    return (_db.select(_db.vehicles)..where((v) => v.id.equals(id)))
        .watchSingleOrNull();
  }

  Future<String> addVehicle({
    required String name,
    String makeModel = '',
    String licensePlate = '',
    String? notes,
  }) async {
    final id = newId();
    await _db.into(_db.vehicles).insert(
          VehiclesCompanion.insert(
            id: id,
            name: name,
            makeModel: Value(makeModel),
            licensePlate: Value(licensePlate),
            notes: Value(notes),
            programId: Value(_programId),
          ),
        );
    return id;
  }

  Future<void> updateVehicle({
    required String id,
    String? name,
    String? makeModel,
    String? licensePlate,
    Value<String?> notes = const Value.absent(),
  }) async {
    await (_db.update(_db.vehicles)..where((v) => v.id.equals(id))).write(
      VehiclesCompanion(
        name: name == null ? const Value.absent() : Value(name),
        makeModel: makeModel == null ? const Value.absent() : Value(makeModel),
        licensePlate:
            licensePlate == null ? const Value.absent() : Value(licensePlate),
        notes: notes,
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteVehicle(String id) async {
    await (_db.delete(_db.vehicles)..where((v) => v.id.equals(id))).go();
  }

  /// Re-insert a previously-deleted vehicle row for the undo snackbar.
  /// Historical form submissions that referenced this id keep
  /// resolving correctly once restored — the id stays stable.
  Future<void> restoreVehicle(Vehicle row) async {
    await _db.into(_db.vehicles).insertOnConflictUpdate(row);
  }
}

final vehiclesRepositoryProvider = Provider<VehiclesRepository>((ref) {
  return VehiclesRepository(ref.watch(databaseProvider), ref);
});

final vehiclesProvider = StreamProvider<List<Vehicle>>((ref) {
  return ref.watch(vehiclesRepositoryProvider).watchAll();
});

// Riverpod family return type is complex; inference is intentional.
// ignore: specify_nonobvious_property_types
final vehicleProvider =
    StreamProvider.family<Vehicle?, String>((ref, id) {
  return ref.watch(vehiclesRepositoryProvider).watchVehicle(id);
});
