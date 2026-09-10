---
name: jira
description: "Create a Jira issue in the current project's board from any input — a TODO.md line, a bug report, a Slack message, a vague one-liner. Reads the target board/site/issue-types/labels from a 'jira:' key in this repo's `.zibby/zibby-skills/config.yml`, researches the actual codebase for relevant files and functions to ground the description in fact rather than restating the input, checks for likely duplicates before creating, and reports back the created issue's key and URL. Use this whenever the user asks to file/create/open a Jira issue or ticket for something, not only when working through a TODO.md — it accepts anything describing a piece of work."
argument-hint: "<description of the work to file as a Jira issue> [parent: <ISSUE-KEY>] [sprint: current|none]"
---

# jira

Turns a description of work into a Jira issue grounded in the actual code, not just a restatement
of the input. Works standalone (any input) or as a step another skill hands a TODO.md line to.

## 1. Establish the autonomy level, once, at the start

There are two levels. Pick the one that applies before doing anything else:

- **confirm** — draft the issue, show it, create only after the user says yes.
- **auto** — create straight away without showing the draft first. This run has no human watching
  it, so **every question this skill would otherwise ask is forbidden**. Wherever a later step says
  "ask the user", return the named failure status instead and stop. Only a calling skill sets this
  level.

If a calling skill passed a level explicitly (`zibby:todo-driven-development` always does, in every
one of its modes), use it and don't ask. Otherwise ask the user whether they want `confirm` or `auto`: creating a Jira
issue is visible to the whole team and not something to spam, but re-confirming every time inside
an already-reviewed flow is friction, not safety. Don't assume either way; ask.

**Failure statuses (auto only).** Each is a plain, final line back to the caller — never a
question, never a guess:

- `NO_CONFIG: <what is missing>` — the board configuration can't be resolved (step 2).
- `DUPLICATE: <existing key> <existing url>` — a likely duplicate already exists (step 5).
- `PARENT_MISMATCH: <details>` — a named parent can't legally hold this issue (step 4c).
- `JIRA_UNAVAILABLE: <the error>` — an Atlassian call failed on auth, network, or permissions.

Nothing gets created on any of these.

## 2. Find the board configuration

Read this repo's `.zibby/zibby-skills/config.yml` for a `jira:` key, e.g.:

```yaml
jira:
  board: CZ3TDR1
  site: teamdotblue.atlassian.net
  issueTypes:
    task: Task
    bug: Bug
    parent: Epic
  team: CZ3-DEVREL
  sprint: none
  labels:
    - shoptet-addon-cli
```

- `board` (required) — the Jira project key.
- `site` (required) — the Atlassian cloud site hostname; pass it directly as `cloudId` to the
  Atlassian MCP tools (per their own instructions, the hostname works as a `cloudId` argument
  directly for most calls — fall back to `getAccessibleAtlassianResources` and match by URL only
  if a call rejects it).
- `issueTypes` (optional) — the exact issue type names for this instance, keyed by role:
  `task`, `bug`, and `parent` (the epic-level type a `parent:` issue is created as, used only by
  `zibby:plan-to-backlog`). These names are instance-specific and sometimes localized — one
  project's `Task` is another's `Úkol` — so never assume an English name works.
- `issueType` (optional, superseded) — the older single-type form. When `issueTypes` is absent,
  this value is used as the `task` type and there is no `bug` or `parent` type. Configs written
  before `issueTypes` existed keep working unchanged; don't rewrite them unless the user asks.
- `team` (optional) — the Jira Team (e.g. `CZ3-DEVREL`) assigned to every issue this skill creates.
  Resolved to the field's actual id at create time — see step 7.
- `sprint` (optional, default `none`) — whether issues this skill creates land in the board's
  current sprint. `current` assigns it, `none` leaves the issue in the backlog. It defaults to
  `none` deliberately: filing an issue is not the same as starting it, and a default of `current`
  would drop a whole `zibby:plan-to-backlog` epic into the active sprint at once. A `sprint:`
  argument on the invocation (a caller's, or the user's) overrides the config for that one issue —
  `zibby:todo-driven-development` passes `sprint: none` here and assigns the sprint later, when it
  actually starts implementing.
- `labels` (optional) — a YAML list of labels always applied to issues this skill creates.

If the file or the `jira:` key is missing entirely: tell the user this project has no Jira config
yet and ask whether they want to create one now.

