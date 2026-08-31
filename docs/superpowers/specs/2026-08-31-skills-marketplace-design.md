# zibby-skills as a Claude Code marketplace

**Date:** 2026-08-31
**Status:** approved

## Problem

The skills in this repo depend on third-party skills — `todo-driven-development` needs the
`superpowers` plugin plus the sibling `todo` and Jira skills. Today the only way to get them onto
a new machine is to clone the repo and hand-symlink each directory into `~/.claude/skills/`,
which installs nothing they depend on and gives no way to choose scope.

We want: install the skills on a new machine, choose global (user) or project-local scope, and
have their third-party dependencies come along automatically.

## Decision: use the native plugin system, do not build a package manager

Claude Code already implements this. Verified empirically on CLI 2.1.251:

```
$ claude plugin install rootplug@roottest-mp --scope project -y
✔ Successfully installed plugin: rootplug@roottest-mp (scope: project)
  (+ 1 dependency: explanatory-output-style)

$ claude plugin details rootplug
  Skills (2)  alpha, beta

$ claude plugin uninstall rootplug@roottest-mp --scope project --prune -y
✔ Successfully uninstalled plugin: rootplug (scope: project)
  Removed 1 auto-installed plugin: explanatory-output-style
```

A cross-marketplace dependency (`name@marketplace`) resolved and auto-installed at the requested
scope, skills were discovered from `skills/` with no manifest listing, and `--prune` removed
exactly the auto-installed ones. `--scope project` wrote `enabledPlugins` into the project's
`.claude/settings.json`.

So the deliverable is a **marketplace manifest plus a thin bootstrap script**, not an installer
that reimplements scoping or dependency resolution.

## Decision: one plugin, `zibby`

These three skills are one way of working, not a menu — `todo-driven-development` already depends
on both others, so two of the three possible subsets were never separable. They install together
or not at all.

This also fixes naming. The skill namespace is `<plugin>:<skill>`, and identical plugin and skill
names do not collapse (this session's own skill list shows `frontend-design:frontend-design`
spelled out in full). A single plugin named `zibby` gives:

| Skill | Invocation |
|---|---|
| `todo` | `zibby:todo` |
| `jira` | `zibby:jira` |
| `todo-driven-development` | `zibby:todo-driven-development` |

`tdd` was rejected as a skill name: it reads as test-driven development, and
`superpowers:test-driven-development` is loaded in the same sessions.

`jira` is short because `zibby:create-jira-issue` is a mouthful; its description must carry the
"creates an issue" meaning, since the name alone reads as "do Jira things".

Extensibility is preserved: a genuinely standalone skill written later can become its own plugin
in the same marketplace without disturbing `zibby`.

## Target repo layout

Because the repo is exactly one plugin, the plugin lives at the repo root rather than under
`plugins/<name>/`. Verified working with `"source": "./"`.

```
.claude-plugin/marketplace.json
.claude-plugin/plugin.json
skills/
  todo/SKILL.md
  todo/scripts/todo.py
  jira/SKILL.md
  todo-driven-development/SKILL.md
install.sh
README.md
```

All moves use `git mv` so history follows the files. Two SKILL.md files have uncommitted edits at
the time of writing; `git mv` preserves them, they will show as rename+modify.

## Manifests

`.claude-plugin/marketplace.json`:

```json
{
  "name": "zibby-skills",
  "owner": { "name": "Karel Zíbar", "email": "karel.zibar@team.blue" },
  "metadata": { "description": "Personal Claude Code skills: TODO backlog, Jira issue creation, and the TODO-to-PR pipeline.", "version": "0.1.0" },
  "allowCrossMarketplaceDependenciesOn": ["claude-plugins-official"],
  "plugins": [
    { "name": "zibby", "source": "./", "description": "How Karel works: TODO backlog, Jira issue creation, and the TODO-to-PR pipeline.", "category": "productivity" }
  ]
}
```

`.claude-plugin/plugin.json`:

```json
{
  "name": "zibby",
  "version": "0.1.0",
  "description": "How Karel works: TODO backlog, Jira issue creation, and the TODO-to-PR pipeline.",
  "author": { "name": "Karel Zíbar", "email": "karel.zibar@team.blue" },
  "dependencies": ["superpowers@claude-plugins-official"]
}
```

`allowCrossMarketplaceDependenciesOn` is **required**, not decorative: without it the dependency
on `superpowers@claude-plugins-official` is blocked at install time.

`todo` and `jira` are no longer dependency edges — they are skills inside the same plugin.

## Content edits the rename forces

1. `create-jira-issue/SKILL.md` → `skills/jira/SKILL.md`, `name: jira`, description reworded to
   lead with "Create a Jira issue…" so discovery does not rely on the bare noun.
2. `todo-driven-development/SKILL.md` refers to its siblings by name in prose and in its
   frontmatter description. Every reference to `todo` and `create-jira-issue` becomes `zibby:todo`
   and `zibby:jira`. Its `superpowers` references already use the correct `superpowers:` form.
3. `todo/SKILL.md` invokes `<path-to-this-skill>/scripts/todo.py`. Inside a plugin this becomes
   `${CLAUDE_PLUGIN_ROOT}/skills/todo/scripts/todo.py`.

## install.sh

A bootstrap, not a package manager. Sequence:

1. **Doctor** — check and *report* what the plugin system cannot install: `claude` CLI present
   and >= 2.1, `python3`, `gh`, and whether the Atlassian MCP server is configured (needed by
   `zibby:jira`). Report only; never attempt to install or authenticate these.
2. **Legacy symlink check** — detect `~/.claude/skills/{todo,create-jira-issue,todo-driven-development}`
   symlinks pointing into this repo. They conflict with the plugin install: the same skills would
   register twice, once as `@skills-dir` and once as `@zibby-skills`. Offer to remove them; refuse
   to proceed if declined.
3. **Register the marketplace** — `claude plugin marketplace add <repo path or github ref>`,
   idempotent (a re-run must not error on an already-registered marketplace).
4. **Choose scope** — user or project. Flags for scripted use: `--scope`, `--yes`.
5. **Install** — `claude plugin install zibby@zibby-skills --scope <scope> -y`. `superpowers`
   resolves itself; the script does not enumerate dependencies.
6. **Report** — what was installed, what the doctor flagged, and that a restart is needed before
   the skills load.

Out of scope: installing `gh`/`python3`, authenticating Jira, writing the per-repo `## Jira`
README section. The doctor reports these and leaves them to the user.

## Migration on this machine

After the restructure lands, the current symlinks in `~/.claude/skills/` point at directories that
no longer exist. The migration is part of this work, not a follow-up:

1. `git mv` the skills into `skills/<name>/`, renaming `create-jira-issue` to `jira`.
2. Apply the content edits above.
3. Remove the three symlinks from `~/.claude/skills/`.
4. Run `./install.sh` and install at user scope.
5. Restart the session and confirm the skills appear as `zibby:todo`, `zibby:jira`,
   `zibby:todo-driven-development`.

## README

The repo README is currently one line. It becomes the install instructions: the two-command
path (`claude plugin marketplace add` + `claude plugin install`), the `install.sh` path, what the
doctor checks, and the skill table above.
