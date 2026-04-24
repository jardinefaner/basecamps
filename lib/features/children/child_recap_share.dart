import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/attendance/attendance_repository.dart';
import 'package:basecamp/features/forms/polymorphic/form_submission_repository.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Opens the "Share today's recap" sheet for [child]. Gathers today's
/// schedule items targeting the child's group, today's observations
/// tagged to the child, today's attendance row, and any child-scoped
/// incident form submissions, formats them into a plain-text recap,
/// and hands the string to the system share sheet.
///
/// When the day has nothing recorded yet, shows a snackbar instead of
/// opening the share sheet so the teacher doesn't accidentally text
/// the parent an empty message.
Future<void> showChildRecapShareSheet(
  BuildContext context,
  Child child,
) async {
  // Spin a modal loader while we collect rows — there are a handful of
  // reads and on cold cache they aren't instant.
  final recap = await showDialog<RecapResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _RecapLoaderDialog(child: child),
  );
  if (recap == null) return;
  if (!context.mounted) return;

  if (recap.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'No program activity recorded for ${child.firstName} '
          'today yet. Try again later.',
        ),
      ),
    );
    return;
  }

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
                "Share ${child.firstName}'s recap",
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
              child: Text(
                recap.text,
                style: Theme.of(ctx).textTheme.bodySmall,
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
                  text: recap.text,
                  subject: "${child.firstName}'s day at program",
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
              await Clipboard.setData(ClipboardData(text: recap.text));
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Recap copied to clipboard'),
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

/// Loads the day's data and pops itself with the formatted recap.
/// Isolated so the main flow doesn't have to juggle async state or
/// provider scopes — the dialog owns the one-shot read.
class _RecapLoaderDialog extends ConsumerStatefulWidget {
  const _RecapLoaderDialog({required this.child});

  final Child child;

  @override
  ConsumerState<_RecapLoaderDialog> createState() =>
      _RecapLoaderDialogState();
}

class _RecapLoaderDialogState extends ConsumerState<_RecapLoaderDialog> {
  @override
  void initState() {
    super.initState();
    // Defer so the dialog gets a frame to paint before we dismiss it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final today = DateTime.now();
    final scheduleRepo = ref.read(scheduleRepositoryProvider);
    final obsRepo = ref.read(observationsRepositoryProvider);
    final attRepo = ref.read(attendanceRepositoryProvider);
    final formRepo = ref.read(formSubmissionRepositoryProvider);

    final schedule = await scheduleRepo.watchScheduleForDate(today).first;
    final observations = await obsRepo.watchForKid(widget.child.id).first;
    final domainsByObs = <String, List<ObservationDomain>>{};
    for (final obs in observations) {
      domainsByObs[obs.id] = await obsRepo.domainsForObservation(obs.id);
    }
    final attendanceMap = await attRepo.watchForDay(today).first;
    final incidents = await formRepo.watchByType('incident').first;

    final recap = buildRecapText(
      child: widget.child,
      date: today,
      activities: schedule,
      observations: observations,
      domainsByObservationId: domainsByObs,
      attendance: attendanceMap[widget.child.id],
      incidents: incidents,
    );

    if (!mounted) return;
    Navigator.of(context).pop(recap);
  }

  @override
  Widget build(BuildContext context) {
    return const Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

/// Result of building a recap: the formatted string plus a flag the
/// caller uses to switch to the empty-state snackbar instead of the
/// share sheet. Public so unit tests can assert directly against it.
@immutable
class RecapResult {
  const RecapResult({required this.text, required this.isEmpty});

  final String text;
  final bool isEmpty;
}

/// Pure formatter — takes already-materialized inputs and returns the
/// recap string + emptiness flag. Split from the UI flow so the tests
/// can exercise every branch without booting a widget tree or a DB.
///
/// "Empty" means no activities targeting this child AND no
/// observations AND no attendance row AND no incidents — in that case
/// the returned text is still formed (for tests that want to inspect
/// it) but the caller is expected to suppress the share sheet.
RecapResult buildRecapText({
  required Child child,
  required DateTime date,
  required List<ScheduleItem> activities,
  required List<Observation> observations,
  required Map<String, List<ObservationDomain>> domainsByObservationId,
  required AttendanceRecord? attendance,
  required List<FormSubmission> incidents,
}) {
  // Activities targeting this child: skip "no-groups" (staff prep) and
  // keep anything all-groups or explicitly on this child's group.
  final mine = activities.where((i) {
    if (i.isNoGroups) return false;
    if (i.isAllGroups) return true;
    final gid = child.groupId;
    return gid != null && i.groupIds.contains(gid);
  }).toList()
    ..sort((a, b) {
      if (a.isFullDay != b.isFullDay) return a.isFullDay ? -1 : 1;
      return a.startMinutes.compareTo(b.startMinutes);
    });

  // Observations linked to this child created today (the repository's
  // watchForKid is not day-scoped, so narrow here).
  final start = DateTime(date.year, date.month, date.day);
  final end = start.add(const Duration(days: 1));
  final todaysObs = observations
      .where(
        (o) => !o.createdAt.isBefore(start) && o.createdAt.isBefore(end),
      )
      .toList();

  // Incidents: child-scoped form submissions with child_id == this
  // child and created today. Stale drafts from other days aren't
  // parent-relevant.
  final todaysIncidents = incidents
      .where(
        (s) =>
            s.childId == child.id &&
            !s.createdAt.isBefore(start) &&
            s.createdAt.isBefore(end),
      )
      .toList();

  final empty = mine.isEmpty &&
      todaysObs.isEmpty &&
      attendance == null &&
      todaysIncidents.isEmpty;

  final b = StringBuffer()
    ..write("Hi, here's ")
    ..write(child.firstName)
    ..write("'s day on ")
    ..write(_formatDate(date))
    ..writeln(':')
    ..writeln();

  if (mine.isNotEmpty) {
    b.writeln('Today at program:');
    for (final item in mine) {
      b
        ..write('\u2022 ')
        ..write(item.title);
      if (item.isFullDay) {
        b.writeln(' \u00b7 all day');
      } else {
        b
          ..write(' \u00b7 ')
          ..write(_formatTime(item.startTime))
          ..write('\u2013')
          ..write(_formatTime(item.endTime))
          ..writeln();
      }
    }
    b.writeln();
  }

  if (todaysObs.isNotEmpty) {
    b
      ..write('Observations (')
      ..write(todaysObs.length)
      ..writeln('):');
    // Track running length so long notes get shaved before the recap
    // blows past the 800-char SMS comfort zone.
    const softLimit = 800;
    for (final obs in todaysObs) {
      final domains = domainsByObservationId[obs.id] ?? const [];
      final primary = domains.isNotEmpty
          ? domains.first
          : ObservationDomain.fromName(obs.domain);
      final code = primary.code;
      final label = primary.label;
      final remaining = softLimit - b.length;
      // Default to 120 chars, but clamp to whatever's left in the
      // budget so later obs + sections still fit.
      final budget = remaining < 40
          ? 40
          : (remaining < 120 ? remaining : 120);
      final note = _truncate(obs.note.trim(), budget);
      b
        ..write('\u2022 ')
        ..write(code);
      if (primary != ObservationDomain.other) {
        b
          ..write(' (')
          ..write(label.toLowerCase())
          ..write(')');
      }
      b
        ..write(': ')
        ..writeln(note);
    }
    b.writeln();
  }

  if (attendance != null) {
    final parts = <String>[];
    final clock = attendance.clockTime;
    if (clock != null && clock.isNotEmpty) {
      parts.add('checked in ${_formatTime(clock)}');
    }
    final pickup = attendance.pickupTime;
    if (pickup != null && pickup.isNotEmpty) {
      final by = attendance.pickedUpBy;
      if (by != null && by.trim().isNotEmpty) {
        parts.add('picked up ${_formatTime(pickup)} by ${by.trim()}');
      } else {
        parts.add('picked up ${_formatTime(pickup)}');
      }
    }
    if (parts.isEmpty) {
      // Row exists but no times — still worth a one-liner so the
      // parent sees the status.
      parts.add(attendance.status.name);
    }
    b
      ..write('Attendance: ')
      ..writeln(parts.join(', '))
      ..writeln();
  }

  if (todaysIncidents.isNotEmpty) {
    b
      ..write('Incidents (')
      ..write(todaysIncidents.length)
      ..writeln('):');
    for (final inc in todaysIncidents) {
      final data = decodeFormData(inc);
      final desc = (data['description'] ?? data['summary'] ?? data['note'])
          ?.toString()
          .trim();
      b.write('\u2022 ');
      if (desc != null && desc.isNotEmpty) {
        b.writeln(_truncate(desc, 120));
      } else {
        b.writeln('Incident report filed');
      }
    }
    b.writeln();
  }

  b
    ..writeln('Any questions, feel free to reach out.')
    ..write('\u2014 Basecamp');

  return RecapResult(text: b.toString(), isEmpty: empty);
}

/// "Mon, Apr 24" — short weekday + month + day. No year (the parent
/// knows what year it is).
String _formatDate(DateTime d) {
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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
  final wd = weekdays[(d.weekday - 1).clamp(0, 6)];
  final mo = months[(d.month - 1).clamp(0, 11)];
  return '$wd, $mo ${d.day}';
}

/// "9:00a" / "10:30a" / "3:12p" — matches the existing timeline row
/// formatter on this screen so the share text reads like the UI.
String _formatTime(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return hhmm;
  final h = int.tryParse(parts[0]) ?? 0;
  final m = parts[1];
  final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
  final period = h < 12 ? 'a' : 'p';
  return m == '00' ? '$hour12$period' : '$hour12:$m$period';
}

/// Trim [s] to [max] chars, ending with a trailing "…" when we cut.
/// Never returns more than [max] characters total.
String _truncate(String s, int max) {
  if (s.length <= max) return s;
  if (max <= 1) return '\u2026';
  return '${s.substring(0, max - 1).trimRight()}\u2026';
}
