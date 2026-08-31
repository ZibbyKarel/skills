# zibby Marketplace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn this repo into a single-plugin Claude Code marketplace so the three skills install on any machine with one command and pull `superpowers` in automatically.

**Architecture:** The repo *is* the plugin. `.claude-plugin/marketplace.json` lists one entry, `zibby`, with `"source": "./"`; `.claude-plugin/plugin.json` declares the `superpowers` dependency; skills are auto-discovered from `skills/`. `install.sh` is a thin bootstrap over `claude plugin marketplace add` + `claude plugin install` — it never resolves dependencies itself.

**Tech Stack:** Claude Code plugin manifests (JSON), Markdown skills, Bash, Python 3 (existing `todo.py`).

**Spec:** `docs/superpowers/specs/2026-08-31-skills-marketplace-design.md`

## Global Constraints

- Claude Code CLI **>= 2.1** — `dependencies` auto-install and `--prune` were verified on 2.1.251.
- Marketplace name `zibby-skills`; plugin name `zibby`; skill names `todo`, `jira`, `todo-driven-development`.
- Skills are invoked as `zibby:<skill>`. Identical plugin/skill names do **not** collapse, which is why the plugin is not named after any skill.
- `.claude-plugin/marketplace.json` **must** carry `"allowCrossMarketplaceDependenciesOn": ["claude-plugins-official"]`. Without it, the `superpowers@claude-plugins-official` dependency is blocked at install time.
- Every file move uses `git mv`, never `mv` + `git add`, so history follows the files.
- Two SKILL.md files (`create-jira-issue`, `todo-driven-development`) have uncommitted edits. Do **not** stash or discard them; `git mv` carries them through as rename+modify.
- Brand naming, everywhere including prose and JSON strings: `team.blue` (lowercase, with the period) and `Simply.com`. Never "Team Blue", "TeamBlue", "Team.blue", "Simply".
- `install.sh` reports missing external tools; it never installs or authenticates them.
- There is no test framework in this repo. A task's "test" is a concrete shell command with an expected exit status or output — write and run it *before* the change so you see it fail.

---

### Task 1: Restructure into a valid single-plugin marketplace

Moves every skill under `skills/` and adds both manifests. The repo is in a broken half-state between the move and the manifests, so these belong in one task.

**Files:**
- Create: `.claude-plugin/marketplace.json`
- Create: `.claude-plugin/plugin.json`
- Move: `todo/` → `skills/todo/`
- Move: `create-jira-issue/` → `skills/jira/`
- Move: `todo-driven-development/` → `skills/todo-driven-development/`

**Interfaces:**
- Produces: marketplace `zibby-skills` containing plugin `zibby`; skill directories at `skills/todo`, `skills/jira`, `skills/todo-driven-development`. Tasks 2, 3 and 5 all depend on these exact paths.

- [ ] **Step 1: Write the failing validation check**

Run this now, before changing anything:

```bash
claude plugin validate . 2>&1 | tail -5
```

Expected: FAIL — no `.claude-plugin/marketplace.json` exists yet. Record the exact error text; it is the baseline.

- [ ] **Step 2: Move the skills with `git mv`**

```bash
mkdir -p skills
git mv todo skills/todo
git mv create-jira-issue skills/jira
git mv todo-driven-development skills/todo-driven-development
git status --short
```

Expected: three renames listed. `skills/jira/SKILL.md` and `skills/todo-driven-development/SKILL.md` show as rename+modify because of the pre-existing uncommitted edits — that is correct, leave them.

- [ ] **Step 3: Write the marketplace manifest**

Create `.claude-plugin/marketplace.json`:

```json
{
  "name": "zibby-skills",
  "owner": {
    "name": "Karel Zíbar",
    "email": "karel.zibar@team.blue"
  },
  "metadata": {
    "description": "Personal Claude Code skills: TODO backlog, Jira issue creation, and the TODO-to-PR pipeline.",
    "version": "0.1.0"
  },
  "allowCrossMarketplaceDependenciesOn": ["claude-plugins-official"],
  "plugins": [
    {
      "name": "zibby",
      "source": "./",
      "description": "How Karel works: TODO backlog, Jira issue creation, and the TODO-to-PR pipeline.",
      "category": "productivity"
    }
  ]
}
```

