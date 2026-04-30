import 'dart:convert';

import 'package:basecamp/core/format/date.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/attendance/attendance_repository.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/curriculum/curriculum_today.dart';
import 'package:basecamp/features/lesson_sequences/lesson_sequences_repository.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tool catalog for the Ask Basecamp agent.
///
/// Each tool is a small function the LLM can call to fetch a slice
/// of program state. Tools are intentionally narrow — instead of
/// 'give me everything,' each one returns a focused JSON document
/// that fits in a few hundred tokens.
///
/// This is the mechanism that makes the chat *cheap*: the system
/// prompt + tool definitions are tiny (a few hundred tokens) and
/// the LLM only pulls the specific data it needs to answer the
/// current question. No vector DB, no full-state dump, no chat
/// history persisted.
///
/// All tool handlers are pure async functions over a [Ref] — they
/// read existing Riverpod providers to stay consistent with what
/// the rest of the app sees. JSON output goes back to the LLM via
/// the chat-completions `tool` role message.

/// JSON schema for OpenAI's tool-calling. Each entry mirrors the
/// `tools` array in a chat-completions request body.
const List<Map<String, Object?>> askToolSchemas = [
  {
    'type': 'function',
    'function': {
      'name': 'today_overview',
      'description':
          'High-level snapshot of today: date, day of week, total '
              'scheduled activities, children-present count, and how '
              'many observations have been logged so far. Call this '
              "first when the user asks general 'how is today going' "
              'questions.',
      'parameters': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'required': <String>[],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'today_schedule',
      'description':
          "Return today's scheduled activities in chronological "
              'order. Each entry includes title, start/end time, '
              'group(s), and the assigned adult name.',
      'parameters': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'required': <String>[],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'today_curriculum',
      'description':
          'If the program has an active curriculum theme, return '
              'the current theme name + week number + sequence '
              'title + the daily-ritual cards for this week. Returns '
              'null when no theme covers today.',
      'parameters': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'required': <String>[],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'find_child',
      'description':
          'Search the children roster by name (case-insensitive '
              'substring on first or last name). Use when the user '
              'mentions a child by name and you need their id '
              'before calling other tools that require it.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Name fragment to match',
          },
        },
        'required': ['query'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'child_recent_observations',
      'description':
          'Return up to 10 of the most recent observations on a '
              'specific child. Each entry includes the note, '
              'domain, sentiment, and relative timestamp.',
      'parameters': {
        'type': 'object',
        'properties': {
          'child_id': {
            'type': 'string',
            'description': 'Child id from find_child',
          },
        },
        'required': ['child_id'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'find_adult',
      'description':
          'Search the staff roster by name. Returns matching '
              'adults with their id, role, and anchored group.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Name fragment to match',
          },
        },
        'required': ['query'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'open_screen',
      'description':
          'Tell the app to navigate the user to a specific route '
              'after answering. Use sparingly — only when the user '
              'is clearly asking to *go somewhere* rather than to '
              'be told something. Routes that are valid: '
              "'/today', '/observations', '/children/<id>', "
              "'/more/adults/<id>', '/more/curriculum', "
              "'/today/schedule', '/more/library', '/more/setup', "
              "'/more/settings'.",
      'parameters': {
        'type': 'object',
        'properties': {
          'route': {
            'type': 'string',
            'description': 'Route to push',
          },
          'reason': {
            'type': 'string',
            'description':
                'Short label shown on the action button '
                "(e.g. 'Open Today', \"See Sarah's profile\").",
          },
        },
        'required': ['route', 'reason'],
      },
    },
  },
];

/// Result of executing a tool call. Most tools return JSON [data]
/// that gets serialized back to the LLM. The `open_screen` tool is
/// special — it sets [navIntent], which the chat surface picks up
/// and renders as a tappable action chip.
class AskToolResult {
  const AskToolResult({this.data, this.navIntent});

  final Map<String, dynamic>? data;
  final NavIntent? navIntent;
}

class NavIntent {
  const NavIntent({required this.route, required this.label});
  final String route;
  final String label;
}

/// Dispatch a tool call by name. Unknown names return a stub error
/// payload — the LLM will see the failure and either retry with a
/// different tool or give up cleanly.
Future<AskToolResult> runAskTool({
  required Ref ref,
  required String name,
  required Map<String, dynamic> args,
}) async {
  switch (name) {
    case 'today_overview':
      return AskToolResult(data: await _todayOverview(ref));
    case 'today_schedule':
      return AskToolResult(data: await _todaySchedule(ref));
    case 'today_curriculum':
      return AskToolResult(data: await _todayCurriculum(ref));
    case 'find_child':
      return AskToolResult(
        data: await _findChild(ref, args['query'] as String? ?? ''),
      );
    case 'child_recent_observations':
      return AskToolResult(
        data: await _childRecentObservations(
          ref,
          args['child_id'] as String? ?? '',
        ),
      );
    case 'find_adult':
      return AskToolResult(
        data: await _findAdult(ref, args['query'] as String? ?? ''),
      );
    case 'open_screen':
      final route = args['route'] as String? ?? '';
      final reason = args['reason'] as String? ?? 'Open';
      if (route.isEmpty) {
        return const AskToolResult(
          data: {'error': 'route is required'},
        );
      }
      return AskToolResult(
        data: {'queued': true, 'route': route, 'label': reason},
        navIntent: NavIntent(route: route, label: reason),
      );
  }
  return AskToolResult(data: {'error': 'unknown tool: $name'});
}

