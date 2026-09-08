#!/usr/bin/env bash
# Exercises skills/todo/scripts/todo.py in a throwaway git repo.
# The interesting cases are the ones section headings introduce: `add` no longer just appends to
# EOF, and item numbering must stay indifferent to headings appearing above an item.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
SCRIPT="$PWD/skills/todo/scripts/todo.py"
fail=0

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

todo() { (cd "$work" && python3 "$SCRIPT" "$@"); }
reset_repo() {
  rm -rf "$work"
  mkdir -p "$work"
  (cd "$work" && git init -q .)
}

expect() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "ok:   $label"
  else
    echo "FAIL: $label"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    fail=1
  fi
}

expect_file() {
  local label="$1" expected="$2"
  local actual
  actual="$(cat "$work/TODO.md")"
  if [[ "$expected" == "$actual" ]]; then
    echo "ok:   $label"
  else
    echo "FAIL: $label"
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed 's/^/    /'
    fail=1
  fi
}

# --- add --ref renders the same link format `done` already produces -------------------------
reset_repo
todo add "First item" --ref "https://teamdotblue.atlassian.net/browse/CZ3TDR1-601" >/dev/null
todo add "Second item" >/dev/null
todo done 2 "https://teamdotblue.atlassian.net/browse/CZ3TDR1-602" >/dev/null
pending="$(sed -n '3p' "$work/TODO.md")"
closed="$(sed -n '4p' "$work/TODO.md")"
expect "add --ref link format" \
  "1. [ ] First item ([CZ3TDR1-601](https://teamdotblue.atlassian.net/browse/CZ3TDR1-601))" "$pending"
expect "done ref link format unchanged" \
  "2. [x] Second item ([CZ3TDR1-602](https://teamdotblue.atlassian.net/browse/CZ3TDR1-602))" "$closed"

reset_repo
todo add "Plain ref" --ref "see ADR 0064" >/dev/null
expect "add --ref non-URL" "1. [ ] Plain ref (see ADR 0064)" "$(sed -n '3p' "$work/TODO.md")"

# --- add --section creates the section, then files into it ----------------------------------
reset_repo
todo add "Chunk one" --section "Phase Portal ([CZ3TDR1-500](https://example.test/browse/CZ3TDR1-500))" >/dev/null
todo add "Chunk two" --section "Phase Portal ([CZ3TDR1-500](https://example.test/browse/CZ3TDR1-500))" >/dev/null
expect_file "section created once, both items under it" "$(cat <<'EOF'
# TODO

## Phase Portal ([CZ3TDR1-500](https://example.test/browse/CZ3TDR1-500))

1. [ ] Chunk one
2. [ ] Chunk two
EOF
)"

# --- a re-run finds the section by issue key, not by heading text ---------------------------
todo add "Chunk three" --section "Phase Portal, renamed ([CZ3TDR1-500](https://example.test/browse/CZ3TDR1-500))" >/dev/null
expect_file "reworded heading still matches on the issue key" "$(cat <<'EOF'
# TODO

## Phase Portal ([CZ3TDR1-500](https://example.test/browse/CZ3TDR1-500))

1. [ ] Chunk one
2. [ ] Chunk two
3. [ ] Chunk three
EOF
)"

# --- an item goes before the NEXT heading, not to EOF ---------------------------------------
reset_repo
todo add "A1" --section "Epic A ([AAA-1](https://example.test/browse/AAA-1))" >/dev/null
todo add "B1" --section "Epic B ([BBB-2](https://example.test/browse/BBB-2))" >/dev/null
todo add "A2" --section "Epic A ([AAA-1](https://example.test/browse/AAA-1))" >/dev/null
expect_file "insert lands at the end of its own section" "$(cat <<'EOF'
# TODO

## Epic A ([AAA-1](https://example.test/browse/AAA-1))

1. [ ] A1
2. [ ] A2

## Epic B ([BBB-2](https://example.test/browse/BBB-2))

3. [ ] B1
EOF
)"
expect "numbering follows file order across sections" "1. [ ] A1
2. [ ] A2
3. [ ] B1" "$(todo list)"

# --- numbering is unaffected by a heading inserted above an item ----------------------------
reset_repo
todo add "Loose item" >/dev/null
before="$(todo show 1)"
todo add "Sectioned item" --section "Later epic ([CCC-3](https://example.test/browse/CCC-3))" >/dev/null
expect "item 1 still points at the same line after a heading was added" "$before" "$(todo show 1)"
expect "the sectioned item is item 2" "Sectioned item" "$(todo show 2)"
todo done 1 >/dev/null
expect "next skips the closed item, headings and all" "2. Sectioned item" "$(todo next)"

# --- done/undone still address the right line once sections exist ---------------------------
todo done 2 "https://example.test/pull/42" >/dev/null
expect "done inside a section" \
  "2. [x] Sectioned item ([42](https://example.test/pull/42))" "$(tail -1 "$work/TODO.md")"
# `undone` only flips the checkbox — the ref stays, which is now a legitimate state for a
# pending item since `add --ref` puts one there in the first place.
todo undone 2 >/dev/null
expect "undone keeps the ref, flips only the box" \
  "2. [ ] Sectioned item ([42](https://example.test/pull/42))" "$(tail -1 "$work/TODO.md")"

exit $fail
