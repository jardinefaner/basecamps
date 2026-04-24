import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/activity_library/widgets/library_filter_header.dart';
import 'package:flutter_test/flutter_test.dart';

ActivityLibraryData _card({
  required String id,
  String title = 'Untitled',
  String? summary,
  String? hook,
  String? keyPoints,
  int? minAge,
  int? maxAge,
}) {
  final now = DateTime(2026);
  return ActivityLibraryData(
    id: id,
    title: title,
    summary: summary,
    hook: hook,
    keyPoints: keyPoints,
    audienceMinAge: minAge,
    audienceMaxAge: maxAge,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('matchesLibraryFilter — search', () {
    test('matches title substrings, case-insensitive', () {
      final card = _card(id: 'a', title: 'Morning Circle');
      expect(
        matchesLibraryFilter(card, query: 'circle', band: LibraryAgeBand.all),
        isTrue,
      );
      expect(
        matchesLibraryFilter(card, query: 'MORN', band: LibraryAgeBand.all),
        isTrue,
      );
      expect(
        matchesLibraryFilter(card, query: 'snack', band: LibraryAgeBand.all),
        isFalse,
      );
    });

    test('matches summary, hook, and keyPoints too', () {
      final card = _card(
        id: 'a',
        title: 'X',
        summary: 'Explore textures with paint',
        hook: 'Squishy fun',
        keyPoints: 'fine-motor · sensory',
      );
      expect(
        matchesLibraryFilter(card, query: 'texture', band: LibraryAgeBand.all),
        isTrue,
      );
      expect(
        matchesLibraryFilter(card, query: 'squishy', band: LibraryAgeBand.all),
        isTrue,
      );
      expect(
        matchesLibraryFilter(card, query: 'sensory', band: LibraryAgeBand.all),
        isTrue,
      );
      expect(
        matchesLibraryFilter(card, query: 'music', band: LibraryAgeBand.all),
        isFalse,
      );
    });

    test('empty query matches every card', () {
      final card = _card(id: 'a');
      expect(
        matchesLibraryFilter(card, query: '', band: LibraryAgeBand.all),
        isTrue,
      );
      expect(
        matchesLibraryFilter(card, query: '   ', band: LibraryAgeBand.all),
        isTrue,
      );
    });
  });

  group('matchesLibraryFilter — age band', () {
    test('infant (0–2) matches cards whose minAge <= 2', () {
      final infant = _card(id: 'i', minAge: 0, maxAge: 2);
      final toddler = _card(id: 't', minAge: 2, maxAge: 3);
      final preschool = _card(id: 'p', minAge: 3, maxAge: 5);
      final schoolAge = _card(id: 's', minAge: 6, maxAge: 10);
      expect(
        matchesLibraryFilter(infant, query: '', band: LibraryAgeBand.infant),
        isTrue,
      );
      expect(
        matchesLibraryFilter(toddler, query: '', band: LibraryAgeBand.infant),
        isTrue, // minAge 2 <= 2
      );
      expect(
        matchesLibraryFilter(preschool, query: '', band: LibraryAgeBand.infant),
        isFalse,
      );
      expect(
        matchesLibraryFilter(schoolAge, query: '', band: LibraryAgeBand.infant),
        isFalse,
      );
    });

    test('preschool (3–5) matches overlapping ranges', () {
      final toddler = _card(id: 't', minAge: 2, maxAge: 3);
      final preschool = _card(id: 'p', minAge: 3, maxAge: 5);
      final school = _card(id: 's', minAge: 6, maxAge: 8);
      expect(
        matchesLibraryFilter(toddler,
            query: '', band: LibraryAgeBand.preschool),
        isTrue,
      );
      expect(
        matchesLibraryFilter(preschool,
            query: '', band: LibraryAgeBand.preschool),
        isTrue,
      );
      expect(
        matchesLibraryFilter(school,
            query: '', band: LibraryAgeBand.preschool),
        isFalse,
      );
    });

    test('school age matches open-ended ranges (maxAge null)', () {
      final openEnded = _card(id: 'o', minAge: 6);
      final bounded = _card(id: 'b', minAge: 5, maxAge: 8);
      final tooYoung = _card(id: 'y', minAge: 2, maxAge: 4);
      expect(
        matchesLibraryFilter(openEnded,
            query: '', band: LibraryAgeBand.schoolAge),
        isTrue,
      );
      expect(
        matchesLibraryFilter(bounded,
            query: '', band: LibraryAgeBand.schoolAge),
        isTrue,
      );
      expect(
        matchesLibraryFilter(tooYoung,
            query: '', band: LibraryAgeBand.schoolAge),
        isFalse,
      );
    });

    test('null-age cards appear only under "All ages" or "No age set"', () {
      final nullAge = _card(id: 'n');
      expect(
        matchesLibraryFilter(nullAge, query: '', band: LibraryAgeBand.all),
        isTrue,
      );
      expect(
        matchesLibraryFilter(nullAge, query: '', band: LibraryAgeBand.unset),
        isTrue,
      );
      expect(
        matchesLibraryFilter(nullAge, query: '', band: LibraryAgeBand.infant),
        isFalse,
      );
      expect(
        matchesLibraryFilter(nullAge,
            query: '', band: LibraryAgeBand.preschool),
        isFalse,
      );
      expect(
        matchesLibraryFilter(nullAge,
            query: '', band: LibraryAgeBand.schoolAge),
        isFalse,
      );
    });
  });

  group('matchesLibraryFilter — combined', () {
    test('search and band narrow both ways', () {
      final paint = _card(
        id: 'p',
        title: 'Finger paint',
        minAge: 2,
        maxAge: 4,
      );
      final music = _card(
        id: 'm',
        title: 'Music circle',
        minAge: 3,
        maxAge: 5,
      );
      // "paint" matches title, band preschool matches overlap [3,5].
      expect(
        matchesLibraryFilter(paint,
            query: 'paint', band: LibraryAgeBand.preschool),
        isTrue,
      );
      // "music" doesn't match paint's title.
      expect(
        matchesLibraryFilter(paint,
            query: 'music', band: LibraryAgeBand.preschool),
        isFalse,
      );
      // music matches query but infant band excludes it (minAge 3 > 2).
      expect(
        matchesLibraryFilter(music,
            query: 'music', band: LibraryAgeBand.infant),
        isFalse,
      );
    });
  });
}
