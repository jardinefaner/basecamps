import 'package:basecamp/features/observations/observations_repository.dart';

/// A rough local classifier that suggests a domain + sentiment from the
/// text of an observation. It exists to make the capture flow one step
/// shorter — the teacher can accept the suggestion or override it with a
/// tap. Nothing here is definitive.
///
/// This is a stand-in until a real model call (Claude via a Supabase
/// edge function) is wired up. Keeping the interface (`Suggestion`) stable
/// means the UI doesn't change when we swap the backend.
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
  const social = [
    'shared',
    'helped',
    'friend',
    'together',
    'group',
    'kind',
    'comforted',
    'apolog',
    'listen',
    'included',
  ];
  const physical = [
    'ran',
    'jumped',
    'climbed',
    'threw',
    'caught',
    'swim',
    'swam',
    'balance',
    'kicked',
    'active',
  ];
  const creative = [
    'drew',
    'built',
    'painted',
    'created',
    'imagin',
    'made up',
    'performed',
    'acted out',
    'song',
    'story',
  ];
  const cognitive = [
    'figured out',
    'solved',
    'explained',
    'counted',
    'asked why',
    'asked how',
    'read',
    'wrote',
    'understood',
    'puzzle',
  ];
  const behavior = [
    'hit',
    'pushed',
    'argued',
    'tantrum',
    'refused',
    'bit',
    'broke',
    'yelled',
    'cried',
    'angry',
  ];
  const milestone = [
    'first time',
    'finally',
    'all by',
    'proud',
    'mastered',
    'graduated',
    'moved up',
  ];

  for (final w in social) {
    if (text.contains(w)) addDomain(ObservationDomain.social, 2);
  }
  for (final w in physical) {
    if (text.contains(w)) addDomain(ObservationDomain.physical, 2);
  }
  for (final w in creative) {
    if (text.contains(w)) addDomain(ObservationDomain.creative, 2);
  }
  for (final w in cognitive) {
    if (text.contains(w)) addDomain(ObservationDomain.cognitive, 2);
  }
  for (final w in behavior) {
    if (text.contains(w)) addDomain(ObservationDomain.behavior, 2);
  }
  for (final w in milestone) {
    if (text.contains(w)) addDomain(ObservationDomain.milestone, 3);
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
    'helped',
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

  // Pick the winners. Ties resolve to neutral / other.
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
