import 'package:basecamp/features/forms/polymorphic/form_definition.dart';
import 'package:flutter/material.dart';

/// Pre-trip vehicle safety check — lights / tires / gauges / leaks /
/// other / interior / exterior. Mirrors the paper form programs
/// already use; every item is a three-state check-mark field so
/// scanning down the list is fast.
const FormDefinition vehicleCheckForm = FormDefinition(
  typeKey: 'vehicle_check',
  title: 'Vehicle safety inspection',
  shortTitle: 'Vehicle check',
  subtitle: 'Pre-trip safety inspection — lights, tires, brakes.',
  icon: Icons.directions_bus_outlined,
  subjectKind: FormSubjectKind.trip,
  sections: [
    FormSection(
      title: 'Vehicle',
      fields: [
        FormTextField(
          key: 'vehicle_make_model',
          label: 'Make & model',
          hint: 'e.g. Ford Transit 350',
        ),
        FormTextField(
          key: 'license_plate',
          label: 'License plate',
          hint: 'e.g. 03234E4',
        ),
        FormTextField(
          key: 'driver_name',
          label: 'Driver name',
        ),
        FormDateField(
          key: 'check_datetime',
          label: 'Date & time',
          includeTime: true,
        ),
        FormTextField(
          key: 'odometer',
          label: 'Odometer',
          hint: 'e.g. 62,764',
        ),
        FormTextField(
          key: 'fuel_level',
          label: 'Fuel level',
          hint: 'e.g. 3/4 · Full · E',
        ),
      ],
    ),
    FormSection(
      title: 'Lights',
      subtitle: 'Check = OK · × = needs a mechanic look.',
      fields: [
        FormChecklistStatusField(key: 'headlights', label: 'Headlights'),
        FormChecklistStatusField(key: 'brake_lights', label: 'Brake lights'),
        FormChecklistStatusField(key: 'turn_signals', label: 'Turn signals'),
        FormChecklistStatusField(key: 'hazard_lights', label: 'Hazard lights'),
      ],
    ),
    FormSection(
      title: 'Tires',
      fields: [
        FormChecklistStatusField(
          key: 'tires_inflated',
          label: 'Properly inflated',
        ),
      ],
    ),
    FormSection(
      title: 'Gauges',
      fields: [
        FormChecklistStatusField(key: 'fuel_gauge', label: 'Fuel gauge'),
        FormChecklistStatusField(
          key: 'temperature_gauge',
          label: 'Temperature',
        ),
        FormChecklistStatusField(
          key: 'engine_service_lights',
          label: 'Engine service lights',
        ),
      ],
    ),
    FormSection(
      title: 'Leaks (look underneath)',
      fields: [
        FormChecklistStatusField(key: 'leak_oil', label: 'Oil'),
        FormChecklistStatusField(key: 'leak_other', label: 'Other'),
      ],
    ),
    FormSection(
      title: 'Other',
      fields: [
        FormChecklistStatusField(
          key: 'windows_mirrors',
          label: 'Windows & mirrors',
        ),
        FormChecklistStatusField(
          key: 'windshield_wipers',
          label: 'Windshield wipers',
        ),
        FormChecklistStatusField(
          key: 'fans_defroster',
          label: 'Fans & defroster',
        ),
        FormChecklistStatusField(
          key: 'brakes',
          label: 'Brakes (including parking brake)',
        ),
        FormChecklistStatusField(key: 'horn', label: 'Horn'),
        FormChecklistStatusField(
          key: 'emergency_kit',
          label: 'Vehicle emergency / safety kit',
        ),
      ],
    ),
    FormSection(
      title: 'Vehicle interior',
      fields: [
        FormChecklistStatusField(
          key: 'unusual_noises',
          label: 'Noises (listen for unusual ones)',
        ),
        FormChecklistStatusField(
          key: 'seat_belts',
          label: 'Seat belts (one for each passenger)',
        ),
      ],
    ),
    FormSection(
      title: 'Vehicle exterior',
      subtitle: 'Describe any body damage.',
      fields: [
        FormTextField(
          key: 'body_damage',
          label: 'Body damage',
          maxLines: 3,
        ),
      ],
    ),
    FormSection(
      title: 'Notes',
      fields: [
        FormTextField(
          key: 'notes',
          label: 'Notes',
          maxLines: 4,
        ),
      ],
    ),
  ],
);
