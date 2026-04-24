import 'dart:convert';

import 'package:basecamp/config/env.dart';
import 'package:http/http.dart' as http;

/// A draft library card produced by the AI authoring helpers. Every
/// field except [title] is nullable so the caller can distinguish
/// "model didn't fill this" from "model said empty string" and only
/// splat non-null values into empty controllers on the edit sheet.
///
/// Multi-line fields ([keyPoints], [learningGoals], [materials]) come
/// out as already-joined strings — matches how the `activity_library`
/// row stores them (newline-separated text blobs), so the edit sheet
/// can drop them straight into a TextField controller.
class LibraryCardDraft {
  const LibraryCardDraft({
    required this.title,
    this.summary,
    this.hook,
    this.keyPoints,
    this.learningGoals,
    this.audienceMinAge,
    this.audienceMaxAge,
    this.engagementTimeMin,
    this.materials,
    this.sourceUrl,
    this.sourceAttribution,
  });

  /// Parses the OpenAI JSON payload into a draft. Accepts camelCase
  /// and snake_case keys so a model that drifts style doesn't break
  /// the parse. List fields (key_points / learning_goals / materials)
  /// are flattened to newline-joined strings; numeric fields accept
  /// number or numeric string.
  ///
  /// Throws [LibraryDraftParseError] on bad input — caller surfaces
  /// a snackbar.
  factory LibraryCardDraft.fromJson(
    Map<String, dynamic> json, {
    String? sourceUrlOverride,
  }) {
    String? str(String a, [String? b]) {
      final v = json[a] ?? (b == null ? null : json[b]);
      if (v is String) {
        final trimmed = v.trim();
        return trimmed.isEmpty ? null : trimmed;
      }
      return null;
    }

    String? joined(String a, [String? b]) {
      final v = json[a] ?? (b == null ? null : json[b]);
      if (v is List) {
        final lines = v
            .map((e) => (e?.toString() ?? '').trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (lines.isEmpty) return null;
        return lines.join('\n');
      }
      if (v is String) {
        final trimmed = v.trim();
        return trimmed.isEmpty ? null : trimmed;
      }
      return null;
    }

    int? intOr(String a, [String? b]) {
      final v = json[a] ?? (b == null ? null : json[b]);
      if (v is num) return v.round();
      if (v is String) return int.tryParse(v.trim());
      return null;
    }

    final rawTitle = str('title') ?? '';
    if (rawTitle.isEmpty) {
      throw const LibraryDraftParseError(
        'The generator returned a card with no title.',
      );
    }

    return LibraryCardDraft(
      title: rawTitle,
      summary: str('summary'),
      hook: str('hook'),
      keyPoints: joined('keyPoints', 'key_points'),
      learningGoals: joined('learningGoals', 'learning_goals'),
      audienceMinAge: intOr('audienceMinAge', 'audience_min_age'),
      audienceMaxAge: intOr('audienceMaxAge', 'audience_max_age'),
      engagementTimeMin: intOr('engagementTimeMin', 'engagement_time_min'),
      materials: joined('materials'),
      sourceUrl: sourceUrlOverride ?? str('sourceUrl', 'source_url'),
      sourceAttribution: str('sourceAttribution', 'source_attribution'),
    );
  }

  final String title;
  final String? summary;
  final String? hook;
  final String? keyPoints;
  final String? learningGoals;
  final int? audienceMinAge;
  final int? audienceMaxAge;
  final int? engagementTimeMin;
  final String? materials;
  final String? sourceUrl;
  final String? sourceAttribution;
}

/// Raised when an AI call fails in a way the UI should surface. Message
/// is teacher-facing; keep it short and actionable.
class LibraryDraftFailure implements Exception {
  const LibraryDraftFailure(this.message);
  final String message;
  @override
  String toString() => 'LibraryDraftFailure: $message';
}

/// Thrown by [LibraryCardDraft.fromJson] when the payload is malformed.
/// A [LibraryDraftFailure] unless the caller catches it specifically —
/// wrapped with the same surface semantics.
class LibraryDraftParseError extends LibraryDraftFailure {
  const LibraryDraftParseError(super.message);
}

/// Generates a library-card draft from a URL alone. Matches the
/// `ai_classifier.dart` pattern: chat-completions endpoint, JSON
/// response_format, same timeout shape. Throws [LibraryDraftFailure]
/// when the key is missing or the call fails, so the edit sheet can
/// toast a clear message without crashing.
Future<LibraryCardDraft> generateFromUrl(
  String url, {
  Duration timeout = const Duration(seconds: 30),
  http.Client? client,
}) async {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    throw const LibraryDraftFailure('Paste a link first.');
  }
  if (!Env.hasOpenAi) {
    throw const LibraryDraftFailure(
      'AI assist is off in this build — set OPENAI_API_KEY.',
    );
  }
  final c = client ?? http.Client();
  try {
    final response = await c
        .post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${Env.openaiApiKey}',
          },
          body: jsonEncode({
            'model': 'gpt-4o-mini',
            'temperature': 0.4,
            'response_format': {'type': 'json_object'},
            'messages': [
              {'role': 'system', 'content': _systemPromptUrl},
              {'role': 'user', 'content': 'URL: $trimmed'},
            ],
          }),
        )
        .timeout(timeout);
    final payload = _extractJsonObject(response);
    return LibraryCardDraft.fromJson(payload, sourceUrlOverride: trimmed);
  } on LibraryDraftFailure {
    rethrow;
  } on Object catch (e) {
    throw LibraryDraftFailure("Couldn't fill from link: $e");
  } finally {
    if (client == null) c.close();
  }
}

