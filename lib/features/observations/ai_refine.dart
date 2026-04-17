import 'dart:convert';

import 'package:basecamp/config/env.dart';
import 'package:http/http.dart' as http;

/// Rewrites a teacher's quick observation note into a clear, readable
/// version — fixing grammar, cutting filler, restructuring confusing
/// parts — while preserving every fact, name, and number. Goal is "a
/// colleague could read this and understand what happened," not
/// "original but with commas".
///
/// Returns `null` when the key is missing, the input is empty, the call
/// fails, or the model returns nothing — the caller should treat null as
/// "nothing to show" and leave the original untouched.
///
/// Uses gpt-4o-mini for cost; a ~100-token note is well under $0.0005.
Future<String?> refineObservationText(String note) async {
  if (!Env.hasOpenAi) return null;
  final trimmed = note.trim();
  if (trimmed.isEmpty) return null;

  try {
    final response = await http
        .post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${Env.openaiApiKey}',
          },
          body: jsonEncode({
            'model': 'gpt-4o-mini',
            'temperature': 0.2,
            'max_tokens': 600,
            'messages': [
              {'role': 'system', 'content': _systemPrompt},
              {'role': 'user', 'content': trimmed},
            ],
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = body['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return null;
    final message = (choices.first as Map<String, dynamic>)['message']
        as Map<String, dynamic>?;
    final content = (message?['content'] as String?)?.trim();
    if (content == null || content.isEmpty) return null;
    return content;
  } on Object {
    return null;
  }
}

const String _systemPrompt = '''
You refine a teacher's quick observation note into a clear, readable version. Teachers dictate these in the middle of a classroom — so the raw note is often rushed, fragmented, or full of filler. Your job is to make it make sense.

Goals, in order:
1. Make it readable. If the note is confusing, fragmented, or dictated hastily, restructure it so a colleague could read it and instantly understand what happened.
2. Cut every unnecessary word. Remove filler ("uh", "um", "you know", "like", "so", "basically"), stalling, rambling, repetition, false starts ("she — she was"), and spoken-aloud punctuation ("comma", "period"). Prefer active voice.
3. Preserve every fact, name, number, quote, and observation. Do not invent, infer, or embellish.
4. Keep the teacher's warmth and specificity. Do not flatten into bureaucratic boilerplate. If the teacher said "Mia lit up," keep that energy.
5. Fix grammar, spelling, punctuation, and capitalization. Use paragraph breaks for multi-event notes.

Do NOT:
- Add any content, details, context, or interpretation the original didn't contain
- Add a greeting, sign-off, or framing ("Here is the refined note…")
- Change names or numbers
- Remove hedging ("I think", "maybe") if it's a genuine observation of uncertainty — that's a fact about the teacher's read of the situation

If the note is already clear and concise, return it close to unchanged. Return only the refined note text. No prose, no explanation.
''';
