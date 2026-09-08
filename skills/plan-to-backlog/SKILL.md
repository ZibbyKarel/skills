---
name: plan-to-backlog
description: "Turn a written implementation plan into a ready backlog — decompose it into deliverable chunks, file each as a Jira issue under one Epic, link the dependencies between them, and leave a short one-line summary per chunk in TODO.md while the full description lives in the issue. Use this when the user has a plan for a large phase somewhere (a file in the repo, a Confluence page, a Jira description, or pasted text) and wants it cut into smaller shippable pieces with issues created — 'rozsekej tenhle plán do issues', 'break this phase into tickets', 'prepare a backlog from this plan'. Also use it to extend an existing epic when the plan has grown: it compares against the epic's current children and only files what is missing. This is a conductor over zibby:jira and zibby:todo — it owns the decomposition, the parent, and the dependency graph, and nothing else."
argument-hint: "<plan file | plan URL | pasted plan> [--parent <ISSUE-KEY>] [--skip-jira]"
---

# plan-to-backlog

Takes a finished plan and leaves you with a backlog you can start working through: one Epic, one
issue per deliverable chunk, `Blocks` links carrying the order, and a TODO.md section whose lines
are short summaries pointing at those issues.

It owns three things — **the decomposition, the parent, and the dependency graph**. Everything else
belongs to a skill it calls: `zibby:jira` creates every issue (and decides each one's `Task`/`Bug`
type), `zibby:todo` writes every TODO.md line. Don't reimplement either. If `zibby:jira` or
`zibby:todo` isn't available, say so and stop.

## 1. Establish the autonomy level, once, at the start

- **confirm** — you see the proposed decomposition, and each issue's draft before it's created.
- **auto** — you still see the decomposition; individual issue drafts are not shown.
- **unattended** — nothing is shown and **no question may be asked**. Only a calling skill sets
  this level; wherever a step below says "ask", return the named failure status and stop.

If a caller passed a level, use it. Otherwise ask which of `confirm` or `auto` — never assume.

The decomposition checkpoint in step 6 is **not** part of what `auto` suppresses. It is the one
judgment no other skill in this chain can make, it is one decision for the whole batch rather than
a question per item, and filing ten badly cut issues is visible to everyone who reads the board.

**`--skip-jira`** is orthogonal to the level: it files no issues at all (step 8).

## 2. Failure statuses (unattended only)

- `NO_CONFIG: <what is missing>` — the Jira configuration can't be resolved.
- `NO_PLAN: <why>` — no plan could be read from the input (step 3).
- `PLAN_NOT_PERSISTENT: <path>` — the plan isn't committed or otherwise durably reachable (step 3).
- `AMBIGUOUS_DECOMPOSITION: <why>` — the plan can't be cut without a human decision (step 5), or
  the re-run comparison in step 7 is uncertain about a chunk.
- `PARENT_MISMATCH: <details>` — the given parent can't legally hold these issues (step 4).
- `DUPLICATE: <key> <url>` — passed straight through from `zibby:jira` for a single chunk.
- `JIRA_UNAVAILABLE: <the error>` — an Atlassian call failed on auth, network, or permissions.

Nothing is created on `NO_CONFIG`, `NO_PLAN`, `PLAN_NOT_PERSISTENT`, `AMBIGUOUS_DECOMPOSITION` or
`PARENT_MISMATCH`. The other two can occur mid-batch — see step 9.

## 3. Read the plan, and insist it be durable

The argument is one of four things; recognise them in this order:

1. **A path** that exists in the repo → read it.
2. **An Atlassian URL** → fetch it (`getConfluencePage` for a Confluence page, `getJiraIssue` for an
   issue) via the Atlassian MCP tools.
3. **Any other URL** → fetch it. If it can't be fetched, that's `NO_PLAN`.
4. **Anything else** → treat it as the plan text itself.

No argument at all: ask what the plan is. Never assemble one from earlier conversation — a plan you
inferred is a plan nobody approved.

**The plan's source must be persistently reachable before a single issue is created.** The Epic
will point at it, and an epic pointing at something that only ever existed in a chat window is an
epic nobody can act on in three months.

