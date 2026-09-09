#!/usr/bin/env bash
# collect.sh behaviour, against synthetic session transcripts in a throwaway directory.
#
# Argument handling is checked unconditionally. The session-mining checks need `gh` authenticated,
# because the script always runs its GitHub searches first — they use a window in the distant past
# so the searches come back empty and cost nothing. Without `gh` auth those checks are skipped
# rather than failed: a missing credential is not a broken script.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

SCRIPT="skills/standup/scripts/collect.sh"
fail=0

pass() { echo "ok:   $1"; }
bad()  { echo "FAIL: $1"; fail=1; }

check_exit() { # check_exit <expected> <label> <args...>
  local expected="$1" label="$2"; shift 2
  "$SCRIPT" "$@" >/dev/null 2>&1
  local got=$?
  if [[ "$got" == "$expected" ]]; then pass "$label"; else bad "$label (exit $got, wanted $expected)"; fi
}

[[ -x "$SCRIPT" ]] && pass "collect.sh is executable" || bad "collect.sh is executable"

# --- arguments ------------------------------------------------------------------------
"$SCRIPT" --help 2>/dev/null | grep -q -- '--org' && pass "--help documents --org" \
  || bad "--help documents --org"

check_exit 2 "missing --org rejected"    --login me --from 2020-01-01T00:00:00Z --to 2020-01-02T00:00:00Z
check_exit 2 "missing --login rejected"  --org o    --from 2020-01-01T00:00:00Z --to 2020-01-02T00:00:00Z
check_exit 2 "missing --from rejected"   --org o --login me --to 2020-01-02T00:00:00Z
check_exit 2 "missing --to rejected"     --org o --login me --from 2020-01-01T00:00:00Z
check_exit 2 "unknown flag rejected"     --org o --login me --from 2020-01-01T00:00:00Z --to 2020-01-02T00:00:00Z --nope
# Window comparisons are string compares, so a non-UTC timestamp would mis-filter silently.
check_exit 2 "non-UTC --from rejected"   --org o --login me --from 2020-01-01T00:00:00+02:00 --to 2020-01-02T00:00:00Z
check_exit 2 "non-UTC --to rejected"     --org o --login me --from 2020-01-01T00:00:00Z --to 2020-01-02T00:00:00

# --- session mining ------------------------------------------------------------------
if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
  echo "skip: session-mining checks (gh not authenticated)"
  exit $fail
fi
command -v jq >/dev/null 2>&1 || { bad "jq present"; exit $fail; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
S="$WORK/projects"

emit() { # emit <project-dir> <session> <cwd> <branch> <title> <timestamp> <messages>
  local dir="$S/$1" sess="$2" cwd="$3" branch="$4" title="$5" ts="$6" n="$7" i
  mkdir -p "$dir"
  {
    printf '{"type":"ai-title","sessionId":"%s","aiTitle":%s}\n' "$sess" "$(jq -Rn --arg t "$title" '$t')"
    printf '{"type":"last-prompt","sessionId":"%s","lastPrompt":"a prompt"}\n' "$sess"
    for ((i = 0; i < n; i++)); do
      printf '{"type":"user","cwd":"%s","gitBranch":"%s","timestamp":"%s","isSidechain":false,"message":{"role":"user"}}\n' \
        "$cwd" "$branch" "$ts"
    done
  } >"$dir/$sess.jsonl"
}

IN="2026-09-08T10:00:00Z"
OUT_OF="2026-09-01T10:00:00Z"

emit "-Users-zibar-Workspace-work"   aaaa "/Users/zibar/Workspace/work"     main "Real work on the thing"      "$IN"     20
emit "-Users-zibar-Workspace-work"   bbbb "/Users/zibar/Workspace/work"     main "Out of window work"          "$OUT_OF" 20
emit "-Users-zibar-Workspace-work"   cccc "/Users/zibar/Workspace/work"     main "Too short to count"          "$IN"      2
emit "-Users-zibar-Workspace-mine"   dddd "/Users/zibar/Workspace/mine"     main "Personal side project"       "$IN"     20
emit "-Users-zibar-Workspace-work"   eeee "/Users/zibar/Workspace/work"     main "xoxb-not-a-real-token-just-fixture-data token" "$IN" 20
# Throwaway scratch directories must never contribute, whatever they contain.
emit "-private-tmp-claude-501-scratchpad-x" ffff "/private/tmp/x"           main "Scratchpad noise"            "$IN"     20
emit "-private-var-folders-jx-tmp-y"        gggg "/private/var/folders/y"    main "Temp checkout noise"         "$IN"     20

run() { # run <extra args...> — collect over the fixture, print JSON
  "$SCRIPT" --org shoptet --login ZibbyKarel \
    --from 2026-09-08T00:00:00Z --to 2026-09-09T00:00:00Z \
    --sessions-dir "$S" "$@" 2>/dev/null
}

out="$(run --exclude-repo mine)"
if [[ -z "$out" ]]; then
  bad "collector produced output"
  exit $fail
fi
pass "collector produced output"

titles="$(printf '%s' "$out" | jq -r '.sessions[].aiTitle')"

grep -qx "Real work on the thing" <<<"$titles" \
  && pass "in-window session collected" || bad "in-window session collected"
grep -qx "Out of window work" <<<"$titles" \
  && bad "out-of-window session excluded" || pass "out-of-window session excluded"
grep -qx "Too short to count" <<<"$titles" \
  && bad "below-threshold session excluded" || pass "below-threshold session excluded"
grep -qx "Personal side project" <<<"$titles" \
  && bad "--exclude-repo honoured" || pass "--exclude-repo honoured"
grep -q "Scratchpad noise" <<<"$titles" \
  && bad "scratchpad project dir excluded" || pass "scratchpad project dir excluded"
grep -q "Temp checkout noise" <<<"$titles" \
  && bad "temp project dir excluded" || pass "temp project dir excluded"

# The one leak that matters: a credential pasted mid-session ends up in the generated title,
# and everything downstream of the collector is bound for a public channel.
grep -q "xoxb-" <<<"$titles" && bad "credential redacted from session title" \
  || pass "credential redacted from session title"
grep -q "\[redacted\]" <<<"$titles" && pass "redaction marker present" \
  || bad "redaction marker present"

# Without --exclude-repo the same personal session must come back, or the filter proves nothing.
grep -qx "Personal side project" <<<"$(run | jq -r '.sessions[].aiTitle')" \
  && pass "personal session present when not excluded" \
  || bad "personal session present when not excluded"

printf '%s' "$out" | jq -e 'has("window") and has("created") and has("contributed")
  and has("sessions") and has("repos") and has("meetings") and has("notes")' >/dev/null \
  && pass "output carries every top-level key" || bad "output carries every top-level key"

# The calendar has no CLI, so the collector cannot fill this — but the key must exist regardless,
# or the renderer has to guess whether an absent key means "no meetings" or "never looked".
printf '%s' "$out" | jq -e '.meetings == []' >/dev/null \
  && pass "meetings emitted as an empty array" || bad "meetings emitted as an empty array"

exit $fail
