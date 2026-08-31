# zibby-skills as a Claude Code marketplace

**Date:** 2026-08-31
**Status:** approved (approach), pending review (detail)

## Problem

The skills in this repo depend on third-party skills — `todo-driven-development` needs the
`superpowers` plugin plus the sibling `todo` and `create-jira-issue` skills. Today the only way
to get them onto a new machine is to clone the repo and hand-symlink each directory into
`~/.claude/skills/`, which installs nothing they depend on and gives no way to choose scope.

We want: pick which skills to install, choose global (user) or project-local scope, and have
each skill's dependencies come along automatically.

## Decision: use the native plugin system, do not build a package manager

Claude Code already implements all three requirements. Verified empirically on CLI 2.1.251:

```
$ claude plugin install dep-probe@deptest-mp --scope project -y
✔ Successfully installed plugin: dep-probe@deptest-mp (scope: project)
  (+ 2 dependencies: dep-child, explanatory-output-style)

$ claude plugin uninstall dep-probe@deptest-mp --scope project --prune -y
✔ Successfully uninstalled plugin: dep-probe (scope: project)
  Removed 2 auto-installed plugins: dep-child, explanatory-output-style
```

Both an intra-marketplace dependency and a cross-marketplace one (`name@marketplace`) resolved
and auto-installed, at the requested scope, and `--prune` removed exactly the auto-installed
ones. `--scope project` wrote `enabledPlugins` into the project's `.claude/settings.json`.

So the deliverable is a **marketplace manifest plus a thin bootstrap script**, not an installer
that reimplements selection, scoping, or dependency resolution.

## Target repo layout

```
.claude-plugin/marketplace.json
plugins/
  todo/
    .claude-plugin/plugin.json
    skills/todo/SKILL.md
    skills/todo/scripts/todo.py
  create-jira-issue/
    .claude-plugin/plugin.json
    skills/create-jira-issue/SKILL.md
  todo-driven-development/
    .claude-plugin/plugin.json
    skills/todo-driven-development/SKILL.md
install.sh
README.md
```

One plugin per skill — that is what makes per-skill selection possible. Layout mirrors the
existing `shoptet-skills` marketplace at `/Users/zibar/Workspace/skills`, which is a working
example of the same pattern.

All moves use `git mv` so history follows the files. Two SKILL.md files have uncommitted edits
at the time of writing; `git mv` preserves them, they will show as rename+modify.

## Manifests

`.claude-plugin/marketplace.json`:

```json
{
  "name": "zibby-skills",
  "owner": { "name": "Karel Zíbar", "email": "karel.zibar@team.blue" },
  "metadata": { "description": "Personal Claude Code skills: TODO backlog, Jira issue creation, and the TODO-to-PR pipeline.", "version": "0.1.0" },
  "allowCrossMarketplaceDependenciesOn": ["claude-plugins-official"],
  "plugins": [
    { "name": "todo", "source": "./plugins/todo", "category": "productivity" },
    { "name": "create-jira-issue", "source": "./plugins/create-jira-issue", "category": "productivity" },
    { "name": "todo-driven-development", "source": "./plugins/todo-driven-development", "category": "productivity" }
  ]
}
```

`allowCrossMarketplaceDependenciesOn` is **required**, not decorative: without it the dependency
on `superpowers@claude-plugins-official` is blocked at install time.

Dependency edges, declared in each `plugin.json`:

| Plugin | `dependencies` |
|---|---|
| `todo` | — |
| `create-jira-issue` | — |
| `todo-driven-development` | `["todo", "create-jira-issue", "superpowers@claude-plugins-official"]` |

`create-jira-issue` deliberately does not depend on `todo`: it is documented as accepting any
input, not only TODO.md lines, so it stands alone.

## install.sh

A bootstrap, not a package manager. Sequence:

1. **Doctor** — check and *report* what the plugin system cannot install: `claude` CLI present
   and >= 2.1, `python3`, `gh`, and whether the Atlassian MCP server is reachable (needed by
   `create-jira-issue`). Report only; never attempt to install or authenticate these.
2. **Legacy symlink check** — detect `~/.claude/skills/{todo,create-jira-issue,todo-driven-development}`
   symlinks pointing into this repo. These conflict with the plugin install (the same skill would
   register twice, once as `@skills-dir` and once as `@zibby-skills`). Offer to remove them;
   refuse to proceed with a conflicting install if declined.
3. **Register the marketplace** — `claude plugin marketplace add <repo path or github ref>`,
   idempotent.
4. **Pick skills and scope** — a `select` menu over the three plugins plus an "all" option, then
   user vs project scope. Non-interactive flags for scripted use: `--all`, `--scope`, `--yes`.
5. **Install** — one `claude plugin install <name>@zibby-skills --scope <scope> -y` per pick.
   Dependencies resolve themselves; the script does not enumerate them.
6. **Report** — print what was installed, what the doctor flagged, and that a restart is needed
   for the new plugins to load.

Out of scope: installing `gh`/`python3`, authenticating Jira, writing the per-repo `## Jira`
README section. These are reported by the doctor and left to the user.

## Migration on this machine

After the restructure lands, the current symlinks in `~/.claude/skills/` point at directories
that no longer exist. The migration is part of this work, not a follow-up:

1. `git mv` the skills into `plugins/<name>/skills/<name>/`.
2. Remove the three symlinks from `~/.claude/skills/`.
3. Run `./install.sh` and install all three at user scope.
4. Restart the session and confirm the skills are invocable under their plugin namespace.

## Open detail for review

Plugin skills are addressed as `plugin:skill`. With plugin name equal to skill name, invocation
likely becomes `todo:todo`, `create-jira-issue:create-jira-issue`. Options:

- **(a) Keep names identical** — marketplace listing stays clean, invocation stutters.
- **(b) Prefix the plugins** (`zibby-todo`, `zibby-jira`, `zibby-tdd`) — invocation reads better
  (`zibby-todo:todo`), marketplace entries are less obvious.

Recommendation: **(a)**, and confirm the actual invocation name after the first install rather
than guessing. If it turns out ugly in practice, renaming a plugin is a one-line manifest change.
