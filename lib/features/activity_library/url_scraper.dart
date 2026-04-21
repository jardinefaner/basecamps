import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

/// Result of fetching a URL for activity-card generation. Either a
/// successful pull of the page's title + main text (ready to hand to
/// the AI), or a reason the pull failed.
class ScrapedPage {
  const ScrapedPage({
    required this.url,
    required this.title,
    required this.text,
    required this.host,
  });

  final String url;
  final String title;
  final String text;
  final String host;
}

class ScrapeFailure implements Exception {
  const ScrapeFailure(this.reason);
  final String reason;
  @override
  String toString() => 'ScrapeFailure: $reason';
}

/// Basic client-side HTML → main-text extractor. Designed for the
/// activity-library creation flow, where the teacher pastes a link and
/// we want enough text to hand to the AI so it can write a
/// kid-appropriate summary.
///
/// Not a full Readability port — for MVP it grabs the `<title>`, drops
/// script/style/nav/aside/header/footer, concatenates paragraph + list
/// + heading text, and trims to a reasonable size before shipping to
/// the model (keeping tokens + latency bounded).
Future<ScrapedPage> scrapeUrl(
  String rawUrl, {
  Duration timeout = const Duration(seconds: 12),
  int maxChars = 8000,
  http.Client? client,
}) async {
  final uri = _parseAndNormalize(rawUrl);
  if (uri == null) {
    throw const ScrapeFailure("That doesn't look like a valid URL.");
  }
  final c = client ?? http.Client();
  try {
    final response = await c.get(
      uri,
      // Some sites block unknown user agents outright. Claim a plain
      // desktop browser — we're only reading the plain HTML response,
      // not trying to be sneaky.
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/124.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml',
      },
    ).timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ScrapeFailure(
        'The site returned HTTP ${response.statusCode}.',
      );
    }
    final contentType =
        (response.headers['content-type'] ?? '').toLowerCase();
    if (!contentType.contains('html')) {
      throw ScrapeFailure(
        "That link isn't a web page (content type: $contentType).",
      );
    }
    // Prefer the charset from the header; fall back to utf-8. Latin-1
    // fallback would also be reasonable but isn't worth the complexity
    // for MVP — most modern sites are utf-8.
    final bodyText = _decode(response.bodyBytes, contentType);
    final document = html_parser.parse(bodyText);

    final title = _extractTitle(document);
    final text = _extractMainText(document, maxChars: maxChars);
    if (text.trim().length < 120) {
      // Anything under ~120 chars is almost certainly a paywall / JS-
      // only page / parked domain and won't give the model enough to
      // chew on.
      throw const ScrapeFailure(
        "We couldn't find readable text on that page.",
      );
    }
    return ScrapedPage(
      url: uri.toString(),
      title: title,
      text: text,
      host: uri.host,
    );
  } on TimeoutException {
    throw const ScrapeFailure('The site took too long to respond.');
  } on ScrapeFailure {
    rethrow;
  } on Object catch (e) {
    throw ScrapeFailure("Couldn't reach that link: $e");
  } finally {
    if (client == null) c.close();
  }
}

Uri? _parseAndNormalize(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  // Allow bare domains ("example.com/foo") — prefix https:// so
  // Uri.parse accepts them.
  final withScheme = trimmed.startsWith(RegExp('https?://'))
      ? trimmed
      : 'https://$trimmed';
  final parsed = Uri.tryParse(withScheme);
  if (parsed == null) return null;
  if (!parsed.hasScheme || parsed.host.isEmpty) return null;
  if (parsed.scheme != 'http' && parsed.scheme != 'https') return null;
  return parsed;
}

String _decode(List<int> bytes, String contentType) {
  final m = RegExp(r'charset=([^\s;]+)', caseSensitive: false)
      .firstMatch(contentType);
  final charset = m?.group(1)?.toLowerCase() ?? 'utf-8';
  try {
    if (charset == 'utf-8' || charset == 'utf8') return utf8.decode(bytes);
    if (charset == 'latin1' ||
        charset == 'iso-8859-1' ||
        charset == 'windows-1252') {
      return latin1.decode(bytes);
    }
  } on Object {
    // Fall through to utf8 allowing malformed — better to lose a few
    // characters than hard-fail the whole pipeline on encoding.
  }
  return utf8.decode(bytes, allowMalformed: true);
}

String _extractTitle(dom.Document doc) {
  // Prefer Open Graph title when present (matches what social sharers
  // show and is usually cleaner than the raw <title>).
  final og = doc
      .querySelectorAll('meta[property="og:title"]')
      .map((e) => e.attributes['content']?.trim())
      .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
  if (og != null && og.isNotEmpty) return og;
  final t = doc.querySelector('title')?.text.trim() ?? '';
  return t.isEmpty ? 'Untitled page' : t;
}

String _extractMainText(dom.Document doc, {required int maxChars}) {
  // Rip out decorative / navigation chrome that would otherwise dilute
  // the extracted text.
  const removeSelectors = [
    'script',
    'style',
    'noscript',
    'nav',
    'aside',
    'header',
    'footer',
    'form',
    'svg',
    'iframe',
    '[role=navigation]',
    '[role=banner]',
    '[role=contentinfo]',
  ];
  for (final sel in removeSelectors) {
    for (final el in doc.querySelectorAll(sel)) {
      el.remove();
    }
  }

  // Prefer <article> if one exists — it's usually the main body.
  final root = doc.querySelector('article') ??
      doc.querySelector('main') ??
      doc.body ??
      doc.documentElement;
  if (root == null) return '';

  final buf = StringBuffer();
  // Walk in document order; collect block-level text with line breaks
  // between blocks so the AI gets something resembling paragraphs.
  final blocks =
      root.querySelectorAll('p, h1, h2, h3, h4, li, blockquote');
  if (blocks.isNotEmpty) {
    for (final b in blocks) {
      final t = _normalizeWhitespace(b.text);
      if (t.isEmpty) continue;
      buf.writeln(t);
      if (buf.length >= maxChars) break;
    }
  } else {
    buf.write(_normalizeWhitespace(root.text));
  }
  final out = buf.toString().trim();
  return out.length > maxChars ? out.substring(0, maxChars) : out;
}

String _normalizeWhitespace(String s) {
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}
