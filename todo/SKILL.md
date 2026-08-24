---
name: todo
description: "Manage a project's TODO.md checklist — add an item, list items, mark one done or undone, or find the next pending one. Use this whenever the user wants to track personal backlog items for the current project, whether they type an explicit /todo command or just say something like 'add this to my todo list', 'what's on my todo', 'what should I work on next', or 'mark item 3 as done' — they don't need to say 'TODO.md' or name the file explicitly. This is a personal, cross-project tool — it always operates on the TODO.md at the root of whatever git repo the user is currently in, creating the file the first time it's needed."
---

# todo

A thin wrapper around `scripts/todo.py`, which is the actual source of truth for reading and
writing `TODO.md`. Always shell out to it — don't hand-edit the checklist yourself. The script
finds the file at the root of the current git repo (`git rev-parse --show-toplevel`, falling back
to the current directory outside a repo), creates it on first write, and keeps a stable,
line-order numbering scheme so `list`/`next`/`show`/`done`/`undone` all agree on what "item 3"
means.

```bash
python3 <path-to-this-skill>/scripts/todo.py <command> [args]
```

## Commands

| Command | Effect |
|---|---|
| `add "<text>"` | Appends `- [ ] <text>` to TODO.md, creating the file (with a `# TODO` header) if it doesn't exist yet. |
| `list` | Prints every item, numbered 1..N in file order — **both done and pending** count toward the numbering, so a number always points at the same line regardless of what else has been checked off. |
| `next` | Prints the number and text of the first unchecked item, or `no pending items`. Use this to drive "work through the whole list" flows without the caller tracking state itself. |
| `show <n>` | Prints just the text of item `n`. |
| `done <n> [ref]` | Checks off item `n`. If `ref` is a URL, it's appended as a markdown link labeled with the URL's last path segment (e.g. a Jira `.../browse/CZ3TDR1-582` link renders as `([CZ3TDR1-582](...))`); a non-URL `ref` is appended in plain parentheses. Omit `ref` for a plain checkbox flip. |
| `undone <n>` | Reverts item `n` to unchecked, e.g. to correct a mistaken `done`. |

## Using it from natural language

Translate the user's request into one line of item text before calling `add` — the same way you'd
write a good commit subject: concise, imperative, specific enough to stand alone months later.
"the search page is kinda slow when there are a lot of results, we should look into that" becomes
`add "Investigate slow search page with large result sets"`, not a verbatim copy of what they said.

For "what should I do next" or "pick something to work on", call `next` (or `list` if they want to
choose rather than take the top of the list) rather than guessing from conversation context — the
file is the source of truth for what's pending.

## Notes

- Item numbers are positional, not stable IDs — they can shift if lines are ever added/removed
  above an item other than through this script. Always re-run `list` (or trust the number a
  command you just ran reported) rather than reusing a number from earlier in a long conversation.
- This skill only touches `TODO.md`'s checklist lines (`- [ ]` / `- [x]`, or `*` bullets). Anything
  else in the file — headings, prose, other lists — is left untouched.
- `done`'s `ref` argument is meant for exactly one thing: recording what closed the item (a Jira
  issue, a PR) without turning TODO.md into a project tracker of its own. Keep it to one link.
