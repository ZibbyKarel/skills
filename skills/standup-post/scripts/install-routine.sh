#!/usr/bin/env bash
# Installs the weekday morning standup as a macOS LaunchAgent: `claude -p "/standup-post"`
# at 07:00, Monday through Friday.
#
# Claude Code's own CronCreate is deliberately not used here — its jobs live in one session's
# memory, die with that session and expire after 7 days, so "every weekday at 7" is not
# something it can promise. launchd is, and it also catches up a run the Mac slept through.
#
#   install-routine.sh [--hour H] [--minute M] [--dry-run]
#   install-routine.sh --uninstall
#
# Exit codes: 0 done, 2 bad arguments, 3 not macOS, 4 claude not on PATH, 5 launchctl refused.
set -uo pipefail

LABEL="com.zibby.standup-post"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="${HOME}/.zibby/standup"
HOUR=7
MINUTE=0
DRY_RUN=0
UNINSTALL=0

die() { printf 'install-routine.sh: %s\n' "$1" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hour)      HOUR="${2:-}";   shift 2 ;;
    --minute)    MINUTE="${2:-}"; shift 2 ;;
    --dry-run)   DRY_RUN=1;       shift ;;
    --uninstall) UNINSTALL=1;     shift ;;
    -h|--help)   sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           die "unknown argument: $1" ;;
  esac
done

[[ "$HOUR"   =~ ^[0-9]{1,2}$ && "$HOUR"   -le 23 ]] || die "--hour must be 0-23"
[[ "$MINUTE" =~ ^[0-9]{1,2}$ && "$MINUTE" -le 59 ]] || die "--minute must be 0-59"

[[ "$(uname -s)" == "Darwin" ]] || {
  printf 'install-routine.sh: launchd is macOS-only; on Linux use a systemd timer or crontab running: claude -p "/standup-post"\n' >&2
  exit 3
}

if [[ "$UNINSTALL" -eq 1 ]]; then
  launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null
  if [[ -f "$PLIST" ]]; then
    rm -f "$PLIST" || die "could not remove $PLIST"
    printf 'removed: %s\n' "$PLIST"
  else
    printf 'nothing to remove: %s does not exist\n' "$PLIST"
  fi
  exit 0
fi

CLAUDE_BIN="$(command -v claude 2>/dev/null)"
[[ -n "$CLAUDE_BIN" ]] || {
  printf 'install-routine.sh: claude not on PATH — the routine would have nothing to run\n' >&2
  exit 4
}

# launchd starts with a near-empty environment, so the agent runs through a login shell: the
# routine needs whatever PATH, node version and credential helpers the user's profile sets up
# for `claude`, `gh` and `jq`.
SHELL_BIN="${SHELL:-/bin/zsh}"
# No `&&`, no `<`, no `>` in here: this string is interpolated straight into XML, and an
# ampersand-escape launchd cannot parse turns the whole agent into a silent no-op.
COMMAND="cd \"\$HOME\"; exec ${CLAUDE_BIN} -p '/standup-post'"

read -r -d '' PLIST_BODY <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${SHELL_BIN}</string>
    <string>-lc</string>
    <string>${COMMAND}</string>
  </array>
  <key>StartCalendarInterval</key>
  <array>
    <dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>${HOUR}</integer><key>Minute</key><integer>${MINUTE}</integer></dict>
    <dict><key>Weekday</key><integer>2</integer><key>Hour</key><integer>${HOUR}</integer><key>Minute</key><integer>${MINUTE}</integer></dict>
    <dict><key>Weekday</key><integer>3</integer><key>Hour</key><integer>${HOUR}</integer><key>Minute</key><integer>${MINUTE}</integer></dict>
    <dict><key>Weekday</key><integer>4</integer><key>Hour</key><integer>${HOUR}</integer><key>Minute</key><integer>${MINUTE}</integer></dict>
    <dict><key>Weekday</key><integer>5</integer><key>Hour</key><integer>${HOUR}</integer><key>Minute</key><integer>${MINUTE}</integer></dict>
  </array>
  <key>StandardOutPath</key>
  <string>${LOG_DIR}/routine.log</string>
  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/routine.log</string>
  <key>ProcessType</key>
  <string>Background</string>
</dict>
</plist>
XML

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '%s\n' "$PLIST_BODY"
  printf '\nwould write: %s\n' "$PLIST" >&2
  exit 0
fi

mkdir -p "${HOME}/Library/LaunchAgents" "$LOG_DIR" || die "could not create the agent or log directory"
printf '%s\n' "$PLIST_BODY" >"$PLIST" || die "could not write $PLIST"

# bootout first so a re-run replaces the existing job rather than colliding with it.
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null
if ! out="$(launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>&1)"; then
  printf 'install-routine.sh: launchctl refused the job: %s\n' "$out" >&2
  exit 5
fi

printf 'installed: %s\n' "$PLIST"
printf 'runs:      %s at %02d:%02d, Monday through Friday\n' "$(basename "$CLAUDE_BIN") -p /standup-post" "$HOUR" "$MINUTE"
printf 'log:       %s/routine.log\n' "$LOG_DIR"
printf 'test now:  launchctl kickstart -p gui/%s/%s\n' "$(id -u)" "$LABEL"
printf 'remove:    %s --uninstall\n' "$0"