- A committed file → use `<path>@<short SHA>` (`git rev-parse --short HEAD`) as the reference.
- A URL → the URL is the reference.
- **Pasted text, or an uncommitted/untracked file** → write it to `docs/plans/<slug>.md` if it
  isn't a file yet, then **stop and ask the user to commit it**, and continue once they have. Don't
  commit on their behalf: a commit nobody asked for is a surprise in a repo, and a plan still being
  edited isn't ready to be cut up anyway.
- Unattended: any non-durable source is `PLAN_NOT_PERSISTENT: <path>` — a night run can't wait for
  a commit.

Also read the plan **completely** before proposing anything, including whatever it says about
phasing or ordering. If it already proposes its own slices, that proposal is evidence, not
instruction: it was written to explain the work, not to be reviewable in pieces.

## 4. Settle the parent

Every issue this skill files hangs under one parent — that's what makes the batch a phase rather
than twelve loose tickets.

**A `--parent <ISSUE-KEY>` was given:** it wins, always, and a second parent is never created.
Fetch it with `getJiraIssue` and check its type's `hierarchyLevel` is above the child level. On a
mismatch (e.g. a `Task` named as the parent of `Task`s), stop and offer the two real options —
create an Epic above it, or file these as subtasks of it — and let the user choose. Never switch to
a subtask type yourself: subtasks behave differently in boards, sprints and reports, and a silently
chosen hierarchy gets rearranged by hand later. Unattended: `PARENT_MISMATCH`.

**No parent was given:** propose one. Its title is the phase the plan describes; its description
is a short framing plus **the reference to the plan source from step 3** — never a copy of the
plan, which would be a second version of the same text, drifting from the first the moment either
is edited. Create it through `zibby:jira` with the `issueTypes.parent` type from the config (no
`parent` of its own), and it inherits the config's `labels` and `team` like any other issue. At
`confirm` this proposal is part of the step 6 checkpoint; at `auto` it's created once the
decomposition is confirmed.

If the config has no `issueTypes.parent`, ask which type to use (unattended: `NO_CONFIG`). Guessing
"Epic" on a localized instance is a coin flip.

## 5. Research the code once, for the whole plan

Dispatch **one** research pass — a subagent with an explicit `model: "sonnet"` override, whatever
model this session runs — over the plan as a whole: which files, functions and config the plan
actually touches, and what is true about that code today. Break it into a few parallel dispatches
by area if the plan is broad; the rule is per *plan*, not per chunk.

This result is then handed to every `zibby:jira` call in step 8, which knows to do at most a narrow
top-up instead of researching from scratch. Twelve chunks each re-reading the same three
directories costs more than implementing one of them.

## 6. Propose the decomposition — and stop

Read `references/chunking.md` before cutting anything and follow its procedure — it **is** the
granularity rule. There is deliberately no line or file-count cap in it, because neither predicts
whether a chunk is reviewable; chunks are cut on deliverables and their proofs. Every chunk you
propose must answer that file's five-question checklist, and the question that eliminates most bad
cuts is "what proves it works" — a chunk with no nameable proof is a step, not a deliverable.

Then present, in one message:

