---
name: jira
description: "Create a Jira issue in the current project's board from any input — a TODO.md line, a bug report, a Slack message, a vague one-liner. Reads the target board/site/issue-type/labels from a '## Jira' section in this repo's README.md, researches the actual codebase for relevant files and functions to ground the description in fact rather than restating the input, checks for likely duplicates before creating, and reports back the created issue's key and URL. Use this whenever the user asks to file/create/open a Jira issue or ticket for something, not only when working through a TODO.md — it accepts anything describing a piece of work."
argument-hint: "<description of the work to file as a Jira issue>"
---

# jira

Turns a description of work into a Jira issue grounded in the actual code, not just a restatement
of the input. Works standalone (any input) or as a step another skill hands a TODO.md line to.

## 1. Establish the autonomy level, once, at the start

There are three levels. Pick the one that applies before doing anything else:

- **confirm** — draft the issue, show it, create only after the user says yes.
- **auto** — create straight away without showing the draft first.
- **unattended** — like `auto`, plus: this run has no human watching it, so **every question this
  skill would otherwise ask is forbidden**. Wherever a later step says "ask the user", return the
  named failure status instead and stop. Only a calling skill sets this level.

If a calling skill passed a level explicitly (`zibby:todo-driven-development`'s unattended mode does),
use it and don't ask. Otherwise ask the user whether they want `confirm` or `auto`: creating a Jira
issue is visible to the whole team and not something to spam, but re-confirming every time inside
an already-reviewed flow is friction, not safety. Don't assume either way; ask.

**Failure statuses (unattended only).** Each is a plain, final line back to the caller — never a
question, never a guess:

- `NO_CONFIG: <what is missing>` — the board configuration can't be resolved (step 2).
- `DUPLICATE: <existing key> <existing url>` — a likely duplicate already exists (step 5).
- `JIRA_UNAVAILABLE: <the error>` — an Atlassian call failed on auth, network, or permissions.

Nothing gets created on any of these.

## 2. Find the board configuration

Read this repo's `README.md` for a `## Jira` section with `Key: value` lines, e.g.:

```markdown
## Jira

Board: CZ3TDR1
Site: teamdotblue.atlassian.net
IssueType: Úkol
Labels: shoptet-addon-cli
```

- `Board` (required) — the Jira project key.
- `Site` (required) — the Atlassian cloud site hostname; pass it directly as `cloudId` to the
  Atlassian MCP tools (per their own instructions, the hostname works as a `cloudId` argument
  directly for most calls — fall back to `getAccessibleAtlassianResources` and match by URL only
  if a call rejects it).
- `IssueType` (optional) — the exact issue type name to pass as `issueTypeName`. This is
  instance-specific and often localized (e.g. "Úkol", not "Task") — never assume "Task" works.
- `Labels` (optional) — comma-separated labels always applied to issues this skill creates.

If the section, or `Board`/`Site` within it, is missing: tell the user this project has no Jira
config yet, ask them for the missing values now so this run can proceed, and mention they can add
a `## Jira` section to `README.md` (offer to write it for them) so future runs don't need to ask.

If `IssueType` is missing, call `getJiraProjectIssueTypesMetadata` for the project, show the
available issue type names, ask the user which one to use, and mention they can add `IssueType` to
the README config to skip this question next time.

**Unattended:** neither question may be asked. A missing `Board` or `Site` ends the run with
`NO_CONFIG: <what is missing>`. A missing `IssueType` does too — guessing an issue type name on a
localized instance is how a whole night's run fails identically eleven times.

## 3. Resolve the assignee

Call `atlassianUserInfo` and use its `account_id` as `assignee_account_id` — this always assigns
whoever is actually running the skill, not a hardcoded person.

## 4. Research the codebase before drafting

The input describes a problem or task, not the issue's content — actually go look. Use
Read/Grep/Glob to find the files, functions, or config genuinely relevant to what's being asked,
the way you would before making the change yourself. A good description cites concrete
`path/to/file.ts:42`-style references and states what's actually true about the code today, not a
paraphrase of the input. Scale the depth of research to how vague the input is: a precise TODO line
naming a function needs little; "the search page feels slow" needs enough digging to point at an
actual candidate cause.

Write the description as Markdown (the default `contentFormat`) with short sections as needed —
typically a why, a what, and any file references — rather than one undifferentiated paragraph.

## 5. Check for a likely duplicate before creating

Draft a title (a concise, imperative one-liner — the same bar as a good commit subject) and pull
2-4 distinctive keywords from it. Run `searchJiraIssuesUsingJql` scoped to `project = <Board>` with
those keywords against the summary. If an open (non-Done-category) issue looks like a strong match,
stop and ask the user how to proceed — create anyway, reuse the existing issue, or refine the input
— rather than silently filing a duplicate. This matters most when this skill is invoked repeatedly
over the same source item (e.g. a retried `zibby:todo-driven-development` run after a failure).

**Unattended:** a strong match ends the run with `DUPLICATE: <key> <url>` and creates nothing. Do
not resolve the ambiguity yourself in either direction — filing a duplicate spams a board the whole
team reads, and silently reusing an issue whose scope only looks similar attaches a night's work to
the wrong ticket. Both are worse than handing the decision back in the morning report.

## 6. Confirm (only at autonomy level `confirm`)

Show the drafted title, description, issue type, labels, and assignee. Apply any edits the user
asks for. Skip this step entirely at `auto` and `unattended`.

## 7. Create the issue

Call `createJiraIssue` with `cloudId` (the `Site` value), `projectKey` (`Board`), `issueTypeName`,
`summary` (the drafted title), `description`, `assignee_account_id`, and
`additional_fields: {"labels": [...]}` for the README's `Labels` plus any the user asked to add.

## 8. Report the result

State the created (or reused) issue's key and `webUrl` plainly, e.g.
`Created CZ3TDR1-583: https://teamdotblue.atlassian.net/browse/CZ3TDR1-583` — a caller like
`zibby:todo-driven-development` needs exactly this to link the item back with `todo done <n> <url>` and,
later, in a PR description.
