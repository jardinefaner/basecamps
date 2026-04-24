import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/forms/polymorphic/form_definition.dart'
    as fd;
import 'package:basecamp/features/forms/polymorphic/form_submission_repository.dart';
import 'package:basecamp/features/vehicles/vehicles_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Opens a bottom-sheet preview of [submission] rendered as a plain-
/// text bundle, with Share + Copy actions. The bundle walks every
/// section in [definition] and, for each answered field, writes a
/// "Label: value" line formatted per field type.
///
/// Empty sections (no answered fields) are omitted so the output
/// stays scannable — no bare "SECTION NAME" headers with nothing
/// under them.
///
/// Mirrors the parent-concern share sheet's shape (see
/// `parent_concern_share.dart`); this one is the generic sibling for
/// every polymorphic form type.
Future<void> showFormSubmissionShareSheet(
  BuildContext context,
  WidgetRef ref,
  FormSubmission submission,
  fd.FormDefinition definition,
) async {
  // Pull vehicle + child lists once so the formatter can resolve
  // picker ids to human strings. Latest snapshot — no watch.
  final vehicles = await ref.read(vehiclesProvider.future);
  final children = await ref.read(childrenProvider.future);
  final vehicleNamesById = <String, String>{
    for (final v in vehicles) v.id: _vehicleSummary(v),
  };
  final childNamesById = <String, String>{
    for (final c in children) c.id: _childDisplayName(c),
  };

  final text = buildFormSubmissionShareText(
    submission: submission,
    definition: definition,
    vehicleNamesById: vehicleNamesById,
    childNamesById: childNamesById,
  );

  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Share ${definition.shortTitle.toLowerCase()}',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
            ),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                child: Text(
                  text,
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('Share…'),
            subtitle: const Text(
              'Send via Messages, Mail, or any sharing app',
            ),
            onTap: () async {
              Navigator.of(ctx).pop();
              await SharePlus.instance.share(
                ShareParams(
                  text: text,
                  subject: definition.title,
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text('Copy to clipboard'),
            subtitle: const Text(
              kIsWeb
                  ? 'Safer than Share on web — paste into any app'
                  : 'Paste into any app',
            ),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    ),
  );
}

/// Pure formatter: walks [submission]'s decoded data against
/// [definition] and returns the share text. Split from the UI flow
/// so unit tests can exercise every field-type branch without
/// booting a widget tree.
///
/// Resolution maps ([vehicleNamesById], [childNamesById]) are looked
/// up for picker fields; when an id is missing from the map, the
/// formatter falls back to "(deleted vehicle)" / "(deleted child)"
/// so the reader knows the reference existed but the subject is gone.
String buildFormSubmissionShareText({
  required FormSubmission submission,
  required fd.FormDefinition definition,
  required Map<String, String> vehicleNamesById,
  required Map<String, String> childNamesById,
}) {
  final data = decodeFormData(submission);
  final b = StringBuffer()
    ..writeln(definition.title);

  // Metadata line: "Submitted <date> · <author or "Basecamp">".
  // Drafts with no submittedAt fall back to createdAt so the reader
  // still gets a timestamp; labeled "Submitted" in both cases because
  // it's the only stamp the form surfaces externally.
  final stamp = submission.submittedAt ?? submission.createdAt;
  final author = (submission.authorName?.trim().isNotEmpty ?? false)
      ? submission.authorName!.trim()
      : 'Basecamp';
  b
    ..write('Submitted ')
    ..write(_formatDateTime(stamp))
    ..write(' \u00b7 ')
    ..writeln(author);

  for (final section in definition.sections) {
    final lines = <String>[];
    for (final field in section.fields) {
      final line = _renderField(
        field: field,
        data: data,
        vehicleNamesById: vehicleNamesById,
        childNamesById: childNamesById,
      );
      if (line != null) lines.add(line);
    }
    if (lines.isEmpty) continue;
    b
      ..writeln()
      ..writeln(section.title.toUpperCase());
    for (final line in lines) {
      b
        ..write('  ')
        ..writeln(line);
    }
  }

  b
    ..writeln()
    ..write('\u2014 Basecamp');
  return b.toString();
}

/// Dispatches on [field]'s concrete type and produces a single
/// "Label: value" line, or null when the field has no renderable
/// value (empty optional text, unset checklist, etc.).
String? _renderField({
  required fd.FormField field,
  required Map<String, dynamic> data,
  required Map<String, String> vehicleNamesById,
  required Map<String, String> childNamesById,
}) {
  return switch (field) {
    fd.FormTextField() => _renderText(field, data),
    fd.FormDateField() => _renderDate(field, data),
    fd.FormChecklistStatusField() => _renderChecklist(field, data),
    fd.FormChoiceField() => _renderChoice(field, data),
    fd.FormMultiChoiceField() => _renderMultiChoice(field, data),
    fd.FormBoolField() => _renderBool(field, data),
    fd.FormVehiclePickerField() =>
      _renderVehicle(field, data, vehicleNamesById),
    fd.FormChildPickerField() => _renderChild(field, data, childNamesById),
  };
}

String? _renderText(fd.FormTextField field, Map<String, dynamic> data) {
  final raw = data[field.key];
  if (raw is! String) {
    // Missing entirely — keep required fields visible (with a blank)
    // so the reader can see the gap; omit optional ones.
    if (field.required) return '${field.label}: ';
    return null;
  }
  final trimmed = raw.trim();
  if (trimmed.isEmpty && !field.required) return null;
  return '${field.label}: $trimmed';
}

String? _renderDate(fd.FormDateField field, Map<String, dynamic> data) {
  final raw = data[field.key];
  if (raw is! String) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  return '${field.label}: ${_formatDate(parsed, includeTime: field.includeTime)}';
}

String? _renderChecklist(
  fd.FormChecklistStatusField field,
  Map<String, dynamic> data,
) {
  final raw = data[field.key];
  if (raw is! String) return null;
  return switch (raw) {
    'ok' => '${field.label}: \u2713 OK',
    'attention' => '${field.label}: \u2717 Needs inspection',
    _ => null,
  };
}

String? _renderChoice(fd.FormChoiceField field, Map<String, dynamic> data) {
  final raw = data[field.key];
  if (raw is! String) return null;
  for (final opt in field.options) {
    if (opt.key == raw) return '${field.label}: ${opt.label}';
  }
  return null;
}

String? _renderMultiChoice(
  fd.FormMultiChoiceField field,
  Map<String, dynamic> data,
) {
  final raw = data[field.key];
  if (raw is! List) return null;
  final keys = raw.whereType<String>().toSet();
  if (keys.isEmpty) return null;
  final labels = <String>[];
  // Preserve the definition's option order so output is stable
  // regardless of how the keys were stored.
  for (final opt in field.options) {
    if (keys.contains(opt.key)) labels.add(opt.label);
  }
  if (labels.isEmpty) return null;
  return '${field.label}: ${labels.join(", ")}';
}

String? _renderBool(fd.FormBoolField field, Map<String, dynamic> data) {
  final raw = data[field.key];
  if (raw is! bool) return null;
  return '${field.label}: ${raw ? "Yes" : "No"}';
}

String? _renderVehicle(
  fd.FormVehiclePickerField field,
  Map<String, dynamic> data,
  Map<String, String> vehicleNamesById,
) {
  final raw = data[field.key];
  if (raw is! String || raw.isEmpty) return null;
  final resolved = vehicleNamesById[raw] ?? '(deleted vehicle)';
  return '${field.label}: $resolved';
}

String? _renderChild(
  fd.FormChildPickerField field,
  Map<String, dynamic> data,
  Map<String, String> childNamesById,
) {
  final raw = data[field.key];
  if (raw is! String || raw.isEmpty) return null;
  final resolved = childNamesById[raw] ?? '(deleted child)';
  return '${field.label}: $resolved';
}

/// "Apr 24, 2026" / "Apr 24, 2026 · 9:30a" — matches the spec.
String _formatDate(DateTime d, {bool includeTime = false}) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final mo = months[(d.month - 1).clamp(0, 11)];
  final datePart = '$mo ${d.day}, ${d.year}';
  if (!includeTime) return datePart;
  return '$datePart \u00b7 ${_formatTimeOfDay(d)}';
}

