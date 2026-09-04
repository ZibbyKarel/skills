---
name: todo-driven-development
description: "Drive a project's TODO.md items all the way from backlog to a draft PR — file a researched Jira issue, write and confirm an implementation plan, execute it with subagent-driven development, and open the resulting draft PR linked back to the issue. Use this when the user wants to work through their TODO.md, either one specific item ('process item 3', 'work on the flaky-test todo'), a range of items ('process items 1-4', 'do the first 4'), or the whole backlog ('go through my todo list', 'process everything in TODO.md'), including as an unattended overnight run that reports a table of issues and PRs in the morning. This is a thin conductor over three other skills — zibby:todo, zibby:jira, and the superpowers plugin — not a reimplementation of any of them."
argument-hint: "<item-number> | <start>-<end> | all | (<start>-<end> | all) --unattended"
---

# todo-driven-development

Conducts three existing skills into one pipeline; it owns none of their logic. Depends on `zibby:todo`,
`zibby:jira`, and the `superpowers` plugin (`writing-plans`, `subagent-driven-development`,
`finishing-a-development-branch`) all being available — if `superpowers` isn't installed, say so and
stop rather than reimplementing any part of it.

## Modes

- **One item:** the user names a specific item (by number, or by describing it) — process just that one.
- **Range:** the user names a span of item numbers (`1-4`, "the first 4", "items 2 through 5") —
  process those numbers, in ascending order, and nothing outside the span. Resolve a phrase like
  "the first 4" against `todo list`'s current numbering (`1-4`) before starting; never guess the
  bound from memory of an earlier `list` call in this conversation.
- **Whole backlog:** the user asks to work through the whole file — loop calling `todo next` and
  process each pending item in turn until it reports `no pending items`.
- **Unattended:** any of the above with nobody watching — an overnight run. Same pipeline, but
  every human checkpoint is replaced by a recorded decision, and the run ends with a report table
  instead of a conversation. Only enter this mode when the user asks for it explicitly (`all
  --unattended`, `1-4 --unattended`, "run it overnight", "let it run while I sleep"). Never infer it
  from impatience.

All four run the same per-item pipeline below. The only differences are what feeds the loop and,
in unattended mode, the substitutions named in each step.

## Autonomy level — one-item, range, and whole-backlog modes

Before touching the first item, ask the user once: **auto**, **review**, or **skip Jira**. Never
ask again, and never let a later step re-ask on the run's behalf — the answer governs every item in
this run.

- **auto** — no draft is shown for the Jira issue or the plan; the plan is instead checked by an
  independent subagent reviewer, the same way unattended mode checks it (step 4). Implementation
  and PR creation are already automatic in every mode and don't change.
- **review** — the user sees the drafted Jira issue (step 2) and the drafted plan (step 4) before
  either moves on. Implementation and PR creation are still automatic once the plan is confirmed.
- **skip Jira** — this run files no Jira issues at all: step 2 is skipped for every item, and every
  later step that would touch an issue (spec naming in step 3, the transitions in steps 5 and 6, the
  `Resolves <ISSUE-KEY>` line in the PR body) is skipped too. Use this for a project that isn't
  tracked in Jira, or a run where filing issues isn't wanted. The plan is checked the same
  independent-reviewer way as `auto`.

Unattended mode never asks this question — it already runs `auto`'s per-item behavior, plus the
full question-suppression described below. It always files Jira issues; `skip Jira` is only offered
in one-item, range, and whole-backlog modes.

## Every item runs in its own worktree

This pipeline never implements an item in the main checkout — a run sitting there for the minutes
or hours an implementation takes would block the user out of their own repo the whole time. Every
item gets its own git worktree at `./worktrees/<branch-name>` (the branch name computed in step 5),
in every mode, not only unattended ones.

State this as a declared directory preference — `./worktrees` at the repo root, not the
`.worktrees/` default — when invoking `superpowers:using-git-worktrees`, whether directly or
indirectly through `subagent-driven-development`'s own setup step. `using-git-worktrees` honors a
declared preference without asking for consent first; the point of this rule is that the question
never comes up, in any mode, since the answer is always yes.

Before the first worktree of a run, verify `./worktrees` is git-ignored
(`git check-ignore -q ./worktrees`); if not, append `worktrees/` to `.git/info/exclude` — local-only,
mirroring how the unattended pre-flight handles `.superpowers/`. Never edit the tracked `.gitignore`
for this.

