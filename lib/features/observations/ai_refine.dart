import 'dart:convert';

import 'package:basecamp/config/env.dart';
import 'package:http/http.dart' as http;

/// Lightly refines a teacher's observation note: keeps every word and the
/// teacher's voice, but fixes typos, punctuation, capitalization, and
/// paragraph breaks. No paraphrasing, no added content, no interpretation.
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
            'temperature': 0.1,
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
You lightly refine a teacher's quick observation note so it reads cleanly — nothing more.

Rules:
- KEEP the teacher's exact wording and voice. Do not paraphrase. Do not swap words for "better" synonyms.
- Allow only a slight polish: fix typos, capitalization, punctuation, spacing, and add sensible paragraph breaks if the note runs on.
- Do NOT add content, details, interpretation, or commentary.
- Do NOT remove content unless it is an obvious dictation artifact (e.g. "uh", "um", stray "comma" spoken aloud).
- Do NOT add a greeting, sign-off, or framing ("Here is the refined note…"). Return only the refined note text.
- Preserve names, numbers, and the teacher's tone exactly.

If the note is already clean, return it nearly identical — the goal is readability, not rewriting.
''';