/// Used for the "Submitted …" header line — always shows time so the
/// reader can tell multiple same-day submissions apart.
String _formatDateTime(DateTime d) {
  return _formatDate(d, includeTime: true);
}

/// "9:30a" / "12p" / "3:12p" — mirrors the recap share formatter so
/// the two pieces of shared text read with the same voice.
String _formatTimeOfDay(DateTime d) {
  final h = d.hour;
  final m = d.minute.toString().padLeft(2, '0');
  final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
  final period = h < 12 ? 'a' : 'p';
  return m == '00' ? '$hour12$period' : '$hour12:$m$period';
}

/// Mirrors `_vehicleSummary` in generic_form_screen.dart so the
/// share bundle reads with the same vehicle identity the picker
/// button showed.
String _vehicleSummary(Vehicle v) {
  final extras = <String>[];
  if (v.makeModel.isNotEmpty) extras.add(v.makeModel);
  if (v.licensePlate.isNotEmpty) extras.add(v.licensePlate);
  return extras.isEmpty ? v.name : '${v.name} \u00b7 ${extras.join(" \u00b7 ")}';
}

/// "Firstname L." — mirrors `_displayName` / `_childDisplayName` in
/// the launcher and form screen so saved submissions read the child's
/// name the same way everywhere.
String _childDisplayName(Child c) {
  final last = c.lastName;
  if (last == null || last.trim().isEmpty) return c.firstName;
  return '${c.firstName} ${last.trim()[0]}.';
}
