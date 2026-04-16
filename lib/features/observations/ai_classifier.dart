import 'dart:convert';

import 'package:basecamp/config/env.dart';
import 'package:basecamp/features/observations/classifier.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:http/http.dart' as http;

/// OpenAI-backed version of [suggestTags]. Sends the note text to
/// gpt-4o-mini with a strict JSON schema that constrains the response to
/// our `ObservationDomain` and `ObservationSentiment` enums. Falls back
/// to the local keyword classifier when the key is missing or the call
/// fails — the composer works offline and without an API key.
///
/// Pricing is negligible for this use case (<$0.0003/observation at
/// gpt-4o-mini rates for a ~100-token note).
Future<Suggestion> classifyObservationWithAi(String note) async {
  if (!Env.hasOpenAi) return suggestTags(note);
  if (note.trim().isEmpty) return suggestTags(note);

  try {
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${Env.openaiApiKey}',
      },
      body: jsonEncode({
        'model': 'gpt-4o-mini',
        'temperature': 0,
        'messages': [
          {'role': 'system', 'content': _systemPrompt},
          {'role': 'user', 'content': note},
        ],
        'response_format': {
          'type': 'json_schema',
          'json_schema': {
            'name': 'observation_tags',
            'strict': true,
            'schema': {
              'type': 'object',
              'properties': {
                'domain': {
                  'type': 'string',
                  'enum': [
                    'ssd1',
                    'ssd2',
                    'ssd3',
                    'ssd4',
                    'ssd5',
                    'ssd6',
                    'ssd7',
                    'ssd8',
                    'ssd9',
                    'hlth1',
                    'hlth2',
                    'hlth3',
                    'hlth4',
                    'other',
                  ],
                },
                'sentiment': {
                  'type': 'string',
                  'enum': ['positive', 'neutral', 'concern'],
                },
              },
              'required': ['domain', 'sentiment'],
              'additionalProperties': false,
            },
          },
        },
      }),
    ).timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      return suggestTags(note);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = body['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return suggestTags(note);
    final message = (choices.first as Map<String, dynamic>)['message']
        as Map<String, dynamic>?;
    final content = message?['content'] as String?;
    if (content == null) return suggestTags(note);

    final parsed = jsonDecode(content) as Map<String, dynamic>;
    final domainName = parsed['domain'] as String? ?? 'other';
    final sentimentName = parsed['sentiment'] as String? ?? 'neutral';

    return Suggestion(
      domain: ObservationDomain.fromName(domainName),
      sentiment: ObservationSentiment.fromName(sentimentName),
    );
  } on Object {
    return suggestTags(note);
  }
}

const String _systemPrompt = '''
You classify brief teacher observations from a summer program for children into one of these curriculum domains. Pick the single best match based on the most prominent behavior or moment in the note.

Domains:
- ssd1: Identity of self and connection to others — a child expressing who they are, cultural identity, family ties, sense of belonging.
- ssd2: Self-esteem — a child showing pride, confidence, willingness to try, ownership of a success.
- ssd3: Empathy — comforting, noticing feelings, caring, kind gestures toward others.
- ssd4: Impulse control — waiting, pausing, calming down, OR struggling with impulses (hitting, grabbing, yelling).
- ssd5: Follow rules — following instructions, cleaning up, staying in bounds, waiting in line.
- ssd6: Awareness of diversity — noticing / discussing differences or similarities in people, cultures, traditions.
- ssd7: Interactions with adults — how a child engages with teachers or grown-ups (asking for help, confiding, resistance).
- ssd8: Friendship — playing with others, inclusion, invitations, shared play.
- ssd9: Conflict negotiation — disagreements resolved, compromise, apologies, taking turns, sharing.
- hlth1: Safety — awareness of physical safety, careful behavior, risk-taking.
- hlth2: Understanding healthy lifestyle — food choices, sleep, water, rest.
- hlth3: Personal care routine — handwashing, teeth, dressing, toileting, blowing nose.
- hlth4: Exercise and fitness — running, jumping, climbing, swimming, active play.
- other: doesn't clearly fit any above.

Sentiment:
- positive: a win, a moment of pride or breakthrough.
- neutral: a factual note without clear positive or negative tone.
- concern: a struggle, incident, red flag, or distress.

Return only the JSON matching the schema. No prose.
''';
