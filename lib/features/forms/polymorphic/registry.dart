import 'package:basecamp/features/forms/polymorphic/definitions/behavior_monitoring.dart';
import 'package:basecamp/features/forms/polymorphic/definitions/vehicle_check.dart';
import 'package:basecamp/features/forms/polymorphic/form_definition.dart';

/// All form types the app knows how to render. The registry is
/// static for now — adding a form type means adding a file in
/// `definitions/` and registering it here. Eventually this becomes
/// dynamic (programs configuring their own custom forms) but the
/// shape stays the same: a map from typeKey to FormDefinition.
const List<FormDefinition> _formDefinitions = [
  vehicleCheckForm,
  behaviorMonitoringForm,
];

Map<String, FormDefinition>? _byType;

/// Lookup by the stable on-disk typeKey. Returns null for unknown
/// types — callers (list screen, detail screen) render a "not
/// supported in this build" fallback rather than crashing.
FormDefinition? formDefinitionFor(String typeKey) {
  _byType ??= {for (final d in _formDefinitions) d.typeKey: d};
  return _byType![typeKey];
}

/// All registered definitions, in display order for the forms hub.
List<FormDefinition> get allFormDefinitions => _formDefinitions;

/// Forms that exist as follow-ups to another form (behavior
/// monitoring → parent concern). Lets a parent-form's detail screen
/// ask "what follow-ups can be started from me?"
List<FormDefinition> followUpFormsFor(String parentTypeKey) {
  return [
    for (final d in _formDefinitions)
      if (d.parentTypeKey == parentTypeKey) d,
  ];
}
