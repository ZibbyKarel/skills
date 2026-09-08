#!/usr/bin/env bash
# Fails if any skill still refers to a sibling by its pre-marketplace name,
# or if the todo script path is not plugin-relative.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
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
check_present '^name: plan-to-backlog$'         skills/plan-to-backlog/SKILL.md         'plan-to-backlog skill name intact'
check_present 'CLAUDE_PLUGIN_ROOT'              skills/todo/SKILL.md                    'todo script path is plugin-relative'
check_present 'zibby:jira'                      skills/todo-driven-development/SKILL.md 'tdd points at zibby:jira'
check_present 'zibby:todo'                      skills/todo-driven-development/SKILL.md 'tdd points at zibby:todo'
check_present 'zibby:todo-driven-development'   skills/jira/SKILL.md                    'jira points at zibby:todo-driven-development'
check_present 'zibby:jira'                     skills/plan-to-backlog/SKILL.md         'plan-to-backlog points at zibby:jira'
check_present 'zibby:todo'                     skills/plan-to-backlog/SKILL.md         'plan-to-backlog points at zibby:todo'
check_present 'zibby:plan-to-backlog'          skills/todo-driven-development/SKILL.md 'tdd knows about zibby:plan-to-backlog'
check_present 'CLAUDE_PLUGIN_ROOT'             skills/plan-to-backlog/SKILL.md         'plan-to-backlog todo path is plugin-relative'
check_present 'chunking\.md'                    skills/plan-to-backlog/SKILL.md         'plan-to-backlog reads its chunking rules'
check_present 'references/sprint\.md'          skills/jira/SKILL.md                    'jira reads its sprint procedure'
check_present 'references/sprint\.md'          skills/todo-driven-development/SKILL.md 'tdd reads the same sprint procedure'
check_present 'Unverified'                     skills/plan-to-backlog/SKILL.md         'the Blocks-direction caveat is still recorded'

# The reference file the granularity rule lives in must exist — the skill has no other rule.
if [[ -f skills/plan-to-backlog/references/chunking.md ]]; then
  echo "ok:   chunking rules file present"
else
  echo "FAIL: chunking rules file present"
  fail=1
fi

# Two skills point at the sprint procedure; if the file goes missing they both silently improvise
# a custom field id, which is the one thing it exists to forbid.
if [[ -f skills/jira/references/sprint.md ]]; then
  echo "ok:   sprint procedure file present"
else
  echo "FAIL: sprint procedure file present"
  fail=1
fi

# The chunking rules are a generic procedure. Naming a specific repo, PR number or phase letter
# from someone else's project makes them unreadable for anyone who wasn't there.
check_absent_in() {
  local pattern="$1" file="$2" label="$3"
  if grep -qnE "$pattern" "$file"; then
    echo "FAIL: $label"
    grep -nE "$pattern" "$file" | sed 's/^/    /'
    fail=1
  else
    echo "ok:   $label"
  fi
}
check_absent_in '(PR #[0-9]|Phase 2[a-z]\b|[a-z0-9-]+/[a-z0-9-]+-cli)' \
  skills/plan-to-backlog/references/chunking.md \
  'chunking rules stay generic (no foreign repo, PR or phase references)'

exit $fail
