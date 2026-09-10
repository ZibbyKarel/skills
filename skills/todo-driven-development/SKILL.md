---
name: todo-driven-development
description: "Drive a project's TODO.md items all the way from backlog to a draft PR — file a researched Jira issue, write and confirm an implementation plan, execute it with subagent-driven development, and open the resulting draft PR linked back to the issue. Use this when the user wants to work through their TODO.md, either one specific item ('process item 3', 'work on the flaky-test todo'), a range of items ('process items 1-4', 'do the first 4'), or the whole backlog ('go through my todo list', 'process everything in TODO.md'), including as a --auto overnight run that reports a table of issues and PRs in the morning. This is a thin conductor over three other skills — zibby:todo, zibby:jira, and the superpowers plugin — not a reimplementation of any of them."
argument-hint: "<item-number> | <start>-<end> | all | (<start>-<end> | all) --auto [--skip-jira] [--target <branch>] [--no-pr]"
---

# todo-driven-development

Conducts three existing skills into one pipeline; it owns none of their logic. Items filed ahead
of time by `zibby:plan-to-backlog` are picked up here with their issue reused, not re-filed
(step 2). Depends on `zibby:todo`,
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
- **`--auto`:** any of the above with nobody watching — an overnight run. Same pipeline, but
  every human checkpoint is replaced by a recorded decision, and the run ends with a report table
  instead of a conversation. Only enter this mode when the user asks for it explicitly (`all
  --auto`, `1-4 --auto`, "run it overnight", "let it run while I sleep"). Never infer it
  from impatience.
- **`--skip-jira`:** a flag, combinable with any of the above including `--auto` (`all --auto
  --skip-jira`, `1-4 --auto --skip-jira`), that pre-answers the Jira question from the "Autonomy
  level" section below as **skip Jira** instead of asking or, for `--auto`, instead of `--auto`'s
  usual "always files Jira issues" default. See that section and "What `--auto` does and does not
  relax" for exactly what this does and doesn't change.
- **`--target <branch>`:** a flag, combinable with any of the above, that names the branch every
  item's work integrates against instead of whatever `finishing-a-development-branch`'s own step 3
  would detect or ask about. It works standalone: without `--no-pr` it only changes which branch
  the PR opens against. Combined with `--no-pr` it also names the branch each item merges into
  directly. See step 6 ("Finish the branch") for exactly how it's used in each case.
- **`--no-pr`:** a flag, combinable with any of the above including `--auto` (`all --auto
  --target develop --no-pr`), that pre-answers `finishing-a-development-branch`'s step 4 menu with
  **"1. Merge back to `<base-branch>` locally"** instead of **"2. Push and create a Pull Request"**
  — every item merges straight into the target branch instead of landing in a draft PR. `<base-branch>`
  is `--target`'s branch when given, otherwise whatever step 3 would normally detect. The merge
  stays local — this pipeline never pushes the target branch itself; pushing it onward is left to
  the user. See step 6 for exactly how this changes that step, step 7 for how the loop closes
  without a PR URL, and "What `--auto` does and does not relax" for the standing authorization this
  requires in `--auto` runs.

All four run the same per-item pipeline below. The only differences are what feeds the loop and,
with `--auto`, the substitutions named in each step.

## Autonomy level — one-item, range, and whole-backlog modes (not `--auto`)

Before touching the first item, ask the user once: **review** or **skip Jira**. Never
ask again, and never let a later step re-ask on the run's behalf — the answer governs every item in
this run.

- **review** — the user sees the drafted Jira issue (step 2) and the drafted plan (step 4) before
  either moves on. Implementation and PR creation are still automatic once the plan is confirmed.
- **skip Jira** — this run files no Jira issues at all: step 2 is skipped for every item, and every
  later step that would touch an issue (spec naming in step 3, the transitions in steps 5 and 6, the
  `<ISSUE-KEY>` reference in the PR title and body) is skipped too. Use this for a project that isn't
  tracked in Jira, or a run where filing issues isn't wanted. The plan moves straight to execution
  once `writing-plans` has saved it, the same as `--auto`.

`--auto` never asks this question — it already moves straight from a saved plan to execution, the
same as `skip Jira`, plus the full question-suppression described below. By default it always files
Jira issues; pass the `--skip-jira` flag alongside it (`all --auto --skip-jira`, `1-4 --auto
--skip-jira`) to make an overnight run behave as `skip Jira` for every Jira-related step too — no
issues filed, no transitions attempted, no `<ISSUE-KEY>` in branch or PR title — while every other
`--auto` behavior (continuous execution, standing authorizations, ledger, morning report) is
unchanged. Without the flag, `skip Jira` is only offered as an interactive choice in one-item,
range, and whole-backlog (non-`--auto`) runs; `--skip-jira` also works as a flag in those modes, to
pre-answer the same question without asking.

