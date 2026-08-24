---
name: todo-driven-development
description: "Drive a project's TODO.md items all the way from backlog to a draft PR — file a researched Jira issue, write and confirm an implementation plan, execute it with subagent-driven development, and open the resulting draft PR linked back to the issue. Use this when the user wants to work through their TODO.md, either one specific item ('process item 3', 'work on the flaky-test todo') or the whole backlog ('go through my todo list', 'process everything in TODO.md'). This is a thin conductor over three other skills — todo, create-jira-issue, and the superpowers plugin — not a reimplementation of any of them."
---

# todo-driven-development

Conducts three existing skills into one pipeline; it owns none of their logic. Depends on `todo`,
`create-jira-issue`, and the `superpowers` plugin (`writing-plans`, `subagent-driven-development`,
`finishing-a-development-branch`) all being available — if `superpowers` isn't installed, say so and
stop rather than reimplementing any part of it.

## Modes

- **One item:** the user names a specific item (by number, or by describing it) — process just that one.
- **Whole backlog:** the user asks to work through the whole file — loop calling `todo next` and
  process each pending item in turn until it reports `no pending items`.

Both modes run the same per-item pipeline below. The only difference is what feeds the loop.

## Per-item pipeline

### 1. Get the item's text

`todo show <n>` (one-item mode) or `todo next` (backlog mode, which also gives you `<n>`). This is
the raw input for the next step — don't rephrase or summarize it yourself first.

### 2. File the Jira issue

Invoke the `create-jira-issue` skill with the item's text as input. It asks its own
confirm-before-create question and does its own duplicate check — don't second-guess or
pre-answer either on its behalf, even in backlog mode; each issue is an independent decision.
Take its reported issue key, URL, and the description it drafted.

### 3. Save the issue as a spec

`writing-plans` (next step) argues its plan from a spec file. Write one to
`docs/superpowers/specs/<ISSUE-KEY>.md` containing the issue's title, its URL, and the full drafted
description from step 2 — this is what carries the Jira link all the way through the plan into
every task an implementer sees, so don't skip or shorten it.

### 4. Write the plan

Invoke `superpowers:writing-plans`, pointing it at the spec file from step 3. It saves a plan to
`docs/superpowers/plans/` and asks which execution approach to use.

**Before answering that**, show the user the plan (or a tight summary — files touched, task list,
and anything you'd flag) and ask if it needs changes. This step is not optional and not something
to fold into a "run everything hands-off" preference: confirming the plan's content, not just which
executor runs it, was the whole reason this skill exists over just running subagent-driven-development
directly on an ad hoc plan. Apply any requested changes before moving on.

Once confirmed, answer the execution-approach question with **Subagent-Driven** — this pipeline
always uses `superpowers:subagent-driven-development`, never inline execution.

### 5. Execute

Invoke `superpowers:subagent-driven-development` on the confirmed plan. Let it run to completion
per its own rules (continuous execution, its own model selection, its own review loop) — this
skill doesn't intervene in how it implements or reviews. It ends by directing you to
`superpowers:finishing-a-development-branch`.

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

In backlog mode, go back to step 1 (`todo next`) until there's nothing left.
