#!/usr/bin/env bash
# Exercises install.sh end to end. This IS destructive to real state on the
# machine it runs on: it deletes any real ~/.claude/skills/{todo,create-jira-
# issue,todo-driven-development} symlinks that point into this repo (the
# installer's legacy-symlink cleanup, auto-confirmed via --yes), and it
# registers the real zibby-skills marketplace with `claude` (removed again
# at the end unless it was already registered before this run). The plugin
# itself is only ever installed into a throwaway project directory, never
# at user scope.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
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

# Prove the pre-existing user-scope superpowers install (installed directly,
# not as a dependency of zibby) is there before we touch anything, so the
# post-cleanup assertion below has a real baseline instead of an assumption.
USER_SUPERPOWERS_BEFORE=0
if grep -q '"superpowers@claude-plugins-official": *true' "$HOME/.claude/settings.json" 2>/dev/null; then
  USER_SUPERPOWERS_BEFORE=1
fi

echo "== doctor-only runs and exits 0 or 1, never crashes =="
"$REPO/install.sh" --doctor-only --skip-mcp-check >"$TMP/doctor.log" 2>&1
rc=$?
if [ $rc -gt 1 ]; then echo "FAIL: doctor exited $rc"; cat "$TMP/doctor.log"; fail=1; else echo "ok"; fi

echo "== project-scope install resolves superpowers as a real dependency =="
mkdir -p "$TMP/proj"
( cd "$TMP/proj" && "$REPO/install.sh" --scope project --yes --skip-mcp-check ) >"$TMP/install.log" 2>&1
rc=$?
if [ $rc -ne 0 ]; then echo "FAIL: install exited $rc"; cat "$TMP/install.log"; fail=1; fi

# Assert on resolved state, not on the installer's own prose: install.sh
# prints "superpowers was pulled in automatically" unconditionally on any
# successful install, so grepping install.log for that text would only ever
# test our own echo. The settings.json written by `claude plugin install`
# is what actually reflects whether the dependency was resolved.
if grep -q '"superpowers@claude-plugins-official": *true' "$TMP/proj/.claude/settings.json" 2>/dev/null; then
  echo "ok:   superpowers resolved into project settings"
else
  echo "FAIL: superpowers not present in $TMP/proj/.claude/settings.json"
  cat "$TMP/proj/.claude/settings.json" 2>/dev/null
  fail=1
fi

if grep -q '"zibby@zibby-skills": *true' "$TMP/proj/.claude/settings.json" 2>/dev/null; then
  echo "ok:   zibby enabled in project settings"
else
  echo "FAIL: zibby missing from $TMP/proj/.claude/settings.json"
  cat "$TMP/proj/.claude/settings.json" 2>/dev/null
  fail=1
fi

echo "== re-running the same install is idempotent =="
( cd "$TMP/proj" && "$REPO/install.sh" --scope project --yes --skip-mcp-check ) >"$TMP/install2.log" 2>&1
rc=$?
if [ $rc -ne 0 ]; then
  echo "FAIL: second install exited $rc"
  cat "$TMP/install2.log"
  fail=1
else
  echo "ok:   second install exited 0"
fi
# Match only the marketplace-name line (a "<bullet> zibby-skills" heading),
# not e.g. a "Source: Directory (.../zibby-skills)" line — this repo's own
# path happens to end in "zibby-skills" too, which a plain substring grep
# would double-count.
mp_count="$(claude plugin marketplace list 2>/dev/null | grep -cE '(^|[[:space:]])zibby-skills$')"
if [ "$mp_count" -eq 1 ]; then
  echo "ok:   marketplace registered exactly once after repeat install"
else
  echo "FAIL: marketplace listed $mp_count times after repeat install (expected 1)"
  fail=1
fi
if grep -q '"zibby@zibby-skills": *true' "$TMP/proj/.claude/settings.json" 2>/dev/null; then
  echo "ok:   zibby still enabled in project settings after repeat install"
else
  echo "FAIL: zibby missing from project settings after repeat install"
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

# --prune only removes dependencies auto-installed for the plugin being
# uninstalled; superpowers at user scope was installed directly, before
# this test ever ran, so it must survive. Prove it rather than assume it.
if [ "$USER_SUPERPOWERS_BEFORE" -eq 1 ]; then
  if grep -q '"superpowers@claude-plugins-official": *true' "$HOME/.claude/settings.json" 2>/dev/null; then
    echo "ok:   user-scope superpowers install survived --prune"
  else
    echo "FAIL: user-scope superpowers install was removed by cleanup"
    fail=1
  fi
else
  echo "ok:   no pre-existing user-scope superpowers install to check"
fi

exit $fail