// ---------------------------------------------------------------------------
// Tool handlers
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> _todayOverview(Ref ref) async {
  final now = DateTime.now();
  final today = now.dayOnly;
  final schedule =
      await ref.read(scheduleForDateProvider(today).future);
  // attendanceForDayProvider yields a Map<childId, AttendanceRecord>;
  // count by status.
  final attendance =
      await ref.read(attendanceForDayProvider(today).future);
  final present = attendance.values.where((a) {
    return a.status == AttendanceStatus.present ||
        a.status == AttendanceStatus.late;
  }).length;
  final observations = await ref.read(observationsProvider.future);
  final tomorrow = today.add(const Duration(days: 1));
  final todaysObservations = observations.where((o) {
    final ts = o.createdAt.toLocal();
    return !ts.isBefore(today) && ts.isBefore(tomorrow);
  }).length;
  return {
    'date': _formatDate(today),
    'weekday': _weekdayName(today.weekday),
    'scheduled_activities': schedule.length,
    'children_present': present,
    'observations_logged_today': todaysObservations,
  };
}

Future<Map<String, dynamic>> _todaySchedule(Ref ref) async {
  final now = DateTime.now();
  final today = now.dayOnly;
  final items = await ref.read(scheduleForDateProvider(today).future);
  // ScheduleItem carries adultId only — resolve to a name so the
  // LLM can present human-readable answers without a second call.
  final adults = await ref.read(adultsProvider.future);
  final adultsById = {for (final a in adults) a.id: a};
  return {
    'date': _formatDate(today),
    'items': [
      for (final item in items)
        {
          'title': item.title,
          'start': item.startTime,
          'end': item.endTime,
          'is_full_day': item.isFullDay,
          'all_groups': item.allGroups,
          'adult': item.adultId == null
              ? ''
              : adultsById[item.adultId]?.name ?? '',
          'location': item.location ?? '',
        },
    ],
  };
}

Future<Map<String, dynamic>> _todayCurriculum(Ref ref) async {
  final now = DateTime.now();
  final today = now.dayOnly;
  final day =
      await ref.read(curriculumForDateProvider(today).future);
  if (day == null) {
    return {'has_curriculum': false};
  }
  final ritualEntries = <SequenceItemWithLibrary>[];
  final arc = day.arc;
  if (arc != null) {
    for (var d = 1; d <= 5; d++) {
      final items = arc.dailyByWeekday[d];
      if (items != null) ritualEntries.addAll(items);
    }
    ritualEntries.addAll(arc.dailyUnscheduled);
  }
  return {
    'has_curriculum': true,
    'theme': day.theme.name,
    'week_index': day.weekIndex + 1,
    'total_weeks': day.totalWeeks,
    'sequence_title': day.sequence?.name,
    'core_question': day.sequence?.coreQuestion ?? '',
    'phase': day.sequence?.phase ?? '',
    'rituals': [
      for (final entry in ritualEntries)
        {
          'title': entry.library.title,
          'description': entry.library.summary ?? '',
        },
    ],
    'milestones': [
      for (final entry in arc?.milestones ?? const <SequenceItemWithLibrary>[])
        {
          'title': entry.library.title,
          'description': entry.library.summary ?? '',
        },
    ],
  };
}

Future<Map<String, dynamic>> _findChild(Ref ref, String query) async {
  final children = await ref.read(childrenProvider.future);
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return {'matches': <Map<String, Object?>>[]};
  final matches = [
    for (final c in children)
      if (c.firstName.toLowerCase().contains(q) ||
          (c.lastName ?? '').toLowerCase().contains(q))
        {
          'id': c.id,
          'first_name': c.firstName,
          'last_name': c.lastName ?? '',
          'group_id': c.groupId ?? '',
        },
  ];
  return {'matches': matches.take(10).toList()};
}

Future<Map<String, dynamic>> _childRecentObservations(
  Ref ref,
  String childId,
) async {
  if (childId.isEmpty) {
    return {'observations': <Map<String, Object?>>[]};
  }
  final all = await ref.read(observationsProvider.future);
  final mine = all.where((o) => o.childId == childId).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final recent = mine.take(10);
  return {
    'observations': [
      for (final o in recent)
        {
          'note': o.note,
          'domain': o.domain,
          'sentiment': o.sentiment,
          'created_at': o.createdAt.toIso8601String(),
        },
    ],
  };
}

Future<Map<String, dynamic>> _findAdult(Ref ref, String query) async {
  final adults = await ref.read(adultsProvider.future);
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return {'matches': <Map<String, Object?>>[]};
  final matches = [
    for (final a in adults)
      if (a.name.toLowerCase().contains(q))
        {
          'id': a.id,
          'name': a.name,
          'role': a.role ?? '',
          'anchored_group_id': a.anchoredGroupId ?? '',
        },
  ];
  return {'matches': matches.take(10).toList()};
}

String _formatDate(DateTime d) {
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

String _weekdayName(int w) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return w >= 1 && w <= 7 ? names[w - 1] : '';
}

/// JSON-stringifies a tool result for the LLM. Returns '{}' on null
/// to keep the chat-completions API happy (it requires non-null
/// content on tool messages).
String encodeToolResult(Map<String, dynamic>? data) {
  if (data == null) return '{}';
  return jsonEncode(data);
}