- [ ] **Step 4: Write the plugin manifest**

Create `.claude-plugin/plugin.json`:

```json
{
  "name": "zibby",
  "version": "0.1.0",
  "description": "How Karel works: TODO backlog, Jira issue creation, and the TODO-to-PR pipeline.",
  "author": {
    "name": "Karel Zíbar",
    "email": "karel.zibar@team.blue"
  },
  "homepage": "https://github.com/ZibbyKarel/skills",
  "license": "MIT",
  "keywords": ["todo", "jira", "workflow", "productivity"],
  "dependencies": ["superpowers@claude-plugins-official"]
}
```

- [ ] **Step 5: Run validation to verify it passes**

```bash
claude plugin validate . 2>&1 | tail -5
```

Expected: `✔ Validation passed` (warnings are acceptable only if they concern optional metadata; a warning naming a missing description or author is a real defect — fix it).

- [ ] **Step 6: Verify all three skills are discovered**

```bash
ls skills/*/SKILL.md
grep -h '^name:' skills/*/SKILL.md
```

Expected: three SKILL.md paths. The `name:` values are still `todo`, `create-jira-issue`, `todo-driven-development` — the frontmatter rename happens in Task 2, so `create-jira-issue` here is expected, not a bug.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: restructure repo as the single-plugin zibby marketplace

Skills move under skills/ and the repo root becomes the plugin via
\"source\": \"./\". Cross-marketplace dependency on superpowers is
declared in plugin.json and allowlisted in marketplace.json.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Rename the Jira skill and repoint every cross-skill reference

The skills name each other in prose and in frontmatter descriptions. A missed reference does not fail at install — it fails silently at runtime when the pipeline tries to invoke a skill that no longer answers to that name.

**Files:**
- Modify: `skills/jira/SKILL.md` (lines 2, 3, 22, 95, 117)
- Modify: `skills/todo-driven-development/SKILL.md` (lines 3, 9-10, 86, 96)
- Modify: `skills/todo/SKILL.md` (line 17)

**Interfaces:**
- Consumes: skill directories from Task 1.
- Produces: skill `name:` values `todo`, `jira`, `todo-driven-development`; all sibling references written as `zibby:todo` / `zibby:jira` / `zibby:todo-driven-development`; the todo script path expressed as `${CLAUDE_PLUGIN_ROOT}/skills/todo/scripts/todo.py`.

- [ ] **Step 1: Write the failing reference check**

Create `tests/check-references.sh`:

```bash
#!/usr/bin/env bash
# Fails if any skill still refers to a sibling by its pre-marketplace name,
# or if the todo script path is not plugin-relative.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
fail=0

check_absent() {
  local pattern="$1" label="$2"
  if grep -rnE "$pattern" skills/ >/dev/null 2>&1; then
    echo "FAIL: $label"
    grep -rnE "$pattern" skills/ | sed 's/^/    /'
    fail=1
  else
    echo "ok:   $label"
  fi
}

check_present() {
  local pattern="$1" file="$2" label="$3"
  if grep -qE "$pattern" "$file"; then
    echo "ok:   $label"
  else
    echo "FAIL: $label"
    fail=1
  fi
}

# A bare sibling name, not already namespaced with zibby:
check_absent '(^|[^:[:alnum:]-])create-jira-issue' 'no bare create-jira-issue references'
check_absent '<path-to-this-skill>'                'no <path-to-this-skill> placeholder'

check_present '^name: jira$'                    skills/jira/SKILL.md                    'jira skill renamed'
check_present '^name: todo$'                    skills/todo/SKILL.md                    'todo skill name intact'
check_present '^name: todo-driven-development$' skills/todo-driven-development/SKILL.md 'tdd skill name intact'
check_present 'CLAUDE_PLUGIN_ROOT'              skills/todo/SKILL.md                    'todo script path is plugin-relative'
check_present 'zibby:jira'                      skills/todo-driven-development/SKILL.md 'tdd points at zibby:jira'
check_present 'zibby:todo-driven-development'   skills/jira/SKILL.md                    'jira points at zibby:todo-driven-development'

exit $fail
```

