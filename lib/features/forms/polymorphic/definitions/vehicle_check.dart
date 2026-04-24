import 'package:basecamp/features/forms/polymorphic/form_definition.dart';
import 'package:flutter/material.dart';

/// Pre-trip vehicle safety check — mirrors the FACES paper form
/// programs already use. Section ordering, labels, and driver
/// instructions match the clipboard version so a teacher switching
/// from paper to the app doesn't have to relearn.
///
/// Three-state check-mark per item:
///   * Check = acceptable — vehicle OK to drive
///   * X     = needs a mechanic look — drive only if safe
///   * unset = not yet inspected
/// Safety-risk items (per the paper's bold line) → do not drive
/// until a mechanic inspects. That's handled by the teacher
/// flagging in the notes field and NOT starting the trip, not by
/// the form itself.
const FormDefinition vehicleCheckForm = FormDefinition(
  typeKey: 'vehicle_check',
  title: 'Vehicle Safety Inspection Checklist',
  shortTitle: 'Vehicle check',
  subtitle: 'Complete before each trip. '
      'Checklist mirrors the paper inspection form.',
  icon: Icons.directions_bus_outlined,
  subjectKind: FormSubjectKind.trip,
  // Linear wizard: the whole point of a pre-trip check is to walk
  // every row, not to cherry-pick. Page-per-section forces that
  // discipline, and the teacher can't accidentally ship without
  // looking at brakes.
  presentation: FormPresentation.wizard,
  sections: [
    FormSection(
      title: 'Vehicle information',
      subtitle: 'Driver must complete before each trip.',
      fields: [
        // Vehicle id is the new source-of-truth. Legacy data from
        // pre-v37 checks (which carried `vehicle_make_model` +
        // `license_plate` as free text) still round-trips — those
        // keys are ignored by the picker and surface as read-only
        // context in the form-list summary for old rows.
        FormVehiclePickerField(
          key: 'vehicle_id',
          label: 'Vehicle',
          required: true,
        ),
        FormTextField(
          key: 'driver_name',
          label: 'Driver name',
        ),
        FormDateField(
          key: 'check_datetime',
          label: 'Date & time',
          includeTime: true,
          defaultsToNow: true,
        ),
        FormTextField(
          key: 'odometer',
          label: 'Odometer',
          hint: 'e.g. 62764',
          keyboard: FormTextKeyboard.number,
        ),
        FormTextField(
          key: 'fuel_level',
          label: 'Fuel level (%)',
          hint: 'e.g. 75',
          keyboard: FormTextKeyboard.number,
        ),
      ],
    ),
    FormSection(
      title: 'Lights',
      // Paper form's three-part driver instructions, compressed. First
      // checklist section surfaces them so teachers see the key before
      // tapping their first check mark.
      subtitle: 'Check = acceptable (vehicle OK to drive). '
          'X = needs a mechanic look (drive only if safe). '
          'Any item posing a safety risk → do not drive; flag in '
          'Notes and request immediate inspection.',
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
      subtitle: 'Print legibly.',
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
