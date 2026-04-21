import 'dart:convert';

import 'package:basecamp/config/env.dart';
import 'package:http/http.dart' as http;

/// Structured payload returned by the AI generator. Mirrors the new
/// activity-card columns on `activity_library`: every field the
/// preview renders comes from here.
class GeneratedCard {
  const GeneratedCard({
    required this.title,
    required this.hook,
    required this.summary,
    required this.keyPoints,
    required this.learningGoals,
    required this.engagementTimeMin,
    this.sourceAttribution,
  });

  final String title;
  final String hook;
  final String summary;
  final List<String> keyPoints;
  final List<String> learningGoals;
  final int engagementTimeMin;

  /// Short "via HOST" label. Derived here so the caller doesn't have
  /// to wrangle Uri parsing.
  final String? sourceAttribution;

  bool get isEmpty =>
      title.trim().isEmpty &&
      summary.trim().isEmpty &&
      keyPoints.isEmpty &&
      learningGoals.isEmpty;
}

class GenerateFailure implements Exception {
  const GenerateFailure(this.reason);
  final String reason;
  @override
  String toString() => 'GenerateFailure: $reason';
}

/// Calls OpenAI to turn a scraped page's title + text into an
/// age-appropriate activity card. Uses JSON mode so the response
/// parses cleanly into [GeneratedCard] without regex-wrangling prose.
///
/// Throws [GenerateFailure] with a teacher-facing reason on any error —
/// the caller shows it on the "couldn't read that link" fallback
/// screen.
Future<GeneratedCard> generateActivityCard({
  required String sourceTitle,
  required String sourceText,
  required int audienceMinAge,
  required int audienceMaxAge,
  String? sourceHost,
  String? sourceUrl,
  Duration timeout = const Duration(seconds: 30),
  http.Client? client,
}) async {
  if (!Env.hasOpenAi) {
    throw const GenerateFailure(
      'AI generation is off in this build — set OPENAI_API_KEY.',
    );
  }
  final audienceLabel = audienceLabelFor(audienceMinAge, audienceMaxAge);

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
              {'role': 'system', 'content': _systemPrompt},
              {
                'role': 'user',
                'content': _userPrompt(
                  sourceTitle: sourceTitle,
                  sourceText: sourceText,
                  sourceUrl: sourceUrl,
                  audienceLabel: audienceLabel,
                ),
              },
            ],
          }),
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw GenerateFailure(
        'The generator returned HTTP ${response.statusCode}.',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = body['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const GenerateFailure('The generator returned no content.');
    }
    final message = (choices.first as Map<String, dynamic>)['message']
        as Map<String, dynamic>?;
    final content = message?['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      throw const GenerateFailure('The generator returned empty JSON.');
    }
    final parsed = _parseCardJson(content);
    return GeneratedCard(
      title: parsed.title,
      hook: parsed.hook,
      summary: parsed.summary,
      keyPoints: parsed.keyPoints,
      learningGoals: parsed.learningGoals,
      engagementTimeMin: parsed.engagementTimeMin,
      sourceAttribution:
          sourceHost == null || sourceHost.isEmpty ? null : 'via $sourceHost',
    );
  } on GenerateFailure {
    rethrow;
  } on Object catch (e) {
    throw GenerateFailure("Couldn't generate a card: $e");
  } finally {
    if (client == null) c.close();
  }
}

/// On-demand retrieval fallback — called when client-side scraping
/// couldn't get readable text (paywall, JS-only page, anti-bot, etc.).
/// Hands OpenAI only the URL + audience and asks it to do its best.
///
/// OpenAI's model has broad prior knowledge of popular hosts and URL
/// slugs, which often suffices for well-known sources even without a
/// fresh fetch. Newer OpenAI accounts that have the `web_search` tool
/// enabled will also let the model retrieve directly; this call works
/// either way.
///
/// Returns a [GeneratedCard]; throws [GenerateFailure] if even this
/// fallback produces nothing.
Future<GeneratedCard> generateActivityCardFromUrlOnly({
  required String url,
  required int audienceMinAge,
  required int audienceMaxAge,
  String? sourceHost,
  Duration timeout = const Duration(seconds: 30),
  http.Client? client,
}) async {
  if (!Env.hasOpenAi) {
    throw const GenerateFailure(
      'AI generation is off in this build — set OPENAI_API_KEY.',
    );
  }
  final audienceLabel = audienceLabelFor(audienceMinAge, audienceMaxAge);
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
              {'role': 'system', 'content': _systemPromptUrlOnly},
              {
                'role': 'user',
                'content': 'Audience: $audienceLabel\n'
                    'Source URL: $url\n\n'
                    "We couldn't scrape readable text from this page. "
                    'Generate the card using whatever you know about '
                    'this URL / host / topic. If you have too little '
                    'signal, return the required fields with best-effort '
                    'placeholders rather than refusing — the teacher '
                    'will edit or discard if unsatisfied.',
              },
            ],
          }),
        )
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw GenerateFailure(
        'The generator returned HTTP ${response.statusCode}.',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = body['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const GenerateFailure('The generator returned no content.');
    }
    final message = (choices.first as Map<String, dynamic>)['message']
        as Map<String, dynamic>?;
    final content = message?['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      throw const GenerateFailure('The generator returned empty JSON.');
    }
    final parsed = _parseCardJson(content);
    return GeneratedCard(
      title: parsed.title,
      hook: parsed.hook,
      summary: parsed.summary,
      keyPoints: parsed.keyPoints,
      learningGoals: parsed.learningGoals,
      engagementTimeMin: parsed.engagementTimeMin,
      sourceAttribution:
          sourceHost == null || sourceHost.isEmpty ? null : 'via $sourceHost',
    );
  } on GenerateFailure {
    rethrow;
  } on Object catch (e) {
    throw GenerateFailure("Couldn't generate a card: $e");
  } finally {
    if (client == null) c.close();
  }
}

