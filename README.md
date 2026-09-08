# zibby-skills

A Claude Code marketplace holding one plugin, `zibby` — how I work: a TODO backlog, Jira issue
creation, cutting a written plan into a ready backlog, and the pipeline that drives a TODO item all
the way to a draft PR.

| Skill | What it does |
|---|---|
| `zibby:todo` | Manage the `TODO.md` at the root of whichever repo you're in. |
| `zibby:jira` | Turn any description of work into a researched Jira issue. |
| `zibby:plan-to-backlog` | Cut a written implementation plan into deliverable chunks: one Epic, an issue per chunk, `Blocks` links, and a short summary line per chunk in `TODO.md`. |
| `zibby:todo-driven-development` | Drive a TODO item to a draft PR: issue → plan → implementation → PR. |

The four install together — they are one way of working, not a menu. `zibby:plan-to-backlog` fills
the backlog, `zibby:todo-driven-development` empties it, and both lean on `zibby:todo` and
`zibby:jira`.

## Install

```bash
git clone git@github.com:ZibbyKarel/skills.git zibby-skills
cd zibby-skills
./install.sh
```

`install.sh` checks prerequisites, registers the marketplace and installs at the scope you choose.
Run bare in a terminal, it prompts for the scope; run with stdin that isn't a terminal (CI, a piped
invocation), it has no way to prompt and exits 1 telling you to pass `--scope` explicitly.

Non-interactive:

```bash
./install.sh --scope user
./install.sh --doctor-only          # just the prerequisite report
./install.sh --skip-mcp-check       # skip the Atlassian MCP check in the doctor report
```

Or skip the script entirely:

```bash
claude plugin marketplace add ZibbyKarel/skills
claude plugin install zibby@zibby-skills --scope user
```

Restart Claude Code afterwards — plugins load at session start.

## Dependencies

`superpowers@claude-plugins-official` installs automatically as a declared plugin dependency; you
never install it by hand. This works because `marketplace.json` allowlists that marketplace via
`allowCrossMarketplaceDependenciesOn` — without the allowlist, cross-marketplace dependencies are
blocked at install time.

These are **not** installable by any plugin system, so `install.sh` reports them and leaves them
to you:

- `python3` — `zibby:todo` shells out to it. Blocking.
- `gh` — `zibby:todo-driven-development` opens pull requests with it.
- **Atlassian MCP server**, authenticated — `zibby:jira` needs it. Log in with `/mcp`.
- A `jira:` key in `.zibby/zibby-skills/config.yml` at the root of each repo you file issues from,
  naming the target board, site, issue types, sprint policy and labels. `issueTypes` names the
  `task`, `bug` and `parent` (epic-level) type names for that instance; the older single `issueType`
  key still works and is read as the `task` type. `sprint` (`current` or `none`, default `none`)
  says whether newly filed issues land in the board's current sprint — `zibby:todo-driven-development`
  assigns it per item when it starts implementing, regardless of this key.

## Uninstall

```bash
claude plugin uninstall zibby@zibby-skills --scope user --prune
```

`--prune` also removes `superpowers` if nothing else still depends on it.

## Layout

The repo *is* the plugin — `"source": "./"` in the marketplace manifest, skills auto-discovered
from `skills/`.

```
.claude-plugin/marketplace.json   marketplace zibby-skills, one entry
.claude-plugin/plugin.json        plugin zibby, declares the superpowers dependency
skills/todo/                      SKILL.md + scripts/todo.py
skills/jira/                      SKILL.md + references/sprint.md
skills/plan-to-backlog/           SKILL.md + references/chunking.md
skills/todo-driven-development/
install.sh
tests/                            reference and install smoke checks
```

## Development

```bash
claude plugin validate .      # manifests
./tests/check-references.sh   # cross-skill references
./tests/todo-script.sh        # todo.py behaviour, in a throwaway git repo
./tests/install-smoke.sh      # install into a throwaway project, then clean up
```