## What unattended mode does and does not relax

It replaces **questions** with **recorded decisions**. It does not relax any judgment about what is
safe to do.

Standing authorizations for the whole run:

- push a new feature branch to `origin` and open a **draft** PR from it (step 6's pre-answer).

Everything else that would normally stop a human-supervised run still stops the **item**: a
destructive or irreversible operation, a security-sensitive action, a merge into a shared branch, a
publish, a force-push. When one of those is reached, abandon the item, record it as
`blocked: <what was reached>`, and move to the next one. Never widen this list at 3am to keep a run
going — an item recorded as blocked costs one morning of rework; a night that force-pushed
`develop` costs considerably more.

`subagent-driven-development` already runs continuously and rules on its own conflicts rather than
stalling, so its execution stage needs no changes for unattended use — only the pre-authorization
above, which you state in the dispatch.

## 0. Pre-flight — unattended mode only

The point of pre-flight is that a run which cannot possibly succeed fails at 22:05 with a clear
reason, not at 02:00 with a stalled question nobody will read until morning. Run every check, then
report the results and start; if any check fails, report and **stop the whole run** — do not start
item 1.

1. **`superpowers` is actually invocable.** Confirm `superpowers:writing-plans` and
   `superpowers:subagent-driven-development` appear in this session's available skills. A plugin
   listed as enabled by `claude plugin list` is not the same as a skill the `Skill` tool will
   accept — verify the skill, not the plugin. Without it the pipeline dies at step 4 every time.
2. **Jira is reachable and authenticated.** Call `atlassianUserInfo` once. The Atlassian MCP server
   is interactively authenticated, so a token that expired since the last session turns every item
   into an identical failure.
3. **The base repo is clean.** `git status` in the main checkout must show no uncommitted or
   untracked work. Never stash or discard on the user's behalf here — report and stop.
4. **The run directory is git-ignored.** The ledger lives at `.superpowers/tdd-runs/<run-id>/` in
   the **main checkout** (`run-id` = `date +%Y-%m-%d-%H%M`). If `git check-ignore -q .superpowers`
   fails, append `.superpowers/` to `.git/info/exclude` — local-only, so it never lands in a PR
   diff. Do not edit the tracked `.gitignore` for this.
5. **Snapshot the backlog.** Run `todo list` and write every pending item — its number and text —
   into the ledger before touching anything. Running a range unattended (`1-4 --unattended`)
   snapshots and reports on only the items inside that span, already-done ones included (so the
   ledger can record them as `skipped: already done` per step 1), not the rest of the file. The
   final report names items the user recognises even if TODO.md changed underneath the run.

Then write the ledger header: the run id, the base branch, the item count, and the standing
authorizations above. The ledger is the run's memory: it survives compaction, and every later step
appends to it. If this session is resumed after a crash, the ledger — not recollection — says which
items already have issues and PRs.

## Per-item pipeline

### 1. Get the item's text

`todo show <n>` (one-item mode) or `todo next` (whole-backlog mode, and unattended mode when it's
running the whole backlog, both of which also give you `<n>`). This is the raw input for the next
step — don't rephrase or summarize it yourself first.

**Range mode:** run `todo list` once at the start of the run, not per item, to see which numbers in
the span are already checked off. Walk the span in ascending order; for each `<n>`, if `list`
showed it already done, skip it without running any later step — report it (a ledger row in
unattended mode, a line to the user otherwise) as `skipped: already done` and move to the next
number in the span. For a still-pending `<n>`, use `todo show <n>` for its text, same as one-item
mode. When the span is exhausted, the run ends — there is no `todo next` call and no "no pending
items" condition in this mode.

### 2. File the Jira issue

**If this run's autonomy level is `skip Jira`, skip this step and step 3 entirely** — there is no
issue key, URL, or drafted description. Go straight to step 4, writing the spec file described there
from the item's text directly instead of a Jira description.

Otherwise, invoke the `zibby:jira` skill with the item's text as input.

**One-item, range, and whole-backlog modes:** pass the autonomy level chosen at the top of the run,
explicitly — `confirm` for `review`, `auto` for `auto` — so `zibby:jira` doesn't ask its own
question per item; the run already answered it once. It still runs its own duplicate check
regardless of level, and that check is never pre-answered: if it finds a strong match, let it ask
the user how to proceed (create anyway, reuse, or refine) exactly as it's written — each duplicate
is an independent decision even within an `auto` run.

**Unattended mode:** first check the ledger for this item's row — if it already carries an issue key
from an earlier, interrupted pass of this run, reuse that issue and resume at step 3. Re-filing it
would find the issue this very run created and skip the item as a duplicate of itself.

Otherwise pass `zibby:jira` the autonomy level `unattended` explicitly, which is the one case where
pre-answering that question is correct — the user authorized it when they asked for an overnight
run. That level also turns its own would-be questions into failure statuses. Handle each by ending
the item and moving on, never by deciding for it:

| It returns | Ledger row | Why not decide it yourself |
|---|---|---|
| `DUPLICATE: <key> <url>` | `skipped: duplicate of <key>` | Filing a dup spams a board the team reads; reusing an issue whose scope only looks similar attaches a night's work to the wrong ticket. |
| `NO_CONFIG: <what>` | `failed: jira config` — and **stop the whole run**, every item will fail identically | Guessing a localized issue type name is not a decision, it's a coin flip. |
| `JIRA_UNAVAILABLE: <err>` | `failed: jira unavailable` — stop the whole run on the second consecutive one | One may be a blip; two in a row is an expired token, and the rest of the night would produce nothing. |

Otherwise take its reported issue key, URL, and the description it drafted, and record them.

### 3. Save the issue as a spec

`writing-plans` (next step) argues its plan from a spec file. Write one to
`docs/superpowers/specs/<ISSUE-KEY>.md` containing the issue's title, its URL, and the full drafted
description from step 2 — this is what carries the Jira link all the way through the plan into
every task an implementer sees, so don't skip or shorten it.

**`skip Jira`:** there is no `<ISSUE-KEY>`. Name the file `docs/superpowers/specs/todo-<n>.md` (the
item's number) and write the item's raw text as the spec content — no Jira title, URL, or drafted
description to include.

### 4. Write the plan — and get it checked

Invoke `superpowers:writing-plans`, pointing it at the spec file from step 3. It saves a plan to
`docs/superpowers/plans/` and asks which execution approach to use.

**Before answering that**, the plan's *content* gets checked. This is the step the whole skill
exists for — running `subagent-driven-development` on an unexamined plan is what this pipeline was
built to avoid — so it is never skipped, only performed differently depending on the run's autonomy
level.

**review — the user checks it.** Show them the plan (or a tight summary — files touched, task list,
and anything you'd flag) and ask if it needs changes. This is not optional and not something to fold
into a "run everything hands-off" preference. Apply any requested changes before moving on.

**auto and unattended — an independent reviewer checks it instead of the user.** Dispatch a fresh
subagent on the most capable available model — fresh because a reviewer that watched you write the
plan will agree with it. Hand it two file paths, the spec and the plan, and nothing else; do not
summarize either into the prompt, and do not tell it what you think of the plan. Ask it for four
verdicts:

1. **Coverage** — does every requirement in the spec map to a task in the plan? Name the gaps.
2. **Placeholders** — any "TBD", "handle edge cases", "similar to Task N", or a code step with no
   code? (`writing-plans` calls these plan failures; it also self-reviews for them, which is
   exactly why a second, independent pass is worth its cost.)
3. **Consistency** — do the types, signatures, and names used in later tasks match what earlier
   tasks define?
4. **Scope and safety** — does any task reach outside this repo, touch credentials, migrate or
   delete data, rewrite git history, or change CI/release/publishing configuration?

It returns `SOUND`, `SOUND_WITH_NOTES` (plus the notes), or `DEFECTIVE` (plus the reasons).

- `SOUND` → proceed.
- `SOUND_WITH_NOTES` → record the notes (in the ledger, if this run keeps one) and carry them
  verbatim into step 5's dispatch, so the executing skill's own review loop sees them.
- `DEFECTIVE`, or any finding under verdict 4:
  - **auto** — `auto` suppresses confirmations, not escalations. Stop and show the user the plan
    and the reviewer's reasons, and ask how to proceed, before touching this item further.
  - **unattended** — no one is there to ask. Skip the item. Record
    `skipped: plan defect — <reason>` and move to the next one. The Jira issue stays open and the
    TODO item stays unchecked, which is the correct morning state: a human reads the reason and
    decides. Do not attempt a repair round — a plan a reviewer called defective is a plan whose spec
    or research is wrong upstream, and re-planning it unattended just produces a second wrong plan
    more confidently.

Once the plan is confirmed (any path above), answer the execution-approach question with
**Subagent-Driven** — this pipeline always uses `superpowers:subagent-driven-development`, never
inline execution.

### 5. Execute

**`skip Jira`:** there is no issue to transition — skip the paragraph below and go straight to
naming the branch.

Before dispatching, move the Jira issue into progress: call `getTransitionsForJiraIssue` for the
issue key from step 2, and pick the transition whose name best matches "in progress" — match
case-insensitively and allow for a localized name (this instance's issue types already are, e.g.
"Úkol"); if no name matches but exactly one transition targets a status in the `indeterminate`
category, use that one instead. Call `transitionJiraIssue` with the chosen transition. Treat this as
best-effort: no confident match, or a failed call, gets noted (a ledger row in unattended mode, a
mention to the user otherwise) and the item proceeds regardless — a wrong or missing Jira status is
a one-click fix later, never a reason to stop or fail the item.

Also before dispatching, name the branch to match Jira's own convention rather than letting
`subagent-driven-development`'s setup step invent one: `<ISSUE-KEY>-<slug>`, where `<slug>` is the
issue title lowercased, every run of non-alphanumeric characters collapsed to a single hyphen, and
leading/trailing hyphens trimmed — e.g. issue `CZ3TDR1-590` titled "Shoptet init: add node_modules
to the scaffolded .gitignore" becomes
`CZ3TDR1-590-shoptet-init-add-node-modules-to-the-scaffolded-gitignore`. State this exact branch
name, and the worktree path `./worktrees/<that-branch-name>` per the rule above, in the dispatch
below.

**`skip Jira`:** there is no issue key or title to build this from. Name the branch
`todo-<n>-<slug>`, with `<slug>` built the same way from the TODO item's own text.

Invoke `superpowers:subagent-driven-development` on the confirmed plan, stating the branch name and
worktree path computed above for its setup step to use. Let it run to completion per its own rules
(continuous execution, its own model selection, its own review loop) — this skill doesn't intervene
in how it implements or reviews. It ends by directing you to
`superpowers:finishing-a-development-branch`.

**Unattended mode:** state the standing authorizations from the top of this file in the dispatch, so
its own stop conditions resolve without a human. Carry any `SOUND_WITH_NOTES` findings from step 4
in the same dispatch. When it finishes, copy its "Rulings I made" list into the ledger — those are
decisions taken on the user's behalf while they slept, and the morning report is the only place they
will ever see them.

If it ends without a mergeable branch — a tripped breaker with load-bearing findings parked, or a
stop it could not resolve — record `failed: execution — <its stated reason>` and move to the next
item. Do not retry the item in the same run.

### 6. Finish the branch — with two standing answers

Invoke `superpowers:finishing-a-development-branch`. It runs the test suite and, once green,
presents a menu and normally waits for a human answer. For this pipeline specifically, the user
has pre-authorized the answer: when the menu appears, choose **"2. Push and create a Pull
Request"** and create it as a **draft** (`gh pr create --draft`, or the equivalent flag for
whatever forge tooling the skill reaches for) — don't stop and wait for that menu click. Every
other part of that skill (running tests, detecting the environment, determining the base branch,
cleanup) proceeds exactly as it's written; this pipeline only pre-answers the integration
question, and only with this one option.

Compose the PR body so it links the Jira issue from step 2 — e.g. a line like
`Resolves <ISSUE-KEY>: <issue URL>` — since `finishing-a-development-branch`'s own template has no
notion of Jira. Report the created PR's URL once it exists.

**`skip Jira`:** there is no issue to link — omit the `Resolves` line and the transition below
entirely.

Once the PR exists, move the Jira issue to its review status the same best-effort way as step 5:
call `getTransitionsForJiraIssue` again and pick the transition whose name best matches "review"
(case-insensitively, allowing for localization), falling back to a lone `indeterminate`-category
candidate only when no name matches. Call `transitionJiraIssue` with it. A missing match or a
failed call is noted, not fatal, exactly as in step 5 — never skip the item or withhold the PR over
a transition that didn't go through.

If the test suite is red and the branch never reaches a PR, record `failed: tests red` with the
failing suite's name and move on. An item without a PR URL is never marked done in step 7.

### 7. Close the loop

`subagent-driven-development`'s setup step works in a git worktree, and choosing "2. Push and
create a Pull Request" in step 6 leaves you there rather than returning to the main checkout — so
run `todo done` from the **main repo checkout's working directory, not the worktree**. `todo`
resolves TODO.md via `git rev-parse --show-toplevel` from wherever it's invoked, and a worktree has
its own toplevel; running it from inside the worktree would flip the checkbox in a copy of TODO.md
that never makes it back to the branch this pipeline started from.

`todo done <n> <PR-URL>` — the TODO.md item now points at the shipped (draft) PR. The Jira issue
itself is reachable from the PR body and from the plan's spec file, so one link in TODO.md is
enough; don't also try to record the Jira link here.

Whatever stage an item ends at — a shipped PR or any of the `failed`/`skipped` outcomes above —
remove its worktree before moving to the next item (`git worktree remove --force
./worktrees/<its-branch-name>`) once you no longer need it for the report. This applies in every
mode: `./worktrees/` is shared across the whole run, and a leftover entry from a dead or finished
item just clutters it for whichever item comes next.

**Unattended mode:** append the item's finished row to the ledger, return to the main checkout, and
go back to step 1 — `todo next` when running the whole backlog, or the next number in the span when
running a range. Two rules govern the loop:

- **Failure isolation.** One item's failure never ends the run. Record its row, return to the main
  checkout, and take the next item.
- **Systemic-failure stop.** Three consecutive items failing at the same stage is not bad luck —
  it's a broken precondition the pre-flight didn't catch. Stop the run and go straight to the
  report.

In interactive whole-backlog mode, go back to step 1 (`todo next`) until there's nothing left. In
interactive range mode, go back to step 1 for the next number in the span until the span is
exhausted.

## 8. The morning report — unattended mode only

When the loop ends — backlog exhausted, systemic stop, or a hard stop from step 2 — write the report
to `<run-dir>/summary.md` **and** print it as the session's final message. Writing it to a file
first matters: it is the deliverable, and a session that dies while composing a long message leaves
nothing behind otherwise.

The report has four parts, in this order:

**1. The table.** One row per item attempted, in run order:

| # | TODO item | Jira | PR | Status |
|---|---|---|---|---|
| 4 | Add `.env.example` per package | [CZ3TDR1-601](url) | [#42](url) | ✅ done |
| 5 | Remove the repo-documentation skill | [CZ3TDR1-602](url) | — | ⏭️ skipped: plan defect |
| 6 | Move `dev` env vars to flags | — | — | ⏭️ skipped: duplicate of CZ3TDR1-588 |
| 7 | `shoptet version` command | [CZ3TDR1-603](url) | — | ❌ failed: tests red (`test:unit`) |

Cells with no value get `—`, never a blank or a guess.

**2. One-line summary.** Items attempted, PRs opened, skipped, failed — and, if the run stopped
early, which stop condition tripped and at which item.

**3. Rulings made on the user's behalf.** Every `Ruling:` line collected from every item's
`subagent-driven-development` run, each with what it costs if wrong, grouped by item. This is the
list the user reads to find what to undo. Never summarize it away: a ruling that only exists in a
deleted worktree was a decision made in secret.

**4. What needs a human.** Each skipped and failed item, one line each, saying what the next action
is — reconcile a duplicate, fix the upstream spec, look at a red suite. Items in this section still
have open Jira issues and unchecked TODO lines by design.

## Launching an unattended run

Skill questions are only one of the two ways a night run freezes; **permission prompts** are the
other, and no wording in this skill prevents them. Before starting, the session needs either bypass
permissions or an allowlist that already covers `git`, `gh`, `python3`, the project's test and build
commands, and the Atlassian tools.

Prefer a normal interactive session left running overnight over a headless (`claude -p`) or
scheduled cloud run: the Atlassian MCP server is interactively authenticated and may simply be
absent in those environments, which turns the whole run into eleven identical `JIRA_UNAVAILABLE`
rows.

Before the first overnight run on a given project, do one supervised single-item run. It surfaces a
missing plugin, an expired Jira token, or a wrong board configuration in ten minutes instead of
silently consuming the night.
