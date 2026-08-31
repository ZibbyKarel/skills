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
