// The activity copy in this file uses double quotes liberally so
// nested apostrophes ("kid's", "what's") read naturally. The
// `prefer_single_quotes` lint would fire on every line; silence
// it for the whole file since the trade-off is content readability.
// ignore_for_file: prefer_single_quotes, avoid_escaping_inner_quotes

import 'package:basecamp/features/curriculum/templates/curriculum_template.dart';

/// "Different World" — a 10-week summer curriculum for ages 5–12
/// that walks kids from "who am I" through neighborhood, other
/// lives, systems, history, future, mystery, and back to agency.
///
/// Bundled as a built-in template so a teacher can spin up the
/// whole arc in one tap on the templates screen — theme +
/// 10 sequences + 50 sequence items + 50 activity-library cards
/// (each with adjacent-age rewrites). Editable after import like
/// any other curriculum.
///
/// Source: the user's React mockup pasted on 2026-04-28. Each
/// activity card's adjacent-age rewrites are encoded as
/// [AgeBand] entries with representative ages (5, 6.5 → 6,
/// 8-12 → 10) so the curriculum view's age-scaling toggle picks
/// the nearest match.
const differentWorldTemplate = CurriculumTemplate(
  id: 'different-world-2026',
  name: 'Different World',
  tagline: 'A 10-week journey from the smallest world to the biggest unknown.',
  summary:
      'Ages 5–12. Kids walk outward from themselves through their '
      'neighborhood, other lives, systems, history, future, and '
      'mystery — then back to themselves, changed.',
  audience: 'Ages 5–12 · 10 weeks',
  weekCount: 10,
  themeColorHex: '#ff6b6b',
  weeks: [
    // ── PHASE 1 — ALL ABOUT ME ────────────────────────────────
    WeekTemplate(
      week: 1,
      phase: 'ALL ABOUT ME',
      title: 'My World Inside',
      coreQuestion: 'What makes me, me?',
      colorHex: '#ff6b6b',
      description:
          "Before you can explore any world, you have to know who's "
          "doing the exploring. This week is body, senses, "
          "feelings, preferences — the raw material of self.",
      daily: [
        DailyTemplate(
          dayOfWeek: 1,
          name: 'Body Map',
          description:
              'Trace your body on paper. Each day, label something '
              "new you learned about it — what hurts, what's strong, "
              "what's weird, what you like.",
          ageBands: [
            AgeBand(
              age: 5,
              summary:
                  'Body tracing on big paper. Label "where my hand goes," '
                  '"where I tickle." Finger paint over the body parts '
                  'you noticed today.',
            ),
            AgeBand(
              age: 6,
              summary:
                  'Body map with labels — strong spots, soft spots, '
                  'spots where you feel feelings. One new label per day.',
            ),
            AgeBand(
              age: 10,
              summary:
                  'Self-portrait on grid paper with annotations: '
                  'physical, emotional, sensory observations. By Friday '
                  "you have a documented map of yourself.",
            ),
          ],
        ),
        DailyTemplate(
          dayOfWeek: 2,
          name: 'Sense of the Day',
          description:
              'Monday = smell. Tuesday = touch. Wednesday = taste. '
              'Thursday = sound. Friday = sight. Notice one thing '
              'through that sense only.',
          ageBands: [
            AgeBand(
              age: 5,
              summary:
                  "Sensory bin per day — smell jars, touch boxes, taste "
                  "tray. Pick one thing and tell us what it's like.",
            ),
            AgeBand(
              age: 6,
              summary:
                  '"Today I smelled / heard / saw" journal. One vivid '
                  'memory per sense.',
            ),
            AgeBand(
              age: 10,
              summary:
                  'Sensory log — write three sentences each day about '
                  "one thing you noticed only through that sense. "
                  "Compare your week's notes on Friday.",
            ),
          ],
        ),
        DailyTemplate(
          dayOfWeek: 3,
          name: 'Mood Weather',
          description:
              'Every morning, draw the weather inside you. Sunny? '
              'Stormy? Foggy? No wrong answers. Track it all week.',
          ageBands: [
            AgeBand(
              age: 5,
              summary:
                  'Finger paint your weather of the day — sunny yellow, '
                  'stormy gray. One picture per morning.',
            ),
            AgeBand(
              age: 6,
              summary:
                  'Mood weather journal — draw a picture + a one-word '
                  'label for how you feel each morning.',
            ),
            AgeBand(
              age: 10,
              summary:
                  'Weather chart for the week. Picture + a sentence '
                  '("foggy because I had a weird dream"). Look at the '
                  "pattern Friday.",
            ),
          ],
        ),
        DailyTemplate(
          dayOfWeek: 4,
          name: 'My Favorites',
          description:
              'Every day pick one favorite — color, food, song, '
              "place, person — and tell why. Not just what, why.",
        ),
        DailyTemplate(
          dayOfWeek: 5,
          name: 'What I Learned About Me',
          description:
              'One sentence each Friday: "This week I learned I…". '
              "It's a closing reflection that prepares Monday's new "
              'observation.',
        ),
      ],
      milestone: MilestoneTemplate(
        name: 'The Me Museum',
        description:
            'Bring 3 objects from home that explain who you are '
            'without words. Display them. Others guess what they mean.',
      ),
      engineNotes:
          'Drops land in: notice → sense → self, simplify → isolate → '
          "identity. By Friday the engine has each kid's sensory "
          'profile — who notices sounds vs. who notices textures.',
    ),

    WeekTemplate(
      week: 2,
      phase: 'ALL ABOUT ME',
      title: 'My World With Others',
      coreQuestion: 'Who matters to me and why?',
      colorHex: '#ff8c6b',
      description:
          'Still about you — but now through the mirror of '
          'relationships. Family, friends, pets, people you miss. '
          'The self exists in connection.',
      daily: [
        DailyTemplate(
          dayOfWeek: 1,
          name: 'Someone I Know',
          description:
              "Each day, describe one person who matters to you. "
              "Not what they look like — what they DO that makes "
              'them matter.',
        ),
        DailyTemplate(
          dayOfWeek: 2,
          name: 'Kind / Unkind',
          description:
              'One moment today when someone was kind. One moment '
              'that felt unkind. No names needed. Just notice.',
        ),
        DailyTemplate(
          dayOfWeek: 3,
          name: "How I'm Like / Unlike",
          description:
              "Pick someone in your group. One way you're similar. "
              "One way you're different. Both are good.",
        ),
        DailyTemplate(
          dayOfWeek: 4,
          name: 'Pet / Place / Person',
          description:
              'Each day pick one pet, place, OR person you carry '
              'with you and write a tiny love letter.',
        ),
        DailyTemplate(
          dayOfWeek: 5,
          name: 'My Web',
          description:
              'List the people who make up your week. Family, '
              'teachers, friends, the bus driver. Realize how '
              'wide it is.',
        ),
      ],
      milestone: MilestoneTemplate(
        name: 'The Web',
        description:
            'String art on a board. Each kid ties string to every '
            'other kid they learned something about. See the web '
            'form. This is your community.',
      ),
      engineNotes:
          'Drops land in: connect → depend → people, notice → '
          'compare → relationships. First cross-kid convergences '
          'appear — multiple children independently noting the '
          'same patterns about kindness.',
    ),

    // ── PHASE 2 — MY NEIGHBORHOOD ─────────────────────────────
    WeekTemplate(
      week: 3,
      phase: 'MY NEIGHBORHOOD',
      title: 'Right Outside My Door',
      coreQuestion: "What's in my world that I walk past every day?",
      colorHex: '#ffd93d',
      description:
          'The journey outward begins. Not far — just outside. The '
          "sidewalk. The corner store. The tree you've never looked "
          'at closely. The familiar made unfamiliar.',
      daily: [
        DailyTemplate(
          dayOfWeek: 1,
          name: 'Sidewalk Safari',
          description:
              'Walk a short route. Count living things. Count made '
              'things. Which number is bigger? Why?',
        ),
        DailyTemplate(
          dayOfWeek: 2,
          name: 'Sound Map',
          description:
              'Sit still for 3 minutes. Draw a map of every sound '
              'you hear — where it came from, what made it.',
        ),
        DailyTemplate(
          dayOfWeek: 3,
          name: 'Who Works Here?',
          description:
              'Each day, learn about one person who works in or '
              'near the program. What do they do? Why?',
        ),
        DailyTemplate(
          dayOfWeek: 4,
          name: 'Tiny Map',
          description:
              'Draw a map of one block from memory. Walk it. Compare. '
              'What did you forget? What surprised you?',
        ),
        DailyTemplate(
          dayOfWeek: 5,
          name: 'A Smell, A Taste',
          description:
              'Find one new smell or taste in the neighborhood. '
              'Bakery? Garden? Something brewing? Describe it.',
        ),
      ],
      milestone: MilestoneTemplate(
        name: 'Neighborhood Field Guide',
        description:
            'The class creates a field guide to their own block. '
            'Plants, animals, people, buildings, smells, sounds. '
            'Illustrated by the kids. A document of the ordinary.',
      ),
      engineNotes:
          'Drops shift to: notice → sense → environment, name → '
          'classify → local ecology. Kids start categorizing '
          'without being told to — bugs vs. birds, loud streets '
          'vs. quiet ones.',
    ),

    WeekTemplate(
      week: 4,
      phase: 'MY NEIGHBORHOOD',
      title: 'The Hidden Neighborhood',
      coreQuestion: "What's here that most people never see?",
      colorHex: '#f0c929',
      description:
          'Deeper. Under the sidewalk there are pipes. Inside the '
          'walls there are wires. Behind the counter there\'s a '
          'whole system. The invisible infrastructure of daily life.',
      daily: [
        DailyTemplate(
          dayOfWeek: 1,
          name: 'Where Does It Come From?',
          description:
              'Pick one thing you used today — water, food, '
              'electricity, your shirt. Trace it backwards. How did '
              'it get here?',
        ),
        DailyTemplate(
          dayOfWeek: 2,
          name: 'The Invisible Job',
          description:
              'Find one thing that works perfectly and nobody '
              'notices. Who made that happen?',
        ),
        DailyTemplate(
          dayOfWeek: 3,
          name: 'Before and After',
          description:
              'Find one spot in the neighborhood. What was here '
              'before? What might be here later?',
        ),
        DailyTemplate(
          dayOfWeek: 4,
          name: 'The Helpers',
          description:
              'Maintenance, sanitation, delivery, repair. Pick one '
              'and learn what their day is like.',
        ),
        DailyTemplate(
          dayOfWeek: 5,
          name: 'What If It Stopped?',
          description:
              'One thing that runs invisibly. Imagine it stopped '
              'today. What would break first? What would happen by '
              'tomorrow?',
        ),
      ],
      milestone: MilestoneTemplate(
        name: 'The Invisible Map',
        description:
            'Overlay on the neighborhood map: underground pipes, '
            'power lines, delivery routes, wifi signals. The world '
            "you can't see but depend on.",
      ),
      engineNotes:
          'Drops land in: connect → depend → systems, simplify → '
          'reduce → infrastructure. First deep IF/THEN chains form: '
          'if water comes from pipes → if pipes need pressure → '
          'if pressure needs pumps → if pumps need electricity...',
    ),

    // ── PHASE 3 — BEYOND THE FAMILIAR ─────────────────────────
    WeekTemplate(
      week: 5,
      phase: 'BEYOND THE FAMILIAR',
      title: 'Other Kids, Other Worlds',
      coreQuestion: "What's life like for someone who isn't me?",
      colorHex: '#51cf66',
      description:
          'The first real leap. Same age, completely different '
          "life. A kid in Tokyo. A kid in a village in Ghana. A "
          "kid who can't walk. A kid who speaks three languages. "
          "Different doesn't mean distant.",
      daily: [
        DailyTemplate(
          dayOfWeek: 1,
          name: 'A Day in Their Life',
          description:
              'Each day, learn about one child somewhere else in '
              "the world. What's their morning like? What do they "
              'eat? What do they play?',
        ),
        DailyTemplate(
          dayOfWeek: 2,
          name: 'Same Same Different',
          description:
              "After learning about another kid's life — one thing "
              "that's exactly the same as yours. One thing that's "
              'completely different.',
        ),
        DailyTemplate(
          dayOfWeek: 3,
          name: 'What Would I Miss?',
          description:
              'If you woke up in their life tomorrow, what one '
              'thing from YOUR life would you miss most?',
        ),
        DailyTemplate(
          dayOfWeek: 4,
          name: 'A Word From Their Language',
          description:
              'Learn one word from a language not yours. Use it '
              'all day. By Friday you know five.',
        ),
        DailyTemplate(
          dayOfWeek: 5,
          name: 'Trade Lives For An Hour',
          description:
              'Pick one part of another kid\'s day. Try it — eat '
              'their breakfast, play their game, listen to their '
              'music. Notice what feels familiar.',
        ),
      ],
      milestone: MilestoneTemplate(
        name: 'The Swap',
        description:
            "Each kid 'designs' one day of life as a child from "
            'another place. What would they eat, play, learn, see? '
            'Present it. Others ask questions.',
      ),
      engineNotes:
          'Drops explode into: notice → compare → culture, connect → '
          'correlate → human universals. The convergence counter '
          'lights up — kids across all four age groups independently '
          'discover that play, food, and family are universal even '
          'when the forms differ.',
    ),

    WeekTemplate(
      week: 6,
      phase: 'BEYOND THE FAMILIAR',
      title: 'How the World Works',
      coreQuestion: 'Why do things happen the way they do?',
      colorHex: '#3dbd5d',
      description:
          'Zooming out from people to systems. Weather, ecosystems, '
          'economies, food chains. The big machines that run quietly '
          'underneath everything. This is where IF/THEN becomes '
          'powerful.',
      daily: [
        DailyTemplate(
          dayOfWeek: 1,
          name: 'Chain Reaction',
          description:
              'Start with one event. What does it cause? What does '
              'THAT cause? How far can you go? Dominoes of reality.',
        ),
        DailyTemplate(
          dayOfWeek: 2,
          name: 'What Needs What?',
          description:
              'Pick two things. Does one need the other? Do they '
              'need each other? Do they have nothing to do with '
              'each other?',
        ),
        DailyTemplate(
          dayOfWeek: 3,
          name: 'The Broken Link',
          description:
              'Pick a system (ant colony, cafeteria lunch, '
              'rainstorm). Remove one piece. What falls apart?',
        ),
        DailyTemplate(
          dayOfWeek: 4,
          name: 'Cause Or Coincidence?',
          description:
              "Two things happened. One after the other. Did the "
              'first cause the second? Or were they unrelated? Make '
              'the case both ways.',
        ),
        DailyTemplate(
          dayOfWeek: 5,
          name: 'Build A System',
          description:
              'Three pieces, one rule. Make the simplest system you '
              'can — water + plant + sun, or coin + box + key. '
              'What does it do?',
        ),
      ],
      milestone: MilestoneTemplate(
        name: 'The Big Machine',
        description:
            'Groups of 4-5 kids build a Rube Goldberg-style chain. '
            "Not with marbles — with ideas. 'The sun heats the "
            'ocean → water evaporates → clouds form → it rains → '
            'the river fills → fish can eat → bears catch fish.\' '
            'Biggest chain wins.',
      ),
      engineNotes:
          'Drops land in: connect → cause → systems, connect → '
          'depend → ecology. The longest IF/THEN chains of the '
          'summer form this week. The engine shows systems thinking '
          'emerging naturally.',
    ),

    // ── PHASE 4 — TIME ────────────────────────────────────────
    WeekTemplate(
      week: 7,
      phase: 'TIME',
      title: 'Where Did Everything Come From?',
      coreQuestion: 'What was here before me?',
      colorHex: '#748ffc',
      description:
          "Time travel backwards. History isn't dates — it's the "
          'realization that everything you see was once different. '
          'Your school was once a field. Your city was once forest. '
          'Your language was once grunts.',
      daily: [
        DailyTemplate(
          dayOfWeek: 1,
          name: 'The Old Question',
          description:
              'Pick one thing in the room. How old is it? Not when '
              'was it bought — when was the FIRST one ever made? '
              'Guess, then find out.',
        ),
        DailyTemplate(
          dayOfWeek: 2,
          name: 'Ask an Elder',
          description:
              "One question for someone older: \"What was this "
              "place like when you were my age?\" Bring the answer "
              'back.',
        ),
        DailyTemplate(
          dayOfWeek: 3,
          name: 'The Timeline',
          description:
              'Add one thing to the class timeline every day. By '
              'Friday, you can see how things stacked up to become '
              'now.',
        ),
        DailyTemplate(
          dayOfWeek: 4,
          name: 'The Same Spot',
          description:
              'Find one spot — a tree, a corner, a doorway. What '
              'was here a year ago? Ten years? A hundred? Imagine '
              'each layer.',
        ),
        DailyTemplate(
          dayOfWeek: 5,
          name: 'My Own History',
          description:
              'Tell us about you a year ago. Five years ago. The '
              'day you were born. What of that is still in you?',
        ),
      ],
      milestone: MilestoneTemplate(
        name: 'Then and Now',
        description:
            'Pick one spot — the school, the park, the block. '
            'Research what it looked like 10, 50, 100 years ago. '
            'Make a visual timeline. Present the transformation.',
      ),
      engineNotes:
          'Drops land in: connect → sequence → history, notice → '
          'distinguish → time. Kids discover that everything is a '
          'CHAIN — not just causes, but the passage of time '
          'connects everything to everything before it.',
    ),

    WeekTemplate(
      week: 8,
      phase: 'TIME',
      title: "What Hasn't Happened Yet?",
      coreQuestion: "What will the world be like when I'm grown?",
      colorHex: '#5f7fee',
      description:
          'Time travel forward. Prediction, imagination, '
          'responsibility. If the past explains how we got here, '
          "the future asks what we'll do with it. This is where "
          'agency is born.',
      daily: [
        DailyTemplate(
          dayOfWeek: 1,
          name: 'I Predict',
          description:
              'One prediction about the future. Any future — '
              "tomorrow, next year, when you're 30. Write it down. "
              'Seal it.',
        ),
        DailyTemplate(
          dayOfWeek: 2,
          name: 'What If?',
          description:
              "One 'what if' question per day. What if cars could "
              'fly? What if animals could talk? What if school '
              'lasted all year? Follow it seriously.',
        ),
        DailyTemplate(
          dayOfWeek: 3,
          name: 'My Future Self',
          description:
              'Write a tiny letter to yourself at age 20. What do '
              'you hope you remember from this summer?',
        ),
        DailyTemplate(
          dayOfWeek: 4,
          name: 'Design One Thing',
          description:
              'Pick a problem in the world. Sketch one thing that '
              "might fix it. Don't worry if it's possible.",
        ),
        DailyTemplate(
          dayOfWeek: 5,
          name: 'The Choice',
          description:
              'Two futures. One you want. One you fear. Draw both. '
              'Whose job is it to make sure the right one wins?',
        ),
      ],
      milestone: MilestoneTemplate(
        name: 'Design Tomorrow',
        description:
            "Groups design one thing that should exist in the "
            "future but doesn't yet. Could be a tool, a rule, a "
            'place, a job. Build a prototype. Present it.',
      ),
      engineNotes:
          'Drops land in: connect → cause → future, simplify → '
          'abstract → possibility. The engine shows kids making '
          "their first ABSTRACT leaps — reasoning about things "
          "that don't exist yet.",
    ),

    // ── PHASE 5 — THE UNKNOWN ─────────────────────────────────
    WeekTemplate(
      week: 9,
      phase: 'THE UNKNOWN',
      title: 'What Nobody Knows',
      coreQuestion: "What questions don't have answers yet?",
      colorHex: '#cc5de8',
      description:
          'The most important week. Everything so far had answers '
          "somewhere. This week doesn't. What's at the bottom of "
          'the ocean? What happens after we die? Is there life on '
          "other planets? Are there colors we can't see? The gift "
          'of unsolved questions.',
      daily: [
        DailyTemplate(
          dayOfWeek: 1,
          name: 'The Unanswerable',
          description:
              'One question per day that nobody in the world can '
              'answer yet. Not trivia — genuine mystery. Collect '
              'them.',
        ),
        DailyTemplate(
          dayOfWeek: 2,
          name: "What I Don't Know",
          description:
              "Admit one thing you don't understand. Not "
              'embarrassing — brave. The class celebrates '
              'not-knowing.',
        ),
        DailyTemplate(
          dayOfWeek: 3,
          name: 'Beautiful Confusion',
          description:
              'Find one thing that confuses you and explain why '
              'the confusion itself is interesting. The question '
              'is better than any answer.',
        ),
        DailyTemplate(
          dayOfWeek: 4,
          name: 'Two Theories',
          description:
              "Pick a mystery. Make up two completely different "
              'explanations. Both must be possible. Both must be '
              'beautiful.',
        ),
        DailyTemplate(
          dayOfWeek: 5,
          name: 'The Question Wall',
          description:
              "Add three of your wildest unanswered questions to "
              'the class wall. Read everyone else\'s. Pick a '
              'favorite that isn\'t yours.',
        ),
      ],
      milestone: MilestoneTemplate(
        name: 'The Museum of Mysteries',
        description:
            "Each kid picks one unsolved question — from science, "
            "philosophy, their own life — and makes an exhibit. "
            'Not an answer. A beautiful presentation of the '
            'question itself.',
      ),
      engineNotes:
          'Drops land in: notice → sense → mystery, name → define '
          '→ unknown. The engine discovers something new: '
          'questions as a category of truth. Not IF/THEN but '
          'IF/???. Open nodes. The first time the engine holds '
          'uncertainty as knowledge.',
    ),

    WeekTemplate(
      week: 10,
      phase: 'THE UNKNOWN',
      title: 'My Different World',
      coreQuestion:
          "Now that I've seen all this — what world do I want to make?",
      colorHex: '#e050a0',
      description:
          'The return. You started with yourself. You went through '
          'relationships, neighborhood, other lives, systems, '
          'history, future, mystery. Now you come back to you — '
          "but you're different. The last week is about agency. "
          'Not what the world IS but what it COULD BE because '
          "you're in it.",
      daily: [
        DailyTemplate(
          dayOfWeek: 1,
          name: 'My Manifesto Sentence',
          description:
              'One sentence per day about the world you want. By '
              "Friday you have five sentences. That's your "
              'manifesto.',
        ),
        DailyTemplate(
          dayOfWeek: 2,
          name: "What I'll Carry",
          description:
              'One thing from each previous week that changed how '
              'you see. Revisit your own drops in the engine. What '
              'surprised you?',
        ),
        DailyTemplate(
          dayOfWeek: 3,
          name: 'The Gift',
          description:
              "Each day, do one small thing to make someone else's "
              'world slightly different. Report back. Did it work?',
        ),
        DailyTemplate(
          dayOfWeek: 4,
          name: 'My Question Forward',
          description:
              "Pick one question you want to keep asking after the "
              'summer ends. Not to answer — to live with.',
        ),
        DailyTemplate(
          dayOfWeek: 5,
          name: 'The Promise',
          description:
              "One thing you'll do when you go home, because of "
              'this summer. Tell us. We\'ll remind you in a year.',
        ),
      ],
      milestone: MilestoneTemplate(
        name: 'The Different World Fair',
        description:
            "The final event. Each kid presents their 'different "
            "world' — the world as they now see it, the world they "
            'want to build, and the one question they\'re carrying '
            'forward. Families invited.',
      ),
      engineNotes:
          "The entire summer's drops are visible. The engine "
          "shows the journey: from 'I like the color blue' in week "
          "1 to 'the more you learn the more you see what you "
          "don't know' in week 9. The tree is full. The glossary "
          'is alive. The kids built it without ever knowing the '
          'engine existed.',
    ),
  ],
);

/// All built-in templates the user can pick from on the templates
/// screen. Add new templates here.
const builtInCurriculumTemplates = <CurriculumTemplate>[
  differentWorldTemplate,
];