- [ ] **Step 2: Run it to verify it fails**

```bash
chmod +x tests/check-references.sh && ./tests/check-references.sh
```

Expected: FAIL, exit status 1, with `no bare create-jira-issue references`, `no <path-to-this-skill> placeholder`, `jira skill renamed`, and both namespacing checks failing.

- [ ] **Step 3: Rename the Jira skill in its frontmatter**

In `skills/jira/SKILL.md`, set line 2 to `name: jira` and replace the line 3 description with this — it leads with the verb so discovery does not rest on the bare noun "jira":

```
description: "Create a Jira issue in the current project's board from any input — a TODO.md line, a bug report, a Slack message, a vague one-liner. Reads the target board/site/issue-type/labels from a '## Jira' section in this repo's README.md, researches the actual codebase for relevant files and functions to ground the description in fact rather than restating the input, checks for likely duplicates before creating, and reports back the created issue's key and URL. Use this whenever the user asks to file/create/open a Jira issue or ticket for something, not only when working through a TODO.md — it accepts anything describing a piece of work."
```

Change the `# create-jira-issue` H1 heading to `# jira`. (`tests/check-references.sh` enforces this — the bare-name pattern matches the heading too.)

- [ ] **Step 4: Repoint the sibling references in the Jira skill**

Three prose references to the pipeline skill, at roughly lines 22, 95 and 117 of `skills/jira/SKILL.md`. Replace each backticked `` `todo-driven-development` `` with `` `zibby:todo-driven-development` ``:

```bash
sed -i '' 's/`todo-driven-development`/`zibby:todo-driven-development`/g' skills/jira/SKILL.md
grep -n 'zibby:todo-driven-development' skills/jira/SKILL.md
```

Expected: three matching lines.

- [ ] **Step 5: Repoint the sibling references in the pipeline skill**

In `skills/todo-driven-development/SKILL.md`:

- Line 3 (frontmatter description): change the clause `three other skills — todo, create-jira-issue, and the superpowers plugin —` to `three other skills — zibby:todo, zibby:jira, and the superpowers plugin —`.
- Lines 9-10: change `Depends on \`todo\`,` / `` `create-jira-issue`, and the `superpowers` plugin `` to `` Depends on `zibby:todo`, `` / `` `zibby:jira`, and the `superpowers` plugin ``.
- Line 86: `Invoke the \`create-jira-issue\` skill with the item's text as input.` → `Invoke the \`zibby:jira\` skill with the item's text as input.`
- Line 96: `Otherwise pass \`create-jira-issue\` the autonomy level \`unattended\`` → `Otherwise pass \`zibby:jira\` the autonomy level \`unattended\``.

Leave every `todo list` / `todo next` / `todo show <n>` / `todo done <n>` alone — those name the todo skill's *commands*, not the skill, and renaming them would break the documented CLI surface.

- [ ] **Step 6: Make the todo script path plugin-relative**

In `skills/todo/SKILL.md`, replace the line 17 code block body:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/todo/scripts/todo.py <command> [args]
```

`CLAUDE_PLUGIN_ROOT` is set by Claude Code to the installed plugin's root directory, which is what makes this work from any project.

- [ ] **Step 7: Run the reference check to verify it passes**

```bash
./tests/check-references.sh
```

Expected: every line `ok:`, exit status 0.

- [ ] **Step 8: Re-validate the plugin**

```bash
claude plugin validate . 2>&1 | tail -5
```

Expected: `✔ Validation passed`.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "refactor: rename create-jira-issue to jira and namespace sibling references

Skills are addressed as zibby:<skill> once installed as a plugin, so
every cross-skill reference is repointed. Adds tests/check-references.sh
to catch a missed rename, which otherwise fails silently at runtime.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Write `install.sh`

**Files:**
- Create: `install.sh`
- Create: `tests/install-smoke.sh`

**Interfaces:**
- Consumes: marketplace `zibby-skills` and plugin `zibby` from Task 1.
- Produces: `./install.sh [--scope user|project|local] [--yes] [--doctor-only] [--skip-mcp-check]`, exit 0 on success, exit 1 on a failed prerequisite or a declined symlink removal.

- [ ] **Step 1: Write the failing smoke test**

Create `tests/install-smoke.sh`:

```bash
#!/usr/bin/env bash
# Exercises install.sh without touching the real user scope: installs into a
# throwaway project directory, then uninstalls and prunes.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
REPO="$PWD"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

