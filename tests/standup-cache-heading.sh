#!/usr/bin/env bash
# cache-heading.sh behaviour, against throwaway config fixtures.
#
# What these checks are really protecting: the config is the one file in this skill that must not
# drift between mornings, and a heading written by reflowing YAML loses comments and reorders keys.
# Every check below is a way that could go wrong.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

SCRIPT="skills/standup/scripts/cache-heading.sh"
fail=0

pass() { echo "ok:   $1"; }
bad()  { echo "FAIL: $1"; fail=1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[[ -x "$SCRIPT" ]] && pass "cache-heading.sh is executable" || bad "cache-heading.sh is executable"

"$SCRIPT" --help 2>/dev/null | grep -q -- '--heading' && pass "--help documents --heading" \
  || bad "--help documents --heading"

check_exit() { # check_exit <expected> <label> <args...>
  local expected="$1" label="$2"; shift 2
  "$SCRIPT" "$@" >/dev/null 2>&1
  local got=$?
  if [[ "$got" == "$expected" ]]; then pass "$label"; else bad "$label (exit $got, wanted $expected)"; fi
}

check_exit 2 "missing --repo rejected"    --heading H --config /dev/null
check_exit 2 "missing --heading rejected" --repo r --config /dev/null
check_exit 2 "unknown flag rejected"      --repo r --heading H --config /dev/null --nope
check_exit 2 "missing config rejected"    --repo r --heading H --config "$WORK/nope.yml"

# --- the empty-map form, which is what a fresh config ships with -----------------------
cat >"$WORK/empty.yml" <<'EOF'
# leading comment
standup:
  github:
    org: shoptet
  repos: {}                       # github repo slug -> heading
  authors: {}
other: keep-me
EOF

"$SCRIPT" --repo partner-cli --heading "Shoptet addon CLI" --config "$WORK/empty.yml" >/dev/null 2>&1
"$SCRIPT" --repo cms4        --heading "Monorepo Shoptetu" --config "$WORK/empty.yml" >/dev/null 2>&1

grep -qx '    partner-cli: Shoptet addon CLI' "$WORK/empty.yml" \
  && pass "heading written into empty map" || bad "heading written into empty map"
grep -qx '    cms4: Monorepo Shoptetu' "$WORK/empty.yml" \
  && pass "second heading appended to block" || bad "second heading appended to block"
# The comment belongs on the repos: line. It landed on a value line during the build; that is the bug.
grep -qx '  repos:  # github repo slug -> heading' "$WORK/empty.yml" \
  && pass "trailing comment stays on the repos line" || bad "trailing comment stays on the repos line"
grep -qx '# leading comment' "$WORK/empty.yml" && pass "leading comment preserved" \
  || bad "leading comment preserved"
grep -qx 'other: keep-me' "$WORK/empty.yml" && pass "keys outside standup untouched" \
  || bad "keys outside standup untouched"
grep -qx '  authors: {}' "$WORK/empty.yml" && pass "sibling keys untouched" \
  || bad "sibling keys untouched"

# A heading corrected by hand must survive the next morning's run.
"$SCRIPT" --repo cms4 --heading "Something else entirely" --config "$WORK/empty.yml" >/dev/null 2>&1
got=$?
grep -qx '    cms4: Monorepo Shoptetu' "$WORK/empty.yml" \
  && pass "existing heading not overwritten" || bad "existing heading not overwritten"
grep -q 'Something else entirely' "$WORK/empty.yml" \
  && bad "no second entry for the same repo" || pass "no second entry for the same repo"
[[ "$got" == 0 ]] && pass "already-cached repo exits 0" || bad "already-cached repo exits 0 (got $got)"

# --- headings YAML would misread ------------------------------------------------------
"$SCRIPT" --repo weird --heading 'no: really # yes' --config "$WORK/empty.yml" >/dev/null 2>&1
grep -qx '    weird: "no: really # yes"' "$WORK/empty.yml" \
  && pass "ambiguous heading quoted" || bad "ambiguous heading quoted"

# --- the block form, once a heading already exists ------------------------------------
cat >"$WORK/block.yml" <<'EOF'
standup:
  repos:
    partner-cli: Shoptet addon CLI
  authors: {}
EOF
"$SCRIPT" --repo cms4 --heading "Monorepo Shoptetu" --config "$WORK/block.yml" >/dev/null 2>&1
grep -qx '    cms4: Monorepo Shoptetu' "$WORK/block.yml" \
  && pass "heading appended inside existing block" || bad "heading appended inside existing block"
grep -qx '  authors: {}' "$WORK/block.yml" \
  && pass "block insert lands above the next key" || bad "block insert lands above the next key"

# --- a config with nowhere to write ---------------------------------------------------
printf 'standup:\n  github:\n    org: shoptet\n' >"$WORK/norepos.yml"
before="$(cat "$WORK/norepos.yml")"
check_exit 5 "config without standup.repos exits 5" --repo x --heading y --config "$WORK/norepos.yml"
[[ "$(cat "$WORK/norepos.yml")" == "$before" ]] \
  && pass "failed write leaves the config alone" || bad "failed write leaves the config alone"

printf 'other: thing\n' >"$WORK/nostandup.yml"
check_exit 5 "config without standup exits 5" --repo x --heading y --config "$WORK/nostandup.yml"

# --- an unwritable config -------------------------------------------------------------
cp "$WORK/block.yml" "$WORK/ro.yml"
chmod 400 "$WORK/ro.yml"
if [[ -w "$WORK/ro.yml" ]]; then
  echo "skip: unwritable-config check (running as a user that ignores the mode bits)"
else
  check_exit 4 "unwritable config exits 4" --repo x --heading y --config "$WORK/ro.yml"
fi

exit $fail