Every later step in this pipeline that says "**skip Jira:**" means: this run has no Jira issue for
the item, whether that's because the interactive choice was `skip Jira` or because `--skip-jira` was
passed (with or without `--auto`). Read every such bullet below as covering both.

## Every item runs in its own worktree

This pipeline never implements an item in the main checkout — a run sitting there for the minutes
or hours an implementation takes would block the user out of their own repo the whole time. Every
item gets its own git worktree at `./worktrees/<branch-name>` (the branch name computed in step 5),
in every mode, not only `--auto` ones.

State this as a declared directory preference — `./worktrees` at the repo root, not the
`.worktrees/` default — when invoking `superpowers:using-git-worktrees`, whether directly or
indirectly through `subagent-driven-development`'s own setup step. `using-git-worktrees` honors a
declared preference without asking for consent first; the point of this rule is that the question
never comes up, in any mode, since the answer is always yes.

Before the first worktree of a run, verify `./worktrees` is git-ignored
(`git check-ignore -q ./worktrees`); if not, append `worktrees/` to `.git/info/exclude` — local-only,
mirroring how the `--auto` pre-flight handles `.superpowers/`. Never edit the tracked `.gitignore`
for this.

## What `--auto` does and does not relax

It replaces **questions** with **recorded decisions**. It does not relax any judgment about what is
safe to do.

Standing authorizations for the whole run:

- push a new feature branch to `origin` and open a **draft** PR from it (step 6's pre-answer) — or,
  when `--no-pr` is passed, merge the feature branch **locally** into the target branch (`--target`'s
  branch, or the detected base branch if `--target` is absent) instead. This is the one explicit
  carve-out from the "merge into a shared branch" stop condition below: it covers only this local
  merge of this run's own feature branches into the named target, never a push of that branch
  onward and never any other shared-branch operation.

Everything else that would normally stop a human-supervised run still stops the **item**: a
destructive or irreversible operation, a security-sensitive action, a merge into a shared branch
other than the `--no-pr` case above, a publish, a force-push. When one of those is reached, abandon the item, record it as
`blocked: <what was reached>`, and move to the next one. Never widen this list at 3am to keep a run
going — an item recorded as blocked costs one morning of rework; a night that force-pushed
`develop` costs considerably more.

`subagent-driven-development` already runs continuously and rules on its own conflicts rather than
stalling, so its execution stage needs no changes for `--auto` use — only the pre-authorization
above, which you state in the dispatch.

## 0. Pre-flight — `--auto` only

The point of pre-flight is that a run which cannot possibly succeed fails at 22:05 with a clear
reason, not at 02:00 with a stalled question nobody will read until morning. Run every check, then
report the results and start; if any check fails, report and **stop the whole run** — do not start
item 1.

1. **`superpowers` is actually invocable.** Confirm `superpowers:writing-plans` and
   `superpowers:subagent-driven-development` appear in this session's available skills. A plugin
   listed as enabled by `claude plugin list` is not the same as a skill the `Skill` tool will
   accept — verify the skill, not the plugin. Without it every item dies at step 4 or step 5.
2. **Jira is reachable and authenticated.** Skip this check entirely when `--skip-jira` is also
   given — this run touches no Jira issue, so there is nothing to verify. Otherwise call
   `atlassianUserInfo` once. The Atlassian MCP server is interactively authenticated, so a token
   that expired since the last session turns every item into an identical failure.
3. **The base repo is clean.** `git status` in the main checkout must show no uncommitted or
   untracked work. Never stash or discard on the user's behalf here — report and stop.
4. **The run directory is git-ignored.** The ledger lives at `.superpowers/tdd-runs/<run-id>/` in
   the **main checkout** (`run-id` = `date +%Y-%m-%d-%H%M`). If `git check-ignore -q .superpowers`
   fails, append `.superpowers/` to `.git/info/exclude` — local-only, so it never lands in a PR
   diff. Do not edit the tracked `.gitignore` for this.
5. **Snapshot the backlog.** Run `todo list` and write every pending item — its number and text —
   into the ledger before touching anything. Running a range with `--auto` (`1-4 --auto`)
   snapshots and reports on only the items inside that span, already-done ones included (so the
   ledger can record them as `skipped: already done` per step 1), not the rest of the file. The
   final report names items the user recognises even if TODO.md changed underneath the run.

Then write the ledger header: the run id, the base branch, the item count, and the standing
authorizations above. The ledger is the run's memory: it survives compaction, and every later step
appends to it. If this session is resumed after a crash, the ledger — not recollection — says which
items already have issues and PRs.

## Per-item pipeline

### 1. Get the item's text

`todo show <n>` (one-item mode) or `todo next` (whole-backlog mode, and `--auto` when it's
running the whole backlog, both of which also give you `<n>`). This is the raw input for the next
step — don't rephrase or summarize it yourself first.

**Range mode:** run `todo list` once at the start of the run, not per item, to see which numbers in
the span are already checked off. Walk the span in ascending order; for each `<n>`, if `list`
showed it already done, skip it without running any later step — report it (a ledger row with
`--auto`, a line to the user otherwise) as `skipped: already done` and move to the next
number in the span. For a still-pending `<n>`, use `todo show <n>` for its text, same as one-item
mode. When the span is exhausted, the run ends — there is no `todo next` call and no "no pending
items" condition in this mode.

### 2. File the Jira issue — unless the item already has one

**First, look at the item's text for an issue reference.** `zibby:plan-to-backlog` files issues up
front and leaves each TODO.md line pointing at its own, so a line can arrive here already carrying
`([CZ3TDR1-601](https://…/browse/CZ3TDR1-601))`. When it does:

- Fetch it with `getJiraIssue`. Use **its** summary and description as this item's issue — skip
  filing entirely, and skip the duplicate check with it: there is nothing heuristic to decide when
  the key is written in the line verbatim.
- If its status is in the **Done** category, do not implement anything. Report the item as
  `skipped: <key> is already done` (a ledger row with `--auto`) and move on — a checked-off
  issue with an unchecked TODO line means the two got out of sync, and the fix is a human looking
  at which one is right, not a second implementation of finished work.
- If the fetch fails, treat it as `JIRA_UNAVAILABLE` for this item rather than filing a new issue
  around it — filing a second issue for work that already has one is the exact outcome this check
  exists to prevent.
- A ref that is **not** a Jira issue — a PR URL, or a path to a spec file from a `--skip-jira`
  batch — is not an issue reference. Carry on with this step as written below.

Then continue at step 3 with the fetched issue's key, URL and description.

**If this run's autonomy level is `skip Jira`, or the `--skip-jira` flag is set (including together
with `--auto`), skip this step and step 3 entirely** — there is no issue key, URL, or drafted
description. Go straight to step 4, writing the spec file described there from the item's text
directly instead of a Jira description.