- the parent (existing key, or the proposed Epic's title and description),
- the chunks **grouped into waves** (wave 1 = nothing to wait for, wave 2 = depends only on wave 1,
  and so on) — for each: a **title** written to the standard of a good commit subject, a proposed
  type (`Task` or `Bug` — a proposal only; `zibby:jira` decides for real from the code, and reports
  when it overrides you), what proves the chunk works, and what it consumes from and produces for
  other chunks, named concretely rather than as "needs the earlier work",
- the `Blocks` graph, called out where it is a straight chain: one wave per chunk usually means the
  decomposition didn't look for parallelism, and chunks that could run at the same time are worth
  finding before twelve branches are cut off each other,
- anything you had to decide that the plan didn't say.

Wait for the user. Apply their edits and show the revised list if they change the shape of it.

If the plan can't be cut without a decision only the user can make — it describes two unrelated
phases, or its scope is too vague to name a deliverable — say that instead of guessing. Unattended:
`AMBIGUOUS_DECOMPOSITION: <why>`.

## 7. Before filing: compare against what already exists

A plan that grew is the normal case, and this step is also how a batch that died halfway gets
finished — there is no state file anywhere in this skill.

Query the parent's current children: `searchJiraIssuesUsingJql` with `parent = <PARENT-KEY>`.
Compare them against the confirmed chunks and report three groups:

- **will file** — no plausible match among the children,
- **will skip** — clearly already filed (name the existing key),
- **not sure** — a partial match.

Ask about the "not sure" group before filing any of them. Exact title matching would file a
duplicate after the smallest rewording; silent fuzzy matching swallows a chunk that merely
resembles one already there. Unattended: a non-empty "not sure" group is
`AMBIGUOUS_DECOMPOSITION: <chunk> may already exist as <key>` — file the unambiguous ones first,
then stop and report.

## 8. File the batch

Chunk by chunk, in dependency order: create the issue, then write its TODO.md line, then move to
the next. Never the other way round, and never in one big pass at the end — a batch interrupted
after eight chunks leaves eight issues that are each fully recorded in TODO.md, and step 7 picks up
the remaining four on the next run.

**The issue.** Invoke `zibby:jira` per chunk with: the chunk's text (including its proof and its
consumes/produces contract — the implementer reads the issue, not this conversation), the research
from step 5, the proposed type, the parent key, and `sprint: none` — a backlog is filed to be worked
through later, and a whole epic landing in the active sprint at once is nobody's intent;
`zibby:todo-driven-development` assigns the sprint per item, when it starts implementing that
item. Pass this run's autonomy level through (`confirm` for `confirm`,
`auto` for `auto`, `unattended` for `unattended`) so it doesn't ask per chunk what this run already
answered once. Its duplicate check is never pre-answered — let it ask, per its own rules.

**The TODO.md line.** Straight after the issue exists:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/todo/scripts/todo.py add "<issue title>" \
  --ref "<issue url>" --section "<parent title> ([<PARENT-KEY>](<parent url>))"
```

The line's text is **the issue's title verbatim** — not a second, friendlier phrasing of it, which
would just drift from Jira at the first rename. `--section` puts the whole batch under one heading;
`todo.py` matches that section by the parent key it contains, so a later run lands in the same
section even if the epic was renamed meanwhile.

**`--skip-jira`:** no issues, no epic, no links. Write each chunk's full description to
`docs/superpowers/specs/<slug>.md` and add the TODO line with `--ref` pointing at that file and
`--section "<phase title>"`. The description has to live somewhere or the one-line summary is all
that survives; `zibby:todo-driven-development` already reads specs from that directory.

**Handling what `zibby:jira` returns:** a `DUPLICATE` for one chunk skips that chunk and the batch
continues (report it). `NO_CONFIG` or a second consecutive `JIRA_UNAVAILABLE` stops the batch —
every remaining chunk would fail identically. Nothing already created is ever deleted or closed to
"clean up" a half-finished batch: issue keys don't come back, and step 7 makes the leftovers
harmless.

## 9. Link the dependencies — after the whole batch

Only now, when every key exists: for each dependency, `createIssueLink` with the type **name**
`"Blocks"` (this instance takes the name, not the id `10000`), `inwardIssue` = the blocking chunk,
`outwardIssue` = the blocked chunk. Doing this during step 8 would mean linking to issues that
don't exist yet.

> **Unverified:** that `inwardIssue`/`outwardIssue` assignment follows the tool's own
> documentation, and `getJiraIssue` reports links relative to the issue you fetched, which makes
> the docs easy to misread. **The first time this skill runs against a real board, create one link
> and read it back in the Jira UI to confirm the direction.** A reversed `blocks` looks entirely
> plausible and inverts the whole phase's order. Delete this note once someone has actually
> checked.

A link that fails is reported, never fatal — a missing link is a two-click fix; a missing issue is
not.

## 10. Report

- the parent: key, title, URL,
- a table of chunks: title, issue key + URL, type (and whether `zibby:jira` overrode the proposal),
  TODO.md item number,
- the `Blocks` links created, and any that failed,
- anything skipped, with why (already filed, duplicate, uncertain),
- and, if the batch stopped early, which condition stopped it and what's left.

Then say plainly what to do next: `zibby:todo-driven-development` picks these items up from TODO.md
and, because each line already carries its issue key, reuses the issue rather than filing a new one.