- **Yes** — walk through each item this skill can read from the config, one at a time: `board`,
  `site`, the `issueTypes` names for `task`, `bug` and `parent` (call
  `getJiraProjectIssueTypesMetadata` first and show the available names rather than asking blind),
  `team`, and `labels`, noting which are required (`board`, `site`) and which are optional. Write the answers to `.zibby/zibby-skills/config.yml` under a `jira:` key
  (creating the `.zibby/zibby-skills/` directories first if they don't exist) so future runs don't
  need to ask.
- **No** — ask for `board` and `site` for this run only and proceed without writing a file.

If the config exists but is missing `board` or `site`, ask for the missing values now so this run
can proceed, and offer to add them to the existing config file rather than starting the create flow
above. If neither `issueTypes.task` nor `issueType` resolves, call `getJiraProjectIssueTypesMetadata`
for the project, show the available issue type names, ask the user which one to use, and mention
they can add `issueTypes` to the config file to skip this question next time. A missing
`issueTypes.bug` is not a question: fall back to the task type and say so in the report — a bug
filed as a task is a two-click fix, an invented type name is a failed call.

**Auto:** neither question may be asked. A missing `board` or `site` ends the run with
`NO_CONFIG: <what is missing>`. So does a project with no resolvable task type (`issueTypes.task`
nor `issueType`) — guessing an issue type name on a localized instance is how a whole night's run
fails identically eleven times.

## 3. Resolve the assignee

Call `atlassianUserInfo` and use its `account_id` as `assignee_account_id` — this always assigns
whoever is actually running the skill, not a hardcoded person.

## 4. Research the codebase before drafting

**If the caller handed over research already** — `zibby:plan-to-backlog` does, once per plan
rather than once per chunk — do not dispatch a full pass over the same code again. Read what it
gave you, and dispatch at most one *narrow* top-up for what this specific chunk needs and the
shared pass didn't cover. Twelve chunks from one plan re-researching the same three directories is
how filing a backlog costs more than implementing it. Say in the report that the research was
supplied rather than gathered here.

Otherwise the input describes a problem or task, not the issue's content — actually go look, but don't do the
digging inline: dispatch it to a subagent with an explicit `model: "sonnet"` override, regardless of
whatever model this session is otherwise running. Retrieval like this doesn't need the caller's own
(possibly far more expensive) model, and letting it inherit that model here is how filing a handful
of issues burns tokens out of proportion to the task.

Give the subagent the raw input text and ask it to use Read/Grep/Glob to find the files, functions,
or config genuinely relevant to what's being asked, the way you would before making the change
yourself, and to report back concrete `path/to/file.ts:42` references plus what's actually true
about the code today — never a paraphrase of the input. Scale the number and breadth of dispatches
to how vague the input is: a precise TODO line naming a function needs one narrow dispatch; "the
search page feels slow" needs a broader one (or a few in parallel over distinct candidate areas)
that digs until it can point at an actual candidate cause. Compose the description yourself from
what comes back — don't ask the subagent to draft the issue text.

Write the description as Markdown (`contentFormat: "markdown"`) with short sections as needed —
typically a why, a what, and any file references — rather than one undifferentiated paragraph.
Markdown is fine for prose, but if the body ever needs tickable acceptance criteria, a plain
`- [ ]` line does **not** render as a checkbox on Jira — it comes back as escaped `* \[ \]` text.
Real checkboxes need the description sent as an ADF document (`contentFormat: "adf"`) with the
criteria as a `taskList` of `taskItem` nodes (`state: "TODO"`). Stick to plain markdown sections
unless a caller actually asks for acceptance-criteria checkboxes.

## 4b. Decide the issue type from what the research found

Pick `bug` or `task` (the config names from step 2) on one question: does this describe **existing
code behaving wrongly**, or **work that doesn't exist yet**? Decide it from the research in step 4,
not from the input's tone — "the search page feels slow" is a bug if the research found a
regression and a task if it found a feature that was never built for that load.

A caller may pass a **proposed** type (`zibby:plan-to-backlog` does, so its decomposition
checkpoint can show one). The proposal is not binding: it comes from someone who read the plan,
while you read the code. Override it when the research says otherwise, and **report that you did**,
with the reason — a type silently flipped is a type nobody notices until the board is sorted by it.

If the config has no `bug` type, use the task type and note it. Never invent a type name, and never
use a subtask type here: `zibby:plan-to-backlog` handles hierarchy through `parent`.

## 4c. Resolve the parent, if one was given

A `parent:` argument (a caller's, or the user's) names an issue this one hangs under. Never guess
one, and never create one here — that is `zibby:plan-to-backlog`'s job.

Fetch the named issue with `getJiraIssue` and check its type's `hierarchyLevel` sits **above** the
level of the type chosen in step 4b. `getJiraIssueTypeMetaWithFields` returns no `allowedValues`
for the `parent` field on this kind of instance, so the check is yours to make — Jira enforces it
server-side and rejects the create, which auto reads as an unexplained failure.

- Level above (e.g. `Epic` over `Task`) — pass it.
- Same level or below (e.g. a `Task` named as the parent of a `Task`) — stop. Interactive: tell the
  user the two real options (create an epic above it, or file these as subtasks of it) and let them
  choose; never switch to a subtask type yourself, since subtasks behave differently in boards,
  sprints and reports and a silently chosen hierarchy gets rearranged by hand later. Auto:
  return `PARENT_MISMATCH: <key> is <type> (level <n>), not above <child type>` and create nothing.
- Not fetchable at all — `JIRA_UNAVAILABLE: <the error>`.

## 5. Check for a likely duplicate before creating

Draft a title (a concise, imperative one-liner — the same bar as a good commit subject) and pull
2-4 distinctive keywords from it. Run `searchJiraIssuesUsingJql` scoped to `project = <Board>` with
those keywords against the summary. If an open (non-Done-category) issue looks like a strong match,
stop and ask the user how to proceed — create anyway, reuse the existing issue, or refine the input
— rather than silently filing a duplicate. This matters most when this skill is invoked repeatedly
over the same source item (e.g. a retried `zibby:todo-driven-development` run after a failure).

**Auto:** a strong match ends the run with `DUPLICATE: <key> <url>` and creates nothing. Do
not resolve the ambiguity yourself in either direction — filing a duplicate spams a board the whole
team reads, and silently reusing an issue whose scope only looks similar attaches a night's work to
the wrong ticket. Both are worse than handing the decision back in the morning report.

## 6. Confirm (only at autonomy level `confirm`)

Show the drafted title, description, issue type (and, if you overrode a proposed one, why),
parent, labels, team, sprint, and assignee. Apply any edits the
user asks for. Skip this step entirely at `auto`.

## 7. Create the issue

If the config has a `team`, resolve it to the field's actual id first: call
`getJiraIssueTypeMetaWithFields` for the project and issue type, find the field named "Team" (its
field id is instance-specific — never assume a fixed `customfield_NNNNN` number), and match
`team`'s configured value against that field's allowed values by name to get the id to send. If the
field isn't on this issue type, or `team`'s value isn't among its allowed values, don't guess or
create the field's value from the string: tell the user (interactive) or note it and proceed without
`team` (auto) — a team-less issue is a one-click morning fix, and guessing an id risks
assigning the issue to the wrong team silently.

If this issue is to land in the current sprint — a `sprint: current` argument, or `sprint: current`
in the config with no argument overriding it — resolve the Sprint field id and the current sprint's
id now, following `references/sprint.md` (steps 1 and 2), and add the field to
`additional_fields` below. The `getJiraIssueTypeMetaWithFields` call above already returns every
field on this issue type, Sprint included — read it out of that same response rather than calling
the metadata endpoint a second time. That procedure is best-effort by design: an unresolvable field or an
ambiguous "current" is noted in the report and the issue is created without a sprint, never a
guessed one and never a failed create. With `sprint: none` (the default), skip this entirely.

Call `createJiraIssue` with `cloudId` (the `site` value), `projectKey` (`board`), `issueTypeName`
(the type from step 4b), `summary` (the drafted title), `description`, `assignee_account_id`, and
`additional_fields` built from the config's `labels` plus any the user asked to add, the resolved
`team` field/id if one was found, the resolved sprint field/id if one was found, and — if step 4c
resolved a parent — `parent: {"key": "<PARENT-KEY>"}`. `parent` is the system field (`{"type": "issuelink", "system": "parent"}`); there
is no separate "Epic Link" custom field to set on a modern Jira Cloud project, so don't look for
one.

## 8. Move the issue out of its default creation status

A freshly created issue lands in whatever status its workflow uses as the initial one — on this
board, that is **Request**. Issues this skill files are ready to be picked up, not just requests
waiting for triage, so move it to **TODO** right after creation: call `getTransitionsForJiraIssue`
for the new issue's key, find the transition whose target status is named `To Do` (Jira's internal
name for the TODO column — match case-insensitively and allow for the `To Do`/`TODO` spelling), and
call `transitionJiraIssue` with that transition's id. If no such transition exists from the
issue's current status (workflow doesn't allow it directly, or the status is already something
else), note that in the report below rather than guessing another transition or leaving the issue
silently stuck in Request.

## 9. Report the result

State the created (or reused) issue's key, its type, its parent if it has one, its sprint if one
was assigned (by name, and say so plainly if `sprint: current` was asked for but couldn't be
resolved), its resulting status (`TODO`, or the status it was left in if step 8 couldn't move it),
and its `webUrl` plainly, e.g.
`Created CZ3TDR1-583: https://teamdotblue.atlassian.net/browse/CZ3TDR1-583` — a caller like
`zibby:todo-driven-development` needs exactly this to link the item back with `todo done <n> <url>` and,
later, in a PR description.

## Notes

- There is no delete tool in this MCP. A mistakenly created issue can only be transitioned to a
  terminal status (Done/Cancelled), not hard-deleted; deletion is manual in the Jira UI. Tell the
  user this if they ask to undo a create.
- Jira labels cannot contain spaces. Fine for `agentic` and the configured `labels`, but don't
  invent a multi-word label.