Otherwise, invoke the `zibby:jira` skill with the item's text as input, passing `sprint: none`
explicitly whatever this repo's config says. The sprint is set in step 5, when implementation
actually starts — which is also the only place it can be set for an item that arrived here with an
issue `zibby:plan-to-backlog` filed earlier, since that branch creates nothing.

**One-item, range, and whole-backlog modes (not `--auto`):** pass the autonomy level chosen at the
top of the run, explicitly — `confirm` for `review` — so `zibby:jira` doesn't ask its own question
per item; the run already answered it once. It still runs its own duplicate check regardless of
level, and that check is never pre-answered: if it finds a strong match, let it ask the user how to
proceed (create anyway, reuse, or refine) exactly as it's written — each duplicate is an independent
decision even within this run.

**`--auto`, without `--skip-jira`:** first check the ledger for this item's row — if it already
carries an issue key from an earlier, interrupted pass of this run, reuse that issue and resume at
step 3. Re-filing it would find the issue this very run created and skip the item as a duplicate of
itself.

Otherwise (still `--auto`, still no `--skip-jira`) pass `zibby:jira` the autonomy level `auto`
explicitly, which is the one case where
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
`docs/superpowers/specs/<ISSUE-KEY>.md` containing the issue's title, its URL, and the full
description from step 2 — whether that description was just drafted or fetched from an issue
`zibby:plan-to-backlog` filed earlier — this is what carries the Jira link all the way through the plan into
every task an implementer sees, so don't skip or shorten it.

