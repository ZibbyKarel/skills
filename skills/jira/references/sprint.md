# Assigning the current sprint

The procedure both `zibby:jira` (at create time) and `zibby:todo-driven-development` (on an issue
that already exists) use to put an issue into the board's **current** sprint. It is one procedure in
one file because the two callers must agree on what "current" means and on what happens when it
can't be resolved — a sprint set one way here and another way there is how half a board's issues
end up in a sprint nobody selected.

## It is always best-effort

Every failure mode below ends the same way: **note what happened and carry on**. A missing or wrong
sprint is a drag-and-drop fix that takes one second on the board; an issue assigned to the wrong
sprint, or a run stopped because a custom field wasn't where it was expected, both cost more. So:

- Never guess a `customfield_NNNNN` number, a sprint id, or which of several sprints is meant.
- Never fail an item, stop a run, or withhold a created issue over a sprint that didn't get set.
- Never add a sprint-specific failure status to a caller's auto list — those stop items, and
  this doesn't warrant it. Report it in the run's normal channel (a ledger row in auto, a
  mention to the user otherwise) and move on.

## 1. Resolve the Sprint field's id

Sprint is a custom field whose id differs per Jira instance. Resolve it exactly the way step 7 of
`zibby:jira` resolves the Team field: call `getJiraIssueTypeMetaWithFields` for the project and the
issue type in question, and find the field **named "Sprint"** (allow for a localized name on a
localized instance). Take its field id from the metadata.

If the field isn't on this issue type — it is absent from Scrum-less projects and from some issue
types on Scrum boards — there is no sprint to set. Note it and stop here.

## 2. Resolve the current sprint's id

There is no agile/board tool in the Atlassian MCP server — no sprint listing, no board endpoints —
so the sprint's id comes from one of two places. Try them in this order:

1. **The field's allowed values.** If the Sprint field in the step 1 metadata carries
   `allowedValues`, look for the single entry whose `state` is `active`. One active entry: that's
   the current sprint, take its `id`. Zero, or more than one, means the answer isn't in the
   metadata — fall through to the JQL route rather than picking one.
2. **An issue already in the open sprint.** Run `searchJiraIssuesUsingJql` with
   `project = <board> AND sprint in openSprints() ORDER BY updated DESC`, asking for the Sprint
   field in the returned fields, and read the sprint value off the first issue that has exactly one
   open sprint on it. Its `id` and `name` are the current sprint's.

If neither route yields exactly one sprint, the current sprint isn't resolvable here. Three cases
reach this point, and the common one is not the exotic one:

- **An active sprint with nothing in it yet.** Route 2 finds an open sprint only through an issue
  already in it, so the *first* issue of a freshly started sprint finds nothing — which happens
  once per sprint, every sprint, on a healthy board, not just on a new project. When route 1's
  metadata doesn't carry `allowedValues` either, this issue simply doesn't get the sprint and a
  human drags it in; the next one this run touches resolves fine.
- A board with no active sprint at all, or a Kanban board with no sprints.
- Several open sprints at once (a multi-board project), where "current" is genuinely ambiguous. In all three, note which case it was and stop here; do not pick a sprint.

Record the resolved sprint's **name** alongside its id, so whatever the caller reports says
"assigned to Sprint 41", not an opaque number.

## 3. Apply it

Two paths, depending on whether the issue exists yet:

- **The issue is being created** (`zibby:jira` step 7) — add the resolved field id to the
  `additional_fields` already being built there, next to `labels`, `team` and `parent`.
- **The issue already exists** (`zibby:todo-driven-development` step 5, or any issue filed earlier
  by `zibby:plan-to-backlog`) — call `editJiraIssue` on its key with the same single field.

**Unverified:** the payload shape for the Sprint field is written here as the sprint's numeric id
(`{"<field-id>": <sprint-id>}`), which is what Jira Cloud's greenhopper sprint field takes on both
create and edit. Some instances accept — or require — an array of ids instead. If a call is
rejected on this field, retry once with the id wrapped in an array, and if that also fails treat it
as the best-effort miss described above rather than trying further shapes.
