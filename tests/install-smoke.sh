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