**`skip Jira`:** there is no `<ISSUE-KEY>`. Name the file `docs/superpowers/specs/todo-<n>.md` (the
item's number) and write the item's raw text as the spec content — no Jira title, URL, or drafted
description to include.

### 4. Write the plan

Invoke `superpowers:writing-plans`, pointing it at the spec file from step 3. It saves a plan to
`docs/superpowers/plans/` — running its own self-review (coverage, placeholder scan, type
consistency) before it hands the plan back, fixing anything that check finds rather than reporting
it — and then asks which execution approach to use.

This pipeline adds no independent check of its own on top of that self-review. It did, once: a fresh
subagent re-reading the plan cold and voting `SOUND`/`SOUND_WITH_NOTES`/`DEFECTIVE`. It was removed —
a reviewer with no stake in the plan almost always finds *something* to flag, on a plan that was
perfectly implementable, and the rule this pipeline had (never repair a `DEFECTIVE` verdict
unattended, only skip the item) meant that reflex reliably stopped runs on ordinary, fixable plans
rather than only on genuinely broken ones. `writing-plans`' own self-review is the check; trust it.

**review — the user checks it anyway.** Show them the plan (or a tight summary — files touched, task
list, and anything you'd flag) and ask if it needs changes. This is a different kind of check
(human judgement on intent and scope, not a mechanical re-verification) and stays optional-but-asked
in this one mode; apply any requested changes before moving on.

**skip Jira and `--auto` — move straight to execution.** No further gate. If the plan turns out to
be wrong, that surfaces in step 5 or step 6 the normal way (a task's own review loop, a red test
suite) and is handled by those steps' existing failure handling, not by a plan-level checkpoint here.

Once the plan is saved (and, under `review`, confirmed), answer the execution-approach question with
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
best-effort: no confident match, or a failed call, gets noted (a ledger row with `--auto`, a
mention to the user otherwise) and the item proceeds regardless — a wrong or missing Jira status is
a one-click fix later, never a reason to stop or fail the item.

Then put the issue into the board's **current sprint**, following `zibby:jira`'s
`references/sprint.md`: resolve the Sprint field id and the current sprint's id (steps 1 and 2 of
that file), then apply it with `editJiraIssue` on the issue key (step 3's second path — the issue
already exists here, whether this run filed it in step 2 or `zibby:plan-to-backlog` filed it weeks
ago). This is the same best-effort deal as the transition above and carries the same rules: an
unresolvable field, a board with no active sprint, or a rejected call gets noted (a ledger row with
`--auto`, a mention to the user otherwise) and the item proceeds regardless. It happens here
rather than at filing time because an issue in the current sprint is a claim that the work is
being done now, and that only becomes true at this step.

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

**`--auto`:** state the standing authorizations from the top of this file in the dispatch, so
its own stop conditions resolve without a human. When it finishes, copy its "Rulings I made" list into the ledger — those are
decisions taken on the user's behalf while they slept, and the morning report is the only place they
will ever see them.

If it ends without a mergeable branch — a tripped breaker with load-bearing findings parked, or a
stop it could not resolve — record `failed: execution — <its stated reason>` and move to the next
item. Do not retry the item in the same run.

### 6. Finish the branch — with two standing answers

Invoke `superpowers:finishing-a-development-branch`. It runs the test suite and, once green,
presents a menu and normally waits for a human answer. For this pipeline specifically, the user
has pre-authorized the answer — which one depends on `--no-pr`.

**Without `--no-pr` (default):** when the menu appears, choose **"2. Push and create a Pull
Request"** and create it as a **draft** (`gh pr create --draft`, or the equivalent flag for
whatever forge tooling the skill reaches for) — don't stop and wait for that menu click. If
`--target <branch>` was given, open the PR against `<branch>` (`gh pr create --base <branch>`, or
the equivalent) instead of whatever step 3 would otherwise detect or ask about; without `--target`,
let step 3 detect the base branch as usual. Every other part of that skill (running tests,
detecting the environment, cleanup) proceeds exactly as it's written; this pipeline only
pre-answers the integration question, and only with this one option.

GitHub's Jira integration links a PR to its issue from the bare issue key appearing in the branch
name, a commit message, or the PR title — not from any particular keyword ("Resolves", "Fixes", …)
in the PR body, which isn't one of its documented detection points. The branch name from step 4
already carries `<ISSUE-KEY>` at the start, so linking already works; also prefix the PR title with
`<ISSUE-KEY>` for a second, title-level match. Compose the PR body so it states the issue plainly
for human readers — e.g. a line like `<ISSUE-KEY>: <issue URL>` — since `finishing-a-development-branch`'s
own template has no notion of Jira, but don't rely on the body's wording for the integration itself.
Report the created PR's URL once it exists.