# Never tear down a registration that was already there — after the real
# migration, zibby-skills is the source of the user's installed plugin.
PRE_REGISTERED=0
if claude plugin marketplace list 2>/dev/null | grep -qw zibby-skills; then
  PRE_REGISTERED=1
fi

echo "== doctor-only runs and exits 0 or 1, never crashes =="
"$REPO/install.sh" --doctor-only --skip-mcp-check >"$TMP/doctor.log" 2>&1
rc=$?
if [ $rc -gt 1 ]; then echo "FAIL: doctor exited $rc"; cat "$TMP/doctor.log"; fail=1; else echo "ok"; fi

echo "== project-scope install pulls superpowers in =="
mkdir -p "$TMP/proj"
( cd "$TMP/proj" && "$REPO/install.sh" --scope project --yes --skip-mcp-check ) >"$TMP/install.log" 2>&1
if grep -q "superpowers" "$TMP/install.log"; then echo "ok"; else echo "FAIL: superpowers not mentioned"; cat "$TMP/install.log"; fail=1; fi

if grep -q '"zibby@zibby-skills"' "$TMP/proj/.claude/settings.json" 2>/dev/null; then
  echo "ok:   zibby enabled in project settings"
else
  echo "FAIL: zibby missing from $TMP/proj/.claude/settings.json"
  cat "$TMP/proj/.claude/settings.json" 2>/dev/null
  fail=1
fi

echo "== cleanup =="
# Scoped to the throwaway project, so a user-scope install is untouched.
( cd "$TMP/proj" && claude plugin uninstall zibby@zibby-skills --scope project --prune -y ) >/dev/null 2>&1
if [ "$PRE_REGISTERED" -eq 0 ]; then
  claude plugin marketplace remove zibby-skills >/dev/null 2>&1
  echo "ok:   marketplace unregistered (this run added it)"
else
  echo "ok:   marketplace left registered (it predates this run)"
fi

exit $fail
```

- [ ] **Step 2: Run it to verify it fails**

```bash
chmod +x tests/install-smoke.sh && ./tests/install-smoke.sh
```

Expected: FAIL — `install.sh` does not exist, so the doctor step reports a non-zero crash.

- [ ] **Step 3: Write `install.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE="zibby-skills"
PLUGIN="zibby"
SKILLS_DIR="$HOME/.claude/skills"
LEGACY_LINKS=(todo create-jira-issue todo-driven-development)

SCOPE=""
ASSUME_YES=0
DOCTOR_ONLY=0
SKIP_MCP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --scope) SCOPE="${2:-}"; shift 2 ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --doctor-only) DOCTOR_ONLY=1; shift ;;
    --skip-mcp-check) SKIP_MCP=1; shift ;;
    -h|--help)
      echo "Usage: ./install.sh [--scope user|project|local] [--yes] [--doctor-only] [--skip-mcp-check]"
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------- doctor
blocking=0

say ""
say "Checking prerequisites"

