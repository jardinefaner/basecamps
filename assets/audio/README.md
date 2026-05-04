# BASECamp Survey audio assets

Pre-rendered Deepgram Aura voice samples for the BASECamp Student
Survey kiosk. Each subfolder is one of the 10 voices the teacher
can pick from in the setup form; each MP3 inside is a single
phrase keyed by `sha256(text)[:16]`.

## Generating

```bash
export DEEPGRAM_API_KEY=...        # https://console.deepgram.com
dart run tool/generate_voices.dart
```

The script reads canonical phrases from
`lib/features/surveys/canonical_questions.dart` and renders each
× each of the 10 voices to MP3. Files that already exist are
skipped, so re-running after a phrase change just generates the
diff. One-time cost is ~$0.30; incremental edits are pennies.

## Path scheme

```
assets/audio/<voiceCode>/<sha256(text)[:16]>.mp3
```

The runtime `SurveyAudioService.surveyAudioAssetPath(voice, text)`
computes the same hash; lookup is `rootBundle.load(path)`.

## What's in here today

The folders are checked in via `.gitkeep` files so the asset
loader has somewhere to look. Until you run the generator,
they're empty and the kiosk runs silently (graceful no-op by
design — no error, just no audio).

## When phrases change

Edit `canonical_questions.dart`, then re-run the generator. The
old phrase's MP3 stays orphaned but doesn't hurt anything; you
can periodically delete unreferenced files with:

```bash
# Dry-run — shows files not referenced by current canonical set.
dart run tool/prune_voices.dart  # not yet implemented
```

(or just `git rm` them by hand for now.)
