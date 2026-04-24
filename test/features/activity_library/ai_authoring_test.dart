import 'package:basecamp/features/activity_library/ai_authoring.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LibraryCardDraft.fromJson', () {
    test('parses the full URL-path shape into a draft', () {
      final draft = LibraryCardDraft.fromJson(
        {
          'title': 'Frog life cycle jar',
          'summary':
              'Kids watch tadpoles become frogs. Over two weeks they track '
                  'changes and draw what they see.',
          'hook': 'What happens inside a frog jar?',
          'keyPoints': ['Observe daily', 'Draw each stage', 'Release after'],
          'learningGoals': ['Life cycles', 'Patience'],
          'audienceMinAge': 4,
          'audienceMaxAge': 6,
          'engagementTimeMin': 20,
          'materials': ['Jar', 'Tadpoles', 'Notebook'],
          'sourceAttribution': 'BBC.com',
        },
        sourceUrlOverride: 'https://bbc.com/frogs',
      );
      expect(draft.title, 'Frog life cycle jar');
      expect(draft.summary, contains('tadpoles'));
      expect(draft.hook, 'What happens inside a frog jar?');
      // List → newline-joined string; the edit sheet drops the blob
      // straight into a multiline TextField controller.
      expect(draft.keyPoints, 'Observe daily\nDraw each stage\nRelease after');
      expect(draft.learningGoals, 'Life cycles\nPatience');
      expect(draft.audienceMinAge, 4);
      expect(draft.audienceMaxAge, 6);
      expect(draft.engagementTimeMin, 20);
      expect(draft.materials, 'Jar\nTadpoles\nNotebook');
      expect(draft.sourceUrl, 'https://bbc.com/frogs');
      expect(draft.sourceAttribution, 'BBC.com');
    });

    test('accepts snake_case keys for the description path', () {
      final draft = LibraryCardDraft.fromJson({
        'title': 'Marble painting',
        'summary': 'Tilt a tray to roll marbles through paint.',
        'hook': 'Can you draw without touching the paper?',
        'key_points': ['Load the tray', 'Tilt slowly'],
        'learning_goals': ['Fine motor control'],
        'audience_min_age': 3,
        'audience_max_age': 5,
        'engagement_time_min': 10,
        'materials': ['Marbles', 'Paint'],
      });
      expect(draft.title, 'Marble painting');
      expect(draft.keyPoints, 'Load the tray\nTilt slowly');
      expect(draft.learningGoals, 'Fine motor control');
      expect(draft.audienceMinAge, 3);
      expect(draft.audienceMaxAge, 5);
      expect(draft.engagementTimeMin, 10);
      expect(draft.materials, 'Marbles\nPaint');
      // No source attribution or URL from the description path.
      expect(draft.sourceAttribution, isNull);
      expect(draft.sourceUrl, isNull);
    });

    test('leaves optional fields null when absent', () {
      final draft = LibraryCardDraft.fromJson({'title': 'Bare-bones card'});
      expect(draft.title, 'Bare-bones card');
      expect(draft.summary, isNull);
      expect(draft.hook, isNull);
      expect(draft.keyPoints, isNull);
      expect(draft.learningGoals, isNull);
      expect(draft.audienceMinAge, isNull);
      expect(draft.audienceMaxAge, isNull);
      expect(draft.engagementTimeMin, isNull);
      expect(draft.materials, isNull);
    });

    test('drops empty array entries from joined lists', () {
      final draft = LibraryCardDraft.fromJson({
        'title': 'Mix',
        'keyPoints': ['  ', 'Real point', '', '  Another  '],
      });
      expect(draft.keyPoints, 'Real point\nAnother');
    });

    test('returns null for an empty list instead of an empty string', () {
      final draft = LibraryCardDraft.fromJson({
        'title': 'Empty lists',
        'keyPoints': <String>[],
        'learning_goals': <String>[],
      });
      expect(draft.keyPoints, isNull);
      expect(draft.learningGoals, isNull);
    });

    test('accepts numeric strings for int fields', () {
      final draft = LibraryCardDraft.fromJson({
        'title': 'Stringy ages',
        'audienceMinAge': '4',
        'audienceMaxAge': '6',
        'engagementTimeMin': '25',
      });
      expect(draft.audienceMinAge, 4);
      expect(draft.audienceMaxAge, 6);
      expect(draft.engagementTimeMin, 25);
    });

    test('rejects a card with no title', () {
      expect(
        () => LibraryCardDraft.fromJson({'summary': 'no title here'}),
        throwsA(isA<LibraryDraftParseError>()),
      );
    });

    test('rejects a card with an empty title string', () {
      expect(
        () => LibraryCardDraft.fromJson({'title': '   '}),
        throwsA(isA<LibraryDraftParseError>()),
      );
    });

    test(
      'LibraryDraftParseError is also a LibraryDraftFailure so UI catch-all works',
      () {
        try {
          LibraryCardDraft.fromJson({});
          fail('should have thrown');
        } on LibraryDraftFailure catch (e) {
          expect(e.message, isNotEmpty);
        }
      },
    );
  });
}