if command -v claude >/dev/null 2>&1; then
  ver="$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  major="${ver%%.*}"; rest="${ver#*.}"; minor="${rest%%.*}"
  if [ -n "$ver" ] && { [ "${major:-0}" -gt 2 ] || { [ "${major:-0}" -eq 2 ] && [ "${minor:-0}" -ge 1 ]; }; }; then
    ok "claude $ver"
  else
    bad "claude ${ver:-unknown} — this installer needs >= 2.1 for plugin dependency auto-install"
    blocking=1
  fi
else
  bad "claude CLI not found on PATH"
  blocking=1
fi

if command -v python3 >/dev/null 2>&1; then
  ok "python3 $(python3 --version 2>&1 | awk '{print $2}')  (zibby:todo)"
else
  bad "python3 not found — zibby:todo shells out to it and will not work"
  blocking=1
fi

if command -v gh >/dev/null 2>&1; then
  ok "gh $(gh --version 2>/dev/null | head -1 | awk '{print $3}')  (zibby:todo-driven-development opens PRs)"
else
  warn "gh not found — zibby:todo-driven-development cannot open pull requests. Install: https://cli.github.com"
fi

if [ "$SKIP_MCP" -eq 1 ]; then
  warn "Atlassian MCP check skipped"
elif mcp_out="$(claude mcp list 2>/dev/null)"; then
  atl="$(printf '%s\n' "$mcp_out" | grep -i atlassian | head -1)"
  if [ -z "$atl" ]; then
    warn "Atlassian MCP server not configured — zibby:jira cannot reach Jira"
  elif printf '%s' "$atl" | grep -q "Connected"; then
    ok "Atlassian MCP connected  (zibby:jira)"
  else
    warn "Atlassian MCP configured but not authenticated — run /mcp inside Claude Code to log in"
  fi
else
  warn "could not query MCP servers; skipping the Atlassian check"
fi

warn "Each repo you use zibby:jira in needs a '## Jira' section in its README.md — the installer cannot write that for you"

if [ "$blocking" -eq 1 ]; then
  say ""
  say "Blocking prerequisites are missing. Nothing was installed."
  exit 1
fi

if [ "$DOCTOR_ONLY" -eq 1 ]; then
  say ""
  say "Doctor only — nothing installed."
  exit 0
fi

# ------------------------------------------------- legacy symlink cleanup
stale=()
for name in "${LEGACY_LINKS[@]}"; do
  link="$SKILLS_DIR/$name"
  if [ -L "$link" ]; then
    target="$(readlink "$link")"
    case "$target" in
      "$REPO_ROOT"|"$REPO_ROOT"/*) stale+=("$link") ;;
    esac
  fi
done

if [ "${#stale[@]}" -gt 0 ]; then
  say ""
  say "Found ${#stale[@]} legacy skills-dir symlink(s) pointing into this repo:"
  printf '    %s\n' "${stale[@]}"
  say ""
  say "These conflict with the plugin install — the same skills would register"
  say "twice, once as @skills-dir and once as @$MARKETPLACE."
  if [ "$ASSUME_YES" -eq 1 ]; then
    reply=y
  else
    printf 'Remove them? [y/N] '
    read -r reply
  fi
  case "$reply" in
    y|Y|yes)
      for link in "${stale[@]}"; do rm "$link" && ok "removed $link"; done ;;
    *)
      bad "Declined. Refusing to install a conflicting copy."
      exit 1 ;;
  esac
fi

# -------------------------------------------------- register marketplace
say ""
if claude plugin marketplace list 2>/dev/null | grep -qw "$MARKETPLACE"; then
  ok "marketplace $MARKETPLACE already registered"
else
  say "Registering marketplace $MARKETPLACE…"
  if claude plugin marketplace add "$REPO_ROOT" >/dev/null 2>&1; then
    ok "marketplace $MARKETPLACE added"
  else
    bad "could not add marketplace from $REPO_ROOT"
    exit 1
  fi
fi

# ------------------------------------------------------------ pick scope
if [ -z "$SCOPE" ]; then
  say ""
  say "Install scope:"
  say "  user     — every project on this machine"
  say "  project  — only $(pwd), committed to its .claude/settings.json"
  say "  local    — only $(pwd), not committed"
  printf 'Scope [user]: '
  read -r SCOPE
  SCOPE="${SCOPE:-user}"
fi

case "$SCOPE" in
  user|project|local) ;;
  *) bad "invalid scope: $SCOPE (expected user, project or local)"; exit 1 ;;
esac

# --------------------------------------------------------------- install
say ""
say "Installing $PLUGIN@$MARKETPLACE at $SCOPE scope…"
if claude plugin install "$PLUGIN@$MARKETPLACE" --scope "$SCOPE" -y; then
  say ""
  ok "Installed. Skills available after restarting Claude Code:"
  say "    zibby:todo"
  say "    zibby:jira"
  say "    zibby:todo-driven-development"
  say ""
  say "  superpowers was pulled in automatically as a dependency."
  say "  Remove everything later with:"
  say "    claude plugin uninstall $PLUGIN@$MARKETPLACE --scope $SCOPE --prune"
else
  bad "install failed"
  exit 1
fi
```

- [ ] **Step 4: Make it executable and run the smoke test**

```bash
chmod +x install.sh && ./tests/install-smoke.sh
```

Expected: every check `ok`, exit status 0. If the marketplace was already registered from a previous run, the "already registered" branch fires — that is correct, the script is idempotent.

- [ ] **Step 5: Verify the smoke test cleaned up after itself**

```bash
claude plugin marketplace list | grep -c zibby-skills || true
grep -c "zibby@zibby-skills" ~/.claude/settings.json 2>/dev/null || true
```

Expected: `0` from both. The smoke test must leave no trace in user-level config; if either is non-zero, remove it before continuing.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add install.sh bootstrap with prerequisite doctor

Registers the marketplace, clears conflicting skills-dir symlinks, picks
a scope and installs. Dependency resolution is left entirely to the
plugin system. The doctor reports gh/python3/Atlassian MCP rather than
trying to install or authenticate them.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Rewrite the README as install instructions

The README is currently one line (`# skills`). It is now the front door for a marketplace.

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: everything from Tasks 1-3.

- [ ] **Step 1: Write the failing content check**

```bash
grep -c "claude plugin marketplace add" README.md
```

Expected: `0` — the instructions are not there yet.

- [ ] **Step 2: Write the README**

Replace `README.md` entirely:

````markdown
# zibby-skills

A Claude Code marketplace holding one plugin, `zibby` — how I work: a TODO backlog, Jira issue
creation, and the pipeline that drives a TODO item all the way to a draft PR.

| Skill | What it does |
|---|---|
| `zibby:todo` | Manage the `TODO.md` at the root of whichever repo you're in. |
| `zibby:jira` | Turn any description of work into a researched Jira issue. |
| `zibby:todo-driven-development` | Drive a TODO item to a draft PR: issue → plan → implementation → PR. |

The three install together — they are one way of working, not a menu, and the pipeline skill needs
both others.

## Install

```bash
git clone git@github.com:ZibbyKarel/skills.git zibby-skills
cd zibby-skills
./install.sh
```

`install.sh` checks prerequisites, clears any conflicting `~/.claude/skills` symlinks from the
pre-marketplace layout, registers the marketplace and installs at the scope you choose.

Non-interactive:

```bash
./install.sh --scope user --yes
./install.sh --doctor-only     # just the prerequisite report
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
- A `## Jira` section in the README of each repo you file issues from, naming the target board,
  site, issue type and labels.

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
skills/jira/
skills/todo-driven-development/
install.sh
tests/                            reference and install smoke checks
```

## Development

```bash
claude plugin validate .      # manifests
./tests/check-references.sh   # cross-skill references
./tests/install-smoke.sh      # install into a throwaway project, then clean up
```
````

- [ ] **Step 3: Verify the check now passes**

```bash
grep -c "claude plugin marketplace add" README.md
```

Expected: `2` or more.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README as marketplace install instructions

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Migrate this machine

The symlinks in `~/.claude/skills/` point at directories that stopped existing in Task 1. This is not a follow-up — the machine is broken until it runs.

**Files:**
- No repo files. Changes `~/.claude/skills/` and `~/.claude/settings.json`.

**Interfaces:**
- Consumes: `install.sh` from Task 3.

> **Run this task from the main checkout at `/Users/zibar/Workspace/zibby-skills`, after the
> branch has been merged — never from a git worktree.** `install.sh` registers the marketplace
> at whatever directory it lives in, and a directory-source marketplace stores that live path
> (see the `shoptet-skills` entry in `~/.claude/plugins/known_marketplaces.json`). Registering
> from a worktree points the user's permanent install at a directory that disappears on cleanup,
> which breaks the plugin silently. This is the same failure mode as commit `2d07dce`.

- [ ] **Step 1: Confirm the symlinks are currently broken**

```bash
ls -l ~/.claude/skills/
for s in todo create-jira-issue todo-driven-development; do
  [ -e "$HOME/.claude/skills/$s" ] && echo "$s: target exists" || echo "$s: BROKEN (expected)"
done
```

Expected: all three report `BROKEN`. That is the state Task 1 created and this task repairs.

- [ ] **Step 2: Run the installer at user scope**

From the main checkout, on the merged branch:

```bash
cd /Users/zibar/Workspace/zibby-skills
./install.sh --scope user
```

Answer `y` when it offers to remove the three legacy symlinks. Expected: doctor report, three `removed …` lines, marketplace registered, then `Successfully installed plugin: zibby@zibby-skills (scope: user) (+ 1 dependency: superpowers)` — or without the dependency clause if `superpowers` is already installed at user scope, which it is on this machine. Either is correct.

- [ ] **Step 3: Verify the installed state**

```bash
ls -l ~/.claude/skills/ | grep -E 'todo|jira' || echo "no legacy symlinks remain (expected)"
claude plugin details zibby
grep -A5 enabledPlugins ~/.claude/settings.json
```

Expected: no legacy symlinks; `Skills (3)  jira, todo, todo-driven-development`; `"zibby@zibby-skills": true` in settings.

- [ ] **Step 4: Confirm the skills load under their new names**

Plugins load at session start, so this needs a fresh session. Start one in any repo and check that `zibby:todo`, `zibby:jira` and `zibby:todo-driven-development` appear in the available skills list, then run:

```
zibby:todo list
```

Expected: the TODO.md items for that repo. If the skills appear under different names than `zibby:*`, report the actual names — the namespace claim is the one part of the design that could not be verified before install.

- [ ] **Step 5: Report to the user**

Tell them explicitly: the symlinks are gone, the plugin is installed at user scope, and what the three skills are actually called. They asked to be told when this step landed.

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| Native plugin system, no custom package manager | 3 (install.sh delegates) |
| One plugin `zibby`, skill names and namespace | 1, 2 |
| Target repo layout, `"source": "./"` | 1 |
| Both manifests, `allowCrossMarketplaceDependenciesOn` | 1 |
| Content edits forced by the rename (3 items) | 2 |
| install.sh six-step sequence | 3 |
| Migration on this machine (5 steps) | 5 |
| README | 4 |

No gaps.

**Placeholder scan:** every step carries the literal file content or command. No "TBD", no "handle edge cases", no "similar to Task N".

**Type consistency:** `zibby-skills` (marketplace), `zibby` (plugin), and skills `todo` / `jira` / `todo-driven-development` are spelled identically in the manifests, both test scripts, `install.sh`, the README and Task 5's verification commands. `CLAUDE_PLUGIN_ROOT` is used only in `skills/todo/SKILL.md`, asserted by `tests/check-references.sh`.

**Two guards worth not losing in edit:** `tests/install-smoke.sh` only unregisters the
marketplace it registered itself — after Task 5 the user's real install depends on that
registration, and the README tells them to run the smoke test routinely. And Task 5 runs from the
main checkout, because a directory-source marketplace records the live path it was added from.

**One risk carried deliberately:** the `zibby:<skill>` namespace is inferred from this session's skill list showing `frontend-design:frontend-design` un-collapsed, not from installing this plugin. Task 5 Step 4 verifies it for real, and a wrong guess costs one line in `marketplace.json`.
