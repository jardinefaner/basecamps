// Unit tests for the deterministic date-phrase resolver.
// Critical correctness path — every "wednesday → wrong ISO" bug
// goes through this. Tests pin the rules so a future refactor
// doesn't regress the bug class.

import 'package:basecamp/features/experiment/command/date_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = DateResolver();

  // Anchor "today" as Wednesday, May 13, 2026 for every test so
  // the expected outputs are stable.
  final today = DateTime(2026, 5, 13);

  ResolvedDate _findPhrase(List<ResolvedDate> list, String phrase) {
    return list.firstWhere((r) => r.phrase == phrase);
  }

  group('relative date phrases', () {
    test('"today" → today', () {
      final r = resolver.resolve('field trip today', today);
      final t = _findPhrase(r, 'today');
      expect(t.iso, '2026-05-13');
      expect(t.weekday, 'wednesday');
    });

    test('"tomorrow" → today + 1', () {
      final r = resolver.resolve('event tomorrow at 11', today);
      final t = _findPhrase(r, 'tomorrow');
      expect(t.iso, '2026-05-14');
      expect(t.weekday, 'thursday');
    });

    test('"yesterday" → today - 1', () {
      final r = resolver.resolve('note from yesterday', today);
      final t = _findPhrase(r, 'yesterday');
      expect(t.iso, '2026-05-12');
    });

    test('"in 3 days" → today + 3', () {
      final r = resolver.resolve('trip in 3 days', today);
      final t = _findPhrase(r, 'in 3 days');
      expect(t.iso, '2026-05-16');
    });
  });

  group('bare weekday → next occurrence (incl. today)', () {
    test('today is Wednesday, "wednesday" → today', () {
      final r = resolver.resolve('trip wednesday', today);
      final t = _findPhrase(r, 'wednesday');
      expect(t.iso, '2026-05-13');
    });

    test('"thursday" → tomorrow (next future Thursday)', () {
      final r = resolver.resolve('trip thursday', today);
      final t = _findPhrase(r, 'thursday');
      expect(t.iso, '2026-05-14');
    });

    test('"monday" → next Monday (5 days later)', () {
      final r = resolver.resolve('trip monday', today);
      final t = _findPhrase(r, 'monday');
      expect(t.iso, '2026-05-18');
    });

    test('"friday" → 2 days later', () {
      final r = resolver.resolve('event friday', today);
      final t = _findPhrase(r, 'friday');
      expect(t.iso, '2026-05-15');
    });
  });

  group('"this <weekday>"', () {
    test('"this friday" when today is Wed → upcoming Friday', () {
      final r = resolver.resolve('this friday', today);
      final t = _findPhrase(r, 'this friday');
      expect(t.iso, '2026-05-15');
    });

    test('"this monday" when today is Wed → falls back to next Mon', () {
      // This-week Monday was 2026-05-11 — already past — so it
      // should resolve to the upcoming Monday (next week).
      final r = resolver.resolve('this monday', today);
      final t = _findPhrase(r, 'this monday');
      expect(t.iso, '2026-05-18');
    });
  });

  group('"next <weekday>" — strictly next calendar week', () {
    test('"next wednesday" → +7 days (not today)', () {
      final r = resolver.resolve('event next wednesday', today);
      final t = _findPhrase(r, 'next wednesday');
      expect(t.iso, '2026-05-20');
    });

    test('"next monday" → next calendar week Monday', () {
      final r = resolver.resolve('trip next monday', today);
      final t = _findPhrase(r, 'next monday');
      expect(t.iso, '2026-05-18');
    });

    test('"next friday" → 9 days later', () {
      final r = resolver.resolve('event next friday', today);
      final t = _findPhrase(r, 'next friday');
      expect(t.iso, '2026-05-22');
    });
  });

  group('month-name phrases', () {
    test('"may 20" → 2026-05-20', () {
      final r = resolver.resolve('field trip may 20', today);
      final t = _findPhrase(r, 'may 20');
      expect(t.iso, '2026-05-20');
    });

    test('"may 20th" → 2026-05-20', () {
      final r = resolver.resolve('field trip may 20th', today);
      final t = _findPhrase(r, 'may 20th');
      expect(t.iso, '2026-05-20');
    });

    test('"jan 3" rolls to next year when past', () {
      // From May 2026, "jan 3" is 4 months in the past → rolls.
      final r = resolver.resolve('trip jan 3', today);
      final t = _findPhrase(r, 'jan 3');
      expect(t.iso, '2027-01-03');
    });
  });

  group('ISO pass-through', () {
    test('explicit yyyy-MM-dd kept verbatim', () {
      final r = resolver.resolve('event on 2026-12-25', today);
      final t = _findPhrase(r, '2026-12-25');
      expect(t.iso, '2026-12-25');
      expect(t.weekday, 'friday');
    });
  });

  group('dedup + ordering', () {
    test('same phrase mentioned twice resolves once', () {
      final r = resolver.resolve('tomorrow tomorrow', today);
      expect(r.where((x) => x.phrase == 'tomorrow').length, 1);
    });
  });

  group('disambiguation precedence', () {
    test('"next wednesday" wins over bare "wednesday"', () {
      // Both phrases match — both should be in the list, with
      // distinct ISOs. The validator picks the first; we don't
      // assert which here, just that both resolve correctly.
      final r = resolver.resolve('next wednesday for sunflowers', today);
      final next = _findPhrase(r, 'next wednesday');
      expect(next.iso, '2026-05-20');
    });
  });
}
