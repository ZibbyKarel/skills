---
name: standup-post
description: "Post the daily standup into its Slack thread, unattended. Finds the standup thread in the configured channel, drives the zibby:standup pipeline for the default window (yesterday, or Friday–Sunday on a Monday), converts the rendered links to Slack's syntax and posts into the thread. This is what the weekday morning routine runs; a person who just wants to read their standup runs zibby:standup instead. Reads its settings from the 'standup:' key in ~/.zibby/zibby-skills/config.yml."
argument-hint: ""
disable-model-invocation: true
model: sonnet
---

# standup-post

The unattended half of the standup. `zibby:standup` collects and renders; this finds the thread,
drives that same pipeline, and posts the result publicly under the user's name.

**Nobody is watching.** Every question the pipeline would otherwise ask is forbidden here: wherever
a step says "ask the user", return the named failure status and stop. This is the one rule that
separates this skill from `zibby:standup`, and it applies to the steps this skill borrows too.

**Only the user (or the scheduled task) invokes this** — `disable-model-invocation: true`. It posts
to a channel the whole team reads; an agent must never decide on its own that it should.

**Pinned to Sonnet** for the same reason `zibby:standup` is: this fires 250 times a year, and the
work is a fixed sequence of API calls. Rendering still happens on Haiku, inside the borrowed step.

## 1. Find the standup thread

Read `~/.zibby/zibby-skills/config.yml`, take `standup.slack.channel` (required) and
`standup.slack.threadMaxAgeHours` (optional, default 18). `slack.channel` is **this skill's**
required value — `zibby:standup` never reads it and never offers to fill it in.

Missing, it ends the run before anything else happens:
`NO_CONFIG: standup.slack.channel (find the channel id with slack_search_channels and add it)`.
Do not ask, and do not look it up and proceed: a channel id guessed at 07:00 posts the standup
somewhere nobody expected it.

Find the thread **before collecting anything**: if there is nowhere to post, that changes how the
run ends, and it is better to know up front.

Read the channel with `slack_read_channel` (limit 30) and take the **most recent** message whose
text contains `vlákno pro standup`. Match on the text, **not on the author** — it is usually the
`Templates DevRel dialy standup` bot early in the morning, and sometimes a teammate posts it by hand
when the bot is late. Its `ts` is the `thread_ts` for step 4.

The thread is the **posting target only**. It does not define the window: the gap between two
consecutive threads is whatever the bot's schedule happens to be, and a thread posted the evening
before would miss the whole working day it is supposed to report on. The calendar window in step 2
has no such failure mode.

If no matching message exists within `threadMaxAgeHours`, the run cannot post. Still do the work —
run steps 2 and 3, and let the borrowed pipeline persist its JSON and Markdown — then end with
`NO_THREAD: no standup thread in <channel> within <n>h`. Nothing is lost; a later manual
`/standup-post` posts it once the thread appears.

If the channel cannot be read at all: `SLACK_UNAVAILABLE: <the error>`.

## 2. Run the standup pipeline

Read `${CLAUDE_PLUGIN_ROOT}/skills/standup/SKILL.md` and follow its **steps 1 through 5** exactly as
written, with **no period argument** — the default window (yesterday, or Friday through Sunday on a
Monday) is what a morning standup reports. Do not reimplement or summarize those steps here; that
file is the single source of truth for the pipeline, and a second copy of it would drift.

Two adjustments, because this run is unattended:

- **Never ask.** A missing config or an unresolvable required value ends the run with
  `NO_CONFIG: <what is missing>` rather than offering to create anything.
- Its step 6 (print to the terminal) is replaced by steps 3 and 4 below. Its step 7 (write the
  `.md` next to the JSON, and report) still applies — run it, and fold its report into step 5.

Its failure statuses carry through unchanged: `NO_CONFIG`, `NO_ACTIVITY`, `GH_UNAVAILABLE`. On any
of them, post nothing.

## 3. Convert the links to Slack syntax

The render produces Markdown links, because its usual destination is a terminal someone copies out
of. The Slack API wants its own syntax, and posting Markdown through it yields literal brackets.

Rewrite every `[label](url)` as `<url|label>`. Nothing else about the message changes — not a word
of the Czech, not the grouping, not the order. If you find yourself editing anything but the link
syntax, stop: the fix belongs in `references/format.md`, not here.

**Before the first-ever run**, confirm by hand that these links survive `slack_send_message` and
render as links rather than literal angle brackets. The syntax is right for Slack, but this path
goes through an MCP tool whose own docs describe the message as markdown, and nothing upstream would
catch it. Send one throwaway bullet to yourself in a DM and look at it.

## 4. Post it

```
slack_send_message(channel_id: <slack.channel>, thread_ts: <ts from step 1>, message: <converted>)
```

Post once. If the call fails, `SLACK_UNAVAILABLE: <the error>` — do not retry with a reworded
message, and do not fall back to posting at channel top level: a standup outside its thread is
noise in a channel the whole team reads.

This posts publicly, unreviewed, under the user's name. That is the deliberate design, and it is
why `zibby:standup` exists as the read-it-first alternative. Nothing downstream of the render checks
the wording.

## 5. Report, and shout when it failed

Report what the borrowed step 7 reports — the resolved window, the counts, newly cached headings,
every note and degradation — plus the thread permalink the message landed in.

A fatal status also fires a desktop notification, because a run that quietly did nothing at 07:00 is
one you'd otherwise discover at 09:00:

```bash
osascript -e 'display notification "<status>" with title "standup"'
```

A successful run needs no notification — the message is in Slack.

## Scheduling

The routine is a macOS LaunchAgent, installed once:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/standup-post/scripts/install-routine.sh"   # [--hour H] [--minute M]
```

It writes `~/Library/LaunchAgents/com.zibby.standup-post.plist` and loads it: `claude -p
"/standup-post"` at 07:00, Monday through Friday, logging to `~/.zibby/standup/routine.log`.
`--dry-run` prints the plist without touching anything, `--uninstall` removes it, and re-running it
replaces the job rather than doubling it.

**Claude Code's own `CronCreate` is the wrong tool here**, and earlier versions of this skill said
otherwise. Its jobs live in one session's memory, die with that session and expire after seven days
— it cannot promise "every weekday at 7". launchd can, and it also catches up a run the Mac slept
through. Nothing else about the routine changes: the prompt is still the bare `/standup-post`, which
reaches this skill as a **user** invocation, which is what `disable-model-invocation: true` requires.

Two things to check after installing, because a scheduled `claude -p` run is not the same
environment as your terminal: that the Slack, Atlassian and Microsoft 365 MCP servers are
authenticated for it, and that `gh` and `jq` are on the PATH a login shell gives it. The first
morning's `routine.log` answers both.

07:00 on weekdays sits before anyone answers the thread, and it cannot usefully run the evening
before, since the window it reports on hasn't closed yet. Whether it sits *after* the thread appears
depends on the bot: in the channel this skill used to post to it fired at 06:00 daily, but nothing
guarantees the same time here. Confirm the bot's time in the target channel and move the routine if
it is later — a run that fires before the thread exists ends with `NO_THREAD` and posts nothing.

The scheduled run needs no model argument: the frontmatter `model: sonnet` above governs the skill
turn however it was invoked, so the morning task cannot silently land on whatever model the session
happened to start with.

Run `/standup` by hand for a few mornings before scheduling this, and compare what it produces
against what you would have written.
