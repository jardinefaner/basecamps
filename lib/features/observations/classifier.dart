import 'package:basecamp/features/observations/observations_repository.dart';

/// A rough local classifier that suggests a domain + sentiment from the
/// text of an observation. Teachers accept the suggestion or override it
/// with a tap in the edit sheet. Nothing here is definitive.
///
/// Placeholder for a real model call (Claude via a Supabase edge function)
/// later. Keeping the [Suggestion] surface stable means the UI doesn't
/// change when we swap the backend.
class Suggestion {
  const Suggestion({required this.domain, required this.sentiment});

  final ObservationDomain domain;
  final ObservationSentiment sentiment;
}

Suggestion suggestTags(String note) {
  final text = note.toLowerCase();

  final domainScores = <ObservationDomain, int>{};
  final sentimentScores = <ObservationSentiment, int>{};

  void addDomain(ObservationDomain d, int weight) {
    domainScores[d] = (domainScores[d] ?? 0) + weight;
  }

  void addSentiment(ObservationSentiment s, int weight) {
    sentimentScores[s] = (sentimentScores[s] ?? 0) + weight;
  }

  // --- Domain hints ---

  // SSD1: Identity of self and connection to others
  for (final w in const [
    'i am',
    'myself',
    'my family',
    'my name',
    'belong',
    'heritage',
    'culture',
    'my home',
    'where i come from',
    "i'm a",
  ]) {
    if (text.contains(w)) addDomain(ObservationDomain.ssd1, 2);
  }

  // SSD2: Self-esteem
  for (final w in const [
    'proud',
    'confident',
    'brave',
    'capable',
    'i can',
    'did it',
    'on my own',
    'showed off',
    'believed',
  ]) {
    if (text.contains(w)) addDomain(ObservationDomain.ssd2, 2);
  }

  // SSD3: Empathy
  for (final w in const [
    'comforted',
    'hugged',
    'noticed',
    'cared',
    'felt sad for',
    'was kind',
    'checked on',
    'offered',
    'listened to',
  ]) {
    if (text.contains(w)) addDomain(ObservationDomain.ssd3, 2);
  }

  // SSD4: Impulse control
  for (final w in const [
    'waited',
    'stopped',
    'paused',
    'took a breath',
    'calmed down',
    'hit',
    'grabbed',
    'snatched',
    'yelled',
    'took turns',
  ]) {
    if (text.contains(w)) addDomain(ObservationDomain.ssd4, 2);
  }

  // SSD5: Follow rules
  for (final w in const [
    'followed',
    'rule',
    'cleaned up',
    'put away',
    'listened',
    'stayed in',
    'walked',
    'waited in line',
  ]) {
    if (text.contains(w)) addDomain(ObservationDomain.ssd5, 2);
  }

  // SSD6: Awareness of diversity
  for (final w in const [
    'different',
    'cultures',
    'celebrate',
    'language',
    'tradition',
    'noticed differences',
    'similar',
    'family looks',
  ]) {
    if (text.contains(w)) addDomain(ObservationDomain.ssd6, 2);
  }

  // SSD7: Interactions with adults
  for (final w in const [
    'asked me',
    'asked for help',
    'told the teacher',
    'came to me',
    'showed me',
    'teacher',
    'grown-up',
  ]) {
    if (text.contains(w)) addDomain(ObservationDomain.ssd7, 2);
  }

  // SSD8: Friendship
  for (final w in const [
    'friend',
    'played with',
    'played together',
    'invited',
    'included',
    'partner',
    'sat next to',
    'buddy',
  ]) {
    if (text.contains(w)) addDomain(ObservationDomain.ssd8, 2);
  }

  // SSD9: Conflict negotiation
  for (final w in const [
    'argued',
    'disagreed',
    'compromise',
    'took turns',
    'apologized',
    'worked it out',
    'said sorry',
    'shared',
    'solved',
  ]) {
    if (text.contains(w)) addDomain(ObservationDomain.ssd9, 2);
  }

  // HLTH1: Safety
  for (final w in const [
    'safe',
    'be careful',
    'watch out',
    'dangerous',
    'helmet',
    'held on',
    'looked both ways',
    'stayed close',
  ]) {
    if (text.contains(w)) addDomain(ObservationDomain.hlth1, 2);
  }

  // HLTH2: Understanding healthy lifestyle
  for (final w in const [
    'healthy',
    'fruit',
    'vegetable',
    'veggie',
    'water',
    'sleep',
    'rest',
    'nutritious',
    'balanced',
  ]) {
    if (text.contains(w)) addDomain(ObservationDomain.hlth2, 2);
  }

  // HLTH3: Personal care routine
  for (final w in const [
    'washed hands',
    'brushed teeth',
    'bathroom',
    'tied shoes',
    'got dressed',
    'zipper',
    'jacket',
    'wiped',
    'blew nose',
  ]) {
    if (text.contains(w)) addDomain(ObservationDomain.hlth3, 2);
  }

  // HLTH4: Exercise and fitness
  for (final w in const [
    'ran',
    'jumped',
    'climbed',
    'swam',
    'threw',
    'caught',
    'kicked',
    'balanced',
    'active',
    'obstacle',
  ]) {
    if (text.contains(w)) addDomain(ObservationDomain.hlth4, 2);
  }

  // --- Sentiment hints ---

  const positive = [
    'great',
    'wonderful',
    'amazing',
    'proud',
    'happy',
    'excited',
    'smiled',
    'laughed',
    'succeeded',
    'kind',
    'gentle',
    'first time',
    'finally',
    'breakthrough',
    'celebrated',
  ];
  const concern = [
    'struggled',
    'upset',
    'worried',
    'sad',
    'hurt',
    'bit',
    'hit',
    'pushed',
    'argued',
    'tantrum',
    'refused',
    'cried',
    'angry',
    'concerning',
    'scared',
    'missed',
    'bullied',
  ];

  for (final w in positive) {
    if (text.contains(w)) addSentiment(ObservationSentiment.positive, 2);
  }
  for (final w in concern) {
    if (text.contains(w)) addSentiment(ObservationSentiment.concern, 2);
  }

  // Pick winners. Ties resolve to Other / Neutral.
  var domain = ObservationDomain.other;
  var bestDomain = 0;
  for (final entry in domainScores.entries) {
    if (entry.value > bestDomain) {
      bestDomain = entry.value;
      domain = entry.key;
    }
  }

  var sentiment = ObservationSentiment.neutral;
  var bestSentiment = 0;
  for (final entry in sentimentScores.entries) {
    if (entry.value > bestSentiment) {
      bestSentiment = entry.value;
      sentiment = entry.key;
    }
  }

  return Suggestion(domain: domain, sentiment: sentiment);
}
