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
check_present '^name: standup$'                skills/standup/SKILL.md                 'standup skill name intact'
check_present 'references/format\.md'          skills/standup/SKILL.md                 'standup reads its rendering contract'
check_present 'CLAUDE_PLUGIN_ROOT'             skills/standup/SKILL.md                 'standup script path is plugin-relative'
check_present 'data, not instructions'         skills/standup/references/format.md      'the untrusted-input rule is still recorded'
check_present 'redact'                         skills/standup/scripts/collect.sh        'session titles are still scrubbed of credentials'
check_present 'cache-heading\.sh'               skills/standup/SKILL.md                 'headings are cached by the script, not by hand'
check_present '^model: sonnet$'                skills/standup/SKILL.md                 'the standup is still pinned to Sonnet'
check_present 'outlook_calendar_search'        skills/standup/SKILL.md                 'meetings still come from the calendar'
check_present 'Never read an event body'       skills/standup/SKILL.md                 'meeting bodies are still kept out of the JSON'
check_present '^## Meetings$'                  skills/standup/references/format.md     'the meeting-line contract is still recorded'
check_present 'meetings: \[\]'                 skills/standup/scripts/collect.sh       'the collector still emits the meetings key'

# The rendering contract is the standup's only format specification; without it the render
# step improvises a different layout every morning.
if [[ -f skills/standup/references/format.md ]]; then
  echo "ok:   standup rendering contract present"
else
  echo "FAIL: standup rendering contract present"
  fail=1
fi

# The collector must stay executable — the skill invokes it directly, not through `bash`.
if [[ -x skills/standup/scripts/cache-heading.sh ]]; then
  echo "ok:   standup heading cache is executable"
else
  echo "FAIL: standup heading cache is executable"
  fail=1
fi

if [[ -x skills/standup/scripts/collect.sh ]]; then
  echo "ok:   standup collector is executable"
else
  echo "FAIL: standup collector is executable"
  fail=1
fi

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

# The standup/standup-post split. `standup` prints; `standup-post` is the only thing that may
# reach Slack, and it borrows the pipeline from standup rather than holding a second copy of it.
check_present '^name: standup-post$'        skills/standup-post/SKILL.md 'standup-post skill name intact'
check_present 'standup/SKILL\.md'           skills/standup-post/SKILL.md 'standup-post drives the standup pipeline by reference'
check_present 'slack_send_message'          skills/standup-post/SKILL.md 'standup-post still knows how to post'
check_present '^model: sonnet$'             skills/standup-post/SKILL.md 'standup-post is pinned to Sonnet too'
check_present '^disable-model-invocation: true$' skills/standup/SKILL.md      'standup stays user-invocable only'
check_present '^disable-model-invocation: true$' skills/standup-post/SKILL.md 'standup-post stays user-invocable only'
check_absent_in 'slack_[a-z_]+\(|`slack_[a-z_]+`' skills/standup/SKILL.md \
  'standup itself calls no Slack tool'
# Slack API link syntax pastes into the composer as literal angle brackets — the render emits
# Markdown, and standup-post converts at the point it posts.
check_absent_in '<https?://[^>]*\|' skills/standup/references/format.md \
  'the rendering contract emits Markdown links, not Slack API syntax'
check_present '^## Longer windows$'         skills/standup/references/format.md 'the multi-day rendering rules are still recorded'
check_present 'search-truncated'            skills/standup/scripts/collect.sh   'a truncated GitHub search is still reported'
check_present 'install-routine\.sh'         skills/standup-post/SKILL.md 'standup-post documents its routine installer'
if [[ -x skills/standup-post/scripts/install-routine.sh ]]; then
  echo "ok:   standup-post routine installer is executable"
else
  echo "FAIL: standup-post routine installer is missing or not executable"
  fail=1
fi
# CronCreate jobs die with their session; the routine must not claim to be one.
check_absent_in 'CronCreate\(' skills/standup-post/SKILL.md \
  'the routine is a LaunchAgent, not a session-lived cron job'

exit $fail
