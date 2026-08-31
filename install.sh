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
