// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $PodsTable extends Pods with TableInfo<$PodsTable, Pod> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PodsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorHexMeta = const VerificationMeta(
    'colorHex',
  );
  @override
  late final GeneratedColumn<String> colorHex = GeneratedColumn<String>(
    'color_hex',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    colorHex,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pods';
  @override
  VerificationContext validateIntegrity(
    Insertable<Pod> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color_hex')) {
      context.handle(
        _colorHexMeta,
        colorHex.isAcceptableOrUnknown(data['color_hex']!, _colorHexMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Pod map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Pod(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      colorHex: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_hex'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PodsTable createAlias(String alias) {
    return $PodsTable(attachedDatabase, alias);
  }
}

class Pod extends DataClass implements Insertable<Pod> {
  final String id;
  final String name;
  final String? colorHex;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Pod({
    required this.id,
    required this.name,
    this.colorHex,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || colorHex != null) {
      map['color_hex'] = Variable<String>(colorHex);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PodsCompanion toCompanion(bool nullToAbsent) {
    return PodsCompanion(
      id: Value(id),
      name: Value(name),
      colorHex: colorHex == null && nullToAbsent
          ? const Value.absent()
          : Value(colorHex),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Pod.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Pod(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      colorHex: serializer.fromJson<String?>(json['colorHex']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'colorHex': serializer.toJson<String?>(colorHex),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Pod copyWith({
    String? id,
    String? name,
    Value<String?> colorHex = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Pod(
    id: id ?? this.id,
    name: name ?? this.name,
    colorHex: colorHex.present ? colorHex.value : this.colorHex,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Pod copyWithCompanion(PodsCompanion data) {
    return Pod(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      colorHex: data.colorHex.present ? data.colorHex.value : this.colorHex,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Pod(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorHex: $colorHex, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, colorHex, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Pod &&
          other.id == this.id &&
          other.name == this.name &&
          other.colorHex == this.colorHex &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PodsCompanion extends UpdateCompanion<Pod> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> colorHex;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const PodsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.colorHex = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PodsCompanion.insert({
    required String id,
    required String name,
    this.colorHex = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<Pod> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? colorHex,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (colorHex != null) 'color_hex': colorHex,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PodsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? colorHex,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return PodsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (colorHex.present) {
      map['color_hex'] = Variable<String>(colorHex.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PodsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorHex: $colorHex, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KidsTable extends Kids with TableInfo<$KidsTable, Kid> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KidsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firstNameMeta = const VerificationMeta(
    'firstName',
  );
  @override
  late final GeneratedColumn<String> firstName = GeneratedColumn<String>(
    'first_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastNameMeta = const VerificationMeta(
    'lastName',
  );
  @override
  late final GeneratedColumn<String> lastName = GeneratedColumn<String>(
    'last_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _podIdMeta = const VerificationMeta('podId');
  @override
  late final GeneratedColumn<String> podId = GeneratedColumn<String>(
    'pod_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES pods (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _birthDateMeta = const VerificationMeta(
    'birthDate',
  );
  @override
  late final GeneratedColumn<DateTime> birthDate = GeneratedColumn<DateTime>(
    'birth_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pinMeta = const VerificationMeta('pin');
  @override
  late final GeneratedColumn<String> pin = GeneratedColumn<String>(
    'pin',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _parentNameMeta = const VerificationMeta(
    'parentName',
  );
  @override
  late final GeneratedColumn<String> parentName = GeneratedColumn<String>(
    'parent_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avatarPathMeta = const VerificationMeta(
    'avatarPath',
  );
  @override
  late final GeneratedColumn<String> avatarPath = GeneratedColumn<String>(
    'avatar_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    firstName,
    lastName,
    podId,
    birthDate,
    pin,
    notes,
    parentName,
    avatarPath,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'kids';
  @override
  VerificationContext validateIntegrity(
    Insertable<Kid> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('first_name')) {
      context.handle(
        _firstNameMeta,
        firstName.isAcceptableOrUnknown(data['first_name']!, _firstNameMeta),
      );
    } else if (isInserting) {
      context.missing(_firstNameMeta);
    }
    if (data.containsKey('last_name')) {
      context.handle(
        _lastNameMeta,
        lastName.isAcceptableOrUnknown(data['last_name']!, _lastNameMeta),
      );
    }
    if (data.containsKey('pod_id')) {
      context.handle(
        _podIdMeta,
        podId.isAcceptableOrUnknown(data['pod_id']!, _podIdMeta),
      );
    }
    if (data.containsKey('birth_date')) {
      context.handle(
        _birthDateMeta,
        birthDate.isAcceptableOrUnknown(data['birth_date']!, _birthDateMeta),
      );
    }
    if (data.containsKey('pin')) {
      context.handle(
        _pinMeta,
        pin.isAcceptableOrUnknown(data['pin']!, _pinMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('parent_name')) {
      context.handle(
        _parentNameMeta,
        parentName.isAcceptableOrUnknown(data['parent_name']!, _parentNameMeta),
      );
    }
    if (data.containsKey('avatar_path')) {
      context.handle(
        _avatarPathMeta,
        avatarPath.isAcceptableOrUnknown(data['avatar_path']!, _avatarPathMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Kid map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Kid(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      firstName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_name'],
      )!,
      lastName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_name'],
      ),
      podId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pod_id'],
      ),
      birthDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}birth_date'],
      ),
      pin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pin'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      parentName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_name'],
      ),
      avatarPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_path'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $KidsTable createAlias(String alias) {
    return $KidsTable(attachedDatabase, alias);
  }
}

class Kid extends DataClass implements Insertable<Kid> {
  final String id;
  final String firstName;
  final String? lastName;
  final String? podId;
  final DateTime? birthDate;
  final String? pin;
  final String? notes;
  final String? parentName;
  final String? avatarPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Kid({
    required this.id,
    required this.firstName,
    this.lastName,
    this.podId,
    this.birthDate,
    this.pin,
    this.notes,
    this.parentName,
    this.avatarPath,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['first_name'] = Variable<String>(firstName);
    if (!nullToAbsent || lastName != null) {
      map['last_name'] = Variable<String>(lastName);
    }
    if (!nullToAbsent || podId != null) {
      map['pod_id'] = Variable<String>(podId);
    }
    if (!nullToAbsent || birthDate != null) {
      map['birth_date'] = Variable<DateTime>(birthDate);
    }
    if (!nullToAbsent || pin != null) {
      map['pin'] = Variable<String>(pin);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || parentName != null) {
      map['parent_name'] = Variable<String>(parentName);
    }
    if (!nullToAbsent || avatarPath != null) {
      map['avatar_path'] = Variable<String>(avatarPath);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  KidsCompanion toCompanion(bool nullToAbsent) {
    return KidsCompanion(
      id: Value(id),
      firstName: Value(firstName),
      lastName: lastName == null && nullToAbsent
          ? const Value.absent()
          : Value(lastName),
      podId: podId == null && nullToAbsent
          ? const Value.absent()
          : Value(podId),
      birthDate: birthDate == null && nullToAbsent
          ? const Value.absent()
          : Value(birthDate),
      pin: pin == null && nullToAbsent ? const Value.absent() : Value(pin),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      parentName: parentName == null && nullToAbsent
          ? const Value.absent()
          : Value(parentName),
      avatarPath: avatarPath == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarPath),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Kid.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Kid(
      id: serializer.fromJson<String>(json['id']),
      firstName: serializer.fromJson<String>(json['firstName']),
      lastName: serializer.fromJson<String?>(json['lastName']),
      podId: serializer.fromJson<String?>(json['podId']),
      birthDate: serializer.fromJson<DateTime?>(json['birthDate']),
      pin: serializer.fromJson<String?>(json['pin']),
      notes: serializer.fromJson<String?>(json['notes']),
      parentName: serializer.fromJson<String?>(json['parentName']),
      avatarPath: serializer.fromJson<String?>(json['avatarPath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'firstName': serializer.toJson<String>(firstName),
      'lastName': serializer.toJson<String?>(lastName),
      'podId': serializer.toJson<String?>(podId),
      'birthDate': serializer.toJson<DateTime?>(birthDate),
      'pin': serializer.toJson<String?>(pin),
      'notes': serializer.toJson<String?>(notes),
      'parentName': serializer.toJson<String?>(parentName),
      'avatarPath': serializer.toJson<String?>(avatarPath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Kid copyWith({
    String? id,
    String? firstName,
    Value<String?> lastName = const Value.absent(),
    Value<String?> podId = const Value.absent(),
    Value<DateTime?> birthDate = const Value.absent(),
    Value<String?> pin = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<String?> parentName = const Value.absent(),
    Value<String?> avatarPath = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Kid(
    id: id ?? this.id,
    firstName: firstName ?? this.firstName,
    lastName: lastName.present ? lastName.value : this.lastName,
    podId: podId.present ? podId.value : this.podId,
    birthDate: birthDate.present ? birthDate.value : this.birthDate,
    pin: pin.present ? pin.value : this.pin,
    notes: notes.present ? notes.value : this.notes,
    parentName: parentName.present ? parentName.value : this.parentName,
    avatarPath: avatarPath.present ? avatarPath.value : this.avatarPath,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Kid copyWithCompanion(KidsCompanion data) {
    return Kid(
      id: data.id.present ? data.id.value : this.id,
      firstName: data.firstName.present ? data.firstName.value : this.firstName,
      lastName: data.lastName.present ? data.lastName.value : this.lastName,
      podId: data.podId.present ? data.podId.value : this.podId,
      birthDate: data.birthDate.present ? data.birthDate.value : this.birthDate,
      pin: data.pin.present ? data.pin.value : this.pin,
      notes: data.notes.present ? data.notes.value : this.notes,
      parentName: data.parentName.present
          ? data.parentName.value
          : this.parentName,
      avatarPath: data.avatarPath.present
          ? data.avatarPath.value
          : this.avatarPath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Kid(')
          ..write('id: $id, ')
          ..write('firstName: $firstName, ')
          ..write('lastName: $lastName, ')
          ..write('podId: $podId, ')
          ..write('birthDate: $birthDate, ')
          ..write('pin: $pin, ')
          ..write('notes: $notes, ')
          ..write('parentName: $parentName, ')
          ..write('avatarPath: $avatarPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    firstName,
    lastName,
    podId,
    birthDate,
    pin,
    notes,
    parentName,
    avatarPath,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Kid &&
          other.id == this.id &&
          other.firstName == this.firstName &&
          other.lastName == this.lastName &&
          other.podId == this.podId &&
          other.birthDate == this.birthDate &&
          other.pin == this.pin &&
          other.notes == this.notes &&
          other.parentName == this.parentName &&
          other.avatarPath == this.avatarPath &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class KidsCompanion extends UpdateCompanion<Kid> {
  final Value<String> id;
  final Value<String> firstName;
  final Value<String?> lastName;
  final Value<String?> podId;
  final Value<DateTime?> birthDate;
  final Value<String?> pin;
  final Value<String?> notes;
  final Value<String?> parentName;
  final Value<String?> avatarPath;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const KidsCompanion({
    this.id = const Value.absent(),
    this.firstName = const Value.absent(),
    this.lastName = const Value.absent(),
    this.podId = const Value.absent(),
    this.birthDate = const Value.absent(),
    this.pin = const Value.absent(),
    this.notes = const Value.absent(),
    this.parentName = const Value.absent(),
    this.avatarPath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KidsCompanion.insert({
    required String id,
    required String firstName,
    this.lastName = const Value.absent(),
    this.podId = const Value.absent(),
    this.birthDate = const Value.absent(),
    this.pin = const Value.absent(),
    this.notes = const Value.absent(),
    this.parentName = const Value.absent(),
    this.avatarPath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       firstName = Value(firstName);
  static Insertable<Kid> custom({
    Expression<String>? id,
    Expression<String>? firstName,
    Expression<String>? lastName,
    Expression<String>? podId,
    Expression<DateTime>? birthDate,
    Expression<String>? pin,
    Expression<String>? notes,
    Expression<String>? parentName,
    Expression<String>? avatarPath,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (podId != null) 'pod_id': podId,
      if (birthDate != null) 'birth_date': birthDate,
      if (pin != null) 'pin': pin,
      if (notes != null) 'notes': notes,
      if (parentName != null) 'parent_name': parentName,
      if (avatarPath != null) 'avatar_path': avatarPath,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KidsCompanion copyWith({
    Value<String>? id,
    Value<String>? firstName,
    Value<String?>? lastName,
    Value<String?>? podId,
    Value<DateTime?>? birthDate,
    Value<String?>? pin,
    Value<String?>? notes,
    Value<String?>? parentName,
    Value<String?>? avatarPath,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return KidsCompanion(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      podId: podId ?? this.podId,
      birthDate: birthDate ?? this.birthDate,
      pin: pin ?? this.pin,
      notes: notes ?? this.notes,
      parentName: parentName ?? this.parentName,
      avatarPath: avatarPath ?? this.avatarPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (firstName.present) {
      map['first_name'] = Variable<String>(firstName.value);
    }
    if (lastName.present) {
      map['last_name'] = Variable<String>(lastName.value);
    }
    if (podId.present) {
      map['pod_id'] = Variable<String>(podId.value);
    }
    if (birthDate.present) {
      map['birth_date'] = Variable<DateTime>(birthDate.value);
    }
    if (pin.present) {
      map['pin'] = Variable<String>(pin.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (parentName.present) {
      map['parent_name'] = Variable<String>(parentName.value);
    }
    if (avatarPath.present) {
      map['avatar_path'] = Variable<String>(avatarPath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KidsCompanion(')
          ..write('id: $id, ')
          ..write('firstName: $firstName, ')
          ..write('lastName: $lastName, ')
          ..write('podId: $podId, ')
          ..write('birthDate: $birthDate, ')
          ..write('pin: $pin, ')
          ..write('notes: $notes, ')
          ..write('parentName: $parentName, ')
          ..write('avatarPath: $avatarPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TripsTable extends Trips with TableInfo<$TripsTable, Trip> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TripsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endDateMeta = const VerificationMeta(
    'endDate',
  );
  @override
  late final GeneratedColumn<DateTime> endDate = GeneratedColumn<DateTime>(
    'end_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationMeta = const VerificationMeta(
    'location',
  );
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _departureTimeMeta = const VerificationMeta(
    'departureTime',
  );
  @override
  late final GeneratedColumn<String> departureTime = GeneratedColumn<String>(
    'departure_time',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _returnTimeMeta = const VerificationMeta(
    'returnTime',
  );
  @override
  late final GeneratedColumn<String> returnTime = GeneratedColumn<String>(
    'return_time',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    date,
    endDate,
    location,
    notes,
    departureTime,
    returnTime,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trips';
  @override
  VerificationContext validateIntegrity(
    Insertable<Trip> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('end_date')) {
      context.handle(
        _endDateMeta,
        endDate.isAcceptableOrUnknown(data['end_date']!, _endDateMeta),
      );
    }
    if (data.containsKey('location')) {
      context.handle(
        _locationMeta,
        location.isAcceptableOrUnknown(data['location']!, _locationMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('departure_time')) {
      context.handle(
        _departureTimeMeta,
        departureTime.isAcceptableOrUnknown(
          data['departure_time']!,
          _departureTimeMeta,
        ),
      );
    }
    if (data.containsKey('return_time')) {
      context.handle(
        _returnTimeMeta,
        returnTime.isAcceptableOrUnknown(data['return_time']!, _returnTimeMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Trip map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Trip(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      endDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_date'],
      ),
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      departureTime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}departure_time'],
      ),
      returnTime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}return_time'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $TripsTable createAlias(String alias) {
    return $TripsTable(attachedDatabase, alias);
  }
}

class Trip extends DataClass implements Insertable<Trip> {
  final String id;
  final String name;
  final DateTime date;
  final DateTime? endDate;
  final String? location;
  final String? notes;
  final String? departureTime;
  final String? returnTime;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Trip({
    required this.id,
    required this.name,
    required this.date,
    this.endDate,
    this.location,
    this.notes,
    this.departureTime,
    this.returnTime,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['date'] = Variable<DateTime>(date);
    if (!nullToAbsent || endDate != null) {
      map['end_date'] = Variable<DateTime>(endDate);
    }
    if (!nullToAbsent || location != null) {
      map['location'] = Variable<String>(location);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || departureTime != null) {
      map['departure_time'] = Variable<String>(departureTime);
    }
    if (!nullToAbsent || returnTime != null) {
      map['return_time'] = Variable<String>(returnTime);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TripsCompanion toCompanion(bool nullToAbsent) {
    return TripsCompanion(
      id: Value(id),
      name: Value(name),
      date: Value(date),
      endDate: endDate == null && nullToAbsent
          ? const Value.absent()
          : Value(endDate),
      location: location == null && nullToAbsent
          ? const Value.absent()
          : Value(location),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      departureTime: departureTime == null && nullToAbsent
          ? const Value.absent()
          : Value(departureTime),
      returnTime: returnTime == null && nullToAbsent
          ? const Value.absent()
          : Value(returnTime),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Trip.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Trip(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      date: serializer.fromJson<DateTime>(json['date']),
      endDate: serializer.fromJson<DateTime?>(json['endDate']),
      location: serializer.fromJson<String?>(json['location']),
      notes: serializer.fromJson<String?>(json['notes']),
      departureTime: serializer.fromJson<String?>(json['departureTime']),
      returnTime: serializer.fromJson<String?>(json['returnTime']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'date': serializer.toJson<DateTime>(date),
      'endDate': serializer.toJson<DateTime?>(endDate),
      'location': serializer.toJson<String?>(location),
      'notes': serializer.toJson<String?>(notes),
      'departureTime': serializer.toJson<String?>(departureTime),
      'returnTime': serializer.toJson<String?>(returnTime),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Trip copyWith({
    String? id,
    String? name,
    DateTime? date,
    Value<DateTime?> endDate = const Value.absent(),
    Value<String?> location = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<String?> departureTime = const Value.absent(),
    Value<String?> returnTime = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Trip(
    id: id ?? this.id,
    name: name ?? this.name,
    date: date ?? this.date,
    endDate: endDate.present ? endDate.value : this.endDate,
    location: location.present ? location.value : this.location,
    notes: notes.present ? notes.value : this.notes,
    departureTime: departureTime.present
        ? departureTime.value
        : this.departureTime,
    returnTime: returnTime.present ? returnTime.value : this.returnTime,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Trip copyWithCompanion(TripsCompanion data) {
    return Trip(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      date: data.date.present ? data.date.value : this.date,
      endDate: data.endDate.present ? data.endDate.value : this.endDate,
      location: data.location.present ? data.location.value : this.location,
      notes: data.notes.present ? data.notes.value : this.notes,
      departureTime: data.departureTime.present
          ? data.departureTime.value
          : this.departureTime,
      returnTime: data.returnTime.present
          ? data.returnTime.value
          : this.returnTime,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Trip(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('date: $date, ')
          ..write('endDate: $endDate, ')
          ..write('location: $location, ')
          ..write('notes: $notes, ')
          ..write('departureTime: $departureTime, ')
          ..write('returnTime: $returnTime, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    date,
    endDate,
    location,
    notes,
    departureTime,
    returnTime,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Trip &&
          other.id == this.id &&
          other.name == this.name &&
          other.date == this.date &&
          other.endDate == this.endDate &&
          other.location == this.location &&
          other.notes == this.notes &&
          other.departureTime == this.departureTime &&
          other.returnTime == this.returnTime &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TripsCompanion extends UpdateCompanion<Trip> {
  final Value<String> id;
  final Value<String> name;
  final Value<DateTime> date;
  final Value<DateTime?> endDate;
  final Value<String?> location;
  final Value<String?> notes;
  final Value<String?> departureTime;
  final Value<String?> returnTime;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const TripsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.date = const Value.absent(),
    this.endDate = const Value.absent(),
    this.location = const Value.absent(),
    this.notes = const Value.absent(),
    this.departureTime = const Value.absent(),
    this.returnTime = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TripsCompanion.insert({
    required String id,
    required String name,
    required DateTime date,
    this.endDate = const Value.absent(),
    this.location = const Value.absent(),
    this.notes = const Value.absent(),
    this.departureTime = const Value.absent(),
    this.returnTime = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       date = Value(date);
  static Insertable<Trip> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<DateTime>? date,
    Expression<DateTime>? endDate,
    Expression<String>? location,
    Expression<String>? notes,
    Expression<String>? departureTime,
    Expression<String>? returnTime,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (date != null) 'date': date,
      if (endDate != null) 'end_date': endDate,
      if (location != null) 'location': location,
      if (notes != null) 'notes': notes,
      if (departureTime != null) 'departure_time': departureTime,
      if (returnTime != null) 'return_time': returnTime,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TripsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<DateTime>? date,
    Value<DateTime?>? endDate,
    Value<String?>? location,
    Value<String?>? notes,
    Value<String?>? departureTime,
    Value<String?>? returnTime,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return TripsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      date: date ?? this.date,
      endDate: endDate ?? this.endDate,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      departureTime: departureTime ?? this.departureTime,
      returnTime: returnTime ?? this.returnTime,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (endDate.present) {
      map['end_date'] = Variable<DateTime>(endDate.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (departureTime.present) {
      map['departure_time'] = Variable<String>(departureTime.value);
    }
    if (returnTime.present) {
      map['return_time'] = Variable<String>(returnTime.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TripsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('date: $date, ')
          ..write('endDate: $endDate, ')
          ..write('location: $location, ')
          ..write('notes: $notes, ')
          ..write('departureTime: $departureTime, ')
          ..write('returnTime: $returnTime, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TripPodsTable extends TripPods with TableInfo<$TripPodsTable, TripPod> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TripPodsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tripIdMeta = const VerificationMeta('tripId');
  @override
  late final GeneratedColumn<String> tripId = GeneratedColumn<String>(
    'trip_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES trips (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _podIdMeta = const VerificationMeta('podId');
  @override
  late final GeneratedColumn<String> podId = GeneratedColumn<String>(
    'pod_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES pods (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [tripId, podId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trip_pods';
  @override
  VerificationContext validateIntegrity(
    Insertable<TripPod> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('trip_id')) {
      context.handle(
        _tripIdMeta,
        tripId.isAcceptableOrUnknown(data['trip_id']!, _tripIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tripIdMeta);
    }
    if (data.containsKey('pod_id')) {
      context.handle(
        _podIdMeta,
        podId.isAcceptableOrUnknown(data['pod_id']!, _podIdMeta),
      );
    } else if (isInserting) {
      context.missing(_podIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tripId, podId};
  @override
  TripPod map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TripPod(
      tripId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trip_id'],
      )!,
      podId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pod_id'],
      )!,
    );
  }

  @override
  $TripPodsTable createAlias(String alias) {
    return $TripPodsTable(attachedDatabase, alias);
  }
}

class TripPod extends DataClass implements Insertable<TripPod> {
  final String tripId;
  final String podId;
  const TripPod({required this.tripId, required this.podId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['trip_id'] = Variable<String>(tripId);
    map['pod_id'] = Variable<String>(podId);
    return map;
  }

  TripPodsCompanion toCompanion(bool nullToAbsent) {
    return TripPodsCompanion(tripId: Value(tripId), podId: Value(podId));
  }

  factory TripPod.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TripPod(
      tripId: serializer.fromJson<String>(json['tripId']),
      podId: serializer.fromJson<String>(json['podId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tripId': serializer.toJson<String>(tripId),
      'podId': serializer.toJson<String>(podId),
    };
  }

  TripPod copyWith({String? tripId, String? podId}) =>
      TripPod(tripId: tripId ?? this.tripId, podId: podId ?? this.podId);
  TripPod copyWithCompanion(TripPodsCompanion data) {
    return TripPod(
      tripId: data.tripId.present ? data.tripId.value : this.tripId,
      podId: data.podId.present ? data.podId.value : this.podId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TripPod(')
          ..write('tripId: $tripId, ')
          ..write('podId: $podId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tripId, podId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TripPod &&
          other.tripId == this.tripId &&
          other.podId == this.podId);
}

class TripPodsCompanion extends UpdateCompanion<TripPod> {
  final Value<String> tripId;
  final Value<String> podId;
  final Value<int> rowid;
  const TripPodsCompanion({
    this.tripId = const Value.absent(),
    this.podId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TripPodsCompanion.insert({
    required String tripId,
    required String podId,
    this.rowid = const Value.absent(),
  }) : tripId = Value(tripId),
       podId = Value(podId);
  static Insertable<TripPod> custom({
    Expression<String>? tripId,
    Expression<String>? podId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tripId != null) 'trip_id': tripId,
      if (podId != null) 'pod_id': podId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TripPodsCompanion copyWith({
    Value<String>? tripId,
    Value<String>? podId,
    Value<int>? rowid,
  }) {
    return TripPodsCompanion(
      tripId: tripId ?? this.tripId,
      podId: podId ?? this.podId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tripId.present) {
      map['trip_id'] = Variable<String>(tripId.value);
    }
    if (podId.present) {
      map['pod_id'] = Variable<String>(podId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TripPodsCompanion(')
          ..write('tripId: $tripId, ')
          ..write('podId: $podId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CapturesTable extends Captures with TableInfo<$CapturesTable, Capture> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CapturesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _captionMeta = const VerificationMeta(
    'caption',
  );
  @override
  late final GeneratedColumn<String> caption = GeneratedColumn<String>(
    'caption',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _imagePathMeta = const VerificationMeta(
    'imagePath',
  );
  @override
  late final GeneratedColumn<String> imagePath = GeneratedColumn<String>(
    'image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tripIdMeta = const VerificationMeta('tripId');
  @override
  late final GeneratedColumn<String> tripId = GeneratedColumn<String>(
    'trip_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES trips (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _authorNameMeta = const VerificationMeta(
    'authorName',
  );
  @override
  late final GeneratedColumn<String> authorName = GeneratedColumn<String>(
    'author_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    caption,
    imagePath,
    tripId,
    authorName,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'captures';
  @override
  VerificationContext validateIntegrity(
    Insertable<Capture> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('caption')) {
      context.handle(
        _captionMeta,
        caption.isAcceptableOrUnknown(data['caption']!, _captionMeta),
      );
    }
    if (data.containsKey('image_path')) {
      context.handle(
        _imagePathMeta,
        imagePath.isAcceptableOrUnknown(data['image_path']!, _imagePathMeta),
      );
    }
    if (data.containsKey('trip_id')) {
      context.handle(
        _tripIdMeta,
        tripId.isAcceptableOrUnknown(data['trip_id']!, _tripIdMeta),
      );
    }
    if (data.containsKey('author_name')) {
      context.handle(
        _authorNameMeta,
        authorName.isAcceptableOrUnknown(data['author_name']!, _authorNameMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Capture map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Capture(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      caption: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}caption'],
      ),
      imagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_path'],
      ),
      tripId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trip_id'],
      ),
      authorName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_name'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $CapturesTable createAlias(String alias) {
    return $CapturesTable(attachedDatabase, alias);
  }
}

class Capture extends DataClass implements Insertable<Capture> {
  final String id;
  final String kind;
  final String? caption;
  final String? imagePath;
  final String? tripId;
  final String? authorName;
  final DateTime createdAt;
  const Capture({
    required this.id,
    required this.kind,
    this.caption,
    this.imagePath,
    this.tripId,
    this.authorName,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || caption != null) {
      map['caption'] = Variable<String>(caption);
    }
    if (!nullToAbsent || imagePath != null) {
      map['image_path'] = Variable<String>(imagePath);
    }
    if (!nullToAbsent || tripId != null) {
      map['trip_id'] = Variable<String>(tripId);
    }
    if (!nullToAbsent || authorName != null) {
      map['author_name'] = Variable<String>(authorName);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  CapturesCompanion toCompanion(bool nullToAbsent) {
    return CapturesCompanion(
      id: Value(id),
      kind: Value(kind),
      caption: caption == null && nullToAbsent
          ? const Value.absent()
          : Value(caption),
      imagePath: imagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(imagePath),
      tripId: tripId == null && nullToAbsent
          ? const Value.absent()
          : Value(tripId),
      authorName: authorName == null && nullToAbsent
          ? const Value.absent()
          : Value(authorName),
      createdAt: Value(createdAt),
    );
  }

  factory Capture.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Capture(
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      caption: serializer.fromJson<String?>(json['caption']),
      imagePath: serializer.fromJson<String?>(json['imagePath']),
      tripId: serializer.fromJson<String?>(json['tripId']),
      authorName: serializer.fromJson<String?>(json['authorName']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'caption': serializer.toJson<String?>(caption),
      'imagePath': serializer.toJson<String?>(imagePath),
      'tripId': serializer.toJson<String?>(tripId),
      'authorName': serializer.toJson<String?>(authorName),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Capture copyWith({
    String? id,
    String? kind,
    Value<String?> caption = const Value.absent(),
    Value<String?> imagePath = const Value.absent(),
    Value<String?> tripId = const Value.absent(),
    Value<String?> authorName = const Value.absent(),
    DateTime? createdAt,
  }) => Capture(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    caption: caption.present ? caption.value : this.caption,
    imagePath: imagePath.present ? imagePath.value : this.imagePath,
    tripId: tripId.present ? tripId.value : this.tripId,
    authorName: authorName.present ? authorName.value : this.authorName,
    createdAt: createdAt ?? this.createdAt,
  );
  Capture copyWithCompanion(CapturesCompanion data) {
    return Capture(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      caption: data.caption.present ? data.caption.value : this.caption,
      imagePath: data.imagePath.present ? data.imagePath.value : this.imagePath,
      tripId: data.tripId.present ? data.tripId.value : this.tripId,
      authorName: data.authorName.present
          ? data.authorName.value
          : this.authorName,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Capture(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('caption: $caption, ')
          ..write('imagePath: $imagePath, ')
          ..write('tripId: $tripId, ')
          ..write('authorName: $authorName, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, kind, caption, imagePath, tripId, authorName, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Capture &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.caption == this.caption &&
          other.imagePath == this.imagePath &&
          other.tripId == this.tripId &&
          other.authorName == this.authorName &&
          other.createdAt == this.createdAt);
}

class CapturesCompanion extends UpdateCompanion<Capture> {
  final Value<String> id;
  final Value<String> kind;
  final Value<String?> caption;
  final Value<String?> imagePath;
  final Value<String?> tripId;
  final Value<String?> authorName;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const CapturesCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.caption = const Value.absent(),
    this.imagePath = const Value.absent(),
    this.tripId = const Value.absent(),
    this.authorName = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CapturesCompanion.insert({
    required String id,
    required String kind,
    this.caption = const Value.absent(),
    this.imagePath = const Value.absent(),
    this.tripId = const Value.absent(),
    this.authorName = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind);
  static Insertable<Capture> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? caption,
    Expression<String>? imagePath,
    Expression<String>? tripId,
    Expression<String>? authorName,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (caption != null) 'caption': caption,
      if (imagePath != null) 'image_path': imagePath,
      if (tripId != null) 'trip_id': tripId,
      if (authorName != null) 'author_name': authorName,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CapturesCompanion copyWith({
    Value<String>? id,
    Value<String>? kind,
    Value<String?>? caption,
    Value<String?>? imagePath,
    Value<String?>? tripId,
    Value<String?>? authorName,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return CapturesCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      caption: caption ?? this.caption,
      imagePath: imagePath ?? this.imagePath,
      tripId: tripId ?? this.tripId,
      authorName: authorName ?? this.authorName,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (caption.present) {
      map['caption'] = Variable<String>(caption.value);
    }
    if (imagePath.present) {
      map['image_path'] = Variable<String>(imagePath.value);
    }
    if (tripId.present) {
      map['trip_id'] = Variable<String>(tripId.value);
    }
    if (authorName.present) {
      map['author_name'] = Variable<String>(authorName.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CapturesCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('caption: $caption, ')
          ..write('imagePath: $imagePath, ')
          ..write('tripId: $tripId, ')
          ..write('authorName: $authorName, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CaptureKidsTable extends CaptureKids
    with TableInfo<$CaptureKidsTable, CaptureKid> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CaptureKidsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _captureIdMeta = const VerificationMeta(
    'captureId',
  );
  @override
  late final GeneratedColumn<String> captureId = GeneratedColumn<String>(
    'capture_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES captures (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _kidIdMeta = const VerificationMeta('kidId');
  @override
  late final GeneratedColumn<String> kidId = GeneratedColumn<String>(
    'kid_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES kids (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [captureId, kidId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'capture_kids';
  @override
  VerificationContext validateIntegrity(
    Insertable<CaptureKid> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('capture_id')) {
      context.handle(
        _captureIdMeta,
        captureId.isAcceptableOrUnknown(data['capture_id']!, _captureIdMeta),
      );
    } else if (isInserting) {
      context.missing(_captureIdMeta);
    }
    if (data.containsKey('kid_id')) {
      context.handle(
        _kidIdMeta,
        kidId.isAcceptableOrUnknown(data['kid_id']!, _kidIdMeta),
      );
    } else if (isInserting) {
      context.missing(_kidIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {captureId, kidId};
  @override
  CaptureKid map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CaptureKid(
      captureId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}capture_id'],
      )!,
      kidId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kid_id'],
      )!,
    );
  }

  @override
  $CaptureKidsTable createAlias(String alias) {
    return $CaptureKidsTable(attachedDatabase, alias);
  }
}

class CaptureKid extends DataClass implements Insertable<CaptureKid> {
  final String captureId;
  final String kidId;
  const CaptureKid({required this.captureId, required this.kidId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['capture_id'] = Variable<String>(captureId);
    map['kid_id'] = Variable<String>(kidId);
    return map;
  }

  CaptureKidsCompanion toCompanion(bool nullToAbsent) {
    return CaptureKidsCompanion(
      captureId: Value(captureId),
      kidId: Value(kidId),
    );
  }

  factory CaptureKid.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CaptureKid(
      captureId: serializer.fromJson<String>(json['captureId']),
      kidId: serializer.fromJson<String>(json['kidId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'captureId': serializer.toJson<String>(captureId),
      'kidId': serializer.toJson<String>(kidId),
    };
  }

  CaptureKid copyWith({String? captureId, String? kidId}) => CaptureKid(
    captureId: captureId ?? this.captureId,
    kidId: kidId ?? this.kidId,
  );
  CaptureKid copyWithCompanion(CaptureKidsCompanion data) {
    return CaptureKid(
      captureId: data.captureId.present ? data.captureId.value : this.captureId,
      kidId: data.kidId.present ? data.kidId.value : this.kidId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CaptureKid(')
          ..write('captureId: $captureId, ')
          ..write('kidId: $kidId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(captureId, kidId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CaptureKid &&
          other.captureId == this.captureId &&
          other.kidId == this.kidId);
}

class CaptureKidsCompanion extends UpdateCompanion<CaptureKid> {
  final Value<String> captureId;
  final Value<String> kidId;
  final Value<int> rowid;
  const CaptureKidsCompanion({
    this.captureId = const Value.absent(),
    this.kidId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CaptureKidsCompanion.insert({
    required String captureId,
    required String kidId,
    this.rowid = const Value.absent(),
  }) : captureId = Value(captureId),
       kidId = Value(kidId);
  static Insertable<CaptureKid> custom({
    Expression<String>? captureId,
    Expression<String>? kidId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (captureId != null) 'capture_id': captureId,
      if (kidId != null) 'kid_id': kidId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CaptureKidsCompanion copyWith({
    Value<String>? captureId,
    Value<String>? kidId,
    Value<int>? rowid,
  }) {
    return CaptureKidsCompanion(
      captureId: captureId ?? this.captureId,
      kidId: kidId ?? this.kidId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (captureId.present) {
      map['capture_id'] = Variable<String>(captureId.value);
    }
    if (kidId.present) {
      map['kid_id'] = Variable<String>(kidId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CaptureKidsCompanion(')
          ..write('captureId: $captureId, ')
          ..write('kidId: $kidId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ObservationsTable extends Observations
    with TableInfo<$ObservationsTable, Observation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ObservationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetKindMeta = const VerificationMeta(
    'targetKind',
  );
  @override
  late final GeneratedColumn<String> targetKind = GeneratedColumn<String>(
    'target_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kidIdMeta = const VerificationMeta('kidId');
  @override
  late final GeneratedColumn<String> kidId = GeneratedColumn<String>(
    'kid_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES kids (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _podIdMeta = const VerificationMeta('podId');
  @override
  late final GeneratedColumn<String> podId = GeneratedColumn<String>(
    'pod_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES pods (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _activityLabelMeta = const VerificationMeta(
    'activityLabel',
  );
  @override
  late final GeneratedColumn<String> activityLabel = GeneratedColumn<String>(
    'activity_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _domainMeta = const VerificationMeta('domain');
  @override
  late final GeneratedColumn<String> domain = GeneratedColumn<String>(
    'domain',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sentimentMeta = const VerificationMeta(
    'sentiment',
  );
  @override
  late final GeneratedColumn<String> sentiment = GeneratedColumn<String>(
    'sentiment',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteOriginalMeta = const VerificationMeta(
    'noteOriginal',
  );
  @override
  late final GeneratedColumn<String> noteOriginal = GeneratedColumn<String>(
    'note_original',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tripIdMeta = const VerificationMeta('tripId');
  @override
  late final GeneratedColumn<String> tripId = GeneratedColumn<String>(
    'trip_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES trips (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _authorNameMeta = const VerificationMeta(
    'authorName',
  );
  @override
  late final GeneratedColumn<String> authorName = GeneratedColumn<String>(
    'author_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    targetKind,
    kidId,
    podId,
    activityLabel,
    domain,
    sentiment,
    note,
    noteOriginal,
    tripId,
    authorName,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'observations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Observation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('target_kind')) {
      context.handle(
        _targetKindMeta,
        targetKind.isAcceptableOrUnknown(data['target_kind']!, _targetKindMeta),
      );
    } else if (isInserting) {
      context.missing(_targetKindMeta);
    }
    if (data.containsKey('kid_id')) {
      context.handle(
        _kidIdMeta,
        kidId.isAcceptableOrUnknown(data['kid_id']!, _kidIdMeta),
      );
    }
    if (data.containsKey('pod_id')) {
      context.handle(
        _podIdMeta,
        podId.isAcceptableOrUnknown(data['pod_id']!, _podIdMeta),
      );
    }
    if (data.containsKey('activity_label')) {
      context.handle(
        _activityLabelMeta,
        activityLabel.isAcceptableOrUnknown(
          data['activity_label']!,
          _activityLabelMeta,
        ),
      );
    }
    if (data.containsKey('domain')) {
      context.handle(
        _domainMeta,
        domain.isAcceptableOrUnknown(data['domain']!, _domainMeta),
      );
    } else if (isInserting) {
      context.missing(_domainMeta);
    }
    if (data.containsKey('sentiment')) {
      context.handle(
        _sentimentMeta,
        sentiment.isAcceptableOrUnknown(data['sentiment']!, _sentimentMeta),
      );
    } else if (isInserting) {
      context.missing(_sentimentMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    } else if (isInserting) {
      context.missing(_noteMeta);
    }
    if (data.containsKey('note_original')) {
      context.handle(
        _noteOriginalMeta,
        noteOriginal.isAcceptableOrUnknown(
          data['note_original']!,
          _noteOriginalMeta,
        ),
      );
    }
    if (data.containsKey('trip_id')) {
      context.handle(
        _tripIdMeta,
        tripId.isAcceptableOrUnknown(data['trip_id']!, _tripIdMeta),
      );
    }
    if (data.containsKey('author_name')) {
      context.handle(
        _authorNameMeta,
        authorName.isAcceptableOrUnknown(data['author_name']!, _authorNameMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Observation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Observation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      targetKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_kind'],
      )!,
      kidId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kid_id'],
      ),
      podId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pod_id'],
      ),
      activityLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}activity_label'],
      ),
      domain: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}domain'],
      )!,
      sentiment: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sentiment'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      noteOriginal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_original'],
      ),
      tripId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trip_id'],
      ),
      authorName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_name'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ObservationsTable createAlias(String alias) {
    return $ObservationsTable(attachedDatabase, alias);
  }
}

class Observation extends DataClass implements Insertable<Observation> {
  final String id;
  final String targetKind;
  final String? kidId;
  final String? podId;
  final String? activityLabel;
  final String domain;
  final String sentiment;
  final String note;
  final String? noteOriginal;
  final String? tripId;
  final String? authorName;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Observation({
    required this.id,
    required this.targetKind,
    this.kidId,
    this.podId,
    this.activityLabel,
    required this.domain,
    required this.sentiment,
    required this.note,
    this.noteOriginal,
    this.tripId,
    this.authorName,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['target_kind'] = Variable<String>(targetKind);
    if (!nullToAbsent || kidId != null) {
      map['kid_id'] = Variable<String>(kidId);
    }
    if (!nullToAbsent || podId != null) {
      map['pod_id'] = Variable<String>(podId);
    }
    if (!nullToAbsent || activityLabel != null) {
      map['activity_label'] = Variable<String>(activityLabel);
    }
    map['domain'] = Variable<String>(domain);
    map['sentiment'] = Variable<String>(sentiment);
    map['note'] = Variable<String>(note);
    if (!nullToAbsent || noteOriginal != null) {
      map['note_original'] = Variable<String>(noteOriginal);
    }
    if (!nullToAbsent || tripId != null) {
      map['trip_id'] = Variable<String>(tripId);
    }
    if (!nullToAbsent || authorName != null) {
      map['author_name'] = Variable<String>(authorName);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ObservationsCompanion toCompanion(bool nullToAbsent) {
    return ObservationsCompanion(
      id: Value(id),
      targetKind: Value(targetKind),
      kidId: kidId == null && nullToAbsent
          ? const Value.absent()
          : Value(kidId),
      podId: podId == null && nullToAbsent
          ? const Value.absent()
          : Value(podId),
      activityLabel: activityLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(activityLabel),
      domain: Value(domain),
      sentiment: Value(sentiment),
      note: Value(note),
      noteOriginal: noteOriginal == null && nullToAbsent
          ? const Value.absent()
          : Value(noteOriginal),
      tripId: tripId == null && nullToAbsent
          ? const Value.absent()
          : Value(tripId),
      authorName: authorName == null && nullToAbsent
          ? const Value.absent()
          : Value(authorName),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Observation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Observation(
      id: serializer.fromJson<String>(json['id']),
      targetKind: serializer.fromJson<String>(json['targetKind']),
      kidId: serializer.fromJson<String?>(json['kidId']),
      podId: serializer.fromJson<String?>(json['podId']),
      activityLabel: serializer.fromJson<String?>(json['activityLabel']),
      domain: serializer.fromJson<String>(json['domain']),
      sentiment: serializer.fromJson<String>(json['sentiment']),
      note: serializer.fromJson<String>(json['note']),
      noteOriginal: serializer.fromJson<String?>(json['noteOriginal']),
      tripId: serializer.fromJson<String?>(json['tripId']),
      authorName: serializer.fromJson<String?>(json['authorName']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'targetKind': serializer.toJson<String>(targetKind),
      'kidId': serializer.toJson<String?>(kidId),
      'podId': serializer.toJson<String?>(podId),
      'activityLabel': serializer.toJson<String?>(activityLabel),
      'domain': serializer.toJson<String>(domain),
      'sentiment': serializer.toJson<String>(sentiment),
      'note': serializer.toJson<String>(note),
      'noteOriginal': serializer.toJson<String?>(noteOriginal),
      'tripId': serializer.toJson<String?>(tripId),
      'authorName': serializer.toJson<String?>(authorName),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Observation copyWith({
    String? id,
    String? targetKind,
    Value<String?> kidId = const Value.absent(),
    Value<String?> podId = const Value.absent(),
    Value<String?> activityLabel = const Value.absent(),
    String? domain,
    String? sentiment,
    String? note,
    Value<String?> noteOriginal = const Value.absent(),
    Value<String?> tripId = const Value.absent(),
    Value<String?> authorName = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Observation(
    id: id ?? this.id,
    targetKind: targetKind ?? this.targetKind,
    kidId: kidId.present ? kidId.value : this.kidId,
    podId: podId.present ? podId.value : this.podId,
    activityLabel: activityLabel.present
        ? activityLabel.value
        : this.activityLabel,
    domain: domain ?? this.domain,
    sentiment: sentiment ?? this.sentiment,
    note: note ?? this.note,
    noteOriginal: noteOriginal.present ? noteOriginal.value : this.noteOriginal,
    tripId: tripId.present ? tripId.value : this.tripId,
    authorName: authorName.present ? authorName.value : this.authorName,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Observation copyWithCompanion(ObservationsCompanion data) {
    return Observation(
      id: data.id.present ? data.id.value : this.id,
      targetKind: data.targetKind.present
          ? data.targetKind.value
          : this.targetKind,
      kidId: data.kidId.present ? data.kidId.value : this.kidId,
      podId: data.podId.present ? data.podId.value : this.podId,
      activityLabel: data.activityLabel.present
          ? data.activityLabel.value
          : this.activityLabel,
      domain: data.domain.present ? data.domain.value : this.domain,
      sentiment: data.sentiment.present ? data.sentiment.value : this.sentiment,
      note: data.note.present ? data.note.value : this.note,
      noteOriginal: data.noteOriginal.present
          ? data.noteOriginal.value
          : this.noteOriginal,
      tripId: data.tripId.present ? data.tripId.value : this.tripId,
      authorName: data.authorName.present
          ? data.authorName.value
          : this.authorName,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Observation(')
          ..write('id: $id, ')
          ..write('targetKind: $targetKind, ')
          ..write('kidId: $kidId, ')
          ..write('podId: $podId, ')
          ..write('activityLabel: $activityLabel, ')
          ..write('domain: $domain, ')
          ..write('sentiment: $sentiment, ')
          ..write('note: $note, ')
          ..write('noteOriginal: $noteOriginal, ')
          ..write('tripId: $tripId, ')
          ..write('authorName: $authorName, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    targetKind,
    kidId,
    podId,
    activityLabel,
    domain,
    sentiment,
    note,
    noteOriginal,
    tripId,
    authorName,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Observation &&
          other.id == this.id &&
          other.targetKind == this.targetKind &&
          other.kidId == this.kidId &&
          other.podId == this.podId &&
          other.activityLabel == this.activityLabel &&
          other.domain == this.domain &&
          other.sentiment == this.sentiment &&
          other.note == this.note &&
          other.noteOriginal == this.noteOriginal &&
          other.tripId == this.tripId &&
          other.authorName == this.authorName &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ObservationsCompanion extends UpdateCompanion<Observation> {
  final Value<String> id;
  final Value<String> targetKind;
  final Value<String?> kidId;
  final Value<String?> podId;
  final Value<String?> activityLabel;
  final Value<String> domain;
  final Value<String> sentiment;
  final Value<String> note;
  final Value<String?> noteOriginal;
  final Value<String?> tripId;
  final Value<String?> authorName;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ObservationsCompanion({
    this.id = const Value.absent(),
    this.targetKind = const Value.absent(),
    this.kidId = const Value.absent(),
    this.podId = const Value.absent(),
    this.activityLabel = const Value.absent(),
    this.domain = const Value.absent(),
    this.sentiment = const Value.absent(),
    this.note = const Value.absent(),
    this.noteOriginal = const Value.absent(),
    this.tripId = const Value.absent(),
    this.authorName = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ObservationsCompanion.insert({
    required String id,
    required String targetKind,
    this.kidId = const Value.absent(),
    this.podId = const Value.absent(),
    this.activityLabel = const Value.absent(),
    required String domain,
    required String sentiment,
    required String note,
    this.noteOriginal = const Value.absent(),
    this.tripId = const Value.absent(),
    this.authorName = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       targetKind = Value(targetKind),
       domain = Value(domain),
       sentiment = Value(sentiment),
       note = Value(note);
  static Insertable<Observation> custom({
    Expression<String>? id,
    Expression<String>? targetKind,
    Expression<String>? kidId,
    Expression<String>? podId,
    Expression<String>? activityLabel,
    Expression<String>? domain,
    Expression<String>? sentiment,
    Expression<String>? note,
    Expression<String>? noteOriginal,
    Expression<String>? tripId,
    Expression<String>? authorName,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (targetKind != null) 'target_kind': targetKind,
      if (kidId != null) 'kid_id': kidId,
      if (podId != null) 'pod_id': podId,
      if (activityLabel != null) 'activity_label': activityLabel,
      if (domain != null) 'domain': domain,
      if (sentiment != null) 'sentiment': sentiment,
      if (note != null) 'note': note,
      if (noteOriginal != null) 'note_original': noteOriginal,
      if (tripId != null) 'trip_id': tripId,
      if (authorName != null) 'author_name': authorName,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ObservationsCompanion copyWith({
    Value<String>? id,
    Value<String>? targetKind,
    Value<String?>? kidId,
    Value<String?>? podId,
    Value<String?>? activityLabel,
    Value<String>? domain,
    Value<String>? sentiment,
    Value<String>? note,
    Value<String?>? noteOriginal,
    Value<String?>? tripId,
    Value<String?>? authorName,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ObservationsCompanion(
      id: id ?? this.id,
      targetKind: targetKind ?? this.targetKind,
      kidId: kidId ?? this.kidId,
      podId: podId ?? this.podId,
      activityLabel: activityLabel ?? this.activityLabel,
      domain: domain ?? this.domain,
      sentiment: sentiment ?? this.sentiment,
      note: note ?? this.note,
      noteOriginal: noteOriginal ?? this.noteOriginal,
      tripId: tripId ?? this.tripId,
      authorName: authorName ?? this.authorName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (targetKind.present) {
      map['target_kind'] = Variable<String>(targetKind.value);
    }
    if (kidId.present) {
      map['kid_id'] = Variable<String>(kidId.value);
    }
    if (podId.present) {
      map['pod_id'] = Variable<String>(podId.value);
    }
    if (activityLabel.present) {
      map['activity_label'] = Variable<String>(activityLabel.value);
    }
    if (domain.present) {
      map['domain'] = Variable<String>(domain.value);
    }
    if (sentiment.present) {
      map['sentiment'] = Variable<String>(sentiment.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (noteOriginal.present) {
      map['note_original'] = Variable<String>(noteOriginal.value);
    }
    if (tripId.present) {
      map['trip_id'] = Variable<String>(tripId.value);
    }
    if (authorName.present) {
      map['author_name'] = Variable<String>(authorName.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ObservationsCompanion(')
          ..write('id: $id, ')
          ..write('targetKind: $targetKind, ')
          ..write('kidId: $kidId, ')
          ..write('podId: $podId, ')
          ..write('activityLabel: $activityLabel, ')
          ..write('domain: $domain, ')
          ..write('sentiment: $sentiment, ')
          ..write('note: $note, ')
          ..write('noteOriginal: $noteOriginal, ')
          ..write('tripId: $tripId, ')
          ..write('authorName: $authorName, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ObservationKidsTable extends ObservationKids
    with TableInfo<$ObservationKidsTable, ObservationKid> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ObservationKidsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _observationIdMeta = const VerificationMeta(
    'observationId',
  );
  @override
  late final GeneratedColumn<String> observationId = GeneratedColumn<String>(
    'observation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES observations (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _kidIdMeta = const VerificationMeta('kidId');
  @override
  late final GeneratedColumn<String> kidId = GeneratedColumn<String>(
    'kid_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES kids (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [observationId, kidId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'observation_kids';
  @override
  VerificationContext validateIntegrity(
    Insertable<ObservationKid> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('observation_id')) {
      context.handle(
        _observationIdMeta,
        observationId.isAcceptableOrUnknown(
          data['observation_id']!,
          _observationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_observationIdMeta);
    }
    if (data.containsKey('kid_id')) {
      context.handle(
        _kidIdMeta,
        kidId.isAcceptableOrUnknown(data['kid_id']!, _kidIdMeta),
      );
    } else if (isInserting) {
      context.missing(_kidIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {observationId, kidId};
  @override
  ObservationKid map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ObservationKid(
      observationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}observation_id'],
      )!,
      kidId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kid_id'],
      )!,
    );
  }

  @override
  $ObservationKidsTable createAlias(String alias) {
    return $ObservationKidsTable(attachedDatabase, alias);
  }
}

class ObservationKid extends DataClass implements Insertable<ObservationKid> {
  final String observationId;
  final String kidId;
  const ObservationKid({required this.observationId, required this.kidId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['observation_id'] = Variable<String>(observationId);
    map['kid_id'] = Variable<String>(kidId);
    return map;
  }

  ObservationKidsCompanion toCompanion(bool nullToAbsent) {
    return ObservationKidsCompanion(
      observationId: Value(observationId),
      kidId: Value(kidId),
    );
  }

  factory ObservationKid.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ObservationKid(
      observationId: serializer.fromJson<String>(json['observationId']),
      kidId: serializer.fromJson<String>(json['kidId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'observationId': serializer.toJson<String>(observationId),
      'kidId': serializer.toJson<String>(kidId),
    };
  }

  ObservationKid copyWith({String? observationId, String? kidId}) =>
      ObservationKid(
        observationId: observationId ?? this.observationId,
        kidId: kidId ?? this.kidId,
      );
  ObservationKid copyWithCompanion(ObservationKidsCompanion data) {
    return ObservationKid(
      observationId: data.observationId.present
          ? data.observationId.value
          : this.observationId,
      kidId: data.kidId.present ? data.kidId.value : this.kidId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ObservationKid(')
          ..write('observationId: $observationId, ')
          ..write('kidId: $kidId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(observationId, kidId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ObservationKid &&
          other.observationId == this.observationId &&
          other.kidId == this.kidId);
}

class ObservationKidsCompanion extends UpdateCompanion<ObservationKid> {
  final Value<String> observationId;
  final Value<String> kidId;
  final Value<int> rowid;
  const ObservationKidsCompanion({
    this.observationId = const Value.absent(),
    this.kidId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ObservationKidsCompanion.insert({
    required String observationId,
    required String kidId,
    this.rowid = const Value.absent(),
  }) : observationId = Value(observationId),
       kidId = Value(kidId);
  static Insertable<ObservationKid> custom({
    Expression<String>? observationId,
    Expression<String>? kidId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (observationId != null) 'observation_id': observationId,
      if (kidId != null) 'kid_id': kidId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ObservationKidsCompanion copyWith({
    Value<String>? observationId,
    Value<String>? kidId,
    Value<int>? rowid,
  }) {
    return ObservationKidsCompanion(
      observationId: observationId ?? this.observationId,
      kidId: kidId ?? this.kidId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (observationId.present) {
      map['observation_id'] = Variable<String>(observationId.value);
    }
    if (kidId.present) {
      map['kid_id'] = Variable<String>(kidId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ObservationKidsCompanion(')
          ..write('observationId: $observationId, ')
          ..write('kidId: $kidId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ObservationAttachmentsTable extends ObservationAttachments
    with TableInfo<$ObservationAttachmentsTable, ObservationAttachment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ObservationAttachmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _observationIdMeta = const VerificationMeta(
    'observationId',
  );
  @override
  late final GeneratedColumn<String> observationId = GeneratedColumn<String>(
    'observation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES observations (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteUrlMeta = const VerificationMeta(
    'remoteUrl',
  );
  @override
  late final GeneratedColumn<String> remoteUrl = GeneratedColumn<String>(
    'remote_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _thumbnailPathMeta = const VerificationMeta(
    'thumbnailPath',
  );
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
    'thumbnail_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    observationId,
    kind,
    localPath,
    remoteUrl,
    thumbnailPath,
    durationMs,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'observation_attachments';
  @override
  VerificationContext validateIntegrity(
    Insertable<ObservationAttachment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('observation_id')) {
      context.handle(
        _observationIdMeta,
        observationId.isAcceptableOrUnknown(
          data['observation_id']!,
          _observationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_observationIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('remote_url')) {
      context.handle(
        _remoteUrlMeta,
        remoteUrl.isAcceptableOrUnknown(data['remote_url']!, _remoteUrlMeta),
      );
    }
    if (data.containsKey('thumbnail_path')) {
      context.handle(
        _thumbnailPathMeta,
        thumbnailPath.isAcceptableOrUnknown(
          data['thumbnail_path']!,
          _thumbnailPathMeta,
        ),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ObservationAttachment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ObservationAttachment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      observationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}observation_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      )!,
      remoteUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_url'],
      ),
      thumbnailPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_path'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ObservationAttachmentsTable createAlias(String alias) {
    return $ObservationAttachmentsTable(attachedDatabase, alias);
  }
}

class ObservationAttachment extends DataClass
    implements Insertable<ObservationAttachment> {
  final String id;
  final String observationId;
  final String kind;
  final String localPath;
  final String? remoteUrl;
  final String? thumbnailPath;
  final int? durationMs;
  final DateTime createdAt;
  const ObservationAttachment({
    required this.id,
    required this.observationId,
    required this.kind,
    required this.localPath,
    this.remoteUrl,
    this.thumbnailPath,
    this.durationMs,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['observation_id'] = Variable<String>(observationId);
    map['kind'] = Variable<String>(kind);
    map['local_path'] = Variable<String>(localPath);
    if (!nullToAbsent || remoteUrl != null) {
      map['remote_url'] = Variable<String>(remoteUrl);
    }
    if (!nullToAbsent || thumbnailPath != null) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ObservationAttachmentsCompanion toCompanion(bool nullToAbsent) {
    return ObservationAttachmentsCompanion(
      id: Value(id),
      observationId: Value(observationId),
      kind: Value(kind),
      localPath: Value(localPath),
      remoteUrl: remoteUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteUrl),
      thumbnailPath: thumbnailPath == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailPath),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      createdAt: Value(createdAt),
    );
  }

  factory ObservationAttachment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ObservationAttachment(
      id: serializer.fromJson<String>(json['id']),
      observationId: serializer.fromJson<String>(json['observationId']),
      kind: serializer.fromJson<String>(json['kind']),
      localPath: serializer.fromJson<String>(json['localPath']),
      remoteUrl: serializer.fromJson<String?>(json['remoteUrl']),
      thumbnailPath: serializer.fromJson<String?>(json['thumbnailPath']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'observationId': serializer.toJson<String>(observationId),
      'kind': serializer.toJson<String>(kind),
      'localPath': serializer.toJson<String>(localPath),
      'remoteUrl': serializer.toJson<String?>(remoteUrl),
      'thumbnailPath': serializer.toJson<String?>(thumbnailPath),
      'durationMs': serializer.toJson<int?>(durationMs),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ObservationAttachment copyWith({
    String? id,
    String? observationId,
    String? kind,
    String? localPath,
    Value<String?> remoteUrl = const Value.absent(),
    Value<String?> thumbnailPath = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
    DateTime? createdAt,
  }) => ObservationAttachment(
    id: id ?? this.id,
    observationId: observationId ?? this.observationId,
    kind: kind ?? this.kind,
    localPath: localPath ?? this.localPath,
    remoteUrl: remoteUrl.present ? remoteUrl.value : this.remoteUrl,
    thumbnailPath: thumbnailPath.present
        ? thumbnailPath.value
        : this.thumbnailPath,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    createdAt: createdAt ?? this.createdAt,
  );
  ObservationAttachment copyWithCompanion(
    ObservationAttachmentsCompanion data,
  ) {
    return ObservationAttachment(
      id: data.id.present ? data.id.value : this.id,
      observationId: data.observationId.present
          ? data.observationId.value
          : this.observationId,
      kind: data.kind.present ? data.kind.value : this.kind,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      remoteUrl: data.remoteUrl.present ? data.remoteUrl.value : this.remoteUrl,
      thumbnailPath: data.thumbnailPath.present
          ? data.thumbnailPath.value
          : this.thumbnailPath,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ObservationAttachment(')
          ..write('id: $id, ')
          ..write('observationId: $observationId, ')
          ..write('kind: $kind, ')
          ..write('localPath: $localPath, ')
          ..write('remoteUrl: $remoteUrl, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('durationMs: $durationMs, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    observationId,
    kind,
    localPath,
    remoteUrl,
    thumbnailPath,
    durationMs,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ObservationAttachment &&
          other.id == this.id &&
          other.observationId == this.observationId &&
          other.kind == this.kind &&
          other.localPath == this.localPath &&
          other.remoteUrl == this.remoteUrl &&
          other.thumbnailPath == this.thumbnailPath &&
          other.durationMs == this.durationMs &&
          other.createdAt == this.createdAt);
}

class ObservationAttachmentsCompanion
    extends UpdateCompanion<ObservationAttachment> {
  final Value<String> id;
  final Value<String> observationId;
  final Value<String> kind;
  final Value<String> localPath;
  final Value<String?> remoteUrl;
  final Value<String?> thumbnailPath;
  final Value<int?> durationMs;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ObservationAttachmentsCompanion({
    this.id = const Value.absent(),
    this.observationId = const Value.absent(),
    this.kind = const Value.absent(),
    this.localPath = const Value.absent(),
    this.remoteUrl = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ObservationAttachmentsCompanion.insert({
    required String id,
    required String observationId,
    required String kind,
    required String localPath,
    this.remoteUrl = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       observationId = Value(observationId),
       kind = Value(kind),
       localPath = Value(localPath);
  static Insertable<ObservationAttachment> custom({
    Expression<String>? id,
    Expression<String>? observationId,
    Expression<String>? kind,
    Expression<String>? localPath,
    Expression<String>? remoteUrl,
    Expression<String>? thumbnailPath,
    Expression<int>? durationMs,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (observationId != null) 'observation_id': observationId,
      if (kind != null) 'kind': kind,
      if (localPath != null) 'local_path': localPath,
      if (remoteUrl != null) 'remote_url': remoteUrl,
      if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
      if (durationMs != null) 'duration_ms': durationMs,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ObservationAttachmentsCompanion copyWith({
    Value<String>? id,
    Value<String>? observationId,
    Value<String>? kind,
    Value<String>? localPath,
    Value<String?>? remoteUrl,
    Value<String?>? thumbnailPath,
    Value<int?>? durationMs,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ObservationAttachmentsCompanion(
      id: id ?? this.id,
      observationId: observationId ?? this.observationId,
      kind: kind ?? this.kind,
      localPath: localPath ?? this.localPath,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      durationMs: durationMs ?? this.durationMs,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (observationId.present) {
      map['observation_id'] = Variable<String>(observationId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (remoteUrl.present) {
      map['remote_url'] = Variable<String>(remoteUrl.value);
    }
    if (thumbnailPath.present) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ObservationAttachmentsCompanion(')
          ..write('id: $id, ')
          ..write('observationId: $observationId, ')
          ..write('kind: $kind, ')
          ..write('localPath: $localPath, ')
          ..write('remoteUrl: $remoteUrl, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('durationMs: $durationMs, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ObservationDomainTagsTable extends ObservationDomainTags
    with TableInfo<$ObservationDomainTagsTable, ObservationDomainTag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ObservationDomainTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _observationIdMeta = const VerificationMeta(
    'observationId',
  );
  @override
  late final GeneratedColumn<String> observationId = GeneratedColumn<String>(
    'observation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES observations (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _domainMeta = const VerificationMeta('domain');
  @override
  late final GeneratedColumn<String> domain = GeneratedColumn<String>(
    'domain',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [observationId, domain];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'observation_domain_tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<ObservationDomainTag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('observation_id')) {
      context.handle(
        _observationIdMeta,
        observationId.isAcceptableOrUnknown(
          data['observation_id']!,
          _observationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_observationIdMeta);
    }
    if (data.containsKey('domain')) {
      context.handle(
        _domainMeta,
        domain.isAcceptableOrUnknown(data['domain']!, _domainMeta),
      );
    } else if (isInserting) {
      context.missing(_domainMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {observationId, domain};
  @override
  ObservationDomainTag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ObservationDomainTag(
      observationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}observation_id'],
      )!,
      domain: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}domain'],
      )!,
    );
  }

  @override
  $ObservationDomainTagsTable createAlias(String alias) {
    return $ObservationDomainTagsTable(attachedDatabase, alias);
  }
}

class ObservationDomainTag extends DataClass
    implements Insertable<ObservationDomainTag> {
  final String observationId;
  final String domain;
  const ObservationDomainTag({
    required this.observationId,
    required this.domain,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['observation_id'] = Variable<String>(observationId);
    map['domain'] = Variable<String>(domain);
    return map;
  }

  ObservationDomainTagsCompanion toCompanion(bool nullToAbsent) {
    return ObservationDomainTagsCompanion(
      observationId: Value(observationId),
      domain: Value(domain),
    );
  }

  factory ObservationDomainTag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ObservationDomainTag(
      observationId: serializer.fromJson<String>(json['observationId']),
      domain: serializer.fromJson<String>(json['domain']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'observationId': serializer.toJson<String>(observationId),
      'domain': serializer.toJson<String>(domain),
    };
  }

  ObservationDomainTag copyWith({String? observationId, String? domain}) =>
      ObservationDomainTag(
        observationId: observationId ?? this.observationId,
        domain: domain ?? this.domain,
      );
  ObservationDomainTag copyWithCompanion(ObservationDomainTagsCompanion data) {
    return ObservationDomainTag(
      observationId: data.observationId.present
          ? data.observationId.value
          : this.observationId,
      domain: data.domain.present ? data.domain.value : this.domain,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ObservationDomainTag(')
          ..write('observationId: $observationId, ')
          ..write('domain: $domain')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(observationId, domain);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ObservationDomainTag &&
          other.observationId == this.observationId &&
          other.domain == this.domain);
}

class ObservationDomainTagsCompanion
    extends UpdateCompanion<ObservationDomainTag> {
  final Value<String> observationId;
  final Value<String> domain;
  final Value<int> rowid;
  const ObservationDomainTagsCompanion({
    this.observationId = const Value.absent(),
    this.domain = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ObservationDomainTagsCompanion.insert({
    required String observationId,
    required String domain,
    this.rowid = const Value.absent(),
  }) : observationId = Value(observationId),
       domain = Value(domain);
  static Insertable<ObservationDomainTag> custom({
    Expression<String>? observationId,
    Expression<String>? domain,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (observationId != null) 'observation_id': observationId,
      if (domain != null) 'domain': domain,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ObservationDomainTagsCompanion copyWith({
    Value<String>? observationId,
    Value<String>? domain,
    Value<int>? rowid,
  }) {
    return ObservationDomainTagsCompanion(
      observationId: observationId ?? this.observationId,
      domain: domain ?? this.domain,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (observationId.present) {
      map['observation_id'] = Variable<String>(observationId.value);
    }
    if (domain.present) {
      map['domain'] = Variable<String>(domain.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ObservationDomainTagsCompanion(')
          ..write('observationId: $observationId, ')
          ..write('domain: $domain, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SpecialistsTable extends Specialists
    with TableInfo<$SpecialistsTable, Specialist> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SpecialistsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avatarPathMeta = const VerificationMeta(
    'avatarPath',
  );
  @override
  late final GeneratedColumn<String> avatarPath = GeneratedColumn<String>(
    'avatar_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    role,
    notes,
    avatarPath,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'specialists';
  @override
  VerificationContext validateIntegrity(
    Insertable<Specialist> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('avatar_path')) {
      context.handle(
        _avatarPathMeta,
        avatarPath.isAcceptableOrUnknown(data['avatar_path']!, _avatarPathMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Specialist map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Specialist(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      avatarPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_path'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SpecialistsTable createAlias(String alias) {
    return $SpecialistsTable(attachedDatabase, alias);
  }
}

class Specialist extends DataClass implements Insertable<Specialist> {
  final String id;
  final String name;
  final String? role;
  final String? notes;
  final String? avatarPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Specialist({
    required this.id,
    required this.name,
    this.role,
    this.notes,
    this.avatarPath,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || role != null) {
      map['role'] = Variable<String>(role);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || avatarPath != null) {
      map['avatar_path'] = Variable<String>(avatarPath);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SpecialistsCompanion toCompanion(bool nullToAbsent) {
    return SpecialistsCompanion(
      id: Value(id),
      name: Value(name),
      role: role == null && nullToAbsent ? const Value.absent() : Value(role),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      avatarPath: avatarPath == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarPath),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Specialist.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Specialist(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      role: serializer.fromJson<String?>(json['role']),
      notes: serializer.fromJson<String?>(json['notes']),
      avatarPath: serializer.fromJson<String?>(json['avatarPath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'role': serializer.toJson<String?>(role),
      'notes': serializer.toJson<String?>(notes),
      'avatarPath': serializer.toJson<String?>(avatarPath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Specialist copyWith({
    String? id,
    String? name,
    Value<String?> role = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<String?> avatarPath = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Specialist(
    id: id ?? this.id,
    name: name ?? this.name,
    role: role.present ? role.value : this.role,
    notes: notes.present ? notes.value : this.notes,
    avatarPath: avatarPath.present ? avatarPath.value : this.avatarPath,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Specialist copyWithCompanion(SpecialistsCompanion data) {
    return Specialist(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      role: data.role.present ? data.role.value : this.role,
      notes: data.notes.present ? data.notes.value : this.notes,
      avatarPath: data.avatarPath.present
          ? data.avatarPath.value
          : this.avatarPath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Specialist(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('role: $role, ')
          ..write('notes: $notes, ')
          ..write('avatarPath: $avatarPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, role, notes, avatarPath, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Specialist &&
          other.id == this.id &&
          other.name == this.name &&
          other.role == this.role &&
          other.notes == this.notes &&
          other.avatarPath == this.avatarPath &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SpecialistsCompanion extends UpdateCompanion<Specialist> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> role;
  final Value<String?> notes;
  final Value<String?> avatarPath;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SpecialistsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.role = const Value.absent(),
    this.notes = const Value.absent(),
    this.avatarPath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SpecialistsCompanion.insert({
    required String id,
    required String name,
    this.role = const Value.absent(),
    this.notes = const Value.absent(),
    this.avatarPath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<Specialist> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? role,
    Expression<String>? notes,
    Expression<String>? avatarPath,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (role != null) 'role': role,
      if (notes != null) 'notes': notes,
      if (avatarPath != null) 'avatar_path': avatarPath,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SpecialistsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? role,
    Value<String?>? notes,
    Value<String?>? avatarPath,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SpecialistsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      notes: notes ?? this.notes,
      avatarPath: avatarPath ?? this.avatarPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (avatarPath.present) {
      map['avatar_path'] = Variable<String>(avatarPath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SpecialistsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('role: $role, ')
          ..write('notes: $notes, ')
          ..write('avatarPath: $avatarPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SpecialistAvailabilityTable extends SpecialistAvailability
    with TableInfo<$SpecialistAvailabilityTable, SpecialistAvailabilityData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SpecialistAvailabilityTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _specialistIdMeta = const VerificationMeta(
    'specialistId',
  );
  @override
  late final GeneratedColumn<String> specialistId = GeneratedColumn<String>(
    'specialist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES specialists (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _dayOfWeekMeta = const VerificationMeta(
    'dayOfWeek',
  );
  @override
  late final GeneratedColumn<int> dayOfWeek = GeneratedColumn<int>(
    'day_of_week',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startTimeMeta = const VerificationMeta(
    'startTime',
  );
  @override
  late final GeneratedColumn<String> startTime = GeneratedColumn<String>(
    'start_time',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endTimeMeta = const VerificationMeta(
    'endTime',
  );
  @override
  late final GeneratedColumn<String> endTime = GeneratedColumn<String>(
    'end_time',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startDateMeta = const VerificationMeta(
    'startDate',
  );
  @override
  late final GeneratedColumn<DateTime> startDate = GeneratedColumn<DateTime>(
    'start_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endDateMeta = const VerificationMeta(
    'endDate',
  );
  @override
  late final GeneratedColumn<DateTime> endDate = GeneratedColumn<DateTime>(
    'end_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    specialistId,
    dayOfWeek,
    startTime,
    endTime,
    startDate,
    endDate,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'specialist_availability';
  @override
  VerificationContext validateIntegrity(
    Insertable<SpecialistAvailabilityData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('specialist_id')) {
      context.handle(
        _specialistIdMeta,
        specialistId.isAcceptableOrUnknown(
          data['specialist_id']!,
          _specialistIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_specialistIdMeta);
    }
    if (data.containsKey('day_of_week')) {
      context.handle(
        _dayOfWeekMeta,
        dayOfWeek.isAcceptableOrUnknown(data['day_of_week']!, _dayOfWeekMeta),
      );
    } else if (isInserting) {
      context.missing(_dayOfWeekMeta);
    }
    if (data.containsKey('start_time')) {
      context.handle(
        _startTimeMeta,
        startTime.isAcceptableOrUnknown(data['start_time']!, _startTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_startTimeMeta);
    }
    if (data.containsKey('end_time')) {
      context.handle(
        _endTimeMeta,
        endTime.isAcceptableOrUnknown(data['end_time']!, _endTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_endTimeMeta);
    }
    if (data.containsKey('start_date')) {
      context.handle(
        _startDateMeta,
        startDate.isAcceptableOrUnknown(data['start_date']!, _startDateMeta),
      );
    }
    if (data.containsKey('end_date')) {
      context.handle(
        _endDateMeta,
        endDate.isAcceptableOrUnknown(data['end_date']!, _endDateMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SpecialistAvailabilityData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SpecialistAvailabilityData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      specialistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}specialist_id'],
      )!,
      dayOfWeek: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}day_of_week'],
      )!,
      startTime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_time'],
      )!,
      endTime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}end_time'],
      )!,
      startDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_date'],
      ),
      endDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_date'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SpecialistAvailabilityTable createAlias(String alias) {
    return $SpecialistAvailabilityTable(attachedDatabase, alias);
  }
}

class SpecialistAvailabilityData extends DataClass
    implements Insertable<SpecialistAvailabilityData> {
  final String id;
  final String specialistId;
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  const SpecialistAvailabilityData({
    required this.id,
    required this.specialistId,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.startDate,
    this.endDate,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['specialist_id'] = Variable<String>(specialistId);
    map['day_of_week'] = Variable<int>(dayOfWeek);
    map['start_time'] = Variable<String>(startTime);
    map['end_time'] = Variable<String>(endTime);
    if (!nullToAbsent || startDate != null) {
      map['start_date'] = Variable<DateTime>(startDate);
    }
    if (!nullToAbsent || endDate != null) {
      map['end_date'] = Variable<DateTime>(endDate);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SpecialistAvailabilityCompanion toCompanion(bool nullToAbsent) {
    return SpecialistAvailabilityCompanion(
      id: Value(id),
      specialistId: Value(specialistId),
      dayOfWeek: Value(dayOfWeek),
      startTime: Value(startTime),
      endTime: Value(endTime),
      startDate: startDate == null && nullToAbsent
          ? const Value.absent()
          : Value(startDate),
      endDate: endDate == null && nullToAbsent
          ? const Value.absent()
          : Value(endDate),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SpecialistAvailabilityData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SpecialistAvailabilityData(
      id: serializer.fromJson<String>(json['id']),
      specialistId: serializer.fromJson<String>(json['specialistId']),
      dayOfWeek: serializer.fromJson<int>(json['dayOfWeek']),
      startTime: serializer.fromJson<String>(json['startTime']),
      endTime: serializer.fromJson<String>(json['endTime']),
      startDate: serializer.fromJson<DateTime?>(json['startDate']),
      endDate: serializer.fromJson<DateTime?>(json['endDate']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'specialistId': serializer.toJson<String>(specialistId),
      'dayOfWeek': serializer.toJson<int>(dayOfWeek),
      'startTime': serializer.toJson<String>(startTime),
      'endTime': serializer.toJson<String>(endTime),
      'startDate': serializer.toJson<DateTime?>(startDate),
      'endDate': serializer.toJson<DateTime?>(endDate),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SpecialistAvailabilityData copyWith({
    String? id,
    String? specialistId,
    int? dayOfWeek,
    String? startTime,
    String? endTime,
    Value<DateTime?> startDate = const Value.absent(),
    Value<DateTime?> endDate = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SpecialistAvailabilityData(
    id: id ?? this.id,
    specialistId: specialistId ?? this.specialistId,
    dayOfWeek: dayOfWeek ?? this.dayOfWeek,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    startDate: startDate.present ? startDate.value : this.startDate,
    endDate: endDate.present ? endDate.value : this.endDate,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SpecialistAvailabilityData copyWithCompanion(
    SpecialistAvailabilityCompanion data,
  ) {
    return SpecialistAvailabilityData(
      id: data.id.present ? data.id.value : this.id,
      specialistId: data.specialistId.present
          ? data.specialistId.value
          : this.specialistId,
      dayOfWeek: data.dayOfWeek.present ? data.dayOfWeek.value : this.dayOfWeek,
      startTime: data.startTime.present ? data.startTime.value : this.startTime,
      endTime: data.endTime.present ? data.endTime.value : this.endTime,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      endDate: data.endDate.present ? data.endDate.value : this.endDate,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SpecialistAvailabilityData(')
          ..write('id: $id, ')
          ..write('specialistId: $specialistId, ')
          ..write('dayOfWeek: $dayOfWeek, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    specialistId,
    dayOfWeek,
    startTime,
    endTime,
    startDate,
    endDate,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SpecialistAvailabilityData &&
          other.id == this.id &&
          other.specialistId == this.specialistId &&
          other.dayOfWeek == this.dayOfWeek &&
          other.startTime == this.startTime &&
          other.endTime == this.endTime &&
          other.startDate == this.startDate &&
          other.endDate == this.endDate &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SpecialistAvailabilityCompanion
    extends UpdateCompanion<SpecialistAvailabilityData> {
  final Value<String> id;
  final Value<String> specialistId;
  final Value<int> dayOfWeek;
  final Value<String> startTime;
  final Value<String> endTime;
  final Value<DateTime?> startDate;
  final Value<DateTime?> endDate;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SpecialistAvailabilityCompanion({
    this.id = const Value.absent(),
    this.specialistId = const Value.absent(),
    this.dayOfWeek = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.startDate = const Value.absent(),
    this.endDate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SpecialistAvailabilityCompanion.insert({
    required String id,
    required String specialistId,
    required int dayOfWeek,
    required String startTime,
    required String endTime,
    this.startDate = const Value.absent(),
    this.endDate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       specialistId = Value(specialistId),
       dayOfWeek = Value(dayOfWeek),
       startTime = Value(startTime),
       endTime = Value(endTime);
  static Insertable<SpecialistAvailabilityData> custom({
    Expression<String>? id,
    Expression<String>? specialistId,
    Expression<int>? dayOfWeek,
    Expression<String>? startTime,
    Expression<String>? endTime,
    Expression<DateTime>? startDate,
    Expression<DateTime>? endDate,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (specialistId != null) 'specialist_id': specialistId,
      if (dayOfWeek != null) 'day_of_week': dayOfWeek,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SpecialistAvailabilityCompanion copyWith({
    Value<String>? id,
    Value<String>? specialistId,
    Value<int>? dayOfWeek,
    Value<String>? startTime,
    Value<String>? endTime,
    Value<DateTime?>? startDate,
    Value<DateTime?>? endDate,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SpecialistAvailabilityCompanion(
      id: id ?? this.id,
      specialistId: specialistId ?? this.specialistId,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (specialistId.present) {
      map['specialist_id'] = Variable<String>(specialistId.value);
    }
    if (dayOfWeek.present) {
      map['day_of_week'] = Variable<int>(dayOfWeek.value);
    }
    if (startTime.present) {
      map['start_time'] = Variable<String>(startTime.value);
    }
    if (endTime.present) {
      map['end_time'] = Variable<String>(endTime.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<DateTime>(startDate.value);
    }
    if (endDate.present) {
      map['end_date'] = Variable<DateTime>(endDate.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SpecialistAvailabilityCompanion(')
          ..write('id: $id, ')
          ..write('specialistId: $specialistId, ')
          ..write('dayOfWeek: $dayOfWeek, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActivityLibraryTable extends ActivityLibrary
    with TableInfo<$ActivityLibraryTable, ActivityLibraryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActivityLibraryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _defaultDurationMinMeta =
      const VerificationMeta('defaultDurationMin');
  @override
  late final GeneratedColumn<int> defaultDurationMin = GeneratedColumn<int>(
    'default_duration_min',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _specialistIdMeta = const VerificationMeta(
    'specialistId',
  );
  @override
  late final GeneratedColumn<String> specialistId = GeneratedColumn<String>(
    'specialist_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES specialists (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _locationMeta = const VerificationMeta(
    'location',
  );
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    defaultDurationMin,
    specialistId,
    location,
    notes,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'activity_library';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActivityLibraryData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('default_duration_min')) {
      context.handle(
        _defaultDurationMinMeta,
        defaultDurationMin.isAcceptableOrUnknown(
          data['default_duration_min']!,
          _defaultDurationMinMeta,
        ),
      );
    }
    if (data.containsKey('specialist_id')) {
      context.handle(
        _specialistIdMeta,
        specialistId.isAcceptableOrUnknown(
          data['specialist_id']!,
          _specialistIdMeta,
        ),
      );
    }
    if (data.containsKey('location')) {
      context.handle(
        _locationMeta,
        location.isAcceptableOrUnknown(data['location']!, _locationMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ActivityLibraryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActivityLibraryData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      defaultDurationMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}default_duration_min'],
      ),
      specialistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}specialist_id'],
      ),
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ActivityLibraryTable createAlias(String alias) {
    return $ActivityLibraryTable(attachedDatabase, alias);
  }
}

class ActivityLibraryData extends DataClass
    implements Insertable<ActivityLibraryData> {
  final String id;
  final String title;
  final int? defaultDurationMin;
  final String? specialistId;
  final String? location;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ActivityLibraryData({
    required this.id,
    required this.title,
    this.defaultDurationMin,
    this.specialistId,
    this.location,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || defaultDurationMin != null) {
      map['default_duration_min'] = Variable<int>(defaultDurationMin);
    }
    if (!nullToAbsent || specialistId != null) {
      map['specialist_id'] = Variable<String>(specialistId);
    }
    if (!nullToAbsent || location != null) {
      map['location'] = Variable<String>(location);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ActivityLibraryCompanion toCompanion(bool nullToAbsent) {
    return ActivityLibraryCompanion(
      id: Value(id),
      title: Value(title),
      defaultDurationMin: defaultDurationMin == null && nullToAbsent
          ? const Value.absent()
          : Value(defaultDurationMin),
      specialistId: specialistId == null && nullToAbsent
          ? const Value.absent()
          : Value(specialistId),
      location: location == null && nullToAbsent
          ? const Value.absent()
          : Value(location),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ActivityLibraryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActivityLibraryData(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      defaultDurationMin: serializer.fromJson<int?>(json['defaultDurationMin']),
      specialistId: serializer.fromJson<String?>(json['specialistId']),
      location: serializer.fromJson<String?>(json['location']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'defaultDurationMin': serializer.toJson<int?>(defaultDurationMin),
      'specialistId': serializer.toJson<String?>(specialistId),
      'location': serializer.toJson<String?>(location),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ActivityLibraryData copyWith({
    String? id,
    String? title,
    Value<int?> defaultDurationMin = const Value.absent(),
    Value<String?> specialistId = const Value.absent(),
    Value<String?> location = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ActivityLibraryData(
    id: id ?? this.id,
    title: title ?? this.title,
    defaultDurationMin: defaultDurationMin.present
        ? defaultDurationMin.value
        : this.defaultDurationMin,
    specialistId: specialistId.present ? specialistId.value : this.specialistId,
    location: location.present ? location.value : this.location,
    notes: notes.present ? notes.value : this.notes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ActivityLibraryData copyWithCompanion(ActivityLibraryCompanion data) {
    return ActivityLibraryData(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      defaultDurationMin: data.defaultDurationMin.present
          ? data.defaultDurationMin.value
          : this.defaultDurationMin,
      specialistId: data.specialistId.present
          ? data.specialistId.value
          : this.specialistId,
      location: data.location.present ? data.location.value : this.location,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActivityLibraryData(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('defaultDurationMin: $defaultDurationMin, ')
          ..write('specialistId: $specialistId, ')
          ..write('location: $location, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    defaultDurationMin,
    specialistId,
    location,
    notes,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActivityLibraryData &&
          other.id == this.id &&
          other.title == this.title &&
          other.defaultDurationMin == this.defaultDurationMin &&
          other.specialistId == this.specialistId &&
          other.location == this.location &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ActivityLibraryCompanion extends UpdateCompanion<ActivityLibraryData> {
  final Value<String> id;
  final Value<String> title;
  final Value<int?> defaultDurationMin;
  final Value<String?> specialistId;
  final Value<String?> location;
  final Value<String?> notes;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ActivityLibraryCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.defaultDurationMin = const Value.absent(),
    this.specialistId = const Value.absent(),
    this.location = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActivityLibraryCompanion.insert({
    required String id,
    required String title,
    this.defaultDurationMin = const Value.absent(),
    this.specialistId = const Value.absent(),
    this.location = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title);
  static Insertable<ActivityLibraryData> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<int>? defaultDurationMin,
    Expression<String>? specialistId,
    Expression<String>? location,
    Expression<String>? notes,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (defaultDurationMin != null)
        'default_duration_min': defaultDurationMin,
      if (specialistId != null) 'specialist_id': specialistId,
      if (location != null) 'location': location,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActivityLibraryCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<int?>? defaultDurationMin,
    Value<String?>? specialistId,
    Value<String?>? location,
    Value<String?>? notes,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ActivityLibraryCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      defaultDurationMin: defaultDurationMin ?? this.defaultDurationMin,
      specialistId: specialistId ?? this.specialistId,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (defaultDurationMin.present) {
      map['default_duration_min'] = Variable<int>(defaultDurationMin.value);
    }
    if (specialistId.present) {
      map['specialist_id'] = Variable<String>(specialistId.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActivityLibraryCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('defaultDurationMin: $defaultDurationMin, ')
          ..write('specialistId: $specialistId, ')
          ..write('location: $location, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ScheduleTemplatesTable extends ScheduleTemplates
    with TableInfo<$ScheduleTemplatesTable, ScheduleTemplate> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScheduleTemplatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dayOfWeekMeta = const VerificationMeta(
    'dayOfWeek',
  );
  @override
  late final GeneratedColumn<int> dayOfWeek = GeneratedColumn<int>(
    'day_of_week',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startTimeMeta = const VerificationMeta(
    'startTime',
  );
  @override
  late final GeneratedColumn<String> startTime = GeneratedColumn<String>(
    'start_time',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endTimeMeta = const VerificationMeta(
    'endTime',
  );
  @override
  late final GeneratedColumn<String> endTime = GeneratedColumn<String>(
    'end_time',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isFullDayMeta = const VerificationMeta(
    'isFullDay',
  );
  @override
  late final GeneratedColumn<bool> isFullDay = GeneratedColumn<bool>(
    'is_full_day',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_full_day" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _podIdMeta = const VerificationMeta('podId');
  @override
  late final GeneratedColumn<String> podId = GeneratedColumn<String>(
    'pod_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES pods (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _specialistNameMeta = const VerificationMeta(
    'specialistName',
  );
  @override
  late final GeneratedColumn<String> specialistName = GeneratedColumn<String>(
    'specialist_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _specialistIdMeta = const VerificationMeta(
    'specialistId',
  );
  @override
  late final GeneratedColumn<String> specialistId = GeneratedColumn<String>(
    'specialist_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES specialists (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _locationMeta = const VerificationMeta(
    'location',
  );
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startDateMeta = const VerificationMeta(
    'startDate',
  );
  @override
  late final GeneratedColumn<DateTime> startDate = GeneratedColumn<DateTime>(
    'start_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endDateMeta = const VerificationMeta(
    'endDate',
  );
  @override
  late final GeneratedColumn<DateTime> endDate = GeneratedColumn<DateTime>(
    'end_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    dayOfWeek,
    startTime,
    endTime,
    isFullDay,
    title,
    groupId,
    podId,
    specialistName,
    specialistId,
    location,
    notes,
    startDate,
    endDate,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'schedule_templates';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScheduleTemplate> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('day_of_week')) {
      context.handle(
        _dayOfWeekMeta,
        dayOfWeek.isAcceptableOrUnknown(data['day_of_week']!, _dayOfWeekMeta),
      );
    } else if (isInserting) {
      context.missing(_dayOfWeekMeta);
    }
    if (data.containsKey('start_time')) {
      context.handle(
        _startTimeMeta,
        startTime.isAcceptableOrUnknown(data['start_time']!, _startTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_startTimeMeta);
    }
    if (data.containsKey('end_time')) {
      context.handle(
        _endTimeMeta,
        endTime.isAcceptableOrUnknown(data['end_time']!, _endTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_endTimeMeta);
    }
    if (data.containsKey('is_full_day')) {
      context.handle(
        _isFullDayMeta,
        isFullDay.isAcceptableOrUnknown(data['is_full_day']!, _isFullDayMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    }
    if (data.containsKey('pod_id')) {
      context.handle(
        _podIdMeta,
        podId.isAcceptableOrUnknown(data['pod_id']!, _podIdMeta),
      );
    }
    if (data.containsKey('specialist_name')) {
      context.handle(
        _specialistNameMeta,
        specialistName.isAcceptableOrUnknown(
          data['specialist_name']!,
          _specialistNameMeta,
        ),
      );
    }
    if (data.containsKey('specialist_id')) {
      context.handle(
        _specialistIdMeta,
        specialistId.isAcceptableOrUnknown(
          data['specialist_id']!,
          _specialistIdMeta,
        ),
      );
    }
    if (data.containsKey('location')) {
      context.handle(
        _locationMeta,
        location.isAcceptableOrUnknown(data['location']!, _locationMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('start_date')) {
      context.handle(
        _startDateMeta,
        startDate.isAcceptableOrUnknown(data['start_date']!, _startDateMeta),
      );
    }
    if (data.containsKey('end_date')) {
      context.handle(
        _endDateMeta,
        endDate.isAcceptableOrUnknown(data['end_date']!, _endDateMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ScheduleTemplate map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScheduleTemplate(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      dayOfWeek: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}day_of_week'],
      )!,
      startTime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_time'],
      )!,
      endTime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}end_time'],
      )!,
      isFullDay: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_full_day'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      ),
      podId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pod_id'],
      ),
      specialistName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}specialist_name'],
      ),
      specialistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}specialist_id'],
      ),
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      startDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_date'],
      ),
      endDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_date'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ScheduleTemplatesTable createAlias(String alias) {
    return $ScheduleTemplatesTable(attachedDatabase, alias);
  }
}

class ScheduleTemplate extends DataClass
    implements Insertable<ScheduleTemplate> {
  final String id;
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final bool isFullDay;
  final String title;
  final String? groupId;
  final String? podId;
  final String? specialistName;
  final String? specialistId;
  final String? location;
  final String? notes;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ScheduleTemplate({
    required this.id,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.isFullDay,
    required this.title,
    this.groupId,
    this.podId,
    this.specialistName,
    this.specialistId,
    this.location,
    this.notes,
    this.startDate,
    this.endDate,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['day_of_week'] = Variable<int>(dayOfWeek);
    map['start_time'] = Variable<String>(startTime);
    map['end_time'] = Variable<String>(endTime);
    map['is_full_day'] = Variable<bool>(isFullDay);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || groupId != null) {
      map['group_id'] = Variable<String>(groupId);
    }
    if (!nullToAbsent || podId != null) {
      map['pod_id'] = Variable<String>(podId);
    }
    if (!nullToAbsent || specialistName != null) {
      map['specialist_name'] = Variable<String>(specialistName);
    }
    if (!nullToAbsent || specialistId != null) {
      map['specialist_id'] = Variable<String>(specialistId);
    }
    if (!nullToAbsent || location != null) {
      map['location'] = Variable<String>(location);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || startDate != null) {
      map['start_date'] = Variable<DateTime>(startDate);
    }
    if (!nullToAbsent || endDate != null) {
      map['end_date'] = Variable<DateTime>(endDate);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ScheduleTemplatesCompanion toCompanion(bool nullToAbsent) {
    return ScheduleTemplatesCompanion(
      id: Value(id),
      dayOfWeek: Value(dayOfWeek),
      startTime: Value(startTime),
      endTime: Value(endTime),
      isFullDay: Value(isFullDay),
      title: Value(title),
      groupId: groupId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupId),
      podId: podId == null && nullToAbsent
          ? const Value.absent()
          : Value(podId),
      specialistName: specialistName == null && nullToAbsent
          ? const Value.absent()
          : Value(specialistName),
      specialistId: specialistId == null && nullToAbsent
          ? const Value.absent()
          : Value(specialistId),
      location: location == null && nullToAbsent
          ? const Value.absent()
          : Value(location),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      startDate: startDate == null && nullToAbsent
          ? const Value.absent()
          : Value(startDate),
      endDate: endDate == null && nullToAbsent
          ? const Value.absent()
          : Value(endDate),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ScheduleTemplate.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScheduleTemplate(
      id: serializer.fromJson<String>(json['id']),
      dayOfWeek: serializer.fromJson<int>(json['dayOfWeek']),
      startTime: serializer.fromJson<String>(json['startTime']),
      endTime: serializer.fromJson<String>(json['endTime']),
      isFullDay: serializer.fromJson<bool>(json['isFullDay']),
      title: serializer.fromJson<String>(json['title']),
      groupId: serializer.fromJson<String?>(json['groupId']),
      podId: serializer.fromJson<String?>(json['podId']),
      specialistName: serializer.fromJson<String?>(json['specialistName']),
      specialistId: serializer.fromJson<String?>(json['specialistId']),
      location: serializer.fromJson<String?>(json['location']),
      notes: serializer.fromJson<String?>(json['notes']),
      startDate: serializer.fromJson<DateTime?>(json['startDate']),
      endDate: serializer.fromJson<DateTime?>(json['endDate']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'dayOfWeek': serializer.toJson<int>(dayOfWeek),
      'startTime': serializer.toJson<String>(startTime),
      'endTime': serializer.toJson<String>(endTime),
      'isFullDay': serializer.toJson<bool>(isFullDay),
      'title': serializer.toJson<String>(title),
      'groupId': serializer.toJson<String?>(groupId),
      'podId': serializer.toJson<String?>(podId),
      'specialistName': serializer.toJson<String?>(specialistName),
      'specialistId': serializer.toJson<String?>(specialistId),
      'location': serializer.toJson<String?>(location),
      'notes': serializer.toJson<String?>(notes),
      'startDate': serializer.toJson<DateTime?>(startDate),
      'endDate': serializer.toJson<DateTime?>(endDate),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ScheduleTemplate copyWith({
    String? id,
    int? dayOfWeek,
    String? startTime,
    String? endTime,
    bool? isFullDay,
    String? title,
    Value<String?> groupId = const Value.absent(),
    Value<String?> podId = const Value.absent(),
    Value<String?> specialistName = const Value.absent(),
    Value<String?> specialistId = const Value.absent(),
    Value<String?> location = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<DateTime?> startDate = const Value.absent(),
    Value<DateTime?> endDate = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ScheduleTemplate(
    id: id ?? this.id,
    dayOfWeek: dayOfWeek ?? this.dayOfWeek,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    isFullDay: isFullDay ?? this.isFullDay,
    title: title ?? this.title,
    groupId: groupId.present ? groupId.value : this.groupId,
    podId: podId.present ? podId.value : this.podId,
    specialistName: specialistName.present
        ? specialistName.value
        : this.specialistName,
    specialistId: specialistId.present ? specialistId.value : this.specialistId,
    location: location.present ? location.value : this.location,
    notes: notes.present ? notes.value : this.notes,
    startDate: startDate.present ? startDate.value : this.startDate,
    endDate: endDate.present ? endDate.value : this.endDate,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ScheduleTemplate copyWithCompanion(ScheduleTemplatesCompanion data) {
    return ScheduleTemplate(
      id: data.id.present ? data.id.value : this.id,
      dayOfWeek: data.dayOfWeek.present ? data.dayOfWeek.value : this.dayOfWeek,
      startTime: data.startTime.present ? data.startTime.value : this.startTime,
      endTime: data.endTime.present ? data.endTime.value : this.endTime,
      isFullDay: data.isFullDay.present ? data.isFullDay.value : this.isFullDay,
      title: data.title.present ? data.title.value : this.title,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      podId: data.podId.present ? data.podId.value : this.podId,
      specialistName: data.specialistName.present
          ? data.specialistName.value
          : this.specialistName,
      specialistId: data.specialistId.present
          ? data.specialistId.value
          : this.specialistId,
      location: data.location.present ? data.location.value : this.location,
      notes: data.notes.present ? data.notes.value : this.notes,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      endDate: data.endDate.present ? data.endDate.value : this.endDate,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScheduleTemplate(')
          ..write('id: $id, ')
          ..write('dayOfWeek: $dayOfWeek, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('isFullDay: $isFullDay, ')
          ..write('title: $title, ')
          ..write('groupId: $groupId, ')
          ..write('podId: $podId, ')
          ..write('specialistName: $specialistName, ')
          ..write('specialistId: $specialistId, ')
          ..write('location: $location, ')
          ..write('notes: $notes, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    dayOfWeek,
    startTime,
    endTime,
    isFullDay,
    title,
    groupId,
    podId,
    specialistName,
    specialistId,
    location,
    notes,
    startDate,
    endDate,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleTemplate &&
          other.id == this.id &&
          other.dayOfWeek == this.dayOfWeek &&
          other.startTime == this.startTime &&
          other.endTime == this.endTime &&
          other.isFullDay == this.isFullDay &&
          other.title == this.title &&
          other.groupId == this.groupId &&
          other.podId == this.podId &&
          other.specialistName == this.specialistName &&
          other.specialistId == this.specialistId &&
          other.location == this.location &&
          other.notes == this.notes &&
          other.startDate == this.startDate &&
          other.endDate == this.endDate &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ScheduleTemplatesCompanion extends UpdateCompanion<ScheduleTemplate> {
  final Value<String> id;
  final Value<int> dayOfWeek;
  final Value<String> startTime;
  final Value<String> endTime;
  final Value<bool> isFullDay;
  final Value<String> title;
  final Value<String?> groupId;
  final Value<String?> podId;
  final Value<String?> specialistName;
  final Value<String?> specialistId;
  final Value<String?> location;
  final Value<String?> notes;
  final Value<DateTime?> startDate;
  final Value<DateTime?> endDate;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ScheduleTemplatesCompanion({
    this.id = const Value.absent(),
    this.dayOfWeek = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.isFullDay = const Value.absent(),
    this.title = const Value.absent(),
    this.groupId = const Value.absent(),
    this.podId = const Value.absent(),
    this.specialistName = const Value.absent(),
    this.specialistId = const Value.absent(),
    this.location = const Value.absent(),
    this.notes = const Value.absent(),
    this.startDate = const Value.absent(),
    this.endDate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ScheduleTemplatesCompanion.insert({
    required String id,
    required int dayOfWeek,
    required String startTime,
    required String endTime,
    this.isFullDay = const Value.absent(),
    required String title,
    this.groupId = const Value.absent(),
    this.podId = const Value.absent(),
    this.specialistName = const Value.absent(),
    this.specialistId = const Value.absent(),
    this.location = const Value.absent(),
    this.notes = const Value.absent(),
    this.startDate = const Value.absent(),
    this.endDate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       dayOfWeek = Value(dayOfWeek),
       startTime = Value(startTime),
       endTime = Value(endTime),
       title = Value(title);
  static Insertable<ScheduleTemplate> custom({
    Expression<String>? id,
    Expression<int>? dayOfWeek,
    Expression<String>? startTime,
    Expression<String>? endTime,
    Expression<bool>? isFullDay,
    Expression<String>? title,
    Expression<String>? groupId,
    Expression<String>? podId,
    Expression<String>? specialistName,
    Expression<String>? specialistId,
    Expression<String>? location,
    Expression<String>? notes,
    Expression<DateTime>? startDate,
    Expression<DateTime>? endDate,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (dayOfWeek != null) 'day_of_week': dayOfWeek,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
      if (isFullDay != null) 'is_full_day': isFullDay,
      if (title != null) 'title': title,
      if (groupId != null) 'group_id': groupId,
      if (podId != null) 'pod_id': podId,
      if (specialistName != null) 'specialist_name': specialistName,
      if (specialistId != null) 'specialist_id': specialistId,
      if (location != null) 'location': location,
      if (notes != null) 'notes': notes,
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ScheduleTemplatesCompanion copyWith({
    Value<String>? id,
    Value<int>? dayOfWeek,
    Value<String>? startTime,
    Value<String>? endTime,
    Value<bool>? isFullDay,
    Value<String>? title,
    Value<String?>? groupId,
    Value<String?>? podId,
    Value<String?>? specialistName,
    Value<String?>? specialistId,
    Value<String?>? location,
    Value<String?>? notes,
    Value<DateTime?>? startDate,
    Value<DateTime?>? endDate,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ScheduleTemplatesCompanion(
      id: id ?? this.id,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isFullDay: isFullDay ?? this.isFullDay,
      title: title ?? this.title,
      groupId: groupId ?? this.groupId,
      podId: podId ?? this.podId,
      specialistName: specialistName ?? this.specialistName,
      specialistId: specialistId ?? this.specialistId,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (dayOfWeek.present) {
      map['day_of_week'] = Variable<int>(dayOfWeek.value);
    }
    if (startTime.present) {
      map['start_time'] = Variable<String>(startTime.value);
    }
    if (endTime.present) {
      map['end_time'] = Variable<String>(endTime.value);
    }
    if (isFullDay.present) {
      map['is_full_day'] = Variable<bool>(isFullDay.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (podId.present) {
      map['pod_id'] = Variable<String>(podId.value);
    }
    if (specialistName.present) {
      map['specialist_name'] = Variable<String>(specialistName.value);
    }
    if (specialistId.present) {
      map['specialist_id'] = Variable<String>(specialistId.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<DateTime>(startDate.value);
    }
    if (endDate.present) {
      map['end_date'] = Variable<DateTime>(endDate.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScheduleTemplatesCompanion(')
          ..write('id: $id, ')
          ..write('dayOfWeek: $dayOfWeek, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('isFullDay: $isFullDay, ')
          ..write('title: $title, ')
          ..write('groupId: $groupId, ')
          ..write('podId: $podId, ')
          ..write('specialistName: $specialistName, ')
          ..write('specialistId: $specialistId, ')
          ..write('location: $location, ')
          ..write('notes: $notes, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ScheduleEntriesTable extends ScheduleEntries
    with TableInfo<$ScheduleEntriesTable, ScheduleEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScheduleEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endDateMeta = const VerificationMeta(
    'endDate',
  );
  @override
  late final GeneratedColumn<DateTime> endDate = GeneratedColumn<DateTime>(
    'end_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startTimeMeta = const VerificationMeta(
    'startTime',
  );
  @override
  late final GeneratedColumn<String> startTime = GeneratedColumn<String>(
    'start_time',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endTimeMeta = const VerificationMeta(
    'endTime',
  );
  @override
  late final GeneratedColumn<String> endTime = GeneratedColumn<String>(
    'end_time',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isFullDayMeta = const VerificationMeta(
    'isFullDay',
  );
  @override
  late final GeneratedColumn<bool> isFullDay = GeneratedColumn<bool>(
    'is_full_day',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_full_day" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _podIdMeta = const VerificationMeta('podId');
  @override
  late final GeneratedColumn<String> podId = GeneratedColumn<String>(
    'pod_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES pods (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _specialistNameMeta = const VerificationMeta(
    'specialistName',
  );
  @override
  late final GeneratedColumn<String> specialistName = GeneratedColumn<String>(
    'specialist_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _specialistIdMeta = const VerificationMeta(
    'specialistId',
  );
  @override
  late final GeneratedColumn<String> specialistId = GeneratedColumn<String>(
    'specialist_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES specialists (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _locationMeta = const VerificationMeta(
    'location',
  );
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceTripIdMeta = const VerificationMeta(
    'sourceTripId',
  );
  @override
  late final GeneratedColumn<String> sourceTripId = GeneratedColumn<String>(
    'source_trip_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES trips (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _overridesTemplateIdMeta =
      const VerificationMeta('overridesTemplateId');
  @override
  late final GeneratedColumn<String> overridesTemplateId =
      GeneratedColumn<String>(
        'overrides_template_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES schedule_templates (id) ON DELETE SET NULL',
        ),
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    date,
    endDate,
    startTime,
    endTime,
    isFullDay,
    title,
    podId,
    specialistName,
    specialistId,
    location,
    notes,
    kind,
    sourceTripId,
    overridesTemplateId,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'schedule_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScheduleEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('end_date')) {
      context.handle(
        _endDateMeta,
        endDate.isAcceptableOrUnknown(data['end_date']!, _endDateMeta),
      );
    }
    if (data.containsKey('start_time')) {
      context.handle(
        _startTimeMeta,
        startTime.isAcceptableOrUnknown(data['start_time']!, _startTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_startTimeMeta);
    }
    if (data.containsKey('end_time')) {
      context.handle(
        _endTimeMeta,
        endTime.isAcceptableOrUnknown(data['end_time']!, _endTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_endTimeMeta);
    }
    if (data.containsKey('is_full_day')) {
      context.handle(
        _isFullDayMeta,
        isFullDay.isAcceptableOrUnknown(data['is_full_day']!, _isFullDayMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('pod_id')) {
      context.handle(
        _podIdMeta,
        podId.isAcceptableOrUnknown(data['pod_id']!, _podIdMeta),
      );
    }
    if (data.containsKey('specialist_name')) {
      context.handle(
        _specialistNameMeta,
        specialistName.isAcceptableOrUnknown(
          data['specialist_name']!,
          _specialistNameMeta,
        ),
      );
    }
    if (data.containsKey('specialist_id')) {
      context.handle(
        _specialistIdMeta,
        specialistId.isAcceptableOrUnknown(
          data['specialist_id']!,
          _specialistIdMeta,
        ),
      );
    }
    if (data.containsKey('location')) {
      context.handle(
        _locationMeta,
        location.isAcceptableOrUnknown(data['location']!, _locationMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('source_trip_id')) {
      context.handle(
        _sourceTripIdMeta,
        sourceTripId.isAcceptableOrUnknown(
          data['source_trip_id']!,
          _sourceTripIdMeta,
        ),
      );
    }
    if (data.containsKey('overrides_template_id')) {
      context.handle(
        _overridesTemplateIdMeta,
        overridesTemplateId.isAcceptableOrUnknown(
          data['overrides_template_id']!,
          _overridesTemplateIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ScheduleEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScheduleEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      endDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_date'],
      ),
      startTime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_time'],
      )!,
      endTime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}end_time'],
      )!,
      isFullDay: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_full_day'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      podId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pod_id'],
      ),
      specialistName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}specialist_name'],
      ),
      specialistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}specialist_id'],
      ),
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      sourceTripId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_trip_id'],
      ),
      overridesTemplateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}overrides_template_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ScheduleEntriesTable createAlias(String alias) {
    return $ScheduleEntriesTable(attachedDatabase, alias);
  }
}

class ScheduleEntry extends DataClass implements Insertable<ScheduleEntry> {
  final String id;
  final DateTime date;
  final DateTime? endDate;
  final String startTime;
  final String endTime;
  final bool isFullDay;
  final String title;
  final String? podId;
  final String? specialistName;
  final String? specialistId;
  final String? location;
  final String? notes;
  final String kind;
  final String? sourceTripId;
  final String? overridesTemplateId;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ScheduleEntry({
    required this.id,
    required this.date,
    this.endDate,
    required this.startTime,
    required this.endTime,
    required this.isFullDay,
    required this.title,
    this.podId,
    this.specialistName,
    this.specialistId,
    this.location,
    this.notes,
    required this.kind,
    this.sourceTripId,
    this.overridesTemplateId,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['date'] = Variable<DateTime>(date);
    if (!nullToAbsent || endDate != null) {
      map['end_date'] = Variable<DateTime>(endDate);
    }
    map['start_time'] = Variable<String>(startTime);
    map['end_time'] = Variable<String>(endTime);
    map['is_full_day'] = Variable<bool>(isFullDay);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || podId != null) {
      map['pod_id'] = Variable<String>(podId);
    }
    if (!nullToAbsent || specialistName != null) {
      map['specialist_name'] = Variable<String>(specialistName);
    }
    if (!nullToAbsent || specialistId != null) {
      map['specialist_id'] = Variable<String>(specialistId);
    }
    if (!nullToAbsent || location != null) {
      map['location'] = Variable<String>(location);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || sourceTripId != null) {
      map['source_trip_id'] = Variable<String>(sourceTripId);
    }
    if (!nullToAbsent || overridesTemplateId != null) {
      map['overrides_template_id'] = Variable<String>(overridesTemplateId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ScheduleEntriesCompanion toCompanion(bool nullToAbsent) {
    return ScheduleEntriesCompanion(
      id: Value(id),
      date: Value(date),
      endDate: endDate == null && nullToAbsent
          ? const Value.absent()
          : Value(endDate),
      startTime: Value(startTime),
      endTime: Value(endTime),
      isFullDay: Value(isFullDay),
      title: Value(title),
      podId: podId == null && nullToAbsent
          ? const Value.absent()
          : Value(podId),
      specialistName: specialistName == null && nullToAbsent
          ? const Value.absent()
          : Value(specialistName),
      specialistId: specialistId == null && nullToAbsent
          ? const Value.absent()
          : Value(specialistId),
      location: location == null && nullToAbsent
          ? const Value.absent()
          : Value(location),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      kind: Value(kind),
      sourceTripId: sourceTripId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceTripId),
      overridesTemplateId: overridesTemplateId == null && nullToAbsent
          ? const Value.absent()
          : Value(overridesTemplateId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ScheduleEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScheduleEntry(
      id: serializer.fromJson<String>(json['id']),
      date: serializer.fromJson<DateTime>(json['date']),
      endDate: serializer.fromJson<DateTime?>(json['endDate']),
      startTime: serializer.fromJson<String>(json['startTime']),
      endTime: serializer.fromJson<String>(json['endTime']),
      isFullDay: serializer.fromJson<bool>(json['isFullDay']),
      title: serializer.fromJson<String>(json['title']),
      podId: serializer.fromJson<String?>(json['podId']),
      specialistName: serializer.fromJson<String?>(json['specialistName']),
      specialistId: serializer.fromJson<String?>(json['specialistId']),
      location: serializer.fromJson<String?>(json['location']),
      notes: serializer.fromJson<String?>(json['notes']),
      kind: serializer.fromJson<String>(json['kind']),
      sourceTripId: serializer.fromJson<String?>(json['sourceTripId']),
      overridesTemplateId: serializer.fromJson<String?>(
        json['overridesTemplateId'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'date': serializer.toJson<DateTime>(date),
      'endDate': serializer.toJson<DateTime?>(endDate),
      'startTime': serializer.toJson<String>(startTime),
      'endTime': serializer.toJson<String>(endTime),
      'isFullDay': serializer.toJson<bool>(isFullDay),
      'title': serializer.toJson<String>(title),
      'podId': serializer.toJson<String?>(podId),
      'specialistName': serializer.toJson<String?>(specialistName),
      'specialistId': serializer.toJson<String?>(specialistId),
      'location': serializer.toJson<String?>(location),
      'notes': serializer.toJson<String?>(notes),
      'kind': serializer.toJson<String>(kind),
      'sourceTripId': serializer.toJson<String?>(sourceTripId),
      'overridesTemplateId': serializer.toJson<String?>(overridesTemplateId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ScheduleEntry copyWith({
    String? id,
    DateTime? date,
    Value<DateTime?> endDate = const Value.absent(),
    String? startTime,
    String? endTime,
    bool? isFullDay,
    String? title,
    Value<String?> podId = const Value.absent(),
    Value<String?> specialistName = const Value.absent(),
    Value<String?> specialistId = const Value.absent(),
    Value<String?> location = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    String? kind,
    Value<String?> sourceTripId = const Value.absent(),
    Value<String?> overridesTemplateId = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ScheduleEntry(
    id: id ?? this.id,
    date: date ?? this.date,
    endDate: endDate.present ? endDate.value : this.endDate,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    isFullDay: isFullDay ?? this.isFullDay,
    title: title ?? this.title,
    podId: podId.present ? podId.value : this.podId,
    specialistName: specialistName.present
        ? specialistName.value
        : this.specialistName,
    specialistId: specialistId.present ? specialistId.value : this.specialistId,
    location: location.present ? location.value : this.location,
    notes: notes.present ? notes.value : this.notes,
    kind: kind ?? this.kind,
    sourceTripId: sourceTripId.present ? sourceTripId.value : this.sourceTripId,
    overridesTemplateId: overridesTemplateId.present
        ? overridesTemplateId.value
        : this.overridesTemplateId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ScheduleEntry copyWithCompanion(ScheduleEntriesCompanion data) {
    return ScheduleEntry(
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      endDate: data.endDate.present ? data.endDate.value : this.endDate,
      startTime: data.startTime.present ? data.startTime.value : this.startTime,
      endTime: data.endTime.present ? data.endTime.value : this.endTime,
      isFullDay: data.isFullDay.present ? data.isFullDay.value : this.isFullDay,
      title: data.title.present ? data.title.value : this.title,
      podId: data.podId.present ? data.podId.value : this.podId,
      specialistName: data.specialistName.present
          ? data.specialistName.value
          : this.specialistName,
      specialistId: data.specialistId.present
          ? data.specialistId.value
          : this.specialistId,
      location: data.location.present ? data.location.value : this.location,
      notes: data.notes.present ? data.notes.value : this.notes,
      kind: data.kind.present ? data.kind.value : this.kind,
      sourceTripId: data.sourceTripId.present
          ? data.sourceTripId.value
          : this.sourceTripId,
      overridesTemplateId: data.overridesTemplateId.present
          ? data.overridesTemplateId.value
          : this.overridesTemplateId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScheduleEntry(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('endDate: $endDate, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('isFullDay: $isFullDay, ')
          ..write('title: $title, ')
          ..write('podId: $podId, ')
          ..write('specialistName: $specialistName, ')
          ..write('specialistId: $specialistId, ')
          ..write('location: $location, ')
          ..write('notes: $notes, ')
          ..write('kind: $kind, ')
          ..write('sourceTripId: $sourceTripId, ')
          ..write('overridesTemplateId: $overridesTemplateId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    date,
    endDate,
    startTime,
    endTime,
    isFullDay,
    title,
    podId,
    specialistName,
    specialistId,
    location,
    notes,
    kind,
    sourceTripId,
    overridesTemplateId,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleEntry &&
          other.id == this.id &&
          other.date == this.date &&
          other.endDate == this.endDate &&
          other.startTime == this.startTime &&
          other.endTime == this.endTime &&
          other.isFullDay == this.isFullDay &&
          other.title == this.title &&
          other.podId == this.podId &&
          other.specialistName == this.specialistName &&
          other.specialistId == this.specialistId &&
          other.location == this.location &&
          other.notes == this.notes &&
          other.kind == this.kind &&
          other.sourceTripId == this.sourceTripId &&
          other.overridesTemplateId == this.overridesTemplateId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ScheduleEntriesCompanion extends UpdateCompanion<ScheduleEntry> {
  final Value<String> id;
  final Value<DateTime> date;
  final Value<DateTime?> endDate;
  final Value<String> startTime;
  final Value<String> endTime;
  final Value<bool> isFullDay;
  final Value<String> title;
  final Value<String?> podId;
  final Value<String?> specialistName;
  final Value<String?> specialistId;
  final Value<String?> location;
  final Value<String?> notes;
  final Value<String> kind;
  final Value<String?> sourceTripId;
  final Value<String?> overridesTemplateId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ScheduleEntriesCompanion({
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.endDate = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.isFullDay = const Value.absent(),
    this.title = const Value.absent(),
    this.podId = const Value.absent(),
    this.specialistName = const Value.absent(),
    this.specialistId = const Value.absent(),
    this.location = const Value.absent(),
    this.notes = const Value.absent(),
    this.kind = const Value.absent(),
    this.sourceTripId = const Value.absent(),
    this.overridesTemplateId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ScheduleEntriesCompanion.insert({
    required String id,
    required DateTime date,
    this.endDate = const Value.absent(),
    required String startTime,
    required String endTime,
    this.isFullDay = const Value.absent(),
    required String title,
    this.podId = const Value.absent(),
    this.specialistName = const Value.absent(),
    this.specialistId = const Value.absent(),
    this.location = const Value.absent(),
    this.notes = const Value.absent(),
    required String kind,
    this.sourceTripId = const Value.absent(),
    this.overridesTemplateId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       date = Value(date),
       startTime = Value(startTime),
       endTime = Value(endTime),
       title = Value(title),
       kind = Value(kind);
  static Insertable<ScheduleEntry> custom({
    Expression<String>? id,
    Expression<DateTime>? date,
    Expression<DateTime>? endDate,
    Expression<String>? startTime,
    Expression<String>? endTime,
    Expression<bool>? isFullDay,
    Expression<String>? title,
    Expression<String>? podId,
    Expression<String>? specialistName,
    Expression<String>? specialistId,
    Expression<String>? location,
    Expression<String>? notes,
    Expression<String>? kind,
    Expression<String>? sourceTripId,
    Expression<String>? overridesTemplateId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (endDate != null) 'end_date': endDate,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
      if (isFullDay != null) 'is_full_day': isFullDay,
      if (title != null) 'title': title,
      if (podId != null) 'pod_id': podId,
      if (specialistName != null) 'specialist_name': specialistName,
      if (specialistId != null) 'specialist_id': specialistId,
      if (location != null) 'location': location,
      if (notes != null) 'notes': notes,
      if (kind != null) 'kind': kind,
      if (sourceTripId != null) 'source_trip_id': sourceTripId,
      if (overridesTemplateId != null)
        'overrides_template_id': overridesTemplateId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ScheduleEntriesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? date,
    Value<DateTime?>? endDate,
    Value<String>? startTime,
    Value<String>? endTime,
    Value<bool>? isFullDay,
    Value<String>? title,
    Value<String?>? podId,
    Value<String?>? specialistName,
    Value<String?>? specialistId,
    Value<String?>? location,
    Value<String?>? notes,
    Value<String>? kind,
    Value<String?>? sourceTripId,
    Value<String?>? overridesTemplateId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ScheduleEntriesCompanion(
      id: id ?? this.id,
      date: date ?? this.date,
      endDate: endDate ?? this.endDate,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isFullDay: isFullDay ?? this.isFullDay,
      title: title ?? this.title,
      podId: podId ?? this.podId,
      specialistName: specialistName ?? this.specialistName,
      specialistId: specialistId ?? this.specialistId,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      kind: kind ?? this.kind,
      sourceTripId: sourceTripId ?? this.sourceTripId,
      overridesTemplateId: overridesTemplateId ?? this.overridesTemplateId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (endDate.present) {
      map['end_date'] = Variable<DateTime>(endDate.value);
    }
    if (startTime.present) {
      map['start_time'] = Variable<String>(startTime.value);
    }
    if (endTime.present) {
      map['end_time'] = Variable<String>(endTime.value);
    }
    if (isFullDay.present) {
      map['is_full_day'] = Variable<bool>(isFullDay.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (podId.present) {
      map['pod_id'] = Variable<String>(podId.value);
    }
    if (specialistName.present) {
      map['specialist_name'] = Variable<String>(specialistName.value);
    }
    if (specialistId.present) {
      map['specialist_id'] = Variable<String>(specialistId.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (sourceTripId.present) {
      map['source_trip_id'] = Variable<String>(sourceTripId.value);
    }
    if (overridesTemplateId.present) {
      map['overrides_template_id'] = Variable<String>(
        overridesTemplateId.value,
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScheduleEntriesCompanion(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('endDate: $endDate, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('isFullDay: $isFullDay, ')
          ..write('title: $title, ')
          ..write('podId: $podId, ')
          ..write('specialistName: $specialistName, ')
          ..write('specialistId: $specialistId, ')
          ..write('location: $location, ')
          ..write('notes: $notes, ')
          ..write('kind: $kind, ')
          ..write('sourceTripId: $sourceTripId, ')
          ..write('overridesTemplateId: $overridesTemplateId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TemplatePodsTable extends TemplatePods
    with TableInfo<$TemplatePodsTable, TemplatePod> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TemplatePodsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _templateIdMeta = const VerificationMeta(
    'templateId',
  );
  @override
  late final GeneratedColumn<String> templateId = GeneratedColumn<String>(
    'template_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES schedule_templates (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _podIdMeta = const VerificationMeta('podId');
  @override
  late final GeneratedColumn<String> podId = GeneratedColumn<String>(
    'pod_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES pods (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [templateId, podId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'template_pods';
  @override
  VerificationContext validateIntegrity(
    Insertable<TemplatePod> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('template_id')) {
      context.handle(
        _templateIdMeta,
        templateId.isAcceptableOrUnknown(data['template_id']!, _templateIdMeta),
      );
    } else if (isInserting) {
      context.missing(_templateIdMeta);
    }
    if (data.containsKey('pod_id')) {
      context.handle(
        _podIdMeta,
        podId.isAcceptableOrUnknown(data['pod_id']!, _podIdMeta),
      );
    } else if (isInserting) {
      context.missing(_podIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {templateId, podId};
  @override
  TemplatePod map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TemplatePod(
      templateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}template_id'],
      )!,
      podId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pod_id'],
      )!,
    );
  }

  @override
  $TemplatePodsTable createAlias(String alias) {
    return $TemplatePodsTable(attachedDatabase, alias);
  }
}

class TemplatePod extends DataClass implements Insertable<TemplatePod> {
  final String templateId;
  final String podId;
  const TemplatePod({required this.templateId, required this.podId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['template_id'] = Variable<String>(templateId);
    map['pod_id'] = Variable<String>(podId);
    return map;
  }

  TemplatePodsCompanion toCompanion(bool nullToAbsent) {
    return TemplatePodsCompanion(
      templateId: Value(templateId),
      podId: Value(podId),
    );
  }

  factory TemplatePod.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TemplatePod(
      templateId: serializer.fromJson<String>(json['templateId']),
      podId: serializer.fromJson<String>(json['podId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'templateId': serializer.toJson<String>(templateId),
      'podId': serializer.toJson<String>(podId),
    };
  }

  TemplatePod copyWith({String? templateId, String? podId}) => TemplatePod(
    templateId: templateId ?? this.templateId,
    podId: podId ?? this.podId,
  );
  TemplatePod copyWithCompanion(TemplatePodsCompanion data) {
    return TemplatePod(
      templateId: data.templateId.present
          ? data.templateId.value
          : this.templateId,
      podId: data.podId.present ? data.podId.value : this.podId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TemplatePod(')
          ..write('templateId: $templateId, ')
          ..write('podId: $podId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(templateId, podId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TemplatePod &&
          other.templateId == this.templateId &&
          other.podId == this.podId);
}

class TemplatePodsCompanion extends UpdateCompanion<TemplatePod> {
  final Value<String> templateId;
  final Value<String> podId;
  final Value<int> rowid;
  const TemplatePodsCompanion({
    this.templateId = const Value.absent(),
    this.podId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TemplatePodsCompanion.insert({
    required String templateId,
    required String podId,
    this.rowid = const Value.absent(),
  }) : templateId = Value(templateId),
       podId = Value(podId);
  static Insertable<TemplatePod> custom({
    Expression<String>? templateId,
    Expression<String>? podId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (templateId != null) 'template_id': templateId,
      if (podId != null) 'pod_id': podId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TemplatePodsCompanion copyWith({
    Value<String>? templateId,
    Value<String>? podId,
    Value<int>? rowid,
  }) {
    return TemplatePodsCompanion(
      templateId: templateId ?? this.templateId,
      podId: podId ?? this.podId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (templateId.present) {
      map['template_id'] = Variable<String>(templateId.value);
    }
    if (podId.present) {
      map['pod_id'] = Variable<String>(podId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TemplatePodsCompanion(')
          ..write('templateId: $templateId, ')
          ..write('podId: $podId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EntryPodsTable extends EntryPods
    with TableInfo<$EntryPodsTable, EntryPod> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EntryPodsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<String> entryId = GeneratedColumn<String>(
    'entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES schedule_entries (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _podIdMeta = const VerificationMeta('podId');
  @override
  late final GeneratedColumn<String> podId = GeneratedColumn<String>(
    'pod_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES pods (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [entryId, podId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'entry_pods';
  @override
  VerificationContext validateIntegrity(
    Insertable<EntryPod> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('pod_id')) {
      context.handle(
        _podIdMeta,
        podId.isAcceptableOrUnknown(data['pod_id']!, _podIdMeta),
      );
    } else if (isInserting) {
      context.missing(_podIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entryId, podId};
  @override
  EntryPod map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EntryPod(
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_id'],
      )!,
      podId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pod_id'],
      )!,
    );
  }

  @override
  $EntryPodsTable createAlias(String alias) {
    return $EntryPodsTable(attachedDatabase, alias);
  }
}

class EntryPod extends DataClass implements Insertable<EntryPod> {
  final String entryId;
  final String podId;
  const EntryPod({required this.entryId, required this.podId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entry_id'] = Variable<String>(entryId);
    map['pod_id'] = Variable<String>(podId);
    return map;
  }

  EntryPodsCompanion toCompanion(bool nullToAbsent) {
    return EntryPodsCompanion(entryId: Value(entryId), podId: Value(podId));
  }

  factory EntryPod.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EntryPod(
      entryId: serializer.fromJson<String>(json['entryId']),
      podId: serializer.fromJson<String>(json['podId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entryId': serializer.toJson<String>(entryId),
      'podId': serializer.toJson<String>(podId),
    };
  }

  EntryPod copyWith({String? entryId, String? podId}) =>
      EntryPod(entryId: entryId ?? this.entryId, podId: podId ?? this.podId);
  EntryPod copyWithCompanion(EntryPodsCompanion data) {
    return EntryPod(
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      podId: data.podId.present ? data.podId.value : this.podId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EntryPod(')
          ..write('entryId: $entryId, ')
          ..write('podId: $podId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(entryId, podId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EntryPod &&
          other.entryId == this.entryId &&
          other.podId == this.podId);
}

class EntryPodsCompanion extends UpdateCompanion<EntryPod> {
  final Value<String> entryId;
  final Value<String> podId;
  final Value<int> rowid;
  const EntryPodsCompanion({
    this.entryId = const Value.absent(),
    this.podId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EntryPodsCompanion.insert({
    required String entryId,
    required String podId,
    this.rowid = const Value.absent(),
  }) : entryId = Value(entryId),
       podId = Value(podId);
  static Insertable<EntryPod> custom({
    Expression<String>? entryId,
    Expression<String>? podId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entryId != null) 'entry_id': entryId,
      if (podId != null) 'pod_id': podId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EntryPodsCompanion copyWith({
    Value<String>? entryId,
    Value<String>? podId,
    Value<int>? rowid,
  }) {
    return EntryPodsCompanion(
      entryId: entryId ?? this.entryId,
      podId: podId ?? this.podId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entryId.present) {
      map['entry_id'] = Variable<String>(entryId.value);
    }
    if (podId.present) {
      map['pod_id'] = Variable<String>(podId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EntryPodsCompanion(')
          ..write('entryId: $entryId, ')
          ..write('podId: $podId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ParentConcernNotesTable extends ParentConcernNotes
    with TableInfo<$ParentConcernNotesTable, ParentConcernNote> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ParentConcernNotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _childNamesMeta = const VerificationMeta(
    'childNames',
  );
  @override
  late final GeneratedColumn<String> childNames = GeneratedColumn<String>(
    'child_names',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _parentNameMeta = const VerificationMeta(
    'parentName',
  );
  @override
  late final GeneratedColumn<String> parentName = GeneratedColumn<String>(
    'parent_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _concernDateMeta = const VerificationMeta(
    'concernDate',
  );
  @override
  late final GeneratedColumn<DateTime> concernDate = GeneratedColumn<DateTime>(
    'concern_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _staffReceivingMeta = const VerificationMeta(
    'staffReceiving',
  );
  @override
  late final GeneratedColumn<String> staffReceiving = GeneratedColumn<String>(
    'staff_receiving',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _supervisorNotifiedMeta =
      const VerificationMeta('supervisorNotified');
  @override
  late final GeneratedColumn<String> supervisorNotified =
      GeneratedColumn<String>(
        'supervisor_notified',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _methodInPersonMeta = const VerificationMeta(
    'methodInPerson',
  );
  @override
  late final GeneratedColumn<bool> methodInPerson = GeneratedColumn<bool>(
    'method_in_person',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("method_in_person" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _methodPhoneMeta = const VerificationMeta(
    'methodPhone',
  );
  @override
  late final GeneratedColumn<bool> methodPhone = GeneratedColumn<bool>(
    'method_phone',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("method_phone" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _methodEmailMeta = const VerificationMeta(
    'methodEmail',
  );
  @override
  late final GeneratedColumn<bool> methodEmail = GeneratedColumn<bool>(
    'method_email',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("method_email" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _methodOtherMeta = const VerificationMeta(
    'methodOther',
  );
  @override
  late final GeneratedColumn<String> methodOther = GeneratedColumn<String>(
    'method_other',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _concernDescriptionMeta =
      const VerificationMeta('concernDescription');
  @override
  late final GeneratedColumn<String> concernDescription =
      GeneratedColumn<String>(
        'concern_description',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(''),
      );
  static const VerificationMeta _immediateResponseMeta = const VerificationMeta(
    'immediateResponse',
  );
  @override
  late final GeneratedColumn<String> immediateResponse =
      GeneratedColumn<String>(
        'immediate_response',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(''),
      );
  static const VerificationMeta _followUpMonitorMeta = const VerificationMeta(
    'followUpMonitor',
  );
  @override
  late final GeneratedColumn<bool> followUpMonitor = GeneratedColumn<bool>(
    'follow_up_monitor',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("follow_up_monitor" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _followUpStaffCheckInsMeta =
      const VerificationMeta('followUpStaffCheckIns');
  @override
  late final GeneratedColumn<bool> followUpStaffCheckIns =
      GeneratedColumn<bool>(
        'follow_up_staff_check_ins',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("follow_up_staff_check_ins" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _followUpSupervisorReviewMeta =
      const VerificationMeta('followUpSupervisorReview');
  @override
  late final GeneratedColumn<bool> followUpSupervisorReview =
      GeneratedColumn<bool>(
        'follow_up_supervisor_review',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("follow_up_supervisor_review" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _followUpParentConversationMeta =
      const VerificationMeta('followUpParentConversation');
  @override
  late final GeneratedColumn<bool> followUpParentConversation =
      GeneratedColumn<bool>(
        'follow_up_parent_conversation',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("follow_up_parent_conversation" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _followUpOtherMeta = const VerificationMeta(
    'followUpOther',
  );
  @override
  late final GeneratedColumn<String> followUpOther = GeneratedColumn<String>(
    'follow_up_other',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _followUpDateMeta = const VerificationMeta(
    'followUpDate',
  );
  @override
  late final GeneratedColumn<DateTime> followUpDate = GeneratedColumn<DateTime>(
    'follow_up_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _additionalNotesMeta = const VerificationMeta(
    'additionalNotes',
  );
  @override
  late final GeneratedColumn<String> additionalNotes = GeneratedColumn<String>(
    'additional_notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _staffSignatureMeta = const VerificationMeta(
    'staffSignature',
  );
  @override
  late final GeneratedColumn<String> staffSignature = GeneratedColumn<String>(
    'staff_signature',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _staffSignaturePathMeta =
      const VerificationMeta('staffSignaturePath');
  @override
  late final GeneratedColumn<String> staffSignaturePath =
      GeneratedColumn<String>(
        'staff_signature_path',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _staffSignatureDateMeta =
      const VerificationMeta('staffSignatureDate');
  @override
  late final GeneratedColumn<DateTime> staffSignatureDate =
      GeneratedColumn<DateTime>(
        'staff_signature_date',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _supervisorSignatureMeta =
      const VerificationMeta('supervisorSignature');
  @override
  late final GeneratedColumn<String> supervisorSignature =
      GeneratedColumn<String>(
        'supervisor_signature',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _supervisorSignaturePathMeta =
      const VerificationMeta('supervisorSignaturePath');
  @override
  late final GeneratedColumn<String> supervisorSignaturePath =
      GeneratedColumn<String>(
        'supervisor_signature_path',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _supervisorSignatureDateMeta =
      const VerificationMeta('supervisorSignatureDate');
  @override
  late final GeneratedColumn<DateTime> supervisorSignatureDate =
      GeneratedColumn<DateTime>(
        'supervisor_signature_date',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    childNames,
    parentName,
    concernDate,
    staffReceiving,
    supervisorNotified,
    methodInPerson,
    methodPhone,
    methodEmail,
    methodOther,
    concernDescription,
    immediateResponse,
    followUpMonitor,
    followUpStaffCheckIns,
    followUpSupervisorReview,
    followUpParentConversation,
    followUpOther,
    followUpDate,
    additionalNotes,
    staffSignature,
    staffSignaturePath,
    staffSignatureDate,
    supervisorSignature,
    supervisorSignaturePath,
    supervisorSignatureDate,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'parent_concern_notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<ParentConcernNote> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('child_names')) {
      context.handle(
        _childNamesMeta,
        childNames.isAcceptableOrUnknown(data['child_names']!, _childNamesMeta),
      );
    }
    if (data.containsKey('parent_name')) {
      context.handle(
        _parentNameMeta,
        parentName.isAcceptableOrUnknown(data['parent_name']!, _parentNameMeta),
      );
    }
    if (data.containsKey('concern_date')) {
      context.handle(
        _concernDateMeta,
        concernDate.isAcceptableOrUnknown(
          data['concern_date']!,
          _concernDateMeta,
        ),
      );
    }
    if (data.containsKey('staff_receiving')) {
      context.handle(
        _staffReceivingMeta,
        staffReceiving.isAcceptableOrUnknown(
          data['staff_receiving']!,
          _staffReceivingMeta,
        ),
      );
    }
    if (data.containsKey('supervisor_notified')) {
      context.handle(
        _supervisorNotifiedMeta,
        supervisorNotified.isAcceptableOrUnknown(
          data['supervisor_notified']!,
          _supervisorNotifiedMeta,
        ),
      );
    }
    if (data.containsKey('method_in_person')) {
      context.handle(
        _methodInPersonMeta,
        methodInPerson.isAcceptableOrUnknown(
          data['method_in_person']!,
          _methodInPersonMeta,
        ),
      );
    }
    if (data.containsKey('method_phone')) {
      context.handle(
        _methodPhoneMeta,
        methodPhone.isAcceptableOrUnknown(
          data['method_phone']!,
          _methodPhoneMeta,
        ),
      );
    }
    if (data.containsKey('method_email')) {
      context.handle(
        _methodEmailMeta,
        methodEmail.isAcceptableOrUnknown(
          data['method_email']!,
          _methodEmailMeta,
        ),
      );
    }
    if (data.containsKey('method_other')) {
      context.handle(
        _methodOtherMeta,
        methodOther.isAcceptableOrUnknown(
          data['method_other']!,
          _methodOtherMeta,
        ),
      );
    }
    if (data.containsKey('concern_description')) {
      context.handle(
        _concernDescriptionMeta,
        concernDescription.isAcceptableOrUnknown(
          data['concern_description']!,
          _concernDescriptionMeta,
        ),
      );
    }
    if (data.containsKey('immediate_response')) {
      context.handle(
        _immediateResponseMeta,
        immediateResponse.isAcceptableOrUnknown(
          data['immediate_response']!,
          _immediateResponseMeta,
        ),
      );
    }
    if (data.containsKey('follow_up_monitor')) {
      context.handle(
        _followUpMonitorMeta,
        followUpMonitor.isAcceptableOrUnknown(
          data['follow_up_monitor']!,
          _followUpMonitorMeta,
        ),
      );
    }
    if (data.containsKey('follow_up_staff_check_ins')) {
      context.handle(
        _followUpStaffCheckInsMeta,
        followUpStaffCheckIns.isAcceptableOrUnknown(
          data['follow_up_staff_check_ins']!,
          _followUpStaffCheckInsMeta,
        ),
      );
    }
    if (data.containsKey('follow_up_supervisor_review')) {
      context.handle(
        _followUpSupervisorReviewMeta,
        followUpSupervisorReview.isAcceptableOrUnknown(
          data['follow_up_supervisor_review']!,
          _followUpSupervisorReviewMeta,
        ),
      );
    }
    if (data.containsKey('follow_up_parent_conversation')) {
      context.handle(
        _followUpParentConversationMeta,
        followUpParentConversation.isAcceptableOrUnknown(
          data['follow_up_parent_conversation']!,
          _followUpParentConversationMeta,
        ),
      );
    }
    if (data.containsKey('follow_up_other')) {
      context.handle(
        _followUpOtherMeta,
        followUpOther.isAcceptableOrUnknown(
          data['follow_up_other']!,
          _followUpOtherMeta,
        ),
      );
    }
    if (data.containsKey('follow_up_date')) {
      context.handle(
        _followUpDateMeta,
        followUpDate.isAcceptableOrUnknown(
          data['follow_up_date']!,
          _followUpDateMeta,
        ),
      );
    }
    if (data.containsKey('additional_notes')) {
      context.handle(
        _additionalNotesMeta,
        additionalNotes.isAcceptableOrUnknown(
          data['additional_notes']!,
          _additionalNotesMeta,
        ),
      );
    }
    if (data.containsKey('staff_signature')) {
      context.handle(
        _staffSignatureMeta,
        staffSignature.isAcceptableOrUnknown(
          data['staff_signature']!,
          _staffSignatureMeta,
        ),
      );
    }
    if (data.containsKey('staff_signature_path')) {
      context.handle(
        _staffSignaturePathMeta,
        staffSignaturePath.isAcceptableOrUnknown(
          data['staff_signature_path']!,
          _staffSignaturePathMeta,
        ),
      );
    }
    if (data.containsKey('staff_signature_date')) {
      context.handle(
        _staffSignatureDateMeta,
        staffSignatureDate.isAcceptableOrUnknown(
          data['staff_signature_date']!,
          _staffSignatureDateMeta,
        ),
      );
    }
    if (data.containsKey('supervisor_signature')) {
      context.handle(
        _supervisorSignatureMeta,
        supervisorSignature.isAcceptableOrUnknown(
          data['supervisor_signature']!,
          _supervisorSignatureMeta,
        ),
      );
    }
    if (data.containsKey('supervisor_signature_path')) {
      context.handle(
        _supervisorSignaturePathMeta,
        supervisorSignaturePath.isAcceptableOrUnknown(
          data['supervisor_signature_path']!,
          _supervisorSignaturePathMeta,
        ),
      );
    }
    if (data.containsKey('supervisor_signature_date')) {
      context.handle(
        _supervisorSignatureDateMeta,
        supervisorSignatureDate.isAcceptableOrUnknown(
          data['supervisor_signature_date']!,
          _supervisorSignatureDateMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ParentConcernNote map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ParentConcernNote(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      childNames: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}child_names'],
      )!,
      parentName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_name'],
      )!,
      concernDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}concern_date'],
      ),
      staffReceiving: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}staff_receiving'],
      )!,
      supervisorNotified: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}supervisor_notified'],
      ),
      methodInPerson: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}method_in_person'],
      )!,
      methodPhone: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}method_phone'],
      )!,
      methodEmail: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}method_email'],
      )!,
      methodOther: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}method_other'],
      ),
      concernDescription: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}concern_description'],
      )!,
      immediateResponse: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}immediate_response'],
      )!,
      followUpMonitor: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}follow_up_monitor'],
      )!,
      followUpStaffCheckIns: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}follow_up_staff_check_ins'],
      )!,
      followUpSupervisorReview: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}follow_up_supervisor_review'],
      )!,
      followUpParentConversation: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}follow_up_parent_conversation'],
      )!,
      followUpOther: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}follow_up_other'],
      ),
      followUpDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}follow_up_date'],
      ),
      additionalNotes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}additional_notes'],
      ),
      staffSignature: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}staff_signature'],
      ),
      staffSignaturePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}staff_signature_path'],
      ),
      staffSignatureDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}staff_signature_date'],
      ),
      supervisorSignature: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}supervisor_signature'],
      ),
      supervisorSignaturePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}supervisor_signature_path'],
      ),
      supervisorSignatureDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}supervisor_signature_date'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ParentConcernNotesTable createAlias(String alias) {
    return $ParentConcernNotesTable(attachedDatabase, alias);
  }
}

class ParentConcernNote extends DataClass
    implements Insertable<ParentConcernNote> {
  final String id;
  final String childNames;
  final String parentName;
  final DateTime? concernDate;
  final String staffReceiving;
  final String? supervisorNotified;
  final bool methodInPerson;
  final bool methodPhone;
  final bool methodEmail;
  final String? methodOther;
  final String concernDescription;
  final String immediateResponse;
  final bool followUpMonitor;
  final bool followUpStaffCheckIns;
  final bool followUpSupervisorReview;
  final bool followUpParentConversation;
  final String? followUpOther;
  final DateTime? followUpDate;
  final String? additionalNotes;
  final String? staffSignature;
  final String? staffSignaturePath;
  final DateTime? staffSignatureDate;
  final String? supervisorSignature;
  final String? supervisorSignaturePath;
  final DateTime? supervisorSignatureDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ParentConcernNote({
    required this.id,
    required this.childNames,
    required this.parentName,
    this.concernDate,
    required this.staffReceiving,
    this.supervisorNotified,
    required this.methodInPerson,
    required this.methodPhone,
    required this.methodEmail,
    this.methodOther,
    required this.concernDescription,
    required this.immediateResponse,
    required this.followUpMonitor,
    required this.followUpStaffCheckIns,
    required this.followUpSupervisorReview,
    required this.followUpParentConversation,
    this.followUpOther,
    this.followUpDate,
    this.additionalNotes,
    this.staffSignature,
    this.staffSignaturePath,
    this.staffSignatureDate,
    this.supervisorSignature,
    this.supervisorSignaturePath,
    this.supervisorSignatureDate,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['child_names'] = Variable<String>(childNames);
    map['parent_name'] = Variable<String>(parentName);
    if (!nullToAbsent || concernDate != null) {
      map['concern_date'] = Variable<DateTime>(concernDate);
    }
    map['staff_receiving'] = Variable<String>(staffReceiving);
    if (!nullToAbsent || supervisorNotified != null) {
      map['supervisor_notified'] = Variable<String>(supervisorNotified);
    }
    map['method_in_person'] = Variable<bool>(methodInPerson);
    map['method_phone'] = Variable<bool>(methodPhone);
    map['method_email'] = Variable<bool>(methodEmail);
    if (!nullToAbsent || methodOther != null) {
      map['method_other'] = Variable<String>(methodOther);
    }
    map['concern_description'] = Variable<String>(concernDescription);
    map['immediate_response'] = Variable<String>(immediateResponse);
    map['follow_up_monitor'] = Variable<bool>(followUpMonitor);
    map['follow_up_staff_check_ins'] = Variable<bool>(followUpStaffCheckIns);
    map['follow_up_supervisor_review'] = Variable<bool>(
      followUpSupervisorReview,
    );
    map['follow_up_parent_conversation'] = Variable<bool>(
      followUpParentConversation,
    );
    if (!nullToAbsent || followUpOther != null) {
      map['follow_up_other'] = Variable<String>(followUpOther);
    }
    if (!nullToAbsent || followUpDate != null) {
      map['follow_up_date'] = Variable<DateTime>(followUpDate);
    }
    if (!nullToAbsent || additionalNotes != null) {
      map['additional_notes'] = Variable<String>(additionalNotes);
    }
    if (!nullToAbsent || staffSignature != null) {
      map['staff_signature'] = Variable<String>(staffSignature);
    }
    if (!nullToAbsent || staffSignaturePath != null) {
      map['staff_signature_path'] = Variable<String>(staffSignaturePath);
    }
    if (!nullToAbsent || staffSignatureDate != null) {
      map['staff_signature_date'] = Variable<DateTime>(staffSignatureDate);
    }
    if (!nullToAbsent || supervisorSignature != null) {
      map['supervisor_signature'] = Variable<String>(supervisorSignature);
    }
    if (!nullToAbsent || supervisorSignaturePath != null) {
      map['supervisor_signature_path'] = Variable<String>(
        supervisorSignaturePath,
      );
    }
    if (!nullToAbsent || supervisorSignatureDate != null) {
      map['supervisor_signature_date'] = Variable<DateTime>(
        supervisorSignatureDate,
      );
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ParentConcernNotesCompanion toCompanion(bool nullToAbsent) {
    return ParentConcernNotesCompanion(
      id: Value(id),
      childNames: Value(childNames),
      parentName: Value(parentName),
      concernDate: concernDate == null && nullToAbsent
          ? const Value.absent()
          : Value(concernDate),
      staffReceiving: Value(staffReceiving),
      supervisorNotified: supervisorNotified == null && nullToAbsent
          ? const Value.absent()
          : Value(supervisorNotified),
      methodInPerson: Value(methodInPerson),
      methodPhone: Value(methodPhone),
      methodEmail: Value(methodEmail),
      methodOther: methodOther == null && nullToAbsent
          ? const Value.absent()
          : Value(methodOther),
      concernDescription: Value(concernDescription),
      immediateResponse: Value(immediateResponse),
      followUpMonitor: Value(followUpMonitor),
      followUpStaffCheckIns: Value(followUpStaffCheckIns),
      followUpSupervisorReview: Value(followUpSupervisorReview),
      followUpParentConversation: Value(followUpParentConversation),
      followUpOther: followUpOther == null && nullToAbsent
          ? const Value.absent()
          : Value(followUpOther),
      followUpDate: followUpDate == null && nullToAbsent
          ? const Value.absent()
          : Value(followUpDate),
      additionalNotes: additionalNotes == null && nullToAbsent
          ? const Value.absent()
          : Value(additionalNotes),
      staffSignature: staffSignature == null && nullToAbsent
          ? const Value.absent()
          : Value(staffSignature),
      staffSignaturePath: staffSignaturePath == null && nullToAbsent
          ? const Value.absent()
          : Value(staffSignaturePath),
      staffSignatureDate: staffSignatureDate == null && nullToAbsent
          ? const Value.absent()
          : Value(staffSignatureDate),
      supervisorSignature: supervisorSignature == null && nullToAbsent
          ? const Value.absent()
          : Value(supervisorSignature),
      supervisorSignaturePath: supervisorSignaturePath == null && nullToAbsent
          ? const Value.absent()
          : Value(supervisorSignaturePath),
      supervisorSignatureDate: supervisorSignatureDate == null && nullToAbsent
          ? const Value.absent()
          : Value(supervisorSignatureDate),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ParentConcernNote.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ParentConcernNote(
      id: serializer.fromJson<String>(json['id']),
      childNames: serializer.fromJson<String>(json['childNames']),
      parentName: serializer.fromJson<String>(json['parentName']),
      concernDate: serializer.fromJson<DateTime?>(json['concernDate']),
      staffReceiving: serializer.fromJson<String>(json['staffReceiving']),
      supervisorNotified: serializer.fromJson<String?>(
        json['supervisorNotified'],
      ),
      methodInPerson: serializer.fromJson<bool>(json['methodInPerson']),
      methodPhone: serializer.fromJson<bool>(json['methodPhone']),
      methodEmail: serializer.fromJson<bool>(json['methodEmail']),
      methodOther: serializer.fromJson<String?>(json['methodOther']),
      concernDescription: serializer.fromJson<String>(
        json['concernDescription'],
      ),
      immediateResponse: serializer.fromJson<String>(json['immediateResponse']),
      followUpMonitor: serializer.fromJson<bool>(json['followUpMonitor']),
      followUpStaffCheckIns: serializer.fromJson<bool>(
        json['followUpStaffCheckIns'],
      ),
      followUpSupervisorReview: serializer.fromJson<bool>(
        json['followUpSupervisorReview'],
      ),
      followUpParentConversation: serializer.fromJson<bool>(
        json['followUpParentConversation'],
      ),
      followUpOther: serializer.fromJson<String?>(json['followUpOther']),
      followUpDate: serializer.fromJson<DateTime?>(json['followUpDate']),
      additionalNotes: serializer.fromJson<String?>(json['additionalNotes']),
      staffSignature: serializer.fromJson<String?>(json['staffSignature']),
      staffSignaturePath: serializer.fromJson<String?>(
        json['staffSignaturePath'],
      ),
      staffSignatureDate: serializer.fromJson<DateTime?>(
        json['staffSignatureDate'],
      ),
      supervisorSignature: serializer.fromJson<String?>(
        json['supervisorSignature'],
      ),
      supervisorSignaturePath: serializer.fromJson<String?>(
        json['supervisorSignaturePath'],
      ),
      supervisorSignatureDate: serializer.fromJson<DateTime?>(
        json['supervisorSignatureDate'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'childNames': serializer.toJson<String>(childNames),
      'parentName': serializer.toJson<String>(parentName),
      'concernDate': serializer.toJson<DateTime?>(concernDate),
      'staffReceiving': serializer.toJson<String>(staffReceiving),
      'supervisorNotified': serializer.toJson<String?>(supervisorNotified),
      'methodInPerson': serializer.toJson<bool>(methodInPerson),
      'methodPhone': serializer.toJson<bool>(methodPhone),
      'methodEmail': serializer.toJson<bool>(methodEmail),
      'methodOther': serializer.toJson<String?>(methodOther),
      'concernDescription': serializer.toJson<String>(concernDescription),
      'immediateResponse': serializer.toJson<String>(immediateResponse),
      'followUpMonitor': serializer.toJson<bool>(followUpMonitor),
      'followUpStaffCheckIns': serializer.toJson<bool>(followUpStaffCheckIns),
      'followUpSupervisorReview': serializer.toJson<bool>(
        followUpSupervisorReview,
      ),
      'followUpParentConversation': serializer.toJson<bool>(
        followUpParentConversation,
      ),
      'followUpOther': serializer.toJson<String?>(followUpOther),
      'followUpDate': serializer.toJson<DateTime?>(followUpDate),
      'additionalNotes': serializer.toJson<String?>(additionalNotes),
      'staffSignature': serializer.toJson<String?>(staffSignature),
      'staffSignaturePath': serializer.toJson<String?>(staffSignaturePath),
      'staffSignatureDate': serializer.toJson<DateTime?>(staffSignatureDate),
      'supervisorSignature': serializer.toJson<String?>(supervisorSignature),
      'supervisorSignaturePath': serializer.toJson<String?>(
        supervisorSignaturePath,
      ),
      'supervisorSignatureDate': serializer.toJson<DateTime?>(
        supervisorSignatureDate,
      ),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ParentConcernNote copyWith({
    String? id,
    String? childNames,
    String? parentName,
    Value<DateTime?> concernDate = const Value.absent(),
    String? staffReceiving,
    Value<String?> supervisorNotified = const Value.absent(),
    bool? methodInPerson,
    bool? methodPhone,
    bool? methodEmail,
    Value<String?> methodOther = const Value.absent(),
    String? concernDescription,
    String? immediateResponse,
    bool? followUpMonitor,
    bool? followUpStaffCheckIns,
    bool? followUpSupervisorReview,
    bool? followUpParentConversation,
    Value<String?> followUpOther = const Value.absent(),
    Value<DateTime?> followUpDate = const Value.absent(),
    Value<String?> additionalNotes = const Value.absent(),
    Value<String?> staffSignature = const Value.absent(),
    Value<String?> staffSignaturePath = const Value.absent(),
    Value<DateTime?> staffSignatureDate = const Value.absent(),
    Value<String?> supervisorSignature = const Value.absent(),
    Value<String?> supervisorSignaturePath = const Value.absent(),
    Value<DateTime?> supervisorSignatureDate = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ParentConcernNote(
    id: id ?? this.id,
    childNames: childNames ?? this.childNames,
    parentName: parentName ?? this.parentName,
    concernDate: concernDate.present ? concernDate.value : this.concernDate,
    staffReceiving: staffReceiving ?? this.staffReceiving,
    supervisorNotified: supervisorNotified.present
        ? supervisorNotified.value
        : this.supervisorNotified,
    methodInPerson: methodInPerson ?? this.methodInPerson,
    methodPhone: methodPhone ?? this.methodPhone,
    methodEmail: methodEmail ?? this.methodEmail,
    methodOther: methodOther.present ? methodOther.value : this.methodOther,
    concernDescription: concernDescription ?? this.concernDescription,
    immediateResponse: immediateResponse ?? this.immediateResponse,
    followUpMonitor: followUpMonitor ?? this.followUpMonitor,
    followUpStaffCheckIns: followUpStaffCheckIns ?? this.followUpStaffCheckIns,
    followUpSupervisorReview:
        followUpSupervisorReview ?? this.followUpSupervisorReview,
    followUpParentConversation:
        followUpParentConversation ?? this.followUpParentConversation,
    followUpOther: followUpOther.present
        ? followUpOther.value
        : this.followUpOther,
    followUpDate: followUpDate.present ? followUpDate.value : this.followUpDate,
    additionalNotes: additionalNotes.present
        ? additionalNotes.value
        : this.additionalNotes,
    staffSignature: staffSignature.present
        ? staffSignature.value
        : this.staffSignature,
    staffSignaturePath: staffSignaturePath.present
        ? staffSignaturePath.value
        : this.staffSignaturePath,
    staffSignatureDate: staffSignatureDate.present
        ? staffSignatureDate.value
        : this.staffSignatureDate,
    supervisorSignature: supervisorSignature.present
        ? supervisorSignature.value
        : this.supervisorSignature,
    supervisorSignaturePath: supervisorSignaturePath.present
        ? supervisorSignaturePath.value
        : this.supervisorSignaturePath,
    supervisorSignatureDate: supervisorSignatureDate.present
        ? supervisorSignatureDate.value
        : this.supervisorSignatureDate,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ParentConcernNote copyWithCompanion(ParentConcernNotesCompanion data) {
    return ParentConcernNote(
      id: data.id.present ? data.id.value : this.id,
      childNames: data.childNames.present
          ? data.childNames.value
          : this.childNames,
      parentName: data.parentName.present
          ? data.parentName.value
          : this.parentName,
      concernDate: data.concernDate.present
          ? data.concernDate.value
          : this.concernDate,
      staffReceiving: data.staffReceiving.present
          ? data.staffReceiving.value
          : this.staffReceiving,
      supervisorNotified: data.supervisorNotified.present
          ? data.supervisorNotified.value
          : this.supervisorNotified,
      methodInPerson: data.methodInPerson.present
          ? data.methodInPerson.value
          : this.methodInPerson,
      methodPhone: data.methodPhone.present
          ? data.methodPhone.value
          : this.methodPhone,
      methodEmail: data.methodEmail.present
          ? data.methodEmail.value
          : this.methodEmail,
      methodOther: data.methodOther.present
          ? data.methodOther.value
          : this.methodOther,
      concernDescription: data.concernDescription.present
          ? data.concernDescription.value
          : this.concernDescription,
      immediateResponse: data.immediateResponse.present
          ? data.immediateResponse.value
          : this.immediateResponse,
      followUpMonitor: data.followUpMonitor.present
          ? data.followUpMonitor.value
          : this.followUpMonitor,
      followUpStaffCheckIns: data.followUpStaffCheckIns.present
          ? data.followUpStaffCheckIns.value
          : this.followUpStaffCheckIns,
      followUpSupervisorReview: data.followUpSupervisorReview.present
          ? data.followUpSupervisorReview.value
          : this.followUpSupervisorReview,
      followUpParentConversation: data.followUpParentConversation.present
          ? data.followUpParentConversation.value
          : this.followUpParentConversation,
      followUpOther: data.followUpOther.present
          ? data.followUpOther.value
          : this.followUpOther,
      followUpDate: data.followUpDate.present
          ? data.followUpDate.value
          : this.followUpDate,
      additionalNotes: data.additionalNotes.present
          ? data.additionalNotes.value
          : this.additionalNotes,
      staffSignature: data.staffSignature.present
          ? data.staffSignature.value
          : this.staffSignature,
      staffSignaturePath: data.staffSignaturePath.present
          ? data.staffSignaturePath.value
          : this.staffSignaturePath,
      staffSignatureDate: data.staffSignatureDate.present
          ? data.staffSignatureDate.value
          : this.staffSignatureDate,
      supervisorSignature: data.supervisorSignature.present
          ? data.supervisorSignature.value
          : this.supervisorSignature,
      supervisorSignaturePath: data.supervisorSignaturePath.present
          ? data.supervisorSignaturePath.value
          : this.supervisorSignaturePath,
      supervisorSignatureDate: data.supervisorSignatureDate.present
          ? data.supervisorSignatureDate.value
          : this.supervisorSignatureDate,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ParentConcernNote(')
          ..write('id: $id, ')
          ..write('childNames: $childNames, ')
          ..write('parentName: $parentName, ')
          ..write('concernDate: $concernDate, ')
          ..write('staffReceiving: $staffReceiving, ')
          ..write('supervisorNotified: $supervisorNotified, ')
          ..write('methodInPerson: $methodInPerson, ')
          ..write('methodPhone: $methodPhone, ')
          ..write('methodEmail: $methodEmail, ')
          ..write('methodOther: $methodOther, ')
          ..write('concernDescription: $concernDescription, ')
          ..write('immediateResponse: $immediateResponse, ')
          ..write('followUpMonitor: $followUpMonitor, ')
          ..write('followUpStaffCheckIns: $followUpStaffCheckIns, ')
          ..write('followUpSupervisorReview: $followUpSupervisorReview, ')
          ..write('followUpParentConversation: $followUpParentConversation, ')
          ..write('followUpOther: $followUpOther, ')
          ..write('followUpDate: $followUpDate, ')
          ..write('additionalNotes: $additionalNotes, ')
          ..write('staffSignature: $staffSignature, ')
          ..write('staffSignaturePath: $staffSignaturePath, ')
          ..write('staffSignatureDate: $staffSignatureDate, ')
          ..write('supervisorSignature: $supervisorSignature, ')
          ..write('supervisorSignaturePath: $supervisorSignaturePath, ')
          ..write('supervisorSignatureDate: $supervisorSignatureDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    childNames,
    parentName,
    concernDate,
    staffReceiving,
    supervisorNotified,
    methodInPerson,
    methodPhone,
    methodEmail,
    methodOther,
    concernDescription,
    immediateResponse,
    followUpMonitor,
    followUpStaffCheckIns,
    followUpSupervisorReview,
    followUpParentConversation,
    followUpOther,
    followUpDate,
    additionalNotes,
    staffSignature,
    staffSignaturePath,
    staffSignatureDate,
    supervisorSignature,
    supervisorSignaturePath,
    supervisorSignatureDate,
    createdAt,
    updatedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ParentConcernNote &&
          other.id == this.id &&
          other.childNames == this.childNames &&
          other.parentName == this.parentName &&
          other.concernDate == this.concernDate &&
          other.staffReceiving == this.staffReceiving &&
          other.supervisorNotified == this.supervisorNotified &&
          other.methodInPerson == this.methodInPerson &&
          other.methodPhone == this.methodPhone &&
          other.methodEmail == this.methodEmail &&
          other.methodOther == this.methodOther &&
          other.concernDescription == this.concernDescription &&
          other.immediateResponse == this.immediateResponse &&
          other.followUpMonitor == this.followUpMonitor &&
          other.followUpStaffCheckIns == this.followUpStaffCheckIns &&
          other.followUpSupervisorReview == this.followUpSupervisorReview &&
          other.followUpParentConversation == this.followUpParentConversation &&
          other.followUpOther == this.followUpOther &&
          other.followUpDate == this.followUpDate &&
          other.additionalNotes == this.additionalNotes &&
          other.staffSignature == this.staffSignature &&
          other.staffSignaturePath == this.staffSignaturePath &&
          other.staffSignatureDate == this.staffSignatureDate &&
          other.supervisorSignature == this.supervisorSignature &&
          other.supervisorSignaturePath == this.supervisorSignaturePath &&
          other.supervisorSignatureDate == this.supervisorSignatureDate &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ParentConcernNotesCompanion extends UpdateCompanion<ParentConcernNote> {
  final Value<String> id;
  final Value<String> childNames;
  final Value<String> parentName;
  final Value<DateTime?> concernDate;
  final Value<String> staffReceiving;
  final Value<String?> supervisorNotified;
  final Value<bool> methodInPerson;
  final Value<bool> methodPhone;
  final Value<bool> methodEmail;
  final Value<String?> methodOther;
  final Value<String> concernDescription;
  final Value<String> immediateResponse;
  final Value<bool> followUpMonitor;
  final Value<bool> followUpStaffCheckIns;
  final Value<bool> followUpSupervisorReview;
  final Value<bool> followUpParentConversation;
  final Value<String?> followUpOther;
  final Value<DateTime?> followUpDate;
  final Value<String?> additionalNotes;
  final Value<String?> staffSignature;
  final Value<String?> staffSignaturePath;
  final Value<DateTime?> staffSignatureDate;
  final Value<String?> supervisorSignature;
  final Value<String?> supervisorSignaturePath;
  final Value<DateTime?> supervisorSignatureDate;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ParentConcernNotesCompanion({
    this.id = const Value.absent(),
    this.childNames = const Value.absent(),
    this.parentName = const Value.absent(),
    this.concernDate = const Value.absent(),
    this.staffReceiving = const Value.absent(),
    this.supervisorNotified = const Value.absent(),
    this.methodInPerson = const Value.absent(),
    this.methodPhone = const Value.absent(),
    this.methodEmail = const Value.absent(),
    this.methodOther = const Value.absent(),
    this.concernDescription = const Value.absent(),
    this.immediateResponse = const Value.absent(),
    this.followUpMonitor = const Value.absent(),
    this.followUpStaffCheckIns = const Value.absent(),
    this.followUpSupervisorReview = const Value.absent(),
    this.followUpParentConversation = const Value.absent(),
    this.followUpOther = const Value.absent(),
    this.followUpDate = const Value.absent(),
    this.additionalNotes = const Value.absent(),
    this.staffSignature = const Value.absent(),
    this.staffSignaturePath = const Value.absent(),
    this.staffSignatureDate = const Value.absent(),
    this.supervisorSignature = const Value.absent(),
    this.supervisorSignaturePath = const Value.absent(),
    this.supervisorSignatureDate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ParentConcernNotesCompanion.insert({
    required String id,
    this.childNames = const Value.absent(),
    this.parentName = const Value.absent(),
    this.concernDate = const Value.absent(),
    this.staffReceiving = const Value.absent(),
    this.supervisorNotified = const Value.absent(),
    this.methodInPerson = const Value.absent(),
    this.methodPhone = const Value.absent(),
    this.methodEmail = const Value.absent(),
    this.methodOther = const Value.absent(),
    this.concernDescription = const Value.absent(),
    this.immediateResponse = const Value.absent(),
    this.followUpMonitor = const Value.absent(),
    this.followUpStaffCheckIns = const Value.absent(),
    this.followUpSupervisorReview = const Value.absent(),
    this.followUpParentConversation = const Value.absent(),
    this.followUpOther = const Value.absent(),
    this.followUpDate = const Value.absent(),
    this.additionalNotes = const Value.absent(),
    this.staffSignature = const Value.absent(),
    this.staffSignaturePath = const Value.absent(),
    this.staffSignatureDate = const Value.absent(),
    this.supervisorSignature = const Value.absent(),
    this.supervisorSignaturePath = const Value.absent(),
    this.supervisorSignatureDate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<ParentConcernNote> custom({
    Expression<String>? id,
    Expression<String>? childNames,
    Expression<String>? parentName,
    Expression<DateTime>? concernDate,
    Expression<String>? staffReceiving,
    Expression<String>? supervisorNotified,
    Expression<bool>? methodInPerson,
    Expression<bool>? methodPhone,
    Expression<bool>? methodEmail,
    Expression<String>? methodOther,
    Expression<String>? concernDescription,
    Expression<String>? immediateResponse,
    Expression<bool>? followUpMonitor,
    Expression<bool>? followUpStaffCheckIns,
    Expression<bool>? followUpSupervisorReview,
    Expression<bool>? followUpParentConversation,
    Expression<String>? followUpOther,
    Expression<DateTime>? followUpDate,
    Expression<String>? additionalNotes,
    Expression<String>? staffSignature,
    Expression<String>? staffSignaturePath,
    Expression<DateTime>? staffSignatureDate,
    Expression<String>? supervisorSignature,
    Expression<String>? supervisorSignaturePath,
    Expression<DateTime>? supervisorSignatureDate,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (childNames != null) 'child_names': childNames,
      if (parentName != null) 'parent_name': parentName,
      if (concernDate != null) 'concern_date': concernDate,
      if (staffReceiving != null) 'staff_receiving': staffReceiving,
      if (supervisorNotified != null) 'supervisor_notified': supervisorNotified,
      if (methodInPerson != null) 'method_in_person': methodInPerson,
      if (methodPhone != null) 'method_phone': methodPhone,
      if (methodEmail != null) 'method_email': methodEmail,
      if (methodOther != null) 'method_other': methodOther,
      if (concernDescription != null) 'concern_description': concernDescription,
      if (immediateResponse != null) 'immediate_response': immediateResponse,
      if (followUpMonitor != null) 'follow_up_monitor': followUpMonitor,
      if (followUpStaffCheckIns != null)
        'follow_up_staff_check_ins': followUpStaffCheckIns,
      if (followUpSupervisorReview != null)
        'follow_up_supervisor_review': followUpSupervisorReview,
      if (followUpParentConversation != null)
        'follow_up_parent_conversation': followUpParentConversation,
      if (followUpOther != null) 'follow_up_other': followUpOther,
      if (followUpDate != null) 'follow_up_date': followUpDate,
      if (additionalNotes != null) 'additional_notes': additionalNotes,
      if (staffSignature != null) 'staff_signature': staffSignature,
      if (staffSignaturePath != null)
        'staff_signature_path': staffSignaturePath,
      if (staffSignatureDate != null)
        'staff_signature_date': staffSignatureDate,
      if (supervisorSignature != null)
        'supervisor_signature': supervisorSignature,
      if (supervisorSignaturePath != null)
        'supervisor_signature_path': supervisorSignaturePath,
      if (supervisorSignatureDate != null)
        'supervisor_signature_date': supervisorSignatureDate,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ParentConcernNotesCompanion copyWith({
    Value<String>? id,
    Value<String>? childNames,
    Value<String>? parentName,
    Value<DateTime?>? concernDate,
    Value<String>? staffReceiving,
    Value<String?>? supervisorNotified,
    Value<bool>? methodInPerson,
    Value<bool>? methodPhone,
    Value<bool>? methodEmail,
    Value<String?>? methodOther,
    Value<String>? concernDescription,
    Value<String>? immediateResponse,
    Value<bool>? followUpMonitor,
    Value<bool>? followUpStaffCheckIns,
    Value<bool>? followUpSupervisorReview,
    Value<bool>? followUpParentConversation,
    Value<String?>? followUpOther,
    Value<DateTime?>? followUpDate,
    Value<String?>? additionalNotes,
    Value<String?>? staffSignature,
    Value<String?>? staffSignaturePath,
    Value<DateTime?>? staffSignatureDate,
    Value<String?>? supervisorSignature,
    Value<String?>? supervisorSignaturePath,
    Value<DateTime?>? supervisorSignatureDate,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ParentConcernNotesCompanion(
      id: id ?? this.id,
      childNames: childNames ?? this.childNames,
      parentName: parentName ?? this.parentName,
      concernDate: concernDate ?? this.concernDate,
      staffReceiving: staffReceiving ?? this.staffReceiving,
      supervisorNotified: supervisorNotified ?? this.supervisorNotified,
      methodInPerson: methodInPerson ?? this.methodInPerson,
      methodPhone: methodPhone ?? this.methodPhone,
      methodEmail: methodEmail ?? this.methodEmail,
      methodOther: methodOther ?? this.methodOther,
      concernDescription: concernDescription ?? this.concernDescription,
      immediateResponse: immediateResponse ?? this.immediateResponse,
      followUpMonitor: followUpMonitor ?? this.followUpMonitor,
      followUpStaffCheckIns:
          followUpStaffCheckIns ?? this.followUpStaffCheckIns,
      followUpSupervisorReview:
          followUpSupervisorReview ?? this.followUpSupervisorReview,
      followUpParentConversation:
          followUpParentConversation ?? this.followUpParentConversation,
      followUpOther: followUpOther ?? this.followUpOther,
      followUpDate: followUpDate ?? this.followUpDate,
      additionalNotes: additionalNotes ?? this.additionalNotes,
      staffSignature: staffSignature ?? this.staffSignature,
      staffSignaturePath: staffSignaturePath ?? this.staffSignaturePath,
      staffSignatureDate: staffSignatureDate ?? this.staffSignatureDate,
      supervisorSignature: supervisorSignature ?? this.supervisorSignature,
      supervisorSignaturePath:
          supervisorSignaturePath ?? this.supervisorSignaturePath,
      supervisorSignatureDate:
          supervisorSignatureDate ?? this.supervisorSignatureDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (childNames.present) {
      map['child_names'] = Variable<String>(childNames.value);
    }
    if (parentName.present) {
      map['parent_name'] = Variable<String>(parentName.value);
    }
    if (concernDate.present) {
      map['concern_date'] = Variable<DateTime>(concernDate.value);
    }
    if (staffReceiving.present) {
      map['staff_receiving'] = Variable<String>(staffReceiving.value);
    }
    if (supervisorNotified.present) {
      map['supervisor_notified'] = Variable<String>(supervisorNotified.value);
    }
    if (methodInPerson.present) {
      map['method_in_person'] = Variable<bool>(methodInPerson.value);
    }
    if (methodPhone.present) {
      map['method_phone'] = Variable<bool>(methodPhone.value);
    }
    if (methodEmail.present) {
      map['method_email'] = Variable<bool>(methodEmail.value);
    }
    if (methodOther.present) {
      map['method_other'] = Variable<String>(methodOther.value);
    }
    if (concernDescription.present) {
      map['concern_description'] = Variable<String>(concernDescription.value);
    }
    if (immediateResponse.present) {
      map['immediate_response'] = Variable<String>(immediateResponse.value);
    }
    if (followUpMonitor.present) {
      map['follow_up_monitor'] = Variable<bool>(followUpMonitor.value);
    }
    if (followUpStaffCheckIns.present) {
      map['follow_up_staff_check_ins'] = Variable<bool>(
        followUpStaffCheckIns.value,
      );
    }
    if (followUpSupervisorReview.present) {
      map['follow_up_supervisor_review'] = Variable<bool>(
        followUpSupervisorReview.value,
      );
    }
    if (followUpParentConversation.present) {
      map['follow_up_parent_conversation'] = Variable<bool>(
        followUpParentConversation.value,
      );
    }
    if (followUpOther.present) {
      map['follow_up_other'] = Variable<String>(followUpOther.value);
    }
    if (followUpDate.present) {
      map['follow_up_date'] = Variable<DateTime>(followUpDate.value);
    }
    if (additionalNotes.present) {
      map['additional_notes'] = Variable<String>(additionalNotes.value);
    }
    if (staffSignature.present) {
      map['staff_signature'] = Variable<String>(staffSignature.value);
    }
    if (staffSignaturePath.present) {
      map['staff_signature_path'] = Variable<String>(staffSignaturePath.value);
    }
    if (staffSignatureDate.present) {
      map['staff_signature_date'] = Variable<DateTime>(
        staffSignatureDate.value,
      );
    }
    if (supervisorSignature.present) {
      map['supervisor_signature'] = Variable<String>(supervisorSignature.value);
    }
    if (supervisorSignaturePath.present) {
      map['supervisor_signature_path'] = Variable<String>(
        supervisorSignaturePath.value,
      );
    }
    if (supervisorSignatureDate.present) {
      map['supervisor_signature_date'] = Variable<DateTime>(
        supervisorSignatureDate.value,
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ParentConcernNotesCompanion(')
          ..write('id: $id, ')
          ..write('childNames: $childNames, ')
          ..write('parentName: $parentName, ')
          ..write('concernDate: $concernDate, ')
          ..write('staffReceiving: $staffReceiving, ')
          ..write('supervisorNotified: $supervisorNotified, ')
          ..write('methodInPerson: $methodInPerson, ')
          ..write('methodPhone: $methodPhone, ')
          ..write('methodEmail: $methodEmail, ')
          ..write('methodOther: $methodOther, ')
          ..write('concernDescription: $concernDescription, ')
          ..write('immediateResponse: $immediateResponse, ')
          ..write('followUpMonitor: $followUpMonitor, ')
          ..write('followUpStaffCheckIns: $followUpStaffCheckIns, ')
          ..write('followUpSupervisorReview: $followUpSupervisorReview, ')
          ..write('followUpParentConversation: $followUpParentConversation, ')
          ..write('followUpOther: $followUpOther, ')
          ..write('followUpDate: $followUpDate, ')
          ..write('additionalNotes: $additionalNotes, ')
          ..write('staffSignature: $staffSignature, ')
          ..write('staffSignaturePath: $staffSignaturePath, ')
          ..write('staffSignatureDate: $staffSignatureDate, ')
          ..write('supervisorSignature: $supervisorSignature, ')
          ..write('supervisorSignaturePath: $supervisorSignaturePath, ')
          ..write('supervisorSignatureDate: $supervisorSignatureDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PodsTable pods = $PodsTable(this);
  late final $KidsTable kids = $KidsTable(this);
  late final $TripsTable trips = $TripsTable(this);
  late final $TripPodsTable tripPods = $TripPodsTable(this);
  late final $CapturesTable captures = $CapturesTable(this);
  late final $CaptureKidsTable captureKids = $CaptureKidsTable(this);
  late final $ObservationsTable observations = $ObservationsTable(this);
  late final $ObservationKidsTable observationKids = $ObservationKidsTable(
    this,
  );
  late final $ObservationAttachmentsTable observationAttachments =
      $ObservationAttachmentsTable(this);
  late final $ObservationDomainTagsTable observationDomainTags =
      $ObservationDomainTagsTable(this);
  late final $SpecialistsTable specialists = $SpecialistsTable(this);
  late final $SpecialistAvailabilityTable specialistAvailability =
      $SpecialistAvailabilityTable(this);
  late final $ActivityLibraryTable activityLibrary = $ActivityLibraryTable(
    this,
  );
  late final $ScheduleTemplatesTable scheduleTemplates =
      $ScheduleTemplatesTable(this);
  late final $ScheduleEntriesTable scheduleEntries = $ScheduleEntriesTable(
    this,
  );
  late final $TemplatePodsTable templatePods = $TemplatePodsTable(this);
  late final $EntryPodsTable entryPods = $EntryPodsTable(this);
  late final $ParentConcernNotesTable parentConcernNotes =
      $ParentConcernNotesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    pods,
    kids,
    trips,
    tripPods,
    captures,
    captureKids,
    observations,
    observationKids,
    observationAttachments,
    observationDomainTags,
    specialists,
    specialistAvailability,
    activityLibrary,
    scheduleTemplates,
    scheduleEntries,
    templatePods,
    entryPods,
    parentConcernNotes,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'pods',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('kids', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trips',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('trip_pods', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'pods',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('trip_pods', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trips',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('captures', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'captures',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('capture_kids', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'kids',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('capture_kids', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'kids',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('observations', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'pods',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('observations', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trips',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('observations', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'observations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('observation_kids', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'kids',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('observation_kids', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'observations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('observation_attachments', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'observations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('observation_domain_tags', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'specialists',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('specialist_availability', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'specialists',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('activity_library', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'pods',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('schedule_templates', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'specialists',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('schedule_templates', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'pods',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('schedule_entries', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'specialists',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('schedule_entries', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trips',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('schedule_entries', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'schedule_templates',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('schedule_entries', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'schedule_templates',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('template_pods', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'pods',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('template_pods', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'schedule_entries',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('entry_pods', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'pods',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('entry_pods', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$PodsTableCreateCompanionBuilder =
    PodsCompanion Function({
      required String id,
      required String name,
      Value<String?> colorHex,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$PodsTableUpdateCompanionBuilder =
    PodsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> colorHex,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$PodsTableReferences
    extends BaseReferences<_$AppDatabase, $PodsTable, Pod> {
  $$PodsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$KidsTable, List<Kid>> _kidsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.kids,
    aliasName: $_aliasNameGenerator(db.pods.id, db.kids.podId),
  );

  $$KidsTableProcessedTableManager get kidsRefs {
    final manager = $$KidsTableTableManager(
      $_db,
      $_db.kids,
    ).filter((f) => f.podId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_kidsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TripPodsTable, List<TripPod>> _tripPodsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.tripPods,
    aliasName: $_aliasNameGenerator(db.pods.id, db.tripPods.podId),
  );

  $$TripPodsTableProcessedTableManager get tripPodsRefs {
    final manager = $$TripPodsTableTableManager(
      $_db,
      $_db.tripPods,
    ).filter((f) => f.podId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_tripPodsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ObservationsTable, List<Observation>>
  _observationsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.observations,
    aliasName: $_aliasNameGenerator(db.pods.id, db.observations.podId),
  );

  $$ObservationsTableProcessedTableManager get observationsRefs {
    final manager = $$ObservationsTableTableManager(
      $_db,
      $_db.observations,
    ).filter((f) => f.podId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_observationsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ScheduleTemplatesTable, List<ScheduleTemplate>>
  _scheduleTemplatesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.scheduleTemplates,
        aliasName: $_aliasNameGenerator(db.pods.id, db.scheduleTemplates.podId),
      );

  $$ScheduleTemplatesTableProcessedTableManager get scheduleTemplatesRefs {
    final manager = $$ScheduleTemplatesTableTableManager(
      $_db,
      $_db.scheduleTemplates,
    ).filter((f) => f.podId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _scheduleTemplatesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ScheduleEntriesTable, List<ScheduleEntry>>
  _scheduleEntriesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.scheduleEntries,
    aliasName: $_aliasNameGenerator(db.pods.id, db.scheduleEntries.podId),
  );

  $$ScheduleEntriesTableProcessedTableManager get scheduleEntriesRefs {
    final manager = $$ScheduleEntriesTableTableManager(
      $_db,
      $_db.scheduleEntries,
    ).filter((f) => f.podId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _scheduleEntriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TemplatePodsTable, List<TemplatePod>>
  _templatePodsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.templatePods,
    aliasName: $_aliasNameGenerator(db.pods.id, db.templatePods.podId),
  );

  $$TemplatePodsTableProcessedTableManager get templatePodsRefs {
    final manager = $$TemplatePodsTableTableManager(
      $_db,
      $_db.templatePods,
    ).filter((f) => f.podId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_templatePodsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$EntryPodsTable, List<EntryPod>>
  _entryPodsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.entryPods,
    aliasName: $_aliasNameGenerator(db.pods.id, db.entryPods.podId),
  );

  $$EntryPodsTableProcessedTableManager get entryPodsRefs {
    final manager = $$EntryPodsTableTableManager(
      $_db,
      $_db.entryPods,
    ).filter((f) => f.podId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_entryPodsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PodsTableFilterComposer extends Composer<_$AppDatabase, $PodsTable> {
  $$PodsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorHex => $composableBuilder(
    column: $table.colorHex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> kidsRefs(
    Expression<bool> Function($$KidsTableFilterComposer f) f,
  ) {
    final $$KidsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.kids,
      getReferencedColumn: (t) => t.podId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KidsTableFilterComposer(
            $db: $db,
            $table: $db.kids,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> tripPodsRefs(
    Expression<bool> Function($$TripPodsTableFilterComposer f) f,
  ) {
    final $$TripPodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tripPods,
      getReferencedColumn: (t) => t.podId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TripPodsTableFilterComposer(
            $db: $db,
            $table: $db.tripPods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> observationsRefs(
    Expression<bool> Function($$ObservationsTableFilterComposer f) f,
  ) {
    final $$ObservationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.observations,
      getReferencedColumn: (t) => t.podId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationsTableFilterComposer(
            $db: $db,
            $table: $db.observations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> scheduleTemplatesRefs(
    Expression<bool> Function($$ScheduleTemplatesTableFilterComposer f) f,
  ) {
    final $$ScheduleTemplatesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scheduleTemplates,
      getReferencedColumn: (t) => t.podId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScheduleTemplatesTableFilterComposer(
            $db: $db,
            $table: $db.scheduleTemplates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> scheduleEntriesRefs(
    Expression<bool> Function($$ScheduleEntriesTableFilterComposer f) f,
  ) {
    final $$ScheduleEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scheduleEntries,
      getReferencedColumn: (t) => t.podId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScheduleEntriesTableFilterComposer(
            $db: $db,
            $table: $db.scheduleEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> templatePodsRefs(
    Expression<bool> Function($$TemplatePodsTableFilterComposer f) f,
  ) {
    final $$TemplatePodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.templatePods,
      getReferencedColumn: (t) => t.podId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TemplatePodsTableFilterComposer(
            $db: $db,
            $table: $db.templatePods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> entryPodsRefs(
    Expression<bool> Function($$EntryPodsTableFilterComposer f) f,
  ) {
    final $$EntryPodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.entryPods,
      getReferencedColumn: (t) => t.podId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EntryPodsTableFilterComposer(
            $db: $db,
            $table: $db.entryPods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PodsTableOrderingComposer extends Composer<_$AppDatabase, $PodsTable> {
  $$PodsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorHex => $composableBuilder(
    column: $table.colorHex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PodsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PodsTable> {
  $$PodsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get colorHex =>
      $composableBuilder(column: $table.colorHex, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> kidsRefs<T extends Object>(
    Expression<T> Function($$KidsTableAnnotationComposer a) f,
  ) {
    final $$KidsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.kids,
      getReferencedColumn: (t) => t.podId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KidsTableAnnotationComposer(
            $db: $db,
            $table: $db.kids,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> tripPodsRefs<T extends Object>(
    Expression<T> Function($$TripPodsTableAnnotationComposer a) f,
  ) {
    final $$TripPodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tripPods,
      getReferencedColumn: (t) => t.podId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TripPodsTableAnnotationComposer(
            $db: $db,
            $table: $db.tripPods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> observationsRefs<T extends Object>(
    Expression<T> Function($$ObservationsTableAnnotationComposer a) f,
  ) {
    final $$ObservationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.observations,
      getReferencedColumn: (t) => t.podId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationsTableAnnotationComposer(
            $db: $db,
            $table: $db.observations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> scheduleTemplatesRefs<T extends Object>(
    Expression<T> Function($$ScheduleTemplatesTableAnnotationComposer a) f,
  ) {
    final $$ScheduleTemplatesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.scheduleTemplates,
          getReferencedColumn: (t) => t.podId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ScheduleTemplatesTableAnnotationComposer(
                $db: $db,
                $table: $db.scheduleTemplates,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> scheduleEntriesRefs<T extends Object>(
    Expression<T> Function($$ScheduleEntriesTableAnnotationComposer a) f,
  ) {
    final $$ScheduleEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scheduleEntries,
      getReferencedColumn: (t) => t.podId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScheduleEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.scheduleEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> templatePodsRefs<T extends Object>(
    Expression<T> Function($$TemplatePodsTableAnnotationComposer a) f,
  ) {
    final $$TemplatePodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.templatePods,
      getReferencedColumn: (t) => t.podId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TemplatePodsTableAnnotationComposer(
            $db: $db,
            $table: $db.templatePods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> entryPodsRefs<T extends Object>(
    Expression<T> Function($$EntryPodsTableAnnotationComposer a) f,
  ) {
    final $$EntryPodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.entryPods,
      getReferencedColumn: (t) => t.podId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EntryPodsTableAnnotationComposer(
            $db: $db,
            $table: $db.entryPods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PodsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PodsTable,
          Pod,
          $$PodsTableFilterComposer,
          $$PodsTableOrderingComposer,
          $$PodsTableAnnotationComposer,
          $$PodsTableCreateCompanionBuilder,
          $$PodsTableUpdateCompanionBuilder,
          (Pod, $$PodsTableReferences),
          Pod,
          PrefetchHooks Function({
            bool kidsRefs,
            bool tripPodsRefs,
            bool observationsRefs,
            bool scheduleTemplatesRefs,
            bool scheduleEntriesRefs,
            bool templatePodsRefs,
            bool entryPodsRefs,
          })
        > {
  $$PodsTableTableManager(_$AppDatabase db, $PodsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PodsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PodsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PodsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> colorHex = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PodsCompanion(
                id: id,
                name: name,
                colorHex: colorHex,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> colorHex = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PodsCompanion.insert(
                id: id,
                name: name,
                colorHex: colorHex,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$PodsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                kidsRefs = false,
                tripPodsRefs = false,
                observationsRefs = false,
                scheduleTemplatesRefs = false,
                scheduleEntriesRefs = false,
                templatePodsRefs = false,
                entryPodsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (kidsRefs) db.kids,
                    if (tripPodsRefs) db.tripPods,
                    if (observationsRefs) db.observations,
                    if (scheduleTemplatesRefs) db.scheduleTemplates,
                    if (scheduleEntriesRefs) db.scheduleEntries,
                    if (templatePodsRefs) db.templatePods,
                    if (entryPodsRefs) db.entryPods,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (kidsRefs)
                        await $_getPrefetchedData<Pod, $PodsTable, Kid>(
                          currentTable: table,
                          referencedTable: $$PodsTableReferences._kidsRefsTable(
                            db,
                          ),
                          managerFromTypedResult: (p0) =>
                              $$PodsTableReferences(db, table, p0).kidsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.podId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (tripPodsRefs)
                        await $_getPrefetchedData<Pod, $PodsTable, TripPod>(
                          currentTable: table,
                          referencedTable: $$PodsTableReferences
                              ._tripPodsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PodsTableReferences(db, table, p0).tripPodsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.podId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (observationsRefs)
                        await $_getPrefetchedData<Pod, $PodsTable, Observation>(
                          currentTable: table,
                          referencedTable: $$PodsTableReferences
                              ._observationsRefsTable(db),
                          managerFromTypedResult: (p0) => $$PodsTableReferences(
                            db,
                            table,
                            p0,
                          ).observationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.podId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (scheduleTemplatesRefs)
                        await $_getPrefetchedData<
                          Pod,
                          $PodsTable,
                          ScheduleTemplate
                        >(
                          currentTable: table,
                          referencedTable: $$PodsTableReferences
                              ._scheduleTemplatesRefsTable(db),
                          managerFromTypedResult: (p0) => $$PodsTableReferences(
                            db,
                            table,
                            p0,
                          ).scheduleTemplatesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.podId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (scheduleEntriesRefs)
                        await $_getPrefetchedData<
                          Pod,
                          $PodsTable,
                          ScheduleEntry
                        >(
                          currentTable: table,
                          referencedTable: $$PodsTableReferences
                              ._scheduleEntriesRefsTable(db),
                          managerFromTypedResult: (p0) => $$PodsTableReferences(
                            db,
                            table,
                            p0,
                          ).scheduleEntriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.podId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (templatePodsRefs)
                        await $_getPrefetchedData<Pod, $PodsTable, TemplatePod>(
                          currentTable: table,
                          referencedTable: $$PodsTableReferences
                              ._templatePodsRefsTable(db),
                          managerFromTypedResult: (p0) => $$PodsTableReferences(
                            db,
                            table,
                            p0,
                          ).templatePodsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.podId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (entryPodsRefs)
                        await $_getPrefetchedData<Pod, $PodsTable, EntryPod>(
                          currentTable: table,
                          referencedTable: $$PodsTableReferences
                              ._entryPodsRefsTable(db),
                          managerFromTypedResult: (p0) => $$PodsTableReferences(
                            db,
                            table,
                            p0,
                          ).entryPodsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.podId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$PodsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PodsTable,
      Pod,
      $$PodsTableFilterComposer,
      $$PodsTableOrderingComposer,
      $$PodsTableAnnotationComposer,
      $$PodsTableCreateCompanionBuilder,
      $$PodsTableUpdateCompanionBuilder,
      (Pod, $$PodsTableReferences),
      Pod,
      PrefetchHooks Function({
        bool kidsRefs,
        bool tripPodsRefs,
        bool observationsRefs,
        bool scheduleTemplatesRefs,
        bool scheduleEntriesRefs,
        bool templatePodsRefs,
        bool entryPodsRefs,
      })
    >;
typedef $$KidsTableCreateCompanionBuilder =
    KidsCompanion Function({
      required String id,
      required String firstName,
      Value<String?> lastName,
      Value<String?> podId,
      Value<DateTime?> birthDate,
      Value<String?> pin,
      Value<String?> notes,
      Value<String?> parentName,
      Value<String?> avatarPath,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$KidsTableUpdateCompanionBuilder =
    KidsCompanion Function({
      Value<String> id,
      Value<String> firstName,
      Value<String?> lastName,
      Value<String?> podId,
      Value<DateTime?> birthDate,
      Value<String?> pin,
      Value<String?> notes,
      Value<String?> parentName,
      Value<String?> avatarPath,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$KidsTableReferences
    extends BaseReferences<_$AppDatabase, $KidsTable, Kid> {
  $$KidsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PodsTable _podIdTable(_$AppDatabase db) =>
      db.pods.createAlias($_aliasNameGenerator(db.kids.podId, db.pods.id));

  $$PodsTableProcessedTableManager? get podId {
    final $_column = $_itemColumn<String>('pod_id');
    if ($_column == null) return null;
    final manager = $$PodsTableTableManager(
      $_db,
      $_db.pods,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_podIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$CaptureKidsTable, List<CaptureKid>>
  _captureKidsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.captureKids,
    aliasName: $_aliasNameGenerator(db.kids.id, db.captureKids.kidId),
  );

  $$CaptureKidsTableProcessedTableManager get captureKidsRefs {
    final manager = $$CaptureKidsTableTableManager(
      $_db,
      $_db.captureKids,
    ).filter((f) => f.kidId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_captureKidsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ObservationsTable, List<Observation>>
  _observationsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.observations,
    aliasName: $_aliasNameGenerator(db.kids.id, db.observations.kidId),
  );

  $$ObservationsTableProcessedTableManager get observationsRefs {
    final manager = $$ObservationsTableTableManager(
      $_db,
      $_db.observations,
    ).filter((f) => f.kidId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_observationsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ObservationKidsTable, List<ObservationKid>>
  _observationKidsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.observationKids,
    aliasName: $_aliasNameGenerator(db.kids.id, db.observationKids.kidId),
  );

  $$ObservationKidsTableProcessedTableManager get observationKidsRefs {
    final manager = $$ObservationKidsTableTableManager(
      $_db,
      $_db.observationKids,
    ).filter((f) => f.kidId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _observationKidsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$KidsTableFilterComposer extends Composer<_$AppDatabase, $KidsTable> {
  $$KidsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get birthDate => $composableBuilder(
    column: $table.birthDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pin => $composableBuilder(
    column: $table.pin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentName => $composableBuilder(
    column: $table.parentName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarPath => $composableBuilder(
    column: $table.avatarPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PodsTableFilterComposer get podId {
    final $$PodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.podId,
      referencedTable: $db.pods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PodsTableFilterComposer(
            $db: $db,
            $table: $db.pods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> captureKidsRefs(
    Expression<bool> Function($$CaptureKidsTableFilterComposer f) f,
  ) {
    final $$CaptureKidsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.captureKids,
      getReferencedColumn: (t) => t.kidId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CaptureKidsTableFilterComposer(
            $db: $db,
            $table: $db.captureKids,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> observationsRefs(
    Expression<bool> Function($$ObservationsTableFilterComposer f) f,
  ) {
    final $$ObservationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.observations,
      getReferencedColumn: (t) => t.kidId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationsTableFilterComposer(
            $db: $db,
            $table: $db.observations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> observationKidsRefs(
    Expression<bool> Function($$ObservationKidsTableFilterComposer f) f,
  ) {
    final $$ObservationKidsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.observationKids,
      getReferencedColumn: (t) => t.kidId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationKidsTableFilterComposer(
            $db: $db,
            $table: $db.observationKids,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$KidsTableOrderingComposer extends Composer<_$AppDatabase, $KidsTable> {
  $$KidsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get birthDate => $composableBuilder(
    column: $table.birthDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pin => $composableBuilder(
    column: $table.pin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentName => $composableBuilder(
    column: $table.parentName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarPath => $composableBuilder(
    column: $table.avatarPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PodsTableOrderingComposer get podId {
    final $$PodsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.podId,
      referencedTable: $db.pods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PodsTableOrderingComposer(
            $db: $db,
            $table: $db.pods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$KidsTableAnnotationComposer
    extends Composer<_$AppDatabase, $KidsTable> {
  $$KidsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get firstName =>
      $composableBuilder(column: $table.firstName, builder: (column) => column);

  GeneratedColumn<String> get lastName =>
      $composableBuilder(column: $table.lastName, builder: (column) => column);

  GeneratedColumn<DateTime> get birthDate =>
      $composableBuilder(column: $table.birthDate, builder: (column) => column);

  GeneratedColumn<String> get pin =>
      $composableBuilder(column: $table.pin, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get parentName => $composableBuilder(
    column: $table.parentName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get avatarPath => $composableBuilder(
    column: $table.avatarPath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$PodsTableAnnotationComposer get podId {
    final $$PodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.podId,
      referencedTable: $db.pods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PodsTableAnnotationComposer(
            $db: $db,
            $table: $db.pods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> captureKidsRefs<T extends Object>(
    Expression<T> Function($$CaptureKidsTableAnnotationComposer a) f,
  ) {
    final $$CaptureKidsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.captureKids,
      getReferencedColumn: (t) => t.kidId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CaptureKidsTableAnnotationComposer(
            $db: $db,
            $table: $db.captureKids,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> observationsRefs<T extends Object>(
    Expression<T> Function($$ObservationsTableAnnotationComposer a) f,
  ) {
    final $$ObservationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.observations,
      getReferencedColumn: (t) => t.kidId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationsTableAnnotationComposer(
            $db: $db,
            $table: $db.observations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> observationKidsRefs<T extends Object>(
    Expression<T> Function($$ObservationKidsTableAnnotationComposer a) f,
  ) {
    final $$ObservationKidsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.observationKids,
      getReferencedColumn: (t) => t.kidId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationKidsTableAnnotationComposer(
            $db: $db,
            $table: $db.observationKids,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$KidsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KidsTable,
          Kid,
          $$KidsTableFilterComposer,
          $$KidsTableOrderingComposer,
          $$KidsTableAnnotationComposer,
          $$KidsTableCreateCompanionBuilder,
          $$KidsTableUpdateCompanionBuilder,
          (Kid, $$KidsTableReferences),
          Kid,
          PrefetchHooks Function({
            bool podId,
            bool captureKidsRefs,
            bool observationsRefs,
            bool observationKidsRefs,
          })
        > {
  $$KidsTableTableManager(_$AppDatabase db, $KidsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KidsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KidsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KidsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> firstName = const Value.absent(),
                Value<String?> lastName = const Value.absent(),
                Value<String?> podId = const Value.absent(),
                Value<DateTime?> birthDate = const Value.absent(),
                Value<String?> pin = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> parentName = const Value.absent(),
                Value<String?> avatarPath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KidsCompanion(
                id: id,
                firstName: firstName,
                lastName: lastName,
                podId: podId,
                birthDate: birthDate,
                pin: pin,
                notes: notes,
                parentName: parentName,
                avatarPath: avatarPath,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String firstName,
                Value<String?> lastName = const Value.absent(),
                Value<String?> podId = const Value.absent(),
                Value<DateTime?> birthDate = const Value.absent(),
                Value<String?> pin = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> parentName = const Value.absent(),
                Value<String?> avatarPath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KidsCompanion.insert(
                id: id,
                firstName: firstName,
                lastName: lastName,
                podId: podId,
                birthDate: birthDate,
                pin: pin,
                notes: notes,
                parentName: parentName,
                avatarPath: avatarPath,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$KidsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                podId = false,
                captureKidsRefs = false,
                observationsRefs = false,
                observationKidsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (captureKidsRefs) db.captureKids,
                    if (observationsRefs) db.observations,
                    if (observationKidsRefs) db.observationKids,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (podId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.podId,
                                    referencedTable: $$KidsTableReferences
                                        ._podIdTable(db),
                                    referencedColumn: $$KidsTableReferences
                                        ._podIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (captureKidsRefs)
                        await $_getPrefetchedData<Kid, $KidsTable, CaptureKid>(
                          currentTable: table,
                          referencedTable: $$KidsTableReferences
                              ._captureKidsRefsTable(db),
                          managerFromTypedResult: (p0) => $$KidsTableReferences(
                            db,
                            table,
                            p0,
                          ).captureKidsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.kidId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (observationsRefs)
                        await $_getPrefetchedData<Kid, $KidsTable, Observation>(
                          currentTable: table,
                          referencedTable: $$KidsTableReferences
                              ._observationsRefsTable(db),
                          managerFromTypedResult: (p0) => $$KidsTableReferences(
                            db,
                            table,
                            p0,
                          ).observationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.kidId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (observationKidsRefs)
                        await $_getPrefetchedData<
                          Kid,
                          $KidsTable,
                          ObservationKid
                        >(
                          currentTable: table,
                          referencedTable: $$KidsTableReferences
                              ._observationKidsRefsTable(db),
                          managerFromTypedResult: (p0) => $$KidsTableReferences(
                            db,
                            table,
                            p0,
                          ).observationKidsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.kidId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$KidsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KidsTable,
      Kid,
      $$KidsTableFilterComposer,
      $$KidsTableOrderingComposer,
      $$KidsTableAnnotationComposer,
      $$KidsTableCreateCompanionBuilder,
      $$KidsTableUpdateCompanionBuilder,
      (Kid, $$KidsTableReferences),
      Kid,
      PrefetchHooks Function({
        bool podId,
        bool captureKidsRefs,
        bool observationsRefs,
        bool observationKidsRefs,
      })
    >;
typedef $$TripsTableCreateCompanionBuilder =
    TripsCompanion Function({
      required String id,
      required String name,
      required DateTime date,
      Value<DateTime?> endDate,
      Value<String?> location,
      Value<String?> notes,
      Value<String?> departureTime,
      Value<String?> returnTime,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$TripsTableUpdateCompanionBuilder =
    TripsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<DateTime> date,
      Value<DateTime?> endDate,
      Value<String?> location,
      Value<String?> notes,
      Value<String?> departureTime,
      Value<String?> returnTime,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$TripsTableReferences
    extends BaseReferences<_$AppDatabase, $TripsTable, Trip> {
  $$TripsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TripPodsTable, List<TripPod>> _tripPodsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.tripPods,
    aliasName: $_aliasNameGenerator(db.trips.id, db.tripPods.tripId),
  );

  $$TripPodsTableProcessedTableManager get tripPodsRefs {
    final manager = $$TripPodsTableTableManager(
      $_db,
      $_db.tripPods,
    ).filter((f) => f.tripId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_tripPodsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CapturesTable, List<Capture>> _capturesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.captures,
    aliasName: $_aliasNameGenerator(db.trips.id, db.captures.tripId),
  );

  $$CapturesTableProcessedTableManager get capturesRefs {
    final manager = $$CapturesTableTableManager(
      $_db,
      $_db.captures,
    ).filter((f) => f.tripId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_capturesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ObservationsTable, List<Observation>>
  _observationsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.observations,
    aliasName: $_aliasNameGenerator(db.trips.id, db.observations.tripId),
  );

  $$ObservationsTableProcessedTableManager get observationsRefs {
    final manager = $$ObservationsTableTableManager(
      $_db,
      $_db.observations,
    ).filter((f) => f.tripId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_observationsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ScheduleEntriesTable, List<ScheduleEntry>>
  _scheduleEntriesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.scheduleEntries,
    aliasName: $_aliasNameGenerator(
      db.trips.id,
      db.scheduleEntries.sourceTripId,
    ),
  );

  $$ScheduleEntriesTableProcessedTableManager get scheduleEntriesRefs {
    final manager = $$ScheduleEntriesTableTableManager(
      $_db,
      $_db.scheduleEntries,
    ).filter((f) => f.sourceTripId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _scheduleEntriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TripsTableFilterComposer extends Composer<_$AppDatabase, $TripsTable> {
  $$TripsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get departureTime => $composableBuilder(
    column: $table.departureTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get returnTime => $composableBuilder(
    column: $table.returnTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> tripPodsRefs(
    Expression<bool> Function($$TripPodsTableFilterComposer f) f,
  ) {
    final $$TripPodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tripPods,
      getReferencedColumn: (t) => t.tripId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TripPodsTableFilterComposer(
            $db: $db,
            $table: $db.tripPods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> capturesRefs(
    Expression<bool> Function($$CapturesTableFilterComposer f) f,
  ) {
    final $$CapturesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.captures,
      getReferencedColumn: (t) => t.tripId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CapturesTableFilterComposer(
            $db: $db,
            $table: $db.captures,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> observationsRefs(
    Expression<bool> Function($$ObservationsTableFilterComposer f) f,
  ) {
    final $$ObservationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.observations,
      getReferencedColumn: (t) => t.tripId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationsTableFilterComposer(
            $db: $db,
            $table: $db.observations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> scheduleEntriesRefs(
    Expression<bool> Function($$ScheduleEntriesTableFilterComposer f) f,
  ) {
    final $$ScheduleEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scheduleEntries,
      getReferencedColumn: (t) => t.sourceTripId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScheduleEntriesTableFilterComposer(
            $db: $db,
            $table: $db.scheduleEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TripsTableOrderingComposer
    extends Composer<_$AppDatabase, $TripsTable> {
  $$TripsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get departureTime => $composableBuilder(
    column: $table.departureTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get returnTime => $composableBuilder(
    column: $table.returnTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TripsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TripsTable> {
  $$TripsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<DateTime> get endDate =>
      $composableBuilder(column: $table.endDate, builder: (column) => column);

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get departureTime => $composableBuilder(
    column: $table.departureTime,
    builder: (column) => column,
  );

  GeneratedColumn<String> get returnTime => $composableBuilder(
    column: $table.returnTime,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> tripPodsRefs<T extends Object>(
    Expression<T> Function($$TripPodsTableAnnotationComposer a) f,
  ) {
    final $$TripPodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tripPods,
      getReferencedColumn: (t) => t.tripId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TripPodsTableAnnotationComposer(
            $db: $db,
            $table: $db.tripPods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> capturesRefs<T extends Object>(
    Expression<T> Function($$CapturesTableAnnotationComposer a) f,
  ) {
    final $$CapturesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.captures,
      getReferencedColumn: (t) => t.tripId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CapturesTableAnnotationComposer(
            $db: $db,
            $table: $db.captures,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> observationsRefs<T extends Object>(
    Expression<T> Function($$ObservationsTableAnnotationComposer a) f,
  ) {
    final $$ObservationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.observations,
      getReferencedColumn: (t) => t.tripId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationsTableAnnotationComposer(
            $db: $db,
            $table: $db.observations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> scheduleEntriesRefs<T extends Object>(
    Expression<T> Function($$ScheduleEntriesTableAnnotationComposer a) f,
  ) {
    final $$ScheduleEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scheduleEntries,
      getReferencedColumn: (t) => t.sourceTripId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScheduleEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.scheduleEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TripsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TripsTable,
          Trip,
          $$TripsTableFilterComposer,
          $$TripsTableOrderingComposer,
          $$TripsTableAnnotationComposer,
          $$TripsTableCreateCompanionBuilder,
          $$TripsTableUpdateCompanionBuilder,
          (Trip, $$TripsTableReferences),
          Trip,
          PrefetchHooks Function({
            bool tripPodsRefs,
            bool capturesRefs,
            bool observationsRefs,
            bool scheduleEntriesRefs,
          })
        > {
  $$TripsTableTableManager(_$AppDatabase db, $TripsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TripsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TripsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TripsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<DateTime?> endDate = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> departureTime = const Value.absent(),
                Value<String?> returnTime = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TripsCompanion(
                id: id,
                name: name,
                date: date,
                endDate: endDate,
                location: location,
                notes: notes,
                departureTime: departureTime,
                returnTime: returnTime,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required DateTime date,
                Value<DateTime?> endDate = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> departureTime = const Value.absent(),
                Value<String?> returnTime = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TripsCompanion.insert(
                id: id,
                name: name,
                date: date,
                endDate: endDate,
                location: location,
                notes: notes,
                departureTime: departureTime,
                returnTime: returnTime,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$TripsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                tripPodsRefs = false,
                capturesRefs = false,
                observationsRefs = false,
                scheduleEntriesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (tripPodsRefs) db.tripPods,
                    if (capturesRefs) db.captures,
                    if (observationsRefs) db.observations,
                    if (scheduleEntriesRefs) db.scheduleEntries,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (tripPodsRefs)
                        await $_getPrefetchedData<Trip, $TripsTable, TripPod>(
                          currentTable: table,
                          referencedTable: $$TripsTableReferences
                              ._tripPodsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TripsTableReferences(
                                db,
                                table,
                                p0,
                              ).tripPodsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.tripId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (capturesRefs)
                        await $_getPrefetchedData<Trip, $TripsTable, Capture>(
                          currentTable: table,
                          referencedTable: $$TripsTableReferences
                              ._capturesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TripsTableReferences(
                                db,
                                table,
                                p0,
                              ).capturesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.tripId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (observationsRefs)
                        await $_getPrefetchedData<
                          Trip,
                          $TripsTable,
                          Observation
                        >(
                          currentTable: table,
                          referencedTable: $$TripsTableReferences
                              ._observationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TripsTableReferences(
                                db,
                                table,
                                p0,
                              ).observationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.tripId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (scheduleEntriesRefs)
                        await $_getPrefetchedData<
                          Trip,
                          $TripsTable,
                          ScheduleEntry
                        >(
                          currentTable: table,
                          referencedTable: $$TripsTableReferences
                              ._scheduleEntriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TripsTableReferences(
                                db,
                                table,
                                p0,
                              ).scheduleEntriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sourceTripId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$TripsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TripsTable,
      Trip,
      $$TripsTableFilterComposer,
      $$TripsTableOrderingComposer,
      $$TripsTableAnnotationComposer,
      $$TripsTableCreateCompanionBuilder,
      $$TripsTableUpdateCompanionBuilder,
      (Trip, $$TripsTableReferences),
      Trip,
      PrefetchHooks Function({
        bool tripPodsRefs,
        bool capturesRefs,
        bool observationsRefs,
        bool scheduleEntriesRefs,
      })
    >;
typedef $$TripPodsTableCreateCompanionBuilder =
    TripPodsCompanion Function({
      required String tripId,
      required String podId,
      Value<int> rowid,
    });
typedef $$TripPodsTableUpdateCompanionBuilder =
    TripPodsCompanion Function({
      Value<String> tripId,
      Value<String> podId,
      Value<int> rowid,
    });

final class $$TripPodsTableReferences
    extends BaseReferences<_$AppDatabase, $TripPodsTable, TripPod> {
  $$TripPodsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TripsTable _tripIdTable(_$AppDatabase db) => db.trips.createAlias(
    $_aliasNameGenerator(db.tripPods.tripId, db.trips.id),
  );

  $$TripsTableProcessedTableManager get tripId {
    final $_column = $_itemColumn<String>('trip_id')!;

    final manager = $$TripsTableTableManager(
      $_db,
      $_db.trips,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_tripIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $PodsTable _podIdTable(_$AppDatabase db) =>
      db.pods.createAlias($_aliasNameGenerator(db.tripPods.podId, db.pods.id));

  $$PodsTableProcessedTableManager get podId {
    final $_column = $_itemColumn<String>('pod_id')!;

    final manager = $$PodsTableTableManager(
      $_db,
      $_db.pods,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_podIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TripPodsTableFilterComposer
    extends Composer<_$AppDatabase, $TripPodsTable> {
  $$TripPodsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$TripsTableFilterComposer get tripId {
    final $$TripsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tripId,
      referencedTable: $db.trips,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TripsTableFilterComposer(
            $db: $db,
            $table: $db.trips,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PodsTableFilterComposer get podId {
    final $$PodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.podId,
      referencedTable: $db.pods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PodsTableFilterComposer(
            $db: $db,
            $table: $db.pods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TripPodsTableOrderingComposer
    extends Composer<_$AppDatabase, $TripPodsTable> {
  $$TripPodsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$TripsTableOrderingComposer get tripId {
    final $$TripsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tripId,
      referencedTable: $db.trips,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TripsTableOrderingComposer(
            $db: $db,
            $table: $db.trips,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PodsTableOrderingComposer get podId {
    final $$PodsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.podId,
      referencedTable: $db.pods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PodsTableOrderingComposer(
            $db: $db,
            $table: $db.pods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TripPodsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TripPodsTable> {
  $$TripPodsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$TripsTableAnnotationComposer get tripId {
    final $$TripsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tripId,
      referencedTable: $db.trips,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TripsTableAnnotationComposer(
            $db: $db,
            $table: $db.trips,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PodsTableAnnotationComposer get podId {
    final $$PodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.podId,
      referencedTable: $db.pods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PodsTableAnnotationComposer(
            $db: $db,
            $table: $db.pods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TripPodsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TripPodsTable,
          TripPod,
          $$TripPodsTableFilterComposer,
          $$TripPodsTableOrderingComposer,
          $$TripPodsTableAnnotationComposer,
          $$TripPodsTableCreateCompanionBuilder,
          $$TripPodsTableUpdateCompanionBuilder,
          (TripPod, $$TripPodsTableReferences),
          TripPod,
          PrefetchHooks Function({bool tripId, bool podId})
        > {
  $$TripPodsTableTableManager(_$AppDatabase db, $TripPodsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TripPodsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TripPodsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TripPodsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tripId = const Value.absent(),
                Value<String> podId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) =>
                  TripPodsCompanion(tripId: tripId, podId: podId, rowid: rowid),
          createCompanionCallback:
              ({
                required String tripId,
                required String podId,
                Value<int> rowid = const Value.absent(),
              }) => TripPodsCompanion.insert(
                tripId: tripId,
                podId: podId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TripPodsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({tripId = false, podId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (tripId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.tripId,
                                referencedTable: $$TripPodsTableReferences
                                    ._tripIdTable(db),
                                referencedColumn: $$TripPodsTableReferences
                                    ._tripIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (podId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.podId,
                                referencedTable: $$TripPodsTableReferences
                                    ._podIdTable(db),
                                referencedColumn: $$TripPodsTableReferences
                                    ._podIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TripPodsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TripPodsTable,
      TripPod,
      $$TripPodsTableFilterComposer,
      $$TripPodsTableOrderingComposer,
      $$TripPodsTableAnnotationComposer,
      $$TripPodsTableCreateCompanionBuilder,
      $$TripPodsTableUpdateCompanionBuilder,
      (TripPod, $$TripPodsTableReferences),
      TripPod,
      PrefetchHooks Function({bool tripId, bool podId})
    >;
typedef $$CapturesTableCreateCompanionBuilder =
    CapturesCompanion Function({
      required String id,
      required String kind,
      Value<String?> caption,
      Value<String?> imagePath,
      Value<String?> tripId,
      Value<String?> authorName,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$CapturesTableUpdateCompanionBuilder =
    CapturesCompanion Function({
      Value<String> id,
      Value<String> kind,
      Value<String?> caption,
      Value<String?> imagePath,
      Value<String?> tripId,
      Value<String?> authorName,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$CapturesTableReferences
    extends BaseReferences<_$AppDatabase, $CapturesTable, Capture> {
  $$CapturesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TripsTable _tripIdTable(_$AppDatabase db) => db.trips.createAlias(
    $_aliasNameGenerator(db.captures.tripId, db.trips.id),
  );

  $$TripsTableProcessedTableManager? get tripId {
    final $_column = $_itemColumn<String>('trip_id');
    if ($_column == null) return null;
    final manager = $$TripsTableTableManager(
      $_db,
      $_db.trips,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_tripIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$CaptureKidsTable, List<CaptureKid>>
  _captureKidsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.captureKids,
    aliasName: $_aliasNameGenerator(db.captures.id, db.captureKids.captureId),
  );

  $$CaptureKidsTableProcessedTableManager get captureKidsRefs {
    final manager = $$CaptureKidsTableTableManager(
      $_db,
      $_db.captureKids,
    ).filter((f) => f.captureId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_captureKidsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CapturesTableFilterComposer
    extends Composer<_$AppDatabase, $CapturesTable> {
  $$CapturesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get caption => $composableBuilder(
    column: $table.caption,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorName => $composableBuilder(
    column: $table.authorName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$TripsTableFilterComposer get tripId {
    final $$TripsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tripId,
      referencedTable: $db.trips,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TripsTableFilterComposer(
            $db: $db,
            $table: $db.trips,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> captureKidsRefs(
    Expression<bool> Function($$CaptureKidsTableFilterComposer f) f,
  ) {
    final $$CaptureKidsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.captureKids,
      getReferencedColumn: (t) => t.captureId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CaptureKidsTableFilterComposer(
            $db: $db,
            $table: $db.captureKids,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CapturesTableOrderingComposer
    extends Composer<_$AppDatabase, $CapturesTable> {
  $$CapturesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get caption => $composableBuilder(
    column: $table.caption,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorName => $composableBuilder(
    column: $table.authorName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$TripsTableOrderingComposer get tripId {
    final $$TripsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tripId,
      referencedTable: $db.trips,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TripsTableOrderingComposer(
            $db: $db,
            $table: $db.trips,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CapturesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CapturesTable> {
  $$CapturesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get caption =>
      $composableBuilder(column: $table.caption, builder: (column) => column);

  GeneratedColumn<String> get imagePath =>
      $composableBuilder(column: $table.imagePath, builder: (column) => column);

  GeneratedColumn<String> get authorName => $composableBuilder(
    column: $table.authorName,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$TripsTableAnnotationComposer get tripId {
    final $$TripsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tripId,
      referencedTable: $db.trips,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TripsTableAnnotationComposer(
            $db: $db,
            $table: $db.trips,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> captureKidsRefs<T extends Object>(
    Expression<T> Function($$CaptureKidsTableAnnotationComposer a) f,
  ) {
    final $$CaptureKidsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.captureKids,
      getReferencedColumn: (t) => t.captureId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CaptureKidsTableAnnotationComposer(
            $db: $db,
            $table: $db.captureKids,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CapturesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CapturesTable,
          Capture,
          $$CapturesTableFilterComposer,
          $$CapturesTableOrderingComposer,
          $$CapturesTableAnnotationComposer,
          $$CapturesTableCreateCompanionBuilder,
          $$CapturesTableUpdateCompanionBuilder,
          (Capture, $$CapturesTableReferences),
          Capture,
          PrefetchHooks Function({bool tripId, bool captureKidsRefs})
        > {
  $$CapturesTableTableManager(_$AppDatabase db, $CapturesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CapturesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CapturesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CapturesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> caption = const Value.absent(),
                Value<String?> imagePath = const Value.absent(),
                Value<String?> tripId = const Value.absent(),
                Value<String?> authorName = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CapturesCompanion(
                id: id,
                kind: kind,
                caption: caption,
                imagePath: imagePath,
                tripId: tripId,
                authorName: authorName,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String kind,
                Value<String?> caption = const Value.absent(),
                Value<String?> imagePath = const Value.absent(),
                Value<String?> tripId = const Value.absent(),
                Value<String?> authorName = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CapturesCompanion.insert(
                id: id,
                kind: kind,
                caption: caption,
                imagePath: imagePath,
                tripId: tripId,
                authorName: authorName,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CapturesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({tripId = false, captureKidsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (captureKidsRefs) db.captureKids],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (tripId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.tripId,
                                referencedTable: $$CapturesTableReferences
                                    ._tripIdTable(db),
                                referencedColumn: $$CapturesTableReferences
                                    ._tripIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (captureKidsRefs)
                    await $_getPrefetchedData<
                      Capture,
                      $CapturesTable,
                      CaptureKid
                    >(
                      currentTable: table,
                      referencedTable: $$CapturesTableReferences
                          ._captureKidsRefsTable(db),
                      managerFromTypedResult: (p0) => $$CapturesTableReferences(
                        db,
                        table,
                        p0,
                      ).captureKidsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.captureId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CapturesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CapturesTable,
      Capture,
      $$CapturesTableFilterComposer,
      $$CapturesTableOrderingComposer,
      $$CapturesTableAnnotationComposer,
      $$CapturesTableCreateCompanionBuilder,
      $$CapturesTableUpdateCompanionBuilder,
      (Capture, $$CapturesTableReferences),
      Capture,
      PrefetchHooks Function({bool tripId, bool captureKidsRefs})
    >;
typedef $$CaptureKidsTableCreateCompanionBuilder =
    CaptureKidsCompanion Function({
      required String captureId,
      required String kidId,
      Value<int> rowid,
    });
typedef $$CaptureKidsTableUpdateCompanionBuilder =
    CaptureKidsCompanion Function({
      Value<String> captureId,
      Value<String> kidId,
      Value<int> rowid,
    });

final class $$CaptureKidsTableReferences
    extends BaseReferences<_$AppDatabase, $CaptureKidsTable, CaptureKid> {
  $$CaptureKidsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CapturesTable _captureIdTable(_$AppDatabase db) =>
      db.captures.createAlias(
        $_aliasNameGenerator(db.captureKids.captureId, db.captures.id),
      );

  $$CapturesTableProcessedTableManager get captureId {
    final $_column = $_itemColumn<String>('capture_id')!;

    final manager = $$CapturesTableTableManager(
      $_db,
      $_db.captures,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_captureIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $KidsTable _kidIdTable(_$AppDatabase db) => db.kids.createAlias(
    $_aliasNameGenerator(db.captureKids.kidId, db.kids.id),
  );

  $$KidsTableProcessedTableManager get kidId {
    final $_column = $_itemColumn<String>('kid_id')!;

    final manager = $$KidsTableTableManager(
      $_db,
      $_db.kids,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_kidIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CaptureKidsTableFilterComposer
    extends Composer<_$AppDatabase, $CaptureKidsTable> {
  $$CaptureKidsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$CapturesTableFilterComposer get captureId {
    final $$CapturesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.captureId,
      referencedTable: $db.captures,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CapturesTableFilterComposer(
            $db: $db,
            $table: $db.captures,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$KidsTableFilterComposer get kidId {
    final $$KidsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.kidId,
      referencedTable: $db.kids,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KidsTableFilterComposer(
            $db: $db,
            $table: $db.kids,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CaptureKidsTableOrderingComposer
    extends Composer<_$AppDatabase, $CaptureKidsTable> {
  $$CaptureKidsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$CapturesTableOrderingComposer get captureId {
    final $$CapturesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.captureId,
      referencedTable: $db.captures,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CapturesTableOrderingComposer(
            $db: $db,
            $table: $db.captures,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$KidsTableOrderingComposer get kidId {
    final $$KidsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.kidId,
      referencedTable: $db.kids,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KidsTableOrderingComposer(
            $db: $db,
            $table: $db.kids,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CaptureKidsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CaptureKidsTable> {
  $$CaptureKidsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$CapturesTableAnnotationComposer get captureId {
    final $$CapturesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.captureId,
      referencedTable: $db.captures,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CapturesTableAnnotationComposer(
            $db: $db,
            $table: $db.captures,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$KidsTableAnnotationComposer get kidId {
    final $$KidsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.kidId,
      referencedTable: $db.kids,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KidsTableAnnotationComposer(
            $db: $db,
            $table: $db.kids,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CaptureKidsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CaptureKidsTable,
          CaptureKid,
          $$CaptureKidsTableFilterComposer,
          $$CaptureKidsTableOrderingComposer,
          $$CaptureKidsTableAnnotationComposer,
          $$CaptureKidsTableCreateCompanionBuilder,
          $$CaptureKidsTableUpdateCompanionBuilder,
          (CaptureKid, $$CaptureKidsTableReferences),
          CaptureKid,
          PrefetchHooks Function({bool captureId, bool kidId})
        > {
  $$CaptureKidsTableTableManager(_$AppDatabase db, $CaptureKidsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CaptureKidsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CaptureKidsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CaptureKidsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> captureId = const Value.absent(),
                Value<String> kidId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CaptureKidsCompanion(
                captureId: captureId,
                kidId: kidId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String captureId,
                required String kidId,
                Value<int> rowid = const Value.absent(),
              }) => CaptureKidsCompanion.insert(
                captureId: captureId,
                kidId: kidId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CaptureKidsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({captureId = false, kidId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (captureId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.captureId,
                                referencedTable: $$CaptureKidsTableReferences
                                    ._captureIdTable(db),
                                referencedColumn: $$CaptureKidsTableReferences
                                    ._captureIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (kidId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.kidId,
                                referencedTable: $$CaptureKidsTableReferences
                                    ._kidIdTable(db),
                                referencedColumn: $$CaptureKidsTableReferences
                                    ._kidIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CaptureKidsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CaptureKidsTable,
      CaptureKid,
      $$CaptureKidsTableFilterComposer,
      $$CaptureKidsTableOrderingComposer,
      $$CaptureKidsTableAnnotationComposer,
      $$CaptureKidsTableCreateCompanionBuilder,
      $$CaptureKidsTableUpdateCompanionBuilder,
      (CaptureKid, $$CaptureKidsTableReferences),
      CaptureKid,
      PrefetchHooks Function({bool captureId, bool kidId})
    >;
typedef $$ObservationsTableCreateCompanionBuilder =
    ObservationsCompanion Function({
      required String id,
      required String targetKind,
      Value<String?> kidId,
      Value<String?> podId,
      Value<String?> activityLabel,
      required String domain,
      required String sentiment,
      required String note,
      Value<String?> noteOriginal,
      Value<String?> tripId,
      Value<String?> authorName,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$ObservationsTableUpdateCompanionBuilder =
    ObservationsCompanion Function({
      Value<String> id,
      Value<String> targetKind,
      Value<String?> kidId,
      Value<String?> podId,
      Value<String?> activityLabel,
      Value<String> domain,
      Value<String> sentiment,
      Value<String> note,
      Value<String?> noteOriginal,
      Value<String?> tripId,
      Value<String?> authorName,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ObservationsTableReferences
    extends BaseReferences<_$AppDatabase, $ObservationsTable, Observation> {
  $$ObservationsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $KidsTable _kidIdTable(_$AppDatabase db) => db.kids.createAlias(
    $_aliasNameGenerator(db.observations.kidId, db.kids.id),
  );

  $$KidsTableProcessedTableManager? get kidId {
    final $_column = $_itemColumn<String>('kid_id');
    if ($_column == null) return null;
    final manager = $$KidsTableTableManager(
      $_db,
      $_db.kids,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_kidIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $PodsTable _podIdTable(_$AppDatabase db) => db.pods.createAlias(
    $_aliasNameGenerator(db.observations.podId, db.pods.id),
  );

  $$PodsTableProcessedTableManager? get podId {
    final $_column = $_itemColumn<String>('pod_id');
    if ($_column == null) return null;
    final manager = $$PodsTableTableManager(
      $_db,
      $_db.pods,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_podIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TripsTable _tripIdTable(_$AppDatabase db) => db.trips.createAlias(
    $_aliasNameGenerator(db.observations.tripId, db.trips.id),
  );

  $$TripsTableProcessedTableManager? get tripId {
    final $_column = $_itemColumn<String>('trip_id');
    if ($_column == null) return null;
    final manager = $$TripsTableTableManager(
      $_db,
      $_db.trips,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_tripIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ObservationKidsTable, List<ObservationKid>>
  _observationKidsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.observationKids,
    aliasName: $_aliasNameGenerator(
      db.observations.id,
      db.observationKids.observationId,
    ),
  );

  $$ObservationKidsTableProcessedTableManager get observationKidsRefs {
    final manager = $$ObservationKidsTableTableManager(
      $_db,
      $_db.observationKids,
    ).filter((f) => f.observationId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _observationKidsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $ObservationAttachmentsTable,
    List<ObservationAttachment>
  >
  _observationAttachmentsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.observationAttachments,
        aliasName: $_aliasNameGenerator(
          db.observations.id,
          db.observationAttachments.observationId,
        ),
      );

  $$ObservationAttachmentsTableProcessedTableManager
  get observationAttachmentsRefs {
    final manager = $$ObservationAttachmentsTableTableManager(
      $_db,
      $_db.observationAttachments,
    ).filter((f) => f.observationId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _observationAttachmentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $ObservationDomainTagsTable,
    List<ObservationDomainTag>
  >
  _observationDomainTagsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.observationDomainTags,
        aliasName: $_aliasNameGenerator(
          db.observations.id,
          db.observationDomainTags.observationId,
        ),
      );

  $$ObservationDomainTagsTableProcessedTableManager
  get observationDomainTagsRefs {
    final manager = $$ObservationDomainTagsTableTableManager(
      $_db,
      $_db.observationDomainTags,
    ).filter((f) => f.observationId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _observationDomainTagsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ObservationsTableFilterComposer
    extends Composer<_$AppDatabase, $ObservationsTable> {
  $$ObservationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetKind => $composableBuilder(
    column: $table.targetKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get activityLabel => $composableBuilder(
    column: $table.activityLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get domain => $composableBuilder(
    column: $table.domain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sentiment => $composableBuilder(
    column: $table.sentiment,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteOriginal => $composableBuilder(
    column: $table.noteOriginal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorName => $composableBuilder(
    column: $table.authorName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$KidsTableFilterComposer get kidId {
    final $$KidsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.kidId,
      referencedTable: $db.kids,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KidsTableFilterComposer(
            $db: $db,
            $table: $db.kids,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PodsTableFilterComposer get podId {
    final $$PodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.podId,
      referencedTable: $db.pods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PodsTableFilterComposer(
            $db: $db,
            $table: $db.pods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TripsTableFilterComposer get tripId {
    final $$TripsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tripId,
      referencedTable: $db.trips,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TripsTableFilterComposer(
            $db: $db,
            $table: $db.trips,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> observationKidsRefs(
    Expression<bool> Function($$ObservationKidsTableFilterComposer f) f,
  ) {
    final $$ObservationKidsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.observationKids,
      getReferencedColumn: (t) => t.observationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationKidsTableFilterComposer(
            $db: $db,
            $table: $db.observationKids,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> observationAttachmentsRefs(
    Expression<bool> Function($$ObservationAttachmentsTableFilterComposer f) f,
  ) {
    final $$ObservationAttachmentsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.observationAttachments,
          getReferencedColumn: (t) => t.observationId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ObservationAttachmentsTableFilterComposer(
                $db: $db,
                $table: $db.observationAttachments,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> observationDomainTagsRefs(
    Expression<bool> Function($$ObservationDomainTagsTableFilterComposer f) f,
  ) {
    final $$ObservationDomainTagsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.observationDomainTags,
          getReferencedColumn: (t) => t.observationId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ObservationDomainTagsTableFilterComposer(
                $db: $db,
                $table: $db.observationDomainTags,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ObservationsTableOrderingComposer
    extends Composer<_$AppDatabase, $ObservationsTable> {
  $$ObservationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetKind => $composableBuilder(
    column: $table.targetKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get activityLabel => $composableBuilder(
    column: $table.activityLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get domain => $composableBuilder(
    column: $table.domain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sentiment => $composableBuilder(
    column: $table.sentiment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteOriginal => $composableBuilder(
    column: $table.noteOriginal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorName => $composableBuilder(
    column: $table.authorName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$KidsTableOrderingComposer get kidId {
    final $$KidsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.kidId,
      referencedTable: $db.kids,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KidsTableOrderingComposer(
            $db: $db,
            $table: $db.kids,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PodsTableOrderingComposer get podId {
    final $$PodsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.podId,
      referencedTable: $db.pods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PodsTableOrderingComposer(
            $db: $db,
            $table: $db.pods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TripsTableOrderingComposer get tripId {
    final $$TripsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tripId,
      referencedTable: $db.trips,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TripsTableOrderingComposer(
            $db: $db,
            $table: $db.trips,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ObservationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ObservationsTable> {
  $$ObservationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get targetKind => $composableBuilder(
    column: $table.targetKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get activityLabel => $composableBuilder(
    column: $table.activityLabel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get domain =>
      $composableBuilder(column: $table.domain, builder: (column) => column);

  GeneratedColumn<String> get sentiment =>
      $composableBuilder(column: $table.sentiment, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get noteOriginal => $composableBuilder(
    column: $table.noteOriginal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get authorName => $composableBuilder(
    column: $table.authorName,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$KidsTableAnnotationComposer get kidId {
    final $$KidsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.kidId,
      referencedTable: $db.kids,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KidsTableAnnotationComposer(
            $db: $db,
            $table: $db.kids,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PodsTableAnnotationComposer get podId {
    final $$PodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.podId,
      referencedTable: $db.pods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PodsTableAnnotationComposer(
            $db: $db,
            $table: $db.pods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TripsTableAnnotationComposer get tripId {
    final $$TripsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tripId,
      referencedTable: $db.trips,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TripsTableAnnotationComposer(
            $db: $db,
            $table: $db.trips,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> observationKidsRefs<T extends Object>(
    Expression<T> Function($$ObservationKidsTableAnnotationComposer a) f,
  ) {
    final $$ObservationKidsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.observationKids,
      getReferencedColumn: (t) => t.observationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationKidsTableAnnotationComposer(
            $db: $db,
            $table: $db.observationKids,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> observationAttachmentsRefs<T extends Object>(
    Expression<T> Function($$ObservationAttachmentsTableAnnotationComposer a) f,
  ) {
    final $$ObservationAttachmentsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.observationAttachments,
          getReferencedColumn: (t) => t.observationId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ObservationAttachmentsTableAnnotationComposer(
                $db: $db,
                $table: $db.observationAttachments,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> observationDomainTagsRefs<T extends Object>(
    Expression<T> Function($$ObservationDomainTagsTableAnnotationComposer a) f,
  ) {
    final $$ObservationDomainTagsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.observationDomainTags,
          getReferencedColumn: (t) => t.observationId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ObservationDomainTagsTableAnnotationComposer(
                $db: $db,
                $table: $db.observationDomainTags,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ObservationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ObservationsTable,
          Observation,
          $$ObservationsTableFilterComposer,
          $$ObservationsTableOrderingComposer,
          $$ObservationsTableAnnotationComposer,
          $$ObservationsTableCreateCompanionBuilder,
          $$ObservationsTableUpdateCompanionBuilder,
          (Observation, $$ObservationsTableReferences),
          Observation,
          PrefetchHooks Function({
            bool kidId,
            bool podId,
            bool tripId,
            bool observationKidsRefs,
            bool observationAttachmentsRefs,
            bool observationDomainTagsRefs,
          })
        > {
  $$ObservationsTableTableManager(_$AppDatabase db, $ObservationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ObservationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ObservationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ObservationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> targetKind = const Value.absent(),
                Value<String?> kidId = const Value.absent(),
                Value<String?> podId = const Value.absent(),
                Value<String?> activityLabel = const Value.absent(),
                Value<String> domain = const Value.absent(),
                Value<String> sentiment = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<String?> noteOriginal = const Value.absent(),
                Value<String?> tripId = const Value.absent(),
                Value<String?> authorName = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ObservationsCompanion(
                id: id,
                targetKind: targetKind,
                kidId: kidId,
                podId: podId,
                activityLabel: activityLabel,
                domain: domain,
                sentiment: sentiment,
                note: note,
                noteOriginal: noteOriginal,
                tripId: tripId,
                authorName: authorName,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String targetKind,
                Value<String?> kidId = const Value.absent(),
                Value<String?> podId = const Value.absent(),
                Value<String?> activityLabel = const Value.absent(),
                required String domain,
                required String sentiment,
                required String note,
                Value<String?> noteOriginal = const Value.absent(),
                Value<String?> tripId = const Value.absent(),
                Value<String?> authorName = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ObservationsCompanion.insert(
                id: id,
                targetKind: targetKind,
                kidId: kidId,
                podId: podId,
                activityLabel: activityLabel,
                domain: domain,
                sentiment: sentiment,
                note: note,
                noteOriginal: noteOriginal,
                tripId: tripId,
                authorName: authorName,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ObservationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                kidId = false,
                podId = false,
                tripId = false,
                observationKidsRefs = false,
                observationAttachmentsRefs = false,
                observationDomainTagsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (observationKidsRefs) db.observationKids,
                    if (observationAttachmentsRefs) db.observationAttachments,
                    if (observationDomainTagsRefs) db.observationDomainTags,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (kidId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.kidId,
                                    referencedTable:
                                        $$ObservationsTableReferences
                                            ._kidIdTable(db),
                                    referencedColumn:
                                        $$ObservationsTableReferences
                                            ._kidIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (podId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.podId,
                                    referencedTable:
                                        $$ObservationsTableReferences
                                            ._podIdTable(db),
                                    referencedColumn:
                                        $$ObservationsTableReferences
                                            ._podIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (tripId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.tripId,
                                    referencedTable:
                                        $$ObservationsTableReferences
                                            ._tripIdTable(db),
                                    referencedColumn:
                                        $$ObservationsTableReferences
                                            ._tripIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (observationKidsRefs)
                        await $_getPrefetchedData<
                          Observation,
                          $ObservationsTable,
                          ObservationKid
                        >(
                          currentTable: table,
                          referencedTable: $$ObservationsTableReferences
                              ._observationKidsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ObservationsTableReferences(
                                db,
                                table,
                                p0,
                              ).observationKidsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.observationId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (observationAttachmentsRefs)
                        await $_getPrefetchedData<
                          Observation,
                          $ObservationsTable,
                          ObservationAttachment
                        >(
                          currentTable: table,
                          referencedTable: $$ObservationsTableReferences
                              ._observationAttachmentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ObservationsTableReferences(
                                db,
                                table,
                                p0,
                              ).observationAttachmentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.observationId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (observationDomainTagsRefs)
                        await $_getPrefetchedData<
                          Observation,
                          $ObservationsTable,
                          ObservationDomainTag
                        >(
                          currentTable: table,
                          referencedTable: $$ObservationsTableReferences
                              ._observationDomainTagsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ObservationsTableReferences(
                                db,
                                table,
                                p0,
                              ).observationDomainTagsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.observationId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ObservationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ObservationsTable,
      Observation,
      $$ObservationsTableFilterComposer,
      $$ObservationsTableOrderingComposer,
      $$ObservationsTableAnnotationComposer,
      $$ObservationsTableCreateCompanionBuilder,
      $$ObservationsTableUpdateCompanionBuilder,
      (Observation, $$ObservationsTableReferences),
      Observation,
      PrefetchHooks Function({
        bool kidId,
        bool podId,
        bool tripId,
        bool observationKidsRefs,
        bool observationAttachmentsRefs,
        bool observationDomainTagsRefs,
      })
    >;
typedef $$ObservationKidsTableCreateCompanionBuilder =
    ObservationKidsCompanion Function({
      required String observationId,
      required String kidId,
      Value<int> rowid,
    });
typedef $$ObservationKidsTableUpdateCompanionBuilder =
    ObservationKidsCompanion Function({
      Value<String> observationId,
      Value<String> kidId,
      Value<int> rowid,
    });

final class $$ObservationKidsTableReferences
    extends
        BaseReferences<_$AppDatabase, $ObservationKidsTable, ObservationKid> {
  $$ObservationKidsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ObservationsTable _observationIdTable(_$AppDatabase db) =>
      db.observations.createAlias(
        $_aliasNameGenerator(
          db.observationKids.observationId,
          db.observations.id,
        ),
      );

  $$ObservationsTableProcessedTableManager get observationId {
    final $_column = $_itemColumn<String>('observation_id')!;

    final manager = $$ObservationsTableTableManager(
      $_db,
      $_db.observations,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_observationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $KidsTable _kidIdTable(_$AppDatabase db) => db.kids.createAlias(
    $_aliasNameGenerator(db.observationKids.kidId, db.kids.id),
  );

  $$KidsTableProcessedTableManager get kidId {
    final $_column = $_itemColumn<String>('kid_id')!;

    final manager = $$KidsTableTableManager(
      $_db,
      $_db.kids,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_kidIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ObservationKidsTableFilterComposer
    extends Composer<_$AppDatabase, $ObservationKidsTable> {
  $$ObservationKidsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$ObservationsTableFilterComposer get observationId {
    final $$ObservationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.observationId,
      referencedTable: $db.observations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationsTableFilterComposer(
            $db: $db,
            $table: $db.observations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$KidsTableFilterComposer get kidId {
    final $$KidsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.kidId,
      referencedTable: $db.kids,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KidsTableFilterComposer(
            $db: $db,
            $table: $db.kids,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ObservationKidsTableOrderingComposer
    extends Composer<_$AppDatabase, $ObservationKidsTable> {
  $$ObservationKidsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$ObservationsTableOrderingComposer get observationId {
    final $$ObservationsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.observationId,
      referencedTable: $db.observations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationsTableOrderingComposer(
            $db: $db,
            $table: $db.observations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$KidsTableOrderingComposer get kidId {
    final $$KidsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.kidId,
      referencedTable: $db.kids,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KidsTableOrderingComposer(
            $db: $db,
            $table: $db.kids,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ObservationKidsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ObservationKidsTable> {
  $$ObservationKidsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$ObservationsTableAnnotationComposer get observationId {
    final $$ObservationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.observationId,
      referencedTable: $db.observations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationsTableAnnotationComposer(
            $db: $db,
            $table: $db.observations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$KidsTableAnnotationComposer get kidId {
    final $$KidsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.kidId,
      referencedTable: $db.kids,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KidsTableAnnotationComposer(
            $db: $db,
            $table: $db.kids,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ObservationKidsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ObservationKidsTable,
          ObservationKid,
          $$ObservationKidsTableFilterComposer,
          $$ObservationKidsTableOrderingComposer,
          $$ObservationKidsTableAnnotationComposer,
          $$ObservationKidsTableCreateCompanionBuilder,
          $$ObservationKidsTableUpdateCompanionBuilder,
          (ObservationKid, $$ObservationKidsTableReferences),
          ObservationKid,
          PrefetchHooks Function({bool observationId, bool kidId})
        > {
  $$ObservationKidsTableTableManager(
    _$AppDatabase db,
    $ObservationKidsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ObservationKidsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ObservationKidsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ObservationKidsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> observationId = const Value.absent(),
                Value<String> kidId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ObservationKidsCompanion(
                observationId: observationId,
                kidId: kidId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String observationId,
                required String kidId,
                Value<int> rowid = const Value.absent(),
              }) => ObservationKidsCompanion.insert(
                observationId: observationId,
                kidId: kidId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ObservationKidsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({observationId = false, kidId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (observationId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.observationId,
                                referencedTable:
                                    $$ObservationKidsTableReferences
                                        ._observationIdTable(db),
                                referencedColumn:
                                    $$ObservationKidsTableReferences
                                        ._observationIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (kidId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.kidId,
                                referencedTable:
                                    $$ObservationKidsTableReferences
                                        ._kidIdTable(db),
                                referencedColumn:
                                    $$ObservationKidsTableReferences
                                        ._kidIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ObservationKidsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ObservationKidsTable,
      ObservationKid,
      $$ObservationKidsTableFilterComposer,
      $$ObservationKidsTableOrderingComposer,
      $$ObservationKidsTableAnnotationComposer,
      $$ObservationKidsTableCreateCompanionBuilder,
      $$ObservationKidsTableUpdateCompanionBuilder,
      (ObservationKid, $$ObservationKidsTableReferences),
      ObservationKid,
      PrefetchHooks Function({bool observationId, bool kidId})
    >;
typedef $$ObservationAttachmentsTableCreateCompanionBuilder =
    ObservationAttachmentsCompanion Function({
      required String id,
      required String observationId,
      required String kind,
      required String localPath,
      Value<String?> remoteUrl,
      Value<String?> thumbnailPath,
      Value<int?> durationMs,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$ObservationAttachmentsTableUpdateCompanionBuilder =
    ObservationAttachmentsCompanion Function({
      Value<String> id,
      Value<String> observationId,
      Value<String> kind,
      Value<String> localPath,
      Value<String?> remoteUrl,
      Value<String?> thumbnailPath,
      Value<int?> durationMs,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$ObservationAttachmentsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ObservationAttachmentsTable,
          ObservationAttachment
        > {
  $$ObservationAttachmentsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ObservationsTable _observationIdTable(_$AppDatabase db) =>
      db.observations.createAlias(
        $_aliasNameGenerator(
          db.observationAttachments.observationId,
          db.observations.id,
        ),
      );

  $$ObservationsTableProcessedTableManager get observationId {
    final $_column = $_itemColumn<String>('observation_id')!;

    final manager = $$ObservationsTableTableManager(
      $_db,
      $_db.observations,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_observationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ObservationAttachmentsTableFilterComposer
    extends Composer<_$AppDatabase, $ObservationAttachmentsTable> {
  $$ObservationAttachmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteUrl => $composableBuilder(
    column: $table.remoteUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ObservationsTableFilterComposer get observationId {
    final $$ObservationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.observationId,
      referencedTable: $db.observations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationsTableFilterComposer(
            $db: $db,
            $table: $db.observations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ObservationAttachmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $ObservationAttachmentsTable> {
  $$ObservationAttachmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteUrl => $composableBuilder(
    column: $table.remoteUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ObservationsTableOrderingComposer get observationId {
    final $$ObservationsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.observationId,
      referencedTable: $db.observations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationsTableOrderingComposer(
            $db: $db,
            $table: $db.observations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ObservationAttachmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ObservationAttachmentsTable> {
  $$ObservationAttachmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<String> get remoteUrl =>
      $composableBuilder(column: $table.remoteUrl, builder: (column) => column);

  GeneratedColumn<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ObservationsTableAnnotationComposer get observationId {
    final $$ObservationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.observationId,
      referencedTable: $db.observations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationsTableAnnotationComposer(
            $db: $db,
            $table: $db.observations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ObservationAttachmentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ObservationAttachmentsTable,
          ObservationAttachment,
          $$ObservationAttachmentsTableFilterComposer,
          $$ObservationAttachmentsTableOrderingComposer,
          $$ObservationAttachmentsTableAnnotationComposer,
          $$ObservationAttachmentsTableCreateCompanionBuilder,
          $$ObservationAttachmentsTableUpdateCompanionBuilder,
          (ObservationAttachment, $$ObservationAttachmentsTableReferences),
          ObservationAttachment,
          PrefetchHooks Function({bool observationId})
        > {
  $$ObservationAttachmentsTableTableManager(
    _$AppDatabase db,
    $ObservationAttachmentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ObservationAttachmentsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ObservationAttachmentsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ObservationAttachmentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> observationId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> localPath = const Value.absent(),
                Value<String?> remoteUrl = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ObservationAttachmentsCompanion(
                id: id,
                observationId: observationId,
                kind: kind,
                localPath: localPath,
                remoteUrl: remoteUrl,
                thumbnailPath: thumbnailPath,
                durationMs: durationMs,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String observationId,
                required String kind,
                required String localPath,
                Value<String?> remoteUrl = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ObservationAttachmentsCompanion.insert(
                id: id,
                observationId: observationId,
                kind: kind,
                localPath: localPath,
                remoteUrl: remoteUrl,
                thumbnailPath: thumbnailPath,
                durationMs: durationMs,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ObservationAttachmentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({observationId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (observationId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.observationId,
                                referencedTable:
                                    $$ObservationAttachmentsTableReferences
                                        ._observationIdTable(db),
                                referencedColumn:
                                    $$ObservationAttachmentsTableReferences
                                        ._observationIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ObservationAttachmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ObservationAttachmentsTable,
      ObservationAttachment,
      $$ObservationAttachmentsTableFilterComposer,
      $$ObservationAttachmentsTableOrderingComposer,
      $$ObservationAttachmentsTableAnnotationComposer,
      $$ObservationAttachmentsTableCreateCompanionBuilder,
      $$ObservationAttachmentsTableUpdateCompanionBuilder,
      (ObservationAttachment, $$ObservationAttachmentsTableReferences),
      ObservationAttachment,
      PrefetchHooks Function({bool observationId})
    >;
typedef $$ObservationDomainTagsTableCreateCompanionBuilder =
    ObservationDomainTagsCompanion Function({
      required String observationId,
      required String domain,
      Value<int> rowid,
    });
typedef $$ObservationDomainTagsTableUpdateCompanionBuilder =
    ObservationDomainTagsCompanion Function({
      Value<String> observationId,
      Value<String> domain,
      Value<int> rowid,
    });

final class $$ObservationDomainTagsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ObservationDomainTagsTable,
          ObservationDomainTag
        > {
  $$ObservationDomainTagsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ObservationsTable _observationIdTable(_$AppDatabase db) =>
      db.observations.createAlias(
        $_aliasNameGenerator(
          db.observationDomainTags.observationId,
          db.observations.id,
        ),
      );

  $$ObservationsTableProcessedTableManager get observationId {
    final $_column = $_itemColumn<String>('observation_id')!;

    final manager = $$ObservationsTableTableManager(
      $_db,
      $_db.observations,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_observationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ObservationDomainTagsTableFilterComposer
    extends Composer<_$AppDatabase, $ObservationDomainTagsTable> {
  $$ObservationDomainTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get domain => $composableBuilder(
    column: $table.domain,
    builder: (column) => ColumnFilters(column),
  );

  $$ObservationsTableFilterComposer get observationId {
    final $$ObservationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.observationId,
      referencedTable: $db.observations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationsTableFilterComposer(
            $db: $db,
            $table: $db.observations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ObservationDomainTagsTableOrderingComposer
    extends Composer<_$AppDatabase, $ObservationDomainTagsTable> {
  $$ObservationDomainTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get domain => $composableBuilder(
    column: $table.domain,
    builder: (column) => ColumnOrderings(column),
  );

  $$ObservationsTableOrderingComposer get observationId {
    final $$ObservationsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.observationId,
      referencedTable: $db.observations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationsTableOrderingComposer(
            $db: $db,
            $table: $db.observations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ObservationDomainTagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ObservationDomainTagsTable> {
  $$ObservationDomainTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get domain =>
      $composableBuilder(column: $table.domain, builder: (column) => column);

  $$ObservationsTableAnnotationComposer get observationId {
    final $$ObservationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.observationId,
      referencedTable: $db.observations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationsTableAnnotationComposer(
            $db: $db,
            $table: $db.observations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ObservationDomainTagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ObservationDomainTagsTable,
          ObservationDomainTag,
          $$ObservationDomainTagsTableFilterComposer,
          $$ObservationDomainTagsTableOrderingComposer,
          $$ObservationDomainTagsTableAnnotationComposer,
          $$ObservationDomainTagsTableCreateCompanionBuilder,
          $$ObservationDomainTagsTableUpdateCompanionBuilder,
          (ObservationDomainTag, $$ObservationDomainTagsTableReferences),
          ObservationDomainTag,
          PrefetchHooks Function({bool observationId})
        > {
  $$ObservationDomainTagsTableTableManager(
    _$AppDatabase db,
    $ObservationDomainTagsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ObservationDomainTagsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ObservationDomainTagsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ObservationDomainTagsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> observationId = const Value.absent(),
                Value<String> domain = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ObservationDomainTagsCompanion(
                observationId: observationId,
                domain: domain,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String observationId,
                required String domain,
                Value<int> rowid = const Value.absent(),
              }) => ObservationDomainTagsCompanion.insert(
                observationId: observationId,
                domain: domain,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ObservationDomainTagsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({observationId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (observationId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.observationId,
                                referencedTable:
                                    $$ObservationDomainTagsTableReferences
                                        ._observationIdTable(db),
                                referencedColumn:
                                    $$ObservationDomainTagsTableReferences
                                        ._observationIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ObservationDomainTagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ObservationDomainTagsTable,
      ObservationDomainTag,
      $$ObservationDomainTagsTableFilterComposer,
      $$ObservationDomainTagsTableOrderingComposer,
      $$ObservationDomainTagsTableAnnotationComposer,
      $$ObservationDomainTagsTableCreateCompanionBuilder,
      $$ObservationDomainTagsTableUpdateCompanionBuilder,
      (ObservationDomainTag, $$ObservationDomainTagsTableReferences),
      ObservationDomainTag,
      PrefetchHooks Function({bool observationId})
    >;
typedef $$SpecialistsTableCreateCompanionBuilder =
    SpecialistsCompanion Function({
      required String id,
      required String name,
      Value<String?> role,
      Value<String?> notes,
      Value<String?> avatarPath,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$SpecialistsTableUpdateCompanionBuilder =
    SpecialistsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> role,
      Value<String?> notes,
      Value<String?> avatarPath,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$SpecialistsTableReferences
    extends BaseReferences<_$AppDatabase, $SpecialistsTable, Specialist> {
  $$SpecialistsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<
    $SpecialistAvailabilityTable,
    List<SpecialistAvailabilityData>
  >
  _specialistAvailabilityRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.specialistAvailability,
        aliasName: $_aliasNameGenerator(
          db.specialists.id,
          db.specialistAvailability.specialistId,
        ),
      );

  $$SpecialistAvailabilityTableProcessedTableManager
  get specialistAvailabilityRefs {
    final manager = $$SpecialistAvailabilityTableTableManager(
      $_db,
      $_db.specialistAvailability,
    ).filter((f) => f.specialistId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _specialistAvailabilityRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ActivityLibraryTable, List<ActivityLibraryData>>
  _activityLibraryRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.activityLibrary,
    aliasName: $_aliasNameGenerator(
      db.specialists.id,
      db.activityLibrary.specialistId,
    ),
  );

  $$ActivityLibraryTableProcessedTableManager get activityLibraryRefs {
    final manager = $$ActivityLibraryTableTableManager(
      $_db,
      $_db.activityLibrary,
    ).filter((f) => f.specialistId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _activityLibraryRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ScheduleTemplatesTable, List<ScheduleTemplate>>
  _scheduleTemplatesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.scheduleTemplates,
        aliasName: $_aliasNameGenerator(
          db.specialists.id,
          db.scheduleTemplates.specialistId,
        ),
      );

  $$ScheduleTemplatesTableProcessedTableManager get scheduleTemplatesRefs {
    final manager = $$ScheduleTemplatesTableTableManager(
      $_db,
      $_db.scheduleTemplates,
    ).filter((f) => f.specialistId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _scheduleTemplatesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ScheduleEntriesTable, List<ScheduleEntry>>
  _scheduleEntriesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.scheduleEntries,
    aliasName: $_aliasNameGenerator(
      db.specialists.id,
      db.scheduleEntries.specialistId,
    ),
  );

  $$ScheduleEntriesTableProcessedTableManager get scheduleEntriesRefs {
    final manager = $$ScheduleEntriesTableTableManager(
      $_db,
      $_db.scheduleEntries,
    ).filter((f) => f.specialistId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _scheduleEntriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SpecialistsTableFilterComposer
    extends Composer<_$AppDatabase, $SpecialistsTable> {
  $$SpecialistsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarPath => $composableBuilder(
    column: $table.avatarPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> specialistAvailabilityRefs(
    Expression<bool> Function($$SpecialistAvailabilityTableFilterComposer f) f,
  ) {
    final $$SpecialistAvailabilityTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.specialistAvailability,
          getReferencedColumn: (t) => t.specialistId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SpecialistAvailabilityTableFilterComposer(
                $db: $db,
                $table: $db.specialistAvailability,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> activityLibraryRefs(
    Expression<bool> Function($$ActivityLibraryTableFilterComposer f) f,
  ) {
    final $$ActivityLibraryTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.activityLibrary,
      getReferencedColumn: (t) => t.specialistId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivityLibraryTableFilterComposer(
            $db: $db,
            $table: $db.activityLibrary,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> scheduleTemplatesRefs(
    Expression<bool> Function($$ScheduleTemplatesTableFilterComposer f) f,
  ) {
    final $$ScheduleTemplatesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scheduleTemplates,
      getReferencedColumn: (t) => t.specialistId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScheduleTemplatesTableFilterComposer(
            $db: $db,
            $table: $db.scheduleTemplates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> scheduleEntriesRefs(
    Expression<bool> Function($$ScheduleEntriesTableFilterComposer f) f,
  ) {
    final $$ScheduleEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scheduleEntries,
      getReferencedColumn: (t) => t.specialistId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScheduleEntriesTableFilterComposer(
            $db: $db,
            $table: $db.scheduleEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SpecialistsTableOrderingComposer
    extends Composer<_$AppDatabase, $SpecialistsTable> {
  $$SpecialistsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarPath => $composableBuilder(
    column: $table.avatarPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SpecialistsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SpecialistsTable> {
  $$SpecialistsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get avatarPath => $composableBuilder(
    column: $table.avatarPath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> specialistAvailabilityRefs<T extends Object>(
    Expression<T> Function($$SpecialistAvailabilityTableAnnotationComposer a) f,
  ) {
    final $$SpecialistAvailabilityTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.specialistAvailability,
          getReferencedColumn: (t) => t.specialistId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SpecialistAvailabilityTableAnnotationComposer(
                $db: $db,
                $table: $db.specialistAvailability,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> activityLibraryRefs<T extends Object>(
    Expression<T> Function($$ActivityLibraryTableAnnotationComposer a) f,
  ) {
    final $$ActivityLibraryTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.activityLibrary,
      getReferencedColumn: (t) => t.specialistId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivityLibraryTableAnnotationComposer(
            $db: $db,
            $table: $db.activityLibrary,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> scheduleTemplatesRefs<T extends Object>(
    Expression<T> Function($$ScheduleTemplatesTableAnnotationComposer a) f,
  ) {
    final $$ScheduleTemplatesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.scheduleTemplates,
          getReferencedColumn: (t) => t.specialistId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ScheduleTemplatesTableAnnotationComposer(
                $db: $db,
                $table: $db.scheduleTemplates,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> scheduleEntriesRefs<T extends Object>(
    Expression<T> Function($$ScheduleEntriesTableAnnotationComposer a) f,
  ) {
    final $$ScheduleEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scheduleEntries,
      getReferencedColumn: (t) => t.specialistId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScheduleEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.scheduleEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SpecialistsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SpecialistsTable,
          Specialist,
          $$SpecialistsTableFilterComposer,
          $$SpecialistsTableOrderingComposer,
          $$SpecialistsTableAnnotationComposer,
          $$SpecialistsTableCreateCompanionBuilder,
          $$SpecialistsTableUpdateCompanionBuilder,
          (Specialist, $$SpecialistsTableReferences),
          Specialist,
          PrefetchHooks Function({
            bool specialistAvailabilityRefs,
            bool activityLibraryRefs,
            bool scheduleTemplatesRefs,
            bool scheduleEntriesRefs,
          })
        > {
  $$SpecialistsTableTableManager(_$AppDatabase db, $SpecialistsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SpecialistsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SpecialistsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SpecialistsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> role = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> avatarPath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SpecialistsCompanion(
                id: id,
                name: name,
                role: role,
                notes: notes,
                avatarPath: avatarPath,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> role = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> avatarPath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SpecialistsCompanion.insert(
                id: id,
                name: name,
                role: role,
                notes: notes,
                avatarPath: avatarPath,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SpecialistsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                specialistAvailabilityRefs = false,
                activityLibraryRefs = false,
                scheduleTemplatesRefs = false,
                scheduleEntriesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (specialistAvailabilityRefs) db.specialistAvailability,
                    if (activityLibraryRefs) db.activityLibrary,
                    if (scheduleTemplatesRefs) db.scheduleTemplates,
                    if (scheduleEntriesRefs) db.scheduleEntries,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (specialistAvailabilityRefs)
                        await $_getPrefetchedData<
                          Specialist,
                          $SpecialistsTable,
                          SpecialistAvailabilityData
                        >(
                          currentTable: table,
                          referencedTable: $$SpecialistsTableReferences
                              ._specialistAvailabilityRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SpecialistsTableReferences(
                                db,
                                table,
                                p0,
                              ).specialistAvailabilityRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.specialistId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (activityLibraryRefs)
                        await $_getPrefetchedData<
                          Specialist,
                          $SpecialistsTable,
                          ActivityLibraryData
                        >(
                          currentTable: table,
                          referencedTable: $$SpecialistsTableReferences
                              ._activityLibraryRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SpecialistsTableReferences(
                                db,
                                table,
                                p0,
                              ).activityLibraryRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.specialistId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (scheduleTemplatesRefs)
                        await $_getPrefetchedData<
                          Specialist,
                          $SpecialistsTable,
                          ScheduleTemplate
                        >(
                          currentTable: table,
                          referencedTable: $$SpecialistsTableReferences
                              ._scheduleTemplatesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SpecialistsTableReferences(
                                db,
                                table,
                                p0,
                              ).scheduleTemplatesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.specialistId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (scheduleEntriesRefs)
                        await $_getPrefetchedData<
                          Specialist,
                          $SpecialistsTable,
                          ScheduleEntry
                        >(
                          currentTable: table,
                          referencedTable: $$SpecialistsTableReferences
                              ._scheduleEntriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SpecialistsTableReferences(
                                db,
                                table,
                                p0,
                              ).scheduleEntriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.specialistId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SpecialistsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SpecialistsTable,
      Specialist,
      $$SpecialistsTableFilterComposer,
      $$SpecialistsTableOrderingComposer,
      $$SpecialistsTableAnnotationComposer,
      $$SpecialistsTableCreateCompanionBuilder,
      $$SpecialistsTableUpdateCompanionBuilder,
      (Specialist, $$SpecialistsTableReferences),
      Specialist,
      PrefetchHooks Function({
        bool specialistAvailabilityRefs,
        bool activityLibraryRefs,
        bool scheduleTemplatesRefs,
        bool scheduleEntriesRefs,
      })
    >;
typedef $$SpecialistAvailabilityTableCreateCompanionBuilder =
    SpecialistAvailabilityCompanion Function({
      required String id,
      required String specialistId,
      required int dayOfWeek,
      required String startTime,
      required String endTime,
      Value<DateTime?> startDate,
      Value<DateTime?> endDate,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$SpecialistAvailabilityTableUpdateCompanionBuilder =
    SpecialistAvailabilityCompanion Function({
      Value<String> id,
      Value<String> specialistId,
      Value<int> dayOfWeek,
      Value<String> startTime,
      Value<String> endTime,
      Value<DateTime?> startDate,
      Value<DateTime?> endDate,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$SpecialistAvailabilityTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $SpecialistAvailabilityTable,
          SpecialistAvailabilityData
        > {
  $$SpecialistAvailabilityTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SpecialistsTable _specialistIdTable(_$AppDatabase db) =>
      db.specialists.createAlias(
        $_aliasNameGenerator(
          db.specialistAvailability.specialistId,
          db.specialists.id,
        ),
      );

  $$SpecialistsTableProcessedTableManager get specialistId {
    final $_column = $_itemColumn<String>('specialist_id')!;

    final manager = $$SpecialistsTableTableManager(
      $_db,
      $_db.specialists,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_specialistIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SpecialistAvailabilityTableFilterComposer
    extends Composer<_$AppDatabase, $SpecialistAvailabilityTable> {
  $$SpecialistAvailabilityTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dayOfWeek => $composableBuilder(
    column: $table.dayOfWeek,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$SpecialistsTableFilterComposer get specialistId {
    final $$SpecialistsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specialistId,
      referencedTable: $db.specialists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecialistsTableFilterComposer(
            $db: $db,
            $table: $db.specialists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpecialistAvailabilityTableOrderingComposer
    extends Composer<_$AppDatabase, $SpecialistAvailabilityTable> {
  $$SpecialistAvailabilityTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dayOfWeek => $composableBuilder(
    column: $table.dayOfWeek,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SpecialistsTableOrderingComposer get specialistId {
    final $$SpecialistsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specialistId,
      referencedTable: $db.specialists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecialistsTableOrderingComposer(
            $db: $db,
            $table: $db.specialists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpecialistAvailabilityTableAnnotationComposer
    extends Composer<_$AppDatabase, $SpecialistAvailabilityTable> {
  $$SpecialistAvailabilityTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get dayOfWeek =>
      $composableBuilder(column: $table.dayOfWeek, builder: (column) => column);

  GeneratedColumn<String> get startTime =>
      $composableBuilder(column: $table.startTime, builder: (column) => column);

  GeneratedColumn<String> get endTime =>
      $composableBuilder(column: $table.endTime, builder: (column) => column);

  GeneratedColumn<DateTime> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumn<DateTime> get endDate =>
      $composableBuilder(column: $table.endDate, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$SpecialistsTableAnnotationComposer get specialistId {
    final $$SpecialistsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specialistId,
      referencedTable: $db.specialists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecialistsTableAnnotationComposer(
            $db: $db,
            $table: $db.specialists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpecialistAvailabilityTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SpecialistAvailabilityTable,
          SpecialistAvailabilityData,
          $$SpecialistAvailabilityTableFilterComposer,
          $$SpecialistAvailabilityTableOrderingComposer,
          $$SpecialistAvailabilityTableAnnotationComposer,
          $$SpecialistAvailabilityTableCreateCompanionBuilder,
          $$SpecialistAvailabilityTableUpdateCompanionBuilder,
          (SpecialistAvailabilityData, $$SpecialistAvailabilityTableReferences),
          SpecialistAvailabilityData,
          PrefetchHooks Function({bool specialistId})
        > {
  $$SpecialistAvailabilityTableTableManager(
    _$AppDatabase db,
    $SpecialistAvailabilityTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SpecialistAvailabilityTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$SpecialistAvailabilityTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SpecialistAvailabilityTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> specialistId = const Value.absent(),
                Value<int> dayOfWeek = const Value.absent(),
                Value<String> startTime = const Value.absent(),
                Value<String> endTime = const Value.absent(),
                Value<DateTime?> startDate = const Value.absent(),
                Value<DateTime?> endDate = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SpecialistAvailabilityCompanion(
                id: id,
                specialistId: specialistId,
                dayOfWeek: dayOfWeek,
                startTime: startTime,
                endTime: endTime,
                startDate: startDate,
                endDate: endDate,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String specialistId,
                required int dayOfWeek,
                required String startTime,
                required String endTime,
                Value<DateTime?> startDate = const Value.absent(),
                Value<DateTime?> endDate = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SpecialistAvailabilityCompanion.insert(
                id: id,
                specialistId: specialistId,
                dayOfWeek: dayOfWeek,
                startTime: startTime,
                endTime: endTime,
                startDate: startDate,
                endDate: endDate,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SpecialistAvailabilityTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({specialistId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (specialistId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.specialistId,
                                referencedTable:
                                    $$SpecialistAvailabilityTableReferences
                                        ._specialistIdTable(db),
                                referencedColumn:
                                    $$SpecialistAvailabilityTableReferences
                                        ._specialistIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SpecialistAvailabilityTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SpecialistAvailabilityTable,
      SpecialistAvailabilityData,
      $$SpecialistAvailabilityTableFilterComposer,
      $$SpecialistAvailabilityTableOrderingComposer,
      $$SpecialistAvailabilityTableAnnotationComposer,
      $$SpecialistAvailabilityTableCreateCompanionBuilder,
      $$SpecialistAvailabilityTableUpdateCompanionBuilder,
      (SpecialistAvailabilityData, $$SpecialistAvailabilityTableReferences),
      SpecialistAvailabilityData,
      PrefetchHooks Function({bool specialistId})
    >;
typedef $$ActivityLibraryTableCreateCompanionBuilder =
    ActivityLibraryCompanion Function({
      required String id,
      required String title,
      Value<int?> defaultDurationMin,
      Value<String?> specialistId,
      Value<String?> location,
      Value<String?> notes,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$ActivityLibraryTableUpdateCompanionBuilder =
    ActivityLibraryCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<int?> defaultDurationMin,
      Value<String?> specialistId,
      Value<String?> location,
      Value<String?> notes,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ActivityLibraryTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ActivityLibraryTable,
          ActivityLibraryData
        > {
  $$ActivityLibraryTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SpecialistsTable _specialistIdTable(_$AppDatabase db) =>
      db.specialists.createAlias(
        $_aliasNameGenerator(
          db.activityLibrary.specialistId,
          db.specialists.id,
        ),
      );

  $$SpecialistsTableProcessedTableManager? get specialistId {
    final $_column = $_itemColumn<String>('specialist_id');
    if ($_column == null) return null;
    final manager = $$SpecialistsTableTableManager(
      $_db,
      $_db.specialists,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_specialistIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ActivityLibraryTableFilterComposer
    extends Composer<_$AppDatabase, $ActivityLibraryTable> {
  $$ActivityLibraryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get defaultDurationMin => $composableBuilder(
    column: $table.defaultDurationMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$SpecialistsTableFilterComposer get specialistId {
    final $$SpecialistsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specialistId,
      referencedTable: $db.specialists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecialistsTableFilterComposer(
            $db: $db,
            $table: $db.specialists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActivityLibraryTableOrderingComposer
    extends Composer<_$AppDatabase, $ActivityLibraryTable> {
  $$ActivityLibraryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get defaultDurationMin => $composableBuilder(
    column: $table.defaultDurationMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SpecialistsTableOrderingComposer get specialistId {
    final $$SpecialistsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specialistId,
      referencedTable: $db.specialists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecialistsTableOrderingComposer(
            $db: $db,
            $table: $db.specialists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActivityLibraryTableAnnotationComposer
    extends Composer<_$AppDatabase, $ActivityLibraryTable> {
  $$ActivityLibraryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get defaultDurationMin => $composableBuilder(
    column: $table.defaultDurationMin,
    builder: (column) => column,
  );

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$SpecialistsTableAnnotationComposer get specialistId {
    final $$SpecialistsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specialistId,
      referencedTable: $db.specialists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecialistsTableAnnotationComposer(
            $db: $db,
            $table: $db.specialists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActivityLibraryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ActivityLibraryTable,
          ActivityLibraryData,
          $$ActivityLibraryTableFilterComposer,
          $$ActivityLibraryTableOrderingComposer,
          $$ActivityLibraryTableAnnotationComposer,
          $$ActivityLibraryTableCreateCompanionBuilder,
          $$ActivityLibraryTableUpdateCompanionBuilder,
          (ActivityLibraryData, $$ActivityLibraryTableReferences),
          ActivityLibraryData,
          PrefetchHooks Function({bool specialistId})
        > {
  $$ActivityLibraryTableTableManager(
    _$AppDatabase db,
    $ActivityLibraryTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActivityLibraryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActivityLibraryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActivityLibraryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int?> defaultDurationMin = const Value.absent(),
                Value<String?> specialistId = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActivityLibraryCompanion(
                id: id,
                title: title,
                defaultDurationMin: defaultDurationMin,
                specialistId: specialistId,
                location: location,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<int?> defaultDurationMin = const Value.absent(),
                Value<String?> specialistId = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActivityLibraryCompanion.insert(
                id: id,
                title: title,
                defaultDurationMin: defaultDurationMin,
                specialistId: specialistId,
                location: location,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ActivityLibraryTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({specialistId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (specialistId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.specialistId,
                                referencedTable:
                                    $$ActivityLibraryTableReferences
                                        ._specialistIdTable(db),
                                referencedColumn:
                                    $$ActivityLibraryTableReferences
                                        ._specialistIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ActivityLibraryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ActivityLibraryTable,
      ActivityLibraryData,
      $$ActivityLibraryTableFilterComposer,
      $$ActivityLibraryTableOrderingComposer,
      $$ActivityLibraryTableAnnotationComposer,
      $$ActivityLibraryTableCreateCompanionBuilder,
      $$ActivityLibraryTableUpdateCompanionBuilder,
      (ActivityLibraryData, $$ActivityLibraryTableReferences),
      ActivityLibraryData,
      PrefetchHooks Function({bool specialistId})
    >;
typedef $$ScheduleTemplatesTableCreateCompanionBuilder =
    ScheduleTemplatesCompanion Function({
      required String id,
      required int dayOfWeek,
      required String startTime,
      required String endTime,
      Value<bool> isFullDay,
      required String title,
      Value<String?> groupId,
      Value<String?> podId,
      Value<String?> specialistName,
      Value<String?> specialistId,
      Value<String?> location,
      Value<String?> notes,
      Value<DateTime?> startDate,
      Value<DateTime?> endDate,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$ScheduleTemplatesTableUpdateCompanionBuilder =
    ScheduleTemplatesCompanion Function({
      Value<String> id,
      Value<int> dayOfWeek,
      Value<String> startTime,
      Value<String> endTime,
      Value<bool> isFullDay,
      Value<String> title,
      Value<String?> groupId,
      Value<String?> podId,
      Value<String?> specialistName,
      Value<String?> specialistId,
      Value<String?> location,
      Value<String?> notes,
      Value<DateTime?> startDate,
      Value<DateTime?> endDate,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ScheduleTemplatesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ScheduleTemplatesTable,
          ScheduleTemplate
        > {
  $$ScheduleTemplatesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PodsTable _podIdTable(_$AppDatabase db) => db.pods.createAlias(
    $_aliasNameGenerator(db.scheduleTemplates.podId, db.pods.id),
  );

  $$PodsTableProcessedTableManager? get podId {
    final $_column = $_itemColumn<String>('pod_id');
    if ($_column == null) return null;
    final manager = $$PodsTableTableManager(
      $_db,
      $_db.pods,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_podIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SpecialistsTable _specialistIdTable(_$AppDatabase db) =>
      db.specialists.createAlias(
        $_aliasNameGenerator(
          db.scheduleTemplates.specialistId,
          db.specialists.id,
        ),
      );

  $$SpecialistsTableProcessedTableManager? get specialistId {
    final $_column = $_itemColumn<String>('specialist_id');
    if ($_column == null) return null;
    final manager = $$SpecialistsTableTableManager(
      $_db,
      $_db.specialists,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_specialistIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ScheduleEntriesTable, List<ScheduleEntry>>
  _scheduleEntriesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.scheduleEntries,
    aliasName: $_aliasNameGenerator(
      db.scheduleTemplates.id,
      db.scheduleEntries.overridesTemplateId,
    ),
  );

  $$ScheduleEntriesTableProcessedTableManager get scheduleEntriesRefs {
    final manager =
        $$ScheduleEntriesTableTableManager($_db, $_db.scheduleEntries).filter(
          (f) =>
              f.overridesTemplateId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _scheduleEntriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TemplatePodsTable, List<TemplatePod>>
  _templatePodsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.templatePods,
    aliasName: $_aliasNameGenerator(
      db.scheduleTemplates.id,
      db.templatePods.templateId,
    ),
  );

  $$TemplatePodsTableProcessedTableManager get templatePodsRefs {
    final manager = $$TemplatePodsTableTableManager(
      $_db,
      $_db.templatePods,
    ).filter((f) => f.templateId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_templatePodsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ScheduleTemplatesTableFilterComposer
    extends Composer<_$AppDatabase, $ScheduleTemplatesTable> {
  $$ScheduleTemplatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dayOfWeek => $composableBuilder(
    column: $table.dayOfWeek,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFullDay => $composableBuilder(
    column: $table.isFullDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get specialistName => $composableBuilder(
    column: $table.specialistName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PodsTableFilterComposer get podId {
    final $$PodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.podId,
      referencedTable: $db.pods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PodsTableFilterComposer(
            $db: $db,
            $table: $db.pods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SpecialistsTableFilterComposer get specialistId {
    final $$SpecialistsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specialistId,
      referencedTable: $db.specialists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecialistsTableFilterComposer(
            $db: $db,
            $table: $db.specialists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> scheduleEntriesRefs(
    Expression<bool> Function($$ScheduleEntriesTableFilterComposer f) f,
  ) {
    final $$ScheduleEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scheduleEntries,
      getReferencedColumn: (t) => t.overridesTemplateId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScheduleEntriesTableFilterComposer(
            $db: $db,
            $table: $db.scheduleEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> templatePodsRefs(
    Expression<bool> Function($$TemplatePodsTableFilterComposer f) f,
  ) {
    final $$TemplatePodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.templatePods,
      getReferencedColumn: (t) => t.templateId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TemplatePodsTableFilterComposer(
            $db: $db,
            $table: $db.templatePods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ScheduleTemplatesTableOrderingComposer
    extends Composer<_$AppDatabase, $ScheduleTemplatesTable> {
  $$ScheduleTemplatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dayOfWeek => $composableBuilder(
    column: $table.dayOfWeek,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFullDay => $composableBuilder(
    column: $table.isFullDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get specialistName => $composableBuilder(
    column: $table.specialistName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PodsTableOrderingComposer get podId {
    final $$PodsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.podId,
      referencedTable: $db.pods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PodsTableOrderingComposer(
            $db: $db,
            $table: $db.pods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SpecialistsTableOrderingComposer get specialistId {
    final $$SpecialistsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specialistId,
      referencedTable: $db.specialists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecialistsTableOrderingComposer(
            $db: $db,
            $table: $db.specialists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ScheduleTemplatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ScheduleTemplatesTable> {
  $$ScheduleTemplatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get dayOfWeek =>
      $composableBuilder(column: $table.dayOfWeek, builder: (column) => column);

  GeneratedColumn<String> get startTime =>
      $composableBuilder(column: $table.startTime, builder: (column) => column);

  GeneratedColumn<String> get endTime =>
      $composableBuilder(column: $table.endTime, builder: (column) => column);

  GeneratedColumn<bool> get isFullDay =>
      $composableBuilder(column: $table.isFullDay, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get specialistName => $composableBuilder(
    column: $table.specialistName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumn<DateTime> get endDate =>
      $composableBuilder(column: $table.endDate, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$PodsTableAnnotationComposer get podId {
    final $$PodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.podId,
      referencedTable: $db.pods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PodsTableAnnotationComposer(
            $db: $db,
            $table: $db.pods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SpecialistsTableAnnotationComposer get specialistId {
    final $$SpecialistsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specialistId,
      referencedTable: $db.specialists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecialistsTableAnnotationComposer(
            $db: $db,
            $table: $db.specialists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> scheduleEntriesRefs<T extends Object>(
    Expression<T> Function($$ScheduleEntriesTableAnnotationComposer a) f,
  ) {
    final $$ScheduleEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scheduleEntries,
      getReferencedColumn: (t) => t.overridesTemplateId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScheduleEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.scheduleEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> templatePodsRefs<T extends Object>(
    Expression<T> Function($$TemplatePodsTableAnnotationComposer a) f,
  ) {
    final $$TemplatePodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.templatePods,
      getReferencedColumn: (t) => t.templateId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TemplatePodsTableAnnotationComposer(
            $db: $db,
            $table: $db.templatePods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ScheduleTemplatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ScheduleTemplatesTable,
          ScheduleTemplate,
          $$ScheduleTemplatesTableFilterComposer,
          $$ScheduleTemplatesTableOrderingComposer,
          $$ScheduleTemplatesTableAnnotationComposer,
          $$ScheduleTemplatesTableCreateCompanionBuilder,
          $$ScheduleTemplatesTableUpdateCompanionBuilder,
          (ScheduleTemplate, $$ScheduleTemplatesTableReferences),
          ScheduleTemplate,
          PrefetchHooks Function({
            bool podId,
            bool specialistId,
            bool scheduleEntriesRefs,
            bool templatePodsRefs,
          })
        > {
  $$ScheduleTemplatesTableTableManager(
    _$AppDatabase db,
    $ScheduleTemplatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ScheduleTemplatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ScheduleTemplatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ScheduleTemplatesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> dayOfWeek = const Value.absent(),
                Value<String> startTime = const Value.absent(),
                Value<String> endTime = const Value.absent(),
                Value<bool> isFullDay = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<String?> podId = const Value.absent(),
                Value<String?> specialistName = const Value.absent(),
                Value<String?> specialistId = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime?> startDate = const Value.absent(),
                Value<DateTime?> endDate = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScheduleTemplatesCompanion(
                id: id,
                dayOfWeek: dayOfWeek,
                startTime: startTime,
                endTime: endTime,
                isFullDay: isFullDay,
                title: title,
                groupId: groupId,
                podId: podId,
                specialistName: specialistName,
                specialistId: specialistId,
                location: location,
                notes: notes,
                startDate: startDate,
                endDate: endDate,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int dayOfWeek,
                required String startTime,
                required String endTime,
                Value<bool> isFullDay = const Value.absent(),
                required String title,
                Value<String?> groupId = const Value.absent(),
                Value<String?> podId = const Value.absent(),
                Value<String?> specialistName = const Value.absent(),
                Value<String?> specialistId = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime?> startDate = const Value.absent(),
                Value<DateTime?> endDate = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScheduleTemplatesCompanion.insert(
                id: id,
                dayOfWeek: dayOfWeek,
                startTime: startTime,
                endTime: endTime,
                isFullDay: isFullDay,
                title: title,
                groupId: groupId,
                podId: podId,
                specialistName: specialistName,
                specialistId: specialistId,
                location: location,
                notes: notes,
                startDate: startDate,
                endDate: endDate,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ScheduleTemplatesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                podId = false,
                specialistId = false,
                scheduleEntriesRefs = false,
                templatePodsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (scheduleEntriesRefs) db.scheduleEntries,
                    if (templatePodsRefs) db.templatePods,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (podId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.podId,
                                    referencedTable:
                                        $$ScheduleTemplatesTableReferences
                                            ._podIdTable(db),
                                    referencedColumn:
                                        $$ScheduleTemplatesTableReferences
                                            ._podIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (specialistId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.specialistId,
                                    referencedTable:
                                        $$ScheduleTemplatesTableReferences
                                            ._specialistIdTable(db),
                                    referencedColumn:
                                        $$ScheduleTemplatesTableReferences
                                            ._specialistIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (scheduleEntriesRefs)
                        await $_getPrefetchedData<
                          ScheduleTemplate,
                          $ScheduleTemplatesTable,
                          ScheduleEntry
                        >(
                          currentTable: table,
                          referencedTable: $$ScheduleTemplatesTableReferences
                              ._scheduleEntriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ScheduleTemplatesTableReferences(
                                db,
                                table,
                                p0,
                              ).scheduleEntriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.overridesTemplateId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (templatePodsRefs)
                        await $_getPrefetchedData<
                          ScheduleTemplate,
                          $ScheduleTemplatesTable,
                          TemplatePod
                        >(
                          currentTable: table,
                          referencedTable: $$ScheduleTemplatesTableReferences
                              ._templatePodsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ScheduleTemplatesTableReferences(
                                db,
                                table,
                                p0,
                              ).templatePodsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.templateId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ScheduleTemplatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ScheduleTemplatesTable,
      ScheduleTemplate,
      $$ScheduleTemplatesTableFilterComposer,
      $$ScheduleTemplatesTableOrderingComposer,
      $$ScheduleTemplatesTableAnnotationComposer,
      $$ScheduleTemplatesTableCreateCompanionBuilder,
      $$ScheduleTemplatesTableUpdateCompanionBuilder,
      (ScheduleTemplate, $$ScheduleTemplatesTableReferences),
      ScheduleTemplate,
      PrefetchHooks Function({
        bool podId,
        bool specialistId,
        bool scheduleEntriesRefs,
        bool templatePodsRefs,
      })
    >;
typedef $$ScheduleEntriesTableCreateCompanionBuilder =
    ScheduleEntriesCompanion Function({
      required String id,
      required DateTime date,
      Value<DateTime?> endDate,
      required String startTime,
      required String endTime,
      Value<bool> isFullDay,
      required String title,
      Value<String?> podId,
      Value<String?> specialistName,
      Value<String?> specialistId,
      Value<String?> location,
      Value<String?> notes,
      required String kind,
      Value<String?> sourceTripId,
      Value<String?> overridesTemplateId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$ScheduleEntriesTableUpdateCompanionBuilder =
    ScheduleEntriesCompanion Function({
      Value<String> id,
      Value<DateTime> date,
      Value<DateTime?> endDate,
      Value<String> startTime,
      Value<String> endTime,
      Value<bool> isFullDay,
      Value<String> title,
      Value<String?> podId,
      Value<String?> specialistName,
      Value<String?> specialistId,
      Value<String?> location,
      Value<String?> notes,
      Value<String> kind,
      Value<String?> sourceTripId,
      Value<String?> overridesTemplateId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ScheduleEntriesTableReferences
    extends
        BaseReferences<_$AppDatabase, $ScheduleEntriesTable, ScheduleEntry> {
  $$ScheduleEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PodsTable _podIdTable(_$AppDatabase db) => db.pods.createAlias(
    $_aliasNameGenerator(db.scheduleEntries.podId, db.pods.id),
  );

  $$PodsTableProcessedTableManager? get podId {
    final $_column = $_itemColumn<String>('pod_id');
    if ($_column == null) return null;
    final manager = $$PodsTableTableManager(
      $_db,
      $_db.pods,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_podIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SpecialistsTable _specialistIdTable(_$AppDatabase db) =>
      db.specialists.createAlias(
        $_aliasNameGenerator(
          db.scheduleEntries.specialistId,
          db.specialists.id,
        ),
      );

  $$SpecialistsTableProcessedTableManager? get specialistId {
    final $_column = $_itemColumn<String>('specialist_id');
    if ($_column == null) return null;
    final manager = $$SpecialistsTableTableManager(
      $_db,
      $_db.specialists,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_specialistIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TripsTable _sourceTripIdTable(_$AppDatabase db) =>
      db.trips.createAlias(
        $_aliasNameGenerator(db.scheduleEntries.sourceTripId, db.trips.id),
      );

  $$TripsTableProcessedTableManager? get sourceTripId {
    final $_column = $_itemColumn<String>('source_trip_id');
    if ($_column == null) return null;
    final manager = $$TripsTableTableManager(
      $_db,
      $_db.trips,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sourceTripIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ScheduleTemplatesTable _overridesTemplateIdTable(_$AppDatabase db) =>
      db.scheduleTemplates.createAlias(
        $_aliasNameGenerator(
          db.scheduleEntries.overridesTemplateId,
          db.scheduleTemplates.id,
        ),
      );

  $$ScheduleTemplatesTableProcessedTableManager? get overridesTemplateId {
    final $_column = $_itemColumn<String>('overrides_template_id');
    if ($_column == null) return null;
    final manager = $$ScheduleTemplatesTableTableManager(
      $_db,
      $_db.scheduleTemplates,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_overridesTemplateIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$EntryPodsTable, List<EntryPod>>
  _entryPodsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.entryPods,
    aliasName: $_aliasNameGenerator(
      db.scheduleEntries.id,
      db.entryPods.entryId,
    ),
  );

  $$EntryPodsTableProcessedTableManager get entryPodsRefs {
    final manager = $$EntryPodsTableTableManager(
      $_db,
      $_db.entryPods,
    ).filter((f) => f.entryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_entryPodsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ScheduleEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $ScheduleEntriesTable> {
  $$ScheduleEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFullDay => $composableBuilder(
    column: $table.isFullDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get specialistName => $composableBuilder(
    column: $table.specialistName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PodsTableFilterComposer get podId {
    final $$PodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.podId,
      referencedTable: $db.pods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PodsTableFilterComposer(
            $db: $db,
            $table: $db.pods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SpecialistsTableFilterComposer get specialistId {
    final $$SpecialistsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specialistId,
      referencedTable: $db.specialists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecialistsTableFilterComposer(
            $db: $db,
            $table: $db.specialists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TripsTableFilterComposer get sourceTripId {
    final $$TripsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceTripId,
      referencedTable: $db.trips,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TripsTableFilterComposer(
            $db: $db,
            $table: $db.trips,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ScheduleTemplatesTableFilterComposer get overridesTemplateId {
    final $$ScheduleTemplatesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.overridesTemplateId,
      referencedTable: $db.scheduleTemplates,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScheduleTemplatesTableFilterComposer(
            $db: $db,
            $table: $db.scheduleTemplates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> entryPodsRefs(
    Expression<bool> Function($$EntryPodsTableFilterComposer f) f,
  ) {
    final $$EntryPodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.entryPods,
      getReferencedColumn: (t) => t.entryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EntryPodsTableFilterComposer(
            $db: $db,
            $table: $db.entryPods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ScheduleEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $ScheduleEntriesTable> {
  $$ScheduleEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFullDay => $composableBuilder(
    column: $table.isFullDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get specialistName => $composableBuilder(
    column: $table.specialistName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PodsTableOrderingComposer get podId {
    final $$PodsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.podId,
      referencedTable: $db.pods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PodsTableOrderingComposer(
            $db: $db,
            $table: $db.pods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SpecialistsTableOrderingComposer get specialistId {
    final $$SpecialistsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specialistId,
      referencedTable: $db.specialists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecialistsTableOrderingComposer(
            $db: $db,
            $table: $db.specialists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TripsTableOrderingComposer get sourceTripId {
    final $$TripsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceTripId,
      referencedTable: $db.trips,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TripsTableOrderingComposer(
            $db: $db,
            $table: $db.trips,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ScheduleTemplatesTableOrderingComposer get overridesTemplateId {
    final $$ScheduleTemplatesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.overridesTemplateId,
      referencedTable: $db.scheduleTemplates,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScheduleTemplatesTableOrderingComposer(
            $db: $db,
            $table: $db.scheduleTemplates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ScheduleEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ScheduleEntriesTable> {
  $$ScheduleEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<DateTime> get endDate =>
      $composableBuilder(column: $table.endDate, builder: (column) => column);

  GeneratedColumn<String> get startTime =>
      $composableBuilder(column: $table.startTime, builder: (column) => column);

  GeneratedColumn<String> get endTime =>
      $composableBuilder(column: $table.endTime, builder: (column) => column);

  GeneratedColumn<bool> get isFullDay =>
      $composableBuilder(column: $table.isFullDay, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get specialistName => $composableBuilder(
    column: $table.specialistName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$PodsTableAnnotationComposer get podId {
    final $$PodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.podId,
      referencedTable: $db.pods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PodsTableAnnotationComposer(
            $db: $db,
            $table: $db.pods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SpecialistsTableAnnotationComposer get specialistId {
    final $$SpecialistsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specialistId,
      referencedTable: $db.specialists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecialistsTableAnnotationComposer(
            $db: $db,
            $table: $db.specialists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TripsTableAnnotationComposer get sourceTripId {
    final $$TripsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceTripId,
      referencedTable: $db.trips,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TripsTableAnnotationComposer(
            $db: $db,
            $table: $db.trips,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ScheduleTemplatesTableAnnotationComposer get overridesTemplateId {
    final $$ScheduleTemplatesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.overridesTemplateId,
          referencedTable: $db.scheduleTemplates,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ScheduleTemplatesTableAnnotationComposer(
                $db: $db,
                $table: $db.scheduleTemplates,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  Expression<T> entryPodsRefs<T extends Object>(
    Expression<T> Function($$EntryPodsTableAnnotationComposer a) f,
  ) {
    final $$EntryPodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.entryPods,
      getReferencedColumn: (t) => t.entryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EntryPodsTableAnnotationComposer(
            $db: $db,
            $table: $db.entryPods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ScheduleEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ScheduleEntriesTable,
          ScheduleEntry,
          $$ScheduleEntriesTableFilterComposer,
          $$ScheduleEntriesTableOrderingComposer,
          $$ScheduleEntriesTableAnnotationComposer,
          $$ScheduleEntriesTableCreateCompanionBuilder,
          $$ScheduleEntriesTableUpdateCompanionBuilder,
          (ScheduleEntry, $$ScheduleEntriesTableReferences),
          ScheduleEntry,
          PrefetchHooks Function({
            bool podId,
            bool specialistId,
            bool sourceTripId,
            bool overridesTemplateId,
            bool entryPodsRefs,
          })
        > {
  $$ScheduleEntriesTableTableManager(
    _$AppDatabase db,
    $ScheduleEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ScheduleEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ScheduleEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ScheduleEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<DateTime?> endDate = const Value.absent(),
                Value<String> startTime = const Value.absent(),
                Value<String> endTime = const Value.absent(),
                Value<bool> isFullDay = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> podId = const Value.absent(),
                Value<String?> specialistName = const Value.absent(),
                Value<String?> specialistId = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> sourceTripId = const Value.absent(),
                Value<String?> overridesTemplateId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScheduleEntriesCompanion(
                id: id,
                date: date,
                endDate: endDate,
                startTime: startTime,
                endTime: endTime,
                isFullDay: isFullDay,
                title: title,
                podId: podId,
                specialistName: specialistName,
                specialistId: specialistId,
                location: location,
                notes: notes,
                kind: kind,
                sourceTripId: sourceTripId,
                overridesTemplateId: overridesTemplateId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required DateTime date,
                Value<DateTime?> endDate = const Value.absent(),
                required String startTime,
                required String endTime,
                Value<bool> isFullDay = const Value.absent(),
                required String title,
                Value<String?> podId = const Value.absent(),
                Value<String?> specialistName = const Value.absent(),
                Value<String?> specialistId = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                required String kind,
                Value<String?> sourceTripId = const Value.absent(),
                Value<String?> overridesTemplateId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScheduleEntriesCompanion.insert(
                id: id,
                date: date,
                endDate: endDate,
                startTime: startTime,
                endTime: endTime,
                isFullDay: isFullDay,
                title: title,
                podId: podId,
                specialistName: specialistName,
                specialistId: specialistId,
                location: location,
                notes: notes,
                kind: kind,
                sourceTripId: sourceTripId,
                overridesTemplateId: overridesTemplateId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ScheduleEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                podId = false,
                specialistId = false,
                sourceTripId = false,
                overridesTemplateId = false,
                entryPodsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [if (entryPodsRefs) db.entryPods],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (podId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.podId,
                                    referencedTable:
                                        $$ScheduleEntriesTableReferences
                                            ._podIdTable(db),
                                    referencedColumn:
                                        $$ScheduleEntriesTableReferences
                                            ._podIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (specialistId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.specialistId,
                                    referencedTable:
                                        $$ScheduleEntriesTableReferences
                                            ._specialistIdTable(db),
                                    referencedColumn:
                                        $$ScheduleEntriesTableReferences
                                            ._specialistIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (sourceTripId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.sourceTripId,
                                    referencedTable:
                                        $$ScheduleEntriesTableReferences
                                            ._sourceTripIdTable(db),
                                    referencedColumn:
                                        $$ScheduleEntriesTableReferences
                                            ._sourceTripIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (overridesTemplateId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.overridesTemplateId,
                                    referencedTable:
                                        $$ScheduleEntriesTableReferences
                                            ._overridesTemplateIdTable(db),
                                    referencedColumn:
                                        $$ScheduleEntriesTableReferences
                                            ._overridesTemplateIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (entryPodsRefs)
                        await $_getPrefetchedData<
                          ScheduleEntry,
                          $ScheduleEntriesTable,
                          EntryPod
                        >(
                          currentTable: table,
                          referencedTable: $$ScheduleEntriesTableReferences
                              ._entryPodsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ScheduleEntriesTableReferences(
                                db,
                                table,
                                p0,
                              ).entryPodsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.entryId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ScheduleEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ScheduleEntriesTable,
      ScheduleEntry,
      $$ScheduleEntriesTableFilterComposer,
      $$ScheduleEntriesTableOrderingComposer,
      $$ScheduleEntriesTableAnnotationComposer,
      $$ScheduleEntriesTableCreateCompanionBuilder,
      $$ScheduleEntriesTableUpdateCompanionBuilder,
      (ScheduleEntry, $$ScheduleEntriesTableReferences),
      ScheduleEntry,
      PrefetchHooks Function({
        bool podId,
        bool specialistId,
        bool sourceTripId,
        bool overridesTemplateId,
        bool entryPodsRefs,
      })
    >;
typedef $$TemplatePodsTableCreateCompanionBuilder =
    TemplatePodsCompanion Function({
      required String templateId,
      required String podId,
      Value<int> rowid,
    });
typedef $$TemplatePodsTableUpdateCompanionBuilder =
    TemplatePodsCompanion Function({
      Value<String> templateId,
      Value<String> podId,
      Value<int> rowid,
    });

final class $$TemplatePodsTableReferences
    extends BaseReferences<_$AppDatabase, $TemplatePodsTable, TemplatePod> {
  $$TemplatePodsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ScheduleTemplatesTable _templateIdTable(_$AppDatabase db) =>
      db.scheduleTemplates.createAlias(
        $_aliasNameGenerator(
          db.templatePods.templateId,
          db.scheduleTemplates.id,
        ),
      );

  $$ScheduleTemplatesTableProcessedTableManager get templateId {
    final $_column = $_itemColumn<String>('template_id')!;

    final manager = $$ScheduleTemplatesTableTableManager(
      $_db,
      $_db.scheduleTemplates,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_templateIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $PodsTable _podIdTable(_$AppDatabase db) => db.pods.createAlias(
    $_aliasNameGenerator(db.templatePods.podId, db.pods.id),
  );

  $$PodsTableProcessedTableManager get podId {
    final $_column = $_itemColumn<String>('pod_id')!;

    final manager = $$PodsTableTableManager(
      $_db,
      $_db.pods,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_podIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TemplatePodsTableFilterComposer
    extends Composer<_$AppDatabase, $TemplatePodsTable> {
  $$TemplatePodsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$ScheduleTemplatesTableFilterComposer get templateId {
    final $$ScheduleTemplatesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.templateId,
      referencedTable: $db.scheduleTemplates,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScheduleTemplatesTableFilterComposer(
            $db: $db,
            $table: $db.scheduleTemplates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PodsTableFilterComposer get podId {
    final $$PodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.podId,
      referencedTable: $db.pods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PodsTableFilterComposer(
            $db: $db,
            $table: $db.pods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TemplatePodsTableOrderingComposer
    extends Composer<_$AppDatabase, $TemplatePodsTable> {
  $$TemplatePodsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$ScheduleTemplatesTableOrderingComposer get templateId {
    final $$ScheduleTemplatesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.templateId,
      referencedTable: $db.scheduleTemplates,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScheduleTemplatesTableOrderingComposer(
            $db: $db,
            $table: $db.scheduleTemplates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PodsTableOrderingComposer get podId {
    final $$PodsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.podId,
      referencedTable: $db.pods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PodsTableOrderingComposer(
            $db: $db,
            $table: $db.pods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TemplatePodsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TemplatePodsTable> {
  $$TemplatePodsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$ScheduleTemplatesTableAnnotationComposer get templateId {
    final $$ScheduleTemplatesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.templateId,
          referencedTable: $db.scheduleTemplates,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ScheduleTemplatesTableAnnotationComposer(
                $db: $db,
                $table: $db.scheduleTemplates,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$PodsTableAnnotationComposer get podId {
    final $$PodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.podId,
      referencedTable: $db.pods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PodsTableAnnotationComposer(
            $db: $db,
            $table: $db.pods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TemplatePodsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TemplatePodsTable,
          TemplatePod,
          $$TemplatePodsTableFilterComposer,
          $$TemplatePodsTableOrderingComposer,
          $$TemplatePodsTableAnnotationComposer,
          $$TemplatePodsTableCreateCompanionBuilder,
          $$TemplatePodsTableUpdateCompanionBuilder,
          (TemplatePod, $$TemplatePodsTableReferences),
          TemplatePod,
          PrefetchHooks Function({bool templateId, bool podId})
        > {
  $$TemplatePodsTableTableManager(_$AppDatabase db, $TemplatePodsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TemplatePodsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TemplatePodsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TemplatePodsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> templateId = const Value.absent(),
                Value<String> podId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TemplatePodsCompanion(
                templateId: templateId,
                podId: podId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String templateId,
                required String podId,
                Value<int> rowid = const Value.absent(),
              }) => TemplatePodsCompanion.insert(
                templateId: templateId,
                podId: podId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TemplatePodsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({templateId = false, podId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (templateId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.templateId,
                                referencedTable: $$TemplatePodsTableReferences
                                    ._templateIdTable(db),
                                referencedColumn: $$TemplatePodsTableReferences
                                    ._templateIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (podId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.podId,
                                referencedTable: $$TemplatePodsTableReferences
                                    ._podIdTable(db),
                                referencedColumn: $$TemplatePodsTableReferences
                                    ._podIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TemplatePodsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TemplatePodsTable,
      TemplatePod,
      $$TemplatePodsTableFilterComposer,
      $$TemplatePodsTableOrderingComposer,
      $$TemplatePodsTableAnnotationComposer,
      $$TemplatePodsTableCreateCompanionBuilder,
      $$TemplatePodsTableUpdateCompanionBuilder,
      (TemplatePod, $$TemplatePodsTableReferences),
      TemplatePod,
      PrefetchHooks Function({bool templateId, bool podId})
    >;
typedef $$EntryPodsTableCreateCompanionBuilder =
    EntryPodsCompanion Function({
      required String entryId,
      required String podId,
      Value<int> rowid,
    });
typedef $$EntryPodsTableUpdateCompanionBuilder =
    EntryPodsCompanion Function({
      Value<String> entryId,
      Value<String> podId,
      Value<int> rowid,
    });

final class $$EntryPodsTableReferences
    extends BaseReferences<_$AppDatabase, $EntryPodsTable, EntryPod> {
  $$EntryPodsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ScheduleEntriesTable _entryIdTable(_$AppDatabase db) =>
      db.scheduleEntries.createAlias(
        $_aliasNameGenerator(db.entryPods.entryId, db.scheduleEntries.id),
      );

  $$ScheduleEntriesTableProcessedTableManager get entryId {
    final $_column = $_itemColumn<String>('entry_id')!;

    final manager = $$ScheduleEntriesTableTableManager(
      $_db,
      $_db.scheduleEntries,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_entryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $PodsTable _podIdTable(_$AppDatabase db) =>
      db.pods.createAlias($_aliasNameGenerator(db.entryPods.podId, db.pods.id));

  $$PodsTableProcessedTableManager get podId {
    final $_column = $_itemColumn<String>('pod_id')!;

    final manager = $$PodsTableTableManager(
      $_db,
      $_db.pods,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_podIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$EntryPodsTableFilterComposer
    extends Composer<_$AppDatabase, $EntryPodsTable> {
  $$EntryPodsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$ScheduleEntriesTableFilterComposer get entryId {
    final $$ScheduleEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.scheduleEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScheduleEntriesTableFilterComposer(
            $db: $db,
            $table: $db.scheduleEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PodsTableFilterComposer get podId {
    final $$PodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.podId,
      referencedTable: $db.pods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PodsTableFilterComposer(
            $db: $db,
            $table: $db.pods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EntryPodsTableOrderingComposer
    extends Composer<_$AppDatabase, $EntryPodsTable> {
  $$EntryPodsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$ScheduleEntriesTableOrderingComposer get entryId {
    final $$ScheduleEntriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.scheduleEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScheduleEntriesTableOrderingComposer(
            $db: $db,
            $table: $db.scheduleEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PodsTableOrderingComposer get podId {
    final $$PodsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.podId,
      referencedTable: $db.pods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PodsTableOrderingComposer(
            $db: $db,
            $table: $db.pods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EntryPodsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EntryPodsTable> {
  $$EntryPodsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$ScheduleEntriesTableAnnotationComposer get entryId {
    final $$ScheduleEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.scheduleEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScheduleEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.scheduleEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PodsTableAnnotationComposer get podId {
    final $$PodsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.podId,
      referencedTable: $db.pods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PodsTableAnnotationComposer(
            $db: $db,
            $table: $db.pods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EntryPodsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EntryPodsTable,
          EntryPod,
          $$EntryPodsTableFilterComposer,
          $$EntryPodsTableOrderingComposer,
          $$EntryPodsTableAnnotationComposer,
          $$EntryPodsTableCreateCompanionBuilder,
          $$EntryPodsTableUpdateCompanionBuilder,
          (EntryPod, $$EntryPodsTableReferences),
          EntryPod,
          PrefetchHooks Function({bool entryId, bool podId})
        > {
  $$EntryPodsTableTableManager(_$AppDatabase db, $EntryPodsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EntryPodsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EntryPodsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EntryPodsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> entryId = const Value.absent(),
                Value<String> podId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntryPodsCompanion(
                entryId: entryId,
                podId: podId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String entryId,
                required String podId,
                Value<int> rowid = const Value.absent(),
              }) => EntryPodsCompanion.insert(
                entryId: entryId,
                podId: podId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$EntryPodsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({entryId = false, podId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (entryId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.entryId,
                                referencedTable: $$EntryPodsTableReferences
                                    ._entryIdTable(db),
                                referencedColumn: $$EntryPodsTableReferences
                                    ._entryIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (podId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.podId,
                                referencedTable: $$EntryPodsTableReferences
                                    ._podIdTable(db),
                                referencedColumn: $$EntryPodsTableReferences
                                    ._podIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$EntryPodsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EntryPodsTable,
      EntryPod,
      $$EntryPodsTableFilterComposer,
      $$EntryPodsTableOrderingComposer,
      $$EntryPodsTableAnnotationComposer,
      $$EntryPodsTableCreateCompanionBuilder,
      $$EntryPodsTableUpdateCompanionBuilder,
      (EntryPod, $$EntryPodsTableReferences),
      EntryPod,
      PrefetchHooks Function({bool entryId, bool podId})
    >;
typedef $$ParentConcernNotesTableCreateCompanionBuilder =
    ParentConcernNotesCompanion Function({
      required String id,
      Value<String> childNames,
      Value<String> parentName,
      Value<DateTime?> concernDate,
      Value<String> staffReceiving,
      Value<String?> supervisorNotified,
      Value<bool> methodInPerson,
      Value<bool> methodPhone,
      Value<bool> methodEmail,
      Value<String?> methodOther,
      Value<String> concernDescription,
      Value<String> immediateResponse,
      Value<bool> followUpMonitor,
      Value<bool> followUpStaffCheckIns,
      Value<bool> followUpSupervisorReview,
      Value<bool> followUpParentConversation,
      Value<String?> followUpOther,
      Value<DateTime?> followUpDate,
      Value<String?> additionalNotes,
      Value<String?> staffSignature,
      Value<String?> staffSignaturePath,
      Value<DateTime?> staffSignatureDate,
      Value<String?> supervisorSignature,
      Value<String?> supervisorSignaturePath,
      Value<DateTime?> supervisorSignatureDate,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$ParentConcernNotesTableUpdateCompanionBuilder =
    ParentConcernNotesCompanion Function({
      Value<String> id,
      Value<String> childNames,
      Value<String> parentName,
      Value<DateTime?> concernDate,
      Value<String> staffReceiving,
      Value<String?> supervisorNotified,
      Value<bool> methodInPerson,
      Value<bool> methodPhone,
      Value<bool> methodEmail,
      Value<String?> methodOther,
      Value<String> concernDescription,
      Value<String> immediateResponse,
      Value<bool> followUpMonitor,
      Value<bool> followUpStaffCheckIns,
      Value<bool> followUpSupervisorReview,
      Value<bool> followUpParentConversation,
      Value<String?> followUpOther,
      Value<DateTime?> followUpDate,
      Value<String?> additionalNotes,
      Value<String?> staffSignature,
      Value<String?> staffSignaturePath,
      Value<DateTime?> staffSignatureDate,
      Value<String?> supervisorSignature,
      Value<String?> supervisorSignaturePath,
      Value<DateTime?> supervisorSignatureDate,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ParentConcernNotesTableFilterComposer
    extends Composer<_$AppDatabase, $ParentConcernNotesTable> {
  $$ParentConcernNotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get childNames => $composableBuilder(
    column: $table.childNames,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentName => $composableBuilder(
    column: $table.parentName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get concernDate => $composableBuilder(
    column: $table.concernDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get staffReceiving => $composableBuilder(
    column: $table.staffReceiving,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get supervisorNotified => $composableBuilder(
    column: $table.supervisorNotified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get methodInPerson => $composableBuilder(
    column: $table.methodInPerson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get methodPhone => $composableBuilder(
    column: $table.methodPhone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get methodEmail => $composableBuilder(
    column: $table.methodEmail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get methodOther => $composableBuilder(
    column: $table.methodOther,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get concernDescription => $composableBuilder(
    column: $table.concernDescription,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get immediateResponse => $composableBuilder(
    column: $table.immediateResponse,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get followUpMonitor => $composableBuilder(
    column: $table.followUpMonitor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get followUpStaffCheckIns => $composableBuilder(
    column: $table.followUpStaffCheckIns,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get followUpSupervisorReview => $composableBuilder(
    column: $table.followUpSupervisorReview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get followUpParentConversation => $composableBuilder(
    column: $table.followUpParentConversation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get followUpOther => $composableBuilder(
    column: $table.followUpOther,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get followUpDate => $composableBuilder(
    column: $table.followUpDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get additionalNotes => $composableBuilder(
    column: $table.additionalNotes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get staffSignature => $composableBuilder(
    column: $table.staffSignature,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get staffSignaturePath => $composableBuilder(
    column: $table.staffSignaturePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get staffSignatureDate => $composableBuilder(
    column: $table.staffSignatureDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get supervisorSignature => $composableBuilder(
    column: $table.supervisorSignature,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get supervisorSignaturePath => $composableBuilder(
    column: $table.supervisorSignaturePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get supervisorSignatureDate => $composableBuilder(
    column: $table.supervisorSignatureDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ParentConcernNotesTableOrderingComposer
    extends Composer<_$AppDatabase, $ParentConcernNotesTable> {
  $$ParentConcernNotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get childNames => $composableBuilder(
    column: $table.childNames,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentName => $composableBuilder(
    column: $table.parentName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get concernDate => $composableBuilder(
    column: $table.concernDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get staffReceiving => $composableBuilder(
    column: $table.staffReceiving,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get supervisorNotified => $composableBuilder(
    column: $table.supervisorNotified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get methodInPerson => $composableBuilder(
    column: $table.methodInPerson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get methodPhone => $composableBuilder(
    column: $table.methodPhone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get methodEmail => $composableBuilder(
    column: $table.methodEmail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get methodOther => $composableBuilder(
    column: $table.methodOther,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get concernDescription => $composableBuilder(
    column: $table.concernDescription,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get immediateResponse => $composableBuilder(
    column: $table.immediateResponse,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get followUpMonitor => $composableBuilder(
    column: $table.followUpMonitor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get followUpStaffCheckIns => $composableBuilder(
    column: $table.followUpStaffCheckIns,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get followUpSupervisorReview => $composableBuilder(
    column: $table.followUpSupervisorReview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get followUpParentConversation => $composableBuilder(
    column: $table.followUpParentConversation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get followUpOther => $composableBuilder(
    column: $table.followUpOther,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get followUpDate => $composableBuilder(
    column: $table.followUpDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get additionalNotes => $composableBuilder(
    column: $table.additionalNotes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get staffSignature => $composableBuilder(
    column: $table.staffSignature,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get staffSignaturePath => $composableBuilder(
    column: $table.staffSignaturePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get staffSignatureDate => $composableBuilder(
    column: $table.staffSignatureDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get supervisorSignature => $composableBuilder(
    column: $table.supervisorSignature,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get supervisorSignaturePath => $composableBuilder(
    column: $table.supervisorSignaturePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get supervisorSignatureDate => $composableBuilder(
    column: $table.supervisorSignatureDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ParentConcernNotesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ParentConcernNotesTable> {
  $$ParentConcernNotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get childNames => $composableBuilder(
    column: $table.childNames,
    builder: (column) => column,
  );

  GeneratedColumn<String> get parentName => $composableBuilder(
    column: $table.parentName,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get concernDate => $composableBuilder(
    column: $table.concernDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get staffReceiving => $composableBuilder(
    column: $table.staffReceiving,
    builder: (column) => column,
  );

  GeneratedColumn<String> get supervisorNotified => $composableBuilder(
    column: $table.supervisorNotified,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get methodInPerson => $composableBuilder(
    column: $table.methodInPerson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get methodPhone => $composableBuilder(
    column: $table.methodPhone,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get methodEmail => $composableBuilder(
    column: $table.methodEmail,
    builder: (column) => column,
  );

  GeneratedColumn<String> get methodOther => $composableBuilder(
    column: $table.methodOther,
    builder: (column) => column,
  );

  GeneratedColumn<String> get concernDescription => $composableBuilder(
    column: $table.concernDescription,
    builder: (column) => column,
  );

  GeneratedColumn<String> get immediateResponse => $composableBuilder(
    column: $table.immediateResponse,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get followUpMonitor => $composableBuilder(
    column: $table.followUpMonitor,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get followUpStaffCheckIns => $composableBuilder(
    column: $table.followUpStaffCheckIns,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get followUpSupervisorReview => $composableBuilder(
    column: $table.followUpSupervisorReview,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get followUpParentConversation => $composableBuilder(
    column: $table.followUpParentConversation,
    builder: (column) => column,
  );

  GeneratedColumn<String> get followUpOther => $composableBuilder(
    column: $table.followUpOther,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get followUpDate => $composableBuilder(
    column: $table.followUpDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get additionalNotes => $composableBuilder(
    column: $table.additionalNotes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get staffSignature => $composableBuilder(
    column: $table.staffSignature,
    builder: (column) => column,
  );

  GeneratedColumn<String> get staffSignaturePath => $composableBuilder(
    column: $table.staffSignaturePath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get staffSignatureDate => $composableBuilder(
    column: $table.staffSignatureDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get supervisorSignature => $composableBuilder(
    column: $table.supervisorSignature,
    builder: (column) => column,
  );

  GeneratedColumn<String> get supervisorSignaturePath => $composableBuilder(
    column: $table.supervisorSignaturePath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get supervisorSignatureDate => $composableBuilder(
    column: $table.supervisorSignatureDate,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ParentConcernNotesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ParentConcernNotesTable,
          ParentConcernNote,
          $$ParentConcernNotesTableFilterComposer,
          $$ParentConcernNotesTableOrderingComposer,
          $$ParentConcernNotesTableAnnotationComposer,
          $$ParentConcernNotesTableCreateCompanionBuilder,
          $$ParentConcernNotesTableUpdateCompanionBuilder,
          (
            ParentConcernNote,
            BaseReferences<
              _$AppDatabase,
              $ParentConcernNotesTable,
              ParentConcernNote
            >,
          ),
          ParentConcernNote,
          PrefetchHooks Function()
        > {
  $$ParentConcernNotesTableTableManager(
    _$AppDatabase db,
    $ParentConcernNotesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ParentConcernNotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ParentConcernNotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ParentConcernNotesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> childNames = const Value.absent(),
                Value<String> parentName = const Value.absent(),
                Value<DateTime?> concernDate = const Value.absent(),
                Value<String> staffReceiving = const Value.absent(),
                Value<String?> supervisorNotified = const Value.absent(),
                Value<bool> methodInPerson = const Value.absent(),
                Value<bool> methodPhone = const Value.absent(),
                Value<bool> methodEmail = const Value.absent(),
                Value<String?> methodOther = const Value.absent(),
                Value<String> concernDescription = const Value.absent(),
                Value<String> immediateResponse = const Value.absent(),
                Value<bool> followUpMonitor = const Value.absent(),
                Value<bool> followUpStaffCheckIns = const Value.absent(),
                Value<bool> followUpSupervisorReview = const Value.absent(),
                Value<bool> followUpParentConversation = const Value.absent(),
                Value<String?> followUpOther = const Value.absent(),
                Value<DateTime?> followUpDate = const Value.absent(),
                Value<String?> additionalNotes = const Value.absent(),
                Value<String?> staffSignature = const Value.absent(),
                Value<String?> staffSignaturePath = const Value.absent(),
                Value<DateTime?> staffSignatureDate = const Value.absent(),
                Value<String?> supervisorSignature = const Value.absent(),
                Value<String?> supervisorSignaturePath = const Value.absent(),
                Value<DateTime?> supervisorSignatureDate = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ParentConcernNotesCompanion(
                id: id,
                childNames: childNames,
                parentName: parentName,
                concernDate: concernDate,
                staffReceiving: staffReceiving,
                supervisorNotified: supervisorNotified,
                methodInPerson: methodInPerson,
                methodPhone: methodPhone,
                methodEmail: methodEmail,
                methodOther: methodOther,
                concernDescription: concernDescription,
                immediateResponse: immediateResponse,
                followUpMonitor: followUpMonitor,
                followUpStaffCheckIns: followUpStaffCheckIns,
                followUpSupervisorReview: followUpSupervisorReview,
                followUpParentConversation: followUpParentConversation,
                followUpOther: followUpOther,
                followUpDate: followUpDate,
                additionalNotes: additionalNotes,
                staffSignature: staffSignature,
                staffSignaturePath: staffSignaturePath,
                staffSignatureDate: staffSignatureDate,
                supervisorSignature: supervisorSignature,
                supervisorSignaturePath: supervisorSignaturePath,
                supervisorSignatureDate: supervisorSignatureDate,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> childNames = const Value.absent(),
                Value<String> parentName = const Value.absent(),
                Value<DateTime?> concernDate = const Value.absent(),
                Value<String> staffReceiving = const Value.absent(),
                Value<String?> supervisorNotified = const Value.absent(),
                Value<bool> methodInPerson = const Value.absent(),
                Value<bool> methodPhone = const Value.absent(),
                Value<bool> methodEmail = const Value.absent(),
                Value<String?> methodOther = const Value.absent(),
                Value<String> concernDescription = const Value.absent(),
                Value<String> immediateResponse = const Value.absent(),
                Value<bool> followUpMonitor = const Value.absent(),
                Value<bool> followUpStaffCheckIns = const Value.absent(),
                Value<bool> followUpSupervisorReview = const Value.absent(),
                Value<bool> followUpParentConversation = const Value.absent(),
                Value<String?> followUpOther = const Value.absent(),
                Value<DateTime?> followUpDate = const Value.absent(),
                Value<String?> additionalNotes = const Value.absent(),
                Value<String?> staffSignature = const Value.absent(),
                Value<String?> staffSignaturePath = const Value.absent(),
                Value<DateTime?> staffSignatureDate = const Value.absent(),
                Value<String?> supervisorSignature = const Value.absent(),
                Value<String?> supervisorSignaturePath = const Value.absent(),
                Value<DateTime?> supervisorSignatureDate = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ParentConcernNotesCompanion.insert(
                id: id,
                childNames: childNames,
                parentName: parentName,
                concernDate: concernDate,
                staffReceiving: staffReceiving,
                supervisorNotified: supervisorNotified,
                methodInPerson: methodInPerson,
                methodPhone: methodPhone,
                methodEmail: methodEmail,
                methodOther: methodOther,
                concernDescription: concernDescription,
                immediateResponse: immediateResponse,
                followUpMonitor: followUpMonitor,
                followUpStaffCheckIns: followUpStaffCheckIns,
                followUpSupervisorReview: followUpSupervisorReview,
                followUpParentConversation: followUpParentConversation,
                followUpOther: followUpOther,
                followUpDate: followUpDate,
                additionalNotes: additionalNotes,
                staffSignature: staffSignature,
                staffSignaturePath: staffSignaturePath,
                staffSignatureDate: staffSignatureDate,
                supervisorSignature: supervisorSignature,
                supervisorSignaturePath: supervisorSignaturePath,
                supervisorSignatureDate: supervisorSignatureDate,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ParentConcernNotesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ParentConcernNotesTable,
      ParentConcernNote,
      $$ParentConcernNotesTableFilterComposer,
      $$ParentConcernNotesTableOrderingComposer,
      $$ParentConcernNotesTableAnnotationComposer,
      $$ParentConcernNotesTableCreateCompanionBuilder,
      $$ParentConcernNotesTableUpdateCompanionBuilder,
      (
        ParentConcernNote,
        BaseReferences<
          _$AppDatabase,
          $ParentConcernNotesTable,
          ParentConcernNote
        >,
      ),
      ParentConcernNote,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PodsTableTableManager get pods => $$PodsTableTableManager(_db, _db.pods);
  $$KidsTableTableManager get kids => $$KidsTableTableManager(_db, _db.kids);
  $$TripsTableTableManager get trips =>
      $$TripsTableTableManager(_db, _db.trips);
  $$TripPodsTableTableManager get tripPods =>
      $$TripPodsTableTableManager(_db, _db.tripPods);
  $$CapturesTableTableManager get captures =>
      $$CapturesTableTableManager(_db, _db.captures);
  $$CaptureKidsTableTableManager get captureKids =>
      $$CaptureKidsTableTableManager(_db, _db.captureKids);
  $$ObservationsTableTableManager get observations =>
      $$ObservationsTableTableManager(_db, _db.observations);
  $$ObservationKidsTableTableManager get observationKids =>
      $$ObservationKidsTableTableManager(_db, _db.observationKids);
  $$ObservationAttachmentsTableTableManager get observationAttachments =>
      $$ObservationAttachmentsTableTableManager(
        _db,
        _db.observationAttachments,
      );
  $$ObservationDomainTagsTableTableManager get observationDomainTags =>
      $$ObservationDomainTagsTableTableManager(_db, _db.observationDomainTags);
  $$SpecialistsTableTableManager get specialists =>
      $$SpecialistsTableTableManager(_db, _db.specialists);
  $$SpecialistAvailabilityTableTableManager get specialistAvailability =>
      $$SpecialistAvailabilityTableTableManager(
        _db,
        _db.specialistAvailability,
      );
  $$ActivityLibraryTableTableManager get activityLibrary =>
      $$ActivityLibraryTableTableManager(_db, _db.activityLibrary);
  $$ScheduleTemplatesTableTableManager get scheduleTemplates =>
      $$ScheduleTemplatesTableTableManager(_db, _db.scheduleTemplates);
  $$ScheduleEntriesTableTableManager get scheduleEntries =>
      $$ScheduleEntriesTableTableManager(_db, _db.scheduleEntries);
  $$TemplatePodsTableTableManager get templatePods =>
      $$TemplatePodsTableTableManager(_db, _db.templatePods);
  $$EntryPodsTableTableManager get entryPods =>
      $$EntryPodsTableTableManager(_db, _db.entryPods);
  $$ParentConcernNotesTableTableManager get parentConcernNotes =>
      $$ParentConcernNotesTableTableManager(_db, _db.parentConcernNotes);
}
