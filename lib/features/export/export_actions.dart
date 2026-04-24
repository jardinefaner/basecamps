import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/export/lesson_plan_pdf.dart';
import 'package:basecamp/features/lesson_sequences/lesson_sequences_repository.dart';
import 'package:basecamp/features/rooms/rooms_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

/// Glue between the three export callsites and the pure PDF builders
/// in `lesson_plan_pdf.dart`. Each entry point here:
///   1. Reads the needed data out of the repositories (via providers),
///   2. Builds the PDF bytes,
///   3. Hands them off to [Printing.sharePdf] — which pops the system
///      share sheet on iOS/Android and triggers a download on web.
///
/// Errors surface as a snackbar rather than crashing; PDF rendering
/// failures are rare but the share sheet can also be dismissed or
/// unavailable (certain desktop configs), so we swallow and notify
/// rather than throwing.
///
/// The program name is hardcoded to "Basecamp" for now — a future
/// settings field can plumb in a program-specific letterhead label.
const _programName = 'Basecamp';

Future<void> exportDay(
  BuildContext context,
  WidgetRef ref,
  DateTime date,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final repo = ref.read(scheduleRepositoryProvider);
    final items = await repo.watchScheduleForDate(date).first;

    final groupNames = await _groupNames(ref);
    final adultNames = await _adultNames(ref);
    final roomNames = await _roomNames(ref);

    final bytes = await buildDayPdf(
      date: date,
      items: items,
      groupNamesById: groupNames,
      adultNamesById: adultNames,
      roomNamesById: roomNames,
      programName: _programName,
    );

    await Printing.sharePdf(
      bytes: bytes,
      filename: 'schedule-${_isoDate(date)}.pdf',
    );
  } on Object catch (err) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text("Couldn't build PDF — $err.")),
      );
  }
}

Future<void> exportWeek(
  BuildContext context,
  WidgetRef ref,
  DateTime mondayOfWeek,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final repo = ref.read(scheduleRepositoryProvider);
    final byDay = await repo.watchScheduleForWeek(mondayOfWeek).first;

    final groupNames = await _groupNames(ref);
    final adultNames = await _adultNames(ref);
    final roomNames = await _roomNames(ref);

    final bytes = await buildWeekPdf(
      mondayOfWeek: mondayOfWeek,
      itemsByWeekday: byDay,
      groupNamesById: groupNames,
      adultNamesById: adultNames,
      roomNamesById: roomNames,
      programName: _programName,
    );

    await Printing.sharePdf(
      bytes: bytes,
      filename: 'week-${_isoDate(mondayOfWeek)}.pdf',
    );
  } on Object catch (err) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text("Couldn't build PDF — $err.")),
      );
  }
}

Future<void> exportSequence(
  BuildContext context,
  WidgetRef ref,
  String sequenceId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final repo = ref.read(lessonSequencesRepositoryProvider);
    final sequence = await repo.getSequence(sequenceId);
    if (sequence == null) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Sequence not found.')),
        );
      return;
    }
    final joined = await repo.watchItemsJoined(sequenceId).first;
    final items = joined.map((r) => r.library).toList();

    final bytes = await buildSequencePdf(
      sequence: sequence,
      items: items,
      programName: _programName,
    );

    await Printing.sharePdf(
      bytes: bytes,
      filename: 'sequence-${_slugify(sequence.name)}.pdf',
    );
  } on Object catch (err) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text("Couldn't build PDF — $err.")),
      );
  }
}

// ---------------- helpers ----------------

Future<Map<String, String>> _groupNames(WidgetRef ref) async {
  final groups = await ref.read(groupsProvider.future);
  return {for (final g in groups) g.id: g.name};
}

Future<Map<String, String>> _adultNames(WidgetRef ref) async {
  final adults = await ref.read(adultsProvider.future);
  return {for (final a in adults) a.id: a.name};
}

Future<Map<String, String>> _roomNames(WidgetRef ref) async {
  final rooms = await ref.read(roomsProvider.future);
  return {for (final r in rooms) r.id: r.name};
}

String _isoDate(DateTime d) {
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd';
}

/// Kebab-cased filename fragment for a sequence. Keeps letters,
/// digits, and dashes; collapses runs of other characters into a
/// single `-`; strips leading/trailing dashes. Falls back to
/// "sequence" for names with no legal characters (all-emoji, etc.).
String _slugify(String raw) {
  final lower = raw.toLowerCase();
  final sb = StringBuffer();
  var prevDash = false;
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    final isAlnum = RegExp('[a-z0-9]').hasMatch(ch);
    if (isAlnum) {
      sb.write(ch);
      prevDash = false;
    } else if (!prevDash) {
      sb.write('-');
      prevDash = true;
    }
  }
  final cleaned = sb.toString().replaceAll(RegExp(r'^-+|-+$'), '');
  return cleaned.isEmpty ? 'sequence' : cleaned;
}
