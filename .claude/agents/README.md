# Feature audit agents

End-to-end auditors, one per feature area. Each agent walks the
relevant code chain (UI → repo → sync → render) and reports a
punch list of working vs broken — file/line precise, no fluff.

These are **read-only auditors**. They don't run the app, don't
write code, don't suggest redesigns. They confirm the
implementation matches the user's design intent.

## How to invoke

In Claude Code:

```
> use the observations-e2e agent to audit observations
```

Or via the Agent tool with `subagent_type: "observations-e2e"`.

## Existing agents

| Agent | Covers | When to invoke |
|---|---|---|
| `observations-e2e` | Capture, attachment, save, sync, render, edit | After observation refactors; when a user reports an obs bug |

## Planned agents (file stubs to add as features change)

These don't exist yet. Add the `.md` file when the feature has
enough surface area to be worth auditing as a unit. Each follows
the same template as `observations-e2e.md`: a "chain" walk plus an
audit procedure plus a Working/Broken/Notes report format.

| Agent | Covers | Owner files |
|---|---|---|
| `schedule-e2e` | Today schedule, week plan, templates, entries, recurring activities, conflicts | `lib/features/schedule/`, `lib/features/today/today_buckets.dart` |
| `auth-e2e` | Sign in (Google + magic link), implicit flow, PKCE fallback, session restore, sign out | `lib/features/auth/`, `lib/main.dart`, `supabase/functions/openai-chat/`, `supabase/functions/deepgram-token/` |
| `sync-e2e` | Push, pull, realtime per table; cascade specs; dirty fields | `lib/features/sync/`, `lib/database/tables.dart` |
| `attendance-e2e` | Daily attendance, lateness flags, ratio check | `lib/features/attendance/`, `lib/features/today/ratio_check.dart` |
| `children-e2e` | Roster, profile, avatar upload, schedule, observations roll-up | `lib/features/children/` |
| `adults-e2e` | Roster, profile, avatar, day blocks, role assignment | `lib/features/adults/` |
| `forms-e2e` | Polymorphic form definitions, submission, image fields, signature, parent-link | `lib/features/forms/` |
| `curriculum-e2e` | Themes, lesson sequences, daily rituals, week plans, library | `lib/features/curriculum/`, `lib/features/themes/`, `lib/features/lesson_sequences/`, `lib/features/activity_library/` |
| `media-e2e` | Avatar upload, observation attachment upload, media_cache, ensureBytes | `lib/features/sync/media_service.dart`, `lib/ui/media_image.dart` |
| `ask-e2e` | Tool dispatch, OpenAI proxy, timeouts, navigation chips | `lib/features/ask/`, `lib/features/ai/openai_client.dart` |

## Pattern: how to write a new agent

Each agent file has:

1. **YAML frontmatter** with `name`, `description`, `tools`. Tools
   should always be at minimum `Bash, Read, Grep, Glob` so the agent
   can audit but not edit. Add `Agent` only if it needs to spawn
   sub-audits.

2. **One-paragraph framing** of why the chain is failure-prone. Be
   specific about which seams hide bugs.

3. **A "chain" section** — numbered steps that walk from user input
   through to render. Each step calls out the file(s) involved and
   the contract it owes the next step.

4. **An audit procedure** — concrete commands (`flutter analyze`,
   `flutter test <path>`, `git log --oneline -- <path>`) plus what
   to look for in each file. Include past-bug callbacks (e.g. "the
   sync-engine bypass fixed in commit X — re-check it's still in
   place"). These are the highest-signal checks.

5. **Report format** — always the same three buckets: Working,
   Broken, Notes. Working is "passed audit." Broken is what to
   fix, with file:line + diagnosis + proposed fix (no code).
   Notes are gotchas worth flagging but not broken today.

6. **Word limit** — ask for under 600 words. The user has limited
   time and needs a punch list.

## When NOT to add an agent

Don't add an agent for surfaces with under ~300 lines of code or
fewer than 3 commits of bug-fix history. They're cheap to audit
inline and an agent file just adds maintenance overhead.

The threshold is "something that has bitten us at least twice."
Observations qualifies. A small settings screen doesn't.