/// Display label for an audience range: "Age 7" for single-age,
/// "Ages 5–7" for ranges. Used by the wizard's audience chips and the
/// card tile in the library.
String audienceLabelFor(int minAge, int maxAge) {
  if (minAge == maxAge) return 'Age $minAge';
  return 'Ages $minAge–$maxAge';
}

class _ParsedCard {
  const _ParsedCard({
    required this.title,
    required this.hook,
    required this.summary,
    required this.keyPoints,
    required this.learningGoals,
    required this.engagementTimeMin,
  });
  final String title;
  final String hook;
  final String summary;
  final List<String> keyPoints;
  final List<String> learningGoals;
  final int engagementTimeMin;
}

_ParsedCard _parseCardJson(String raw) {
  final Map<String, dynamic> json;
  try {
    json = jsonDecode(raw) as Map<String, dynamic>;
  } on Object catch (e) {
    throw GenerateFailure("Couldn't parse the generator output: $e");
  }
  String str(String key) => (json[key] as String? ?? '').trim();
  List<String> list(String key) {
    final v = json[key];
    if (v is List) {
      return v
          .map((e) => (e?.toString() ?? '').trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  int intOr(String key, int fallback) {
    final v = json[key];
    if (v is num) return v.round();
    if (v is String) {
      final parsed = int.tryParse(v.trim());
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  return _ParsedCard(
    title: str('title'),
    hook: str('hook'),
    summary: str('summary'),
    keyPoints: list('key_points'),
    learningGoals: list('learning_goals'),
    engagementTimeMin: intOr('engagement_time_min', 15).clamp(5, 120),
  );
}

String _userPrompt({
  required String sourceTitle,
  required String sourceText,
  required String audienceLabel,
  String? sourceUrl,
}) {
  // Keep the source text bounded — the scraper already trims, but
  // belt-and-braces.
  final snippet = sourceText.length > 6000
      ? sourceText.substring(0, 6000)
      : sourceText;
  final buf = StringBuffer()
    ..writeln('Audience: $audienceLabel');
  if (sourceUrl != null && sourceUrl.isNotEmpty) {
    // Giving the model the URL alongside the scraped text helps it
    // ground "what kind of page is this?" and — when scraped text is
    // thin (paywall, JS-only page) — fall back on any prior knowledge
    // it has of the host.
    buf.writeln('Source URL: $sourceUrl');
  }
  buf
    ..writeln('Source page title: $sourceTitle')
    ..writeln()
    ..writeln('Source page text:')
    ..writeln(snippet);
  return buf.toString();
}

const String _systemPromptUrlOnly = '''
You turn a URL (alone, without scraped page text) into an age-appropriate "activity card" a teacher can use. You may have prior knowledge of the host/topic from your training.

Return ONLY JSON, exactly these keys:

{
  "title": "Short card title (under 60 chars).",
  "hook": "One short sentence that makes the kid curious.",
  "summary": "2-4 sentences at the audience's reading level about what this source likely covers, why it might interest this age.",
  "key_points": ["3-5 short bullets"],
  "learning_goals": ["1-3 things a kid this age might learn"],
  "engagement_time_min": 15
}

Rules:
- Do not hallucinate specific facts about the exact article. Stay general about the topic / host.
- If the URL is unusable or unknown, return reasonable fallback values — empty hook, generic summary about the host — NEVER an error field.
- Write AT the audience's reading level.
''';

const String _systemPrompt = '''
You turn an arbitrary article / blog / explainer into an age-appropriate "activity card" that a teacher can read in 15 seconds and hand their class.

Return ONLY JSON, no prose, no markdown fences. The JSON must have exactly these keys:

{
  "title": "Short, punchy card title (under 60 chars). Not the raw source title — rewrite for the audience.",
  "hook": "One short sentence that makes the kid curious. Plain, concrete, energetic.",
  "summary": "2–4 sentences at the audience's reading level. Covers what the source is about and why it matters to this age. No filler.",
  "key_points": ["3–5 short bullets", "each under 12 words", "concrete nouns + verbs"],
  "learning_goals": ["1–3 things a kid this age might learn or practice", "each under 12 words"],
  "engagement_time_min": 15
}

Rules:
- Write AT the audience's reading level, not ABOUT it. "Ages 5–7" means short sentences, common words.
- Never invent facts. If the source doesn't cover something, don't add it.
- If the source is too advanced / technical / adult for the audience, still do your best to pull out the age-appropriate parts. Don't refuse.
- `engagement_time_min` is your estimate for how long this holds attention — realistic, usually 5–45.
- All fields are required. If you can't write a useful `hook`, omit it as an empty string — don't fabricate.
''';
