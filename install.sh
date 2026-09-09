#!/usr/bin/env bash
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$REPO_ROOT" ] || [ ! -f "$REPO_ROOT/.claude-plugin/marketplace.json" ]; then
  echo "install.sh: could not resolve this repo's root (got '$REPO_ROOT') — refusing to run," >&2
  echo "  since marketplace registration below needs a real path to add." >&2
  exit 1
fi
MARKETPLACE="zibby-skills"
PLUGIN="zibby"

SCOPE=""
DOCTOR_ONLY=0
SKIP_MCP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --scope)
      if [ $# -lt 2 ]; then
        echo "--scope requires a value: user, project, or local" >&2
        exit 1
      fi
      SCOPE="$2"; shift 2 ;;
    --doctor-only) DOCTOR_ONLY=1; shift ;;
    --skip-mcp-check) SKIP_MCP=1; shift ;;
    -h|--help)
      echo "Usage: ./install.sh [--scope user|project|local] [--doctor-only] [--skip-mcp-check]"
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
  ok "gh $(gh --version 2>/dev/null | head -1 | awk '{print $3}')  (zibby:todo-driven-development opens PRs, zibby:standup collects them)"
  if gh auth status >/dev/null 2>&1; then
    ok "gh authenticated  (zibby:standup)"
  else
    warn "gh is installed but not authenticated — zibby:standup has no source of PR data. Run: gh auth login"
  fi
else
  warn "gh not found — zibby:todo-driven-development cannot open pull requests and zibby:standup cannot collect them. Install: https://cli.github.com"
fi

# jq is not optional for the standup: collect.sh builds its whole document with it.
if command -v jq >/dev/null 2>&1; then
  ok "jq $(jq --version 2>/dev/null | sed 's/^jq-//')  (zibby:standup)"
else
  bad "jq not found — zibby:standup's collector cannot run at all. Install: brew install jq"
  blocking=1
fi

# One `claude mcp list` for every server we care about — it is the slow call here.
check_mcp() { # check_mcp <grep pattern> <label> <what breaks without it>
  row="$(printf '%s\n' "$mcp_out" | grep -i "$1" | head -1)"
  if [ -z "$row" ]; then
    warn "$2 MCP server not configured — $3"
  elif printf '%s' "$row" | grep -q "Connected"; then
    ok "$2 MCP connected  ($4)"
  else
    warn "$2 MCP configured but not authenticated — run /mcp inside Claude Code to log in"
  fi
}

if [ "$SKIP_MCP" -eq 1 ]; then
  warn "MCP checks skipped"
elif mcp_out="$(claude mcp list 2>/dev/null)"; then
  check_mcp atlassian "Atlassian" \
    "zibby:jira cannot reach Jira, and zibby:standup falls back to PR titles" "zibby:jira, zibby:standup"
  check_mcp slack "Slack" \
    "zibby:standup cannot read the standup thread or post into it" "zibby:standup"
  check_mcp 'microsoft.365\|microsoft_365' "Microsoft 365" \
    "zibby:standup renders no meeting line" "zibby:standup"
else
  warn "could not query MCP servers; skipping the Atlassian, Slack and Microsoft 365 checks"
fi

if [ -f "$HOME/.zibby/zibby-skills/config.yml" ] && grep -q '^standup:' "$HOME/.zibby/zibby-skills/config.yml" 2>/dev/null; then
  ok "standup: config present in ~/.zibby/zibby-skills/config.yml"
else
  warn "no 'standup:' key in ~/.zibby/zibby-skills/config.yml — zibby:standup will offer to create one on first run"
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

# Fail before touching anything — not after registering the marketplace —
# if we have no scope and no way to ask for one. This has to be decidable
# from the flags alone, so it belongs before any of the mutations below
# rather than down in the "pick scope" step.
if [ -z "$SCOPE" ] && [ ! -t 0 ]; then
  bad "no --scope given and stdin is not a terminal to prompt on"
  bad "pass --scope user|project|local explicitly"
  exit 1
fi

# -------------------------------------------------- register marketplace
say ""
if claude plugin marketplace list 2>/dev/null | grep -qE "(^|[[:space:]])${MARKETPLACE}\$"; then
  ok "marketplace $MARKETPLACE already registered"
else
  say "Registering marketplace ${MARKETPLACE}…"
  if claude plugin marketplace add "$REPO_ROOT" >/dev/null 2>&1; then
    ok "marketplace $MARKETPLACE added"
  else
    bad "could not add marketplace from $REPO_ROOT"
    exit 1
  fi
fi

# ------------------------------------------------------------ pick scope
# Reaching here with SCOPE unset means stdin is a terminal — the
# non-interactive case already exited earlier, before any mutation.
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
  # Read the list off disk rather than hardcoding it — the hardcoded copy went stale twice,
  # and a skill missing from this list is a skill nobody knows they now have.
  for skill_dir in "$REPO_ROOT"/skills/*/; do
    [ -f "${skill_dir}SKILL.md" ] || continue
    say "    ${PLUGIN}:$(basename "$skill_dir")"
  done
  say ""
  say "  superpowers was pulled in automatically as a dependency."
  say "  Remove everything later with:"
  say "    claude plugin uninstall $PLUGIN@$MARKETPLACE --scope $SCOPE --prune"
else
  bad "install failed"
  exit 1
fi