**With `--no-pr`:** when the menu appears, choose **"1. Merge back to `<base-branch>` locally"**
instead, with `<base-branch>` set to `--target`'s branch if given, or whatever step 3 would
otherwise detect or ask about if `--target` was omitted. That option merges the feature branch,
re-runs the test suite on the merged result, and — once green — deletes the feature branch and
removes its worktree itself (that skill's own step 6); this pipeline's separate worktree-removal
instruction at the end of step 7 is then redundant, see the note there. The merge stays local: this
pipeline never pushes `<base-branch>` onward, even to `origin` — that's left to the user. If tests
fail on the merged result, that skill stops there and leaves the worktree and branch in place
rather than merging broken code; treat this the same as a red test suite below
(`failed: tests red on merge`) and move on without deleting anything.

**`skip Jira`:** there is no issue to link — omit the `Resolves` line and the transition below
entirely. This applies the same way under `--no-pr` and under the default PR path.

Once integration completes — a PR opened (default) or a successful local merge (`--no-pr`) — move
the Jira issue to a status reflecting which one happened, the same best-effort way as step 5:

- **Default:** transition it to whatever best matches "review" (case-insensitively, allowing for
  localization), since a PR is a request for human review, falling back to a lone
  `indeterminate`-category candidate only when no name matches.
- **`--no-pr`:** the work already landed on `<base-branch>` with no review step in between, so
  transition it to whatever best matches "done"/"resolved" instead, falling back to a lone
  `done`-category candidate only when no name matches.

Call `getTransitionsForJiraIssue` and `transitionJiraIssue` as in step 5. A missing match or a
failed call is noted, not fatal, exactly as in step 5 — never skip the item or withhold the PR or
merge over a transition that didn't go through.

If the test suite is red and the branch never integrates — no PR opened under the default path, no
merge landed under `--no-pr` — record `failed: tests red` with the failing suite's name and move
on. An item that hasn't integrated is never marked done in step 7.

### 7. Close the loop

`subagent-driven-development`'s setup step works in a git worktree, and choosing "2. Push and
create a Pull Request" in step 6 leaves you there rather than returning to the main checkout — so
run `todo done` from the **main repo checkout's working directory, not the worktree**. `todo`
resolves TODO.md via `git rev-parse --show-toplevel` from wherever it's invoked, and a worktree has
its own toplevel; running it from inside the worktree would flip the checkbox in a copy of TODO.md
that never makes it back to the branch this pipeline started from. Choosing "1. Merge back
locally" under `--no-pr` already returns you to the main checkout as part of that option, so this
is only a concern in the default (PR) path.

`todo done <n> <PR-URL>` in the default path — the TODO.md item now points at the shipped (draft)
PR. **`--no-pr`:** there is no PR URL; instead run `todo done <n> <base-branch>@<short-sha>` with
the merge commit's short SHA on `<base-branch>`, so the item still points at something that
resolves to the shipped work. The Jira issue itself is reachable from the PR body (default) or the
plan's spec file (either path), so one link in TODO.md is enough; don't also try to record the
Jira link here.

Whatever stage an item ends at — integrated work or any of the `failed`/`skipped` outcomes above —
remove its worktree before moving to the next item (`git worktree remove --force
./worktrees/<its-branch-name>`) once you no longer need it for the report — **except** on the
`--no-pr` success path, where `finishing-a-development-branch`'s own "Merge back locally" option
already removed the worktree and deleted the branch as part of its step 6; running the removal
again there is a no-op at best, so skip it. This applies in every other case regardless of mode:
`./worktrees/` is shared across the whole run, and a leftover entry from a dead or finished item
just clutters it for whichever item comes next.

**`--auto`:** append the item's finished row to the ledger, return to the main checkout, and
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

## 8. The morning report — `--auto` only

When the loop ends — backlog exhausted, systemic stop, or a hard stop from step 2 — write the report
to `<run-dir>/summary.md` **and** print it as the session's final message. Writing it to a file
first matters: it is the deliverable, and a session that dies while composing a long message leaves
nothing behind otherwise.

The report has four parts, in this order:

**1. The table.** One row per item attempted, in run order:

| # | TODO item | Jira | PR | Status |
|---|---|---|---|---|
| 4 | Add `.env.example` per package | [CZ3TDR1-601](url) | [#42](url) | ✅ done |
| 5 | Remove the repo-documentation skill | [CZ3TDR1-602](url) | — | ⏭️ skipped: CZ3TDR1-602 is already done |
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

## Launching a `--auto` run

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