/// Generates a library-card draft from a free-text description. No
/// URL, no attribution — purely the teacher's own words polished into
/// a card shape.
Future<LibraryCardDraft> generateFromDescription(
  String description, {
  Duration timeout = const Duration(seconds: 30),
  http.Client? client,
}) async {
  final trimmed = description.trim();
  if (trimmed.length < 10) {
    throw const LibraryDraftFailure(
      'Give me a bit more to work with — a sentence or two is enough.',
    );
  }
  if (!Env.hasOpenAi) {
    throw const LibraryDraftFailure(
      'AI assist is off in this build — set OPENAI_API_KEY.',
    );
  }
  final c = client ?? http.Client();
  try {
    final response = await c
        .post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${Env.openaiApiKey}',
          },
          body: jsonEncode({
            'model': 'gpt-4o-mini',
            'temperature': 0.4,
            'response_format': {'type': 'json_object'},
            'messages': [
              {'role': 'system', 'content': _systemPromptDescription},
              {'role': 'user', 'content': trimmed},
            ],
          }),
        )
        .timeout(timeout);
    final payload = _extractJsonObject(response);
    return LibraryCardDraft.fromJson(payload);
  } on LibraryDraftFailure {
    rethrow;
  } on Object catch (e) {
    throw LibraryDraftFailure("Couldn't fill from description: $e");
  } finally {
    if (client == null) c.close();
  }
}

Map<String, dynamic> _extractJsonObject(http.Response response) {
  if (response.statusCode != 200) {
    throw LibraryDraftFailure(
      'The generator returned HTTP ${response.statusCode}.',
    );
  }
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final choices = body['choices'] as List<dynamic>?;
  if (choices == null || choices.isEmpty) {
    throw const LibraryDraftFailure('The generator returned no content.');
  }
  final message = (choices.first as Map<String, dynamic>)['message']
      as Map<String, dynamic>?;
  final content = message?['content'] as String?;
  if (content == null || content.trim().isEmpty) {
    throw const LibraryDraftFailure('The generator returned empty JSON.');
  }
  try {
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const LibraryDraftParseError(
        'The generator returned something that is not a JSON object.',
      );
    }
    return decoded;
  } on FormatException catch (e) {
    throw LibraryDraftParseError(
      "Couldn't parse the generator output: ${e.message}",
    );
  }
}

const String _systemPromptUrl = '''
You are helping a preschool teacher import an activity idea from a webpage. Given this URL, return a JSON object describing the activity. Fields:
- title: short, concrete activity title
- summary: 2-3 sentences at a teacher's reading level
- hook: one-line teaser that makes a kid curious
- keyPoints: array of 3-5 short bullets
- learningGoals: array of 2-4 short bullets
- audienceMinAge: integer (years)
- audienceMaxAge: integer (years)
- engagementTimeMin: integer (minutes)
- materials: array of strings
- sourceAttribution: short label like "BBC.com" or "Pinterest — Sarah Jones"

Return valid JSON only, no prose, no markdown. Omit fields you can't populate confidently rather than inventing.
''';

const String _systemPromptDescription = '''
You are helping a preschool teacher author an activity. Given a short description, return a JSON object with:
- title: short, concrete activity title
- summary: 2-3 sentences at a teacher's reading level that faithfully captures the teacher's intent
- hook: one-line teaser
- keyPoints: array of 3-5 short bullets
- learningGoals: array of 2-4 short bullets
- audienceMinAge: integer (years)
- audienceMaxAge: integer (years)
- engagementTimeMin: integer (minutes)
- materials: array of strings

Stick to what the teacher described — do not invent new concepts, examples, or materials they did not mention. Return JSON only, no prose, no markdown. Omit fields you can't populate.
''';
