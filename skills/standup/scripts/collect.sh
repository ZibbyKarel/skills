#!/usr/bin/env bash
# Collects one standup window's raw material into a single JSON document:
# the PRs you opened or merged, the PRs you reviewed or commented on, and the
# Claude Code sessions you ran. Facts only — no prose, no judgement, no ordering
# beyond what the data carries. The rendering step reads this file.
#
# `.meetings` is emitted empty: the calendar lives behind an MCP tool with no CLI, so the
# skill fills that key in after this script runs.
#
#   collect.sh --org shoptet --login ZibbyKarel \
#              --from 2026-09-08T18:00:00Z --to 2026-09-09T05:15:00Z \
#              [--out path.json] [--sessions-dir DIR]
#
# Exit codes: 0 collected, 2 bad arguments, 3 GitHub unreachable.
# A GitHub failure is fatal; unreadable sessions are not — they land in .notes.
set -uo pipefail

ORG=""
LOGIN=""
FROM=""
TO=""
OUT=""
SESSIONS_DIR="${HOME}/.claude/projects"
MIN_MESSAGES=10
EXCLUDE_REPOS=()

die() {
  printf 'collect.sh: %s\n' "$1" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)          ORG="${2:-}";          shift 2 ;;
    --login)        LOGIN="${2:-}";        shift 2 ;;
    --from)         FROM="${2:-}";         shift 2 ;;
    --to)           TO="${2:-}";           shift 2 ;;
    --out)          OUT="${2:-}";          shift 2 ;;
    --sessions-dir) SESSIONS_DIR="${2:-}"; shift 2 ;;
    --min-messages) MIN_MESSAGES="${2:-}"; shift 2 ;;
    --exclude-repo) EXCLUDE_REPOS+=("${2:-}");  shift 2 ;;
    -h|--help)      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)              die "unknown argument: $1" ;;
  esac
done

[[ -n "$ORG"   ]] || die "--org is required"
[[ -n "$LOGIN" ]] || die "--login is required"
[[ -n "$FROM"  ]] || die "--from is required (ISO 8601 UTC, e.g. 2026-09-08T18:00:00Z)"
[[ -n "$TO"    ]] || die "--to is required (ISO 8601 UTC)"
command -v gh >/dev/null 2>&1 || die "gh not on PATH"
command -v jq >/dev/null 2>&1 || die "jq not on PATH"

# ISO 8601 UTC strings sort lexicographically, so every window comparison below is a
# plain string compare. Anything not ending in Z would break that silently.
[[ "$FROM" == *Z ]] || die "--from must be UTC and end in Z"
[[ "$TO"   == *Z ]] || die "--to must be UTC and end in Z"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
: >"$WORK/notes"

note() { printf '%s\n' "$1" >>"$WORK/notes"; }

# GitHub's search date qualifiers are day-granular while the window is timestamp-granular,
# so search wide by date and filter exactly, per item, further down.
FROM_DATE="${FROM%%T*}"
TO_DATE="${TO%%T*}"
RANGE="${FROM_DATE}..${TO_DATE}"

in_window() { # in_window <iso-timestamp>
  local t="${1:-}"
  [[ -n "$t" && "$t" != "null" ]] || return 1
  [[ "$t" > "$FROM" || "$t" == "$FROM" ]] || return 1
  [[ "$t" < "$TO"   || "$t" == "$TO"   ]] || return 1
}

gh_fatal() {
  printf 'collect.sh: GH_UNAVAILABLE: %s\n' "$1" >&2
  exit 3
}

jira_key_from() { # jira_key_from <branch> <title>
  # Not anchored to the start: Jira's own GitHub integration recognizes an issue key
  # anywhere in the branch name or title (e.g. "karel/CZ3TDR1-630-fix-thing"), so a
  # PR with an issue genuinely attached in Jira must still resolve here — otherwise
  # the render falls back to the PR number, which is the bug this fixes.
  local branch="${1:-}" title="${2:-}" key=""
  key="$(printf '%s' "$branch" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -1)"
  if [[ -z "$key" ]]; then
    key="$(printf '%s' "$title" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -1)"
  fi
  printf '%s' "$key"
}

# ---------------------------------------------------------------- own pull requests
#
# Two searches, because "yesterday's work" is either a PR that came into existence in the
# window or one that got merged in it — a PR opened last week and merged yesterday is
# yesterday's work, and searching only on creation drops it.

search_prs() { # search_prs <flag...> — one search, JSON array or fatal
  local out
  out="$(gh search prs --owner "$ORG" --limit 100 "$@" 2>&1)" || gh_fatal "$out"
  printf '%s' "$out"
}

created_raw="$(search_prs --author "$LOGIN" --created "$RANGE" \
  --json number,repository,title,url,state,createdAt,author)"
merged_raw="$(search_prs --author "$LOGIN" --merged --merged-at "$RANGE" \
  --json number,repository,title,url,state,createdAt,closedAt,author)"

# Candidate set as "owner/repo<TAB>number" lines, deduped: the same PR can appear in both
# searches, and it must produce exactly one entry in the output.
printf '%s\n%s\n' "$created_raw" "$merged_raw" \
  | jq -r '.[]? | "\(.repository.nameWithOwner)\t\(.number)"' \
  | sort -u >"$WORK/own-candidates"

: >"$WORK/created.jsonl"
while IFS=$'\t' read -r nwo number; do
  [[ -n "${number:-}" ]] || continue
  view="$(gh pr view "$number" --repo "$nwo" \
    --json number,title,url,state,headRefName,createdAt,mergedAt,isDraft 2>&1)" \
    || { note "pull request $nwo#$number could not be read: $view"; continue; }

  created_at="$(printf '%s' "$view" | jq -r '.createdAt // ""')"
  merged_at="$(printf '%s' "$view"  | jq -r '.mergedAt // ""')"
  branch="$(printf '%s' "$view"     | jq -r '.headRefName // ""')"
  title="$(printf '%s' "$view"      | jq -r '.title // ""')"

  # `merged` wins over `created` for a PR that did both inside the window: the standup
  # should say the work shipped, not that it was opened.
  if in_window "$merged_at"; then
    action="merged"; at="$merged_at"
  elif in_window "$created_at"; then
    action="created"; at="$created_at"
  else
    continue
  fi

  key="$(jira_key_from "$branch" "$title")"
  printf '%s' "$view" | jq -c \
    --arg repo "${nwo##*/}" --arg nwo "$nwo" --arg action "$action" \
    --arg at "$at" --arg key "$key" '
    {
      repo:     $repo,
      number:   .number,
      title:    .title,
      url:      .url,
      branch:   (.headRefName // null),
      state:    (if .isDraft then "draft" else (.state | ascii_downcase) end),
      action:   $action,
      at:       $at,
      jiraKey:  (if $key == "" then null else $key end),
      jiraUrl:  null
    }' >>"$WORK/created.jsonl"
done <"$WORK/own-candidates"

# ------------------------------------------------------------------ review activity
#
# Candidates from two searches again — a formal review and a bare comment are different
# GitHub events, and a day spent only leaving remarks without pressing "Submit review"
# is still a day of review work. Both searches filter on the PR's last-updated date,
# which is coarse; the per-PR pass below is what establishes that *you* did something
# inside the window.

reviewed_raw="$(search_prs --reviewed-by "$LOGIN" --updated "$RANGE" \
  --json number,repository,author)"
commented_raw="$(search_prs --commenter "$LOGIN" --updated "$RANGE" \
  --json number,repository,author)"

# Self-authored PRs drop out here: --reviewed-by and --commenter both match your own PRs,
# and your own comments on your own PR are not code review.
printf '%s\n%s\n' "$reviewed_raw" "$commented_raw" \
  | jq -r --arg me "$LOGIN" '
      .[]? | select((.author.login // "") != $me)
      | "\(.repository.nameWithOwner)\t\(.number)"' \
  | sort -u >"$WORK/review-candidates"

: >"$WORK/authors"
author_name() { # author_name <login> — display name, cached, login as fallback
  local login="$1" cached name
  cached="$(grep -m1 "^${login}	" "$WORK/authors" 2>/dev/null | cut -f2-)"
  if [[ -n "$cached" ]]; then printf '%s' "$cached"; return; fi
  name="$(gh api "users/${login}" --jq '.name // ""' 2>/dev/null)"
  if [[ -z "$name" ]]; then
    name="$login"
    note "github login '$login' has no display name set; using the login verbatim — add an override under standup.authors"
  fi
  printf '%s\t%s\n' "$login" "$name" >>"$WORK/authors"
  printf '%s' "$name"
}

: >"$WORK/contributed.jsonl"
while IFS=$'\t' read -r nwo number; do
  [[ -n "${number:-}" ]] || continue
  owner="${nwo%%/*}"
  repo="${nwo##*/}"

  # Three endpoints, because review activity lands in three different places.
  reviews="$(gh api "repos/${nwo}/pulls/${number}/reviews" --paginate 2>/dev/null \
    | jq -c --arg me "$LOGIN" '[.[]? | select(.user.login == $me)
        | {at: .submitted_at, state: .state, kind: "review"}]' 2>/dev/null || echo '[]')"
  inline="$(gh api "repos/${nwo}/pulls/${number}/comments" --paginate 2>/dev/null \
    | jq -c --arg me "$LOGIN" '[.[]? | select(.user.login == $me)
        | {at: .created_at, state: null, kind: "inline"}]' 2>/dev/null || echo '[]')"
  convo="$(gh api "repos/${nwo}/issues/${number}/comments" --paginate 2>/dev/null \
    | jq -c --arg me "$LOGIN" '[.[]? | select(.user.login == $me)
        | {at: .created_at, state: null, kind: "comment"}]' 2>/dev/null || echo '[]')"

  acts="$(jq -c -n --argjson a "$reviews" --argjson b "$inline" --argjson c "$convo" \
    --arg from "$FROM" --arg to "$TO" '
      ($a + $b + $c)
      | map(select(.at != null and .at >= $from and .at <= $to))
      | sort_by(.at)')"
  [[ "$(printf '%s' "$acts" | jq 'length')" -gt 0 ]] || continue

  view="$(gh pr view "$number" --repo "$nwo" \
    --json number,title,url,state,headRefName,author,isDraft 2>&1)" \
    || { note "pull request $nwo#$number could not be read: $view"; continue; }

  pr_login="$(printf '%s' "$view" | jq -r '.author.login // ""')"
  [[ "$pr_login" != "$LOGIN" ]] || continue
  pr_author="$(author_name "$pr_login")"
  branch="$(printf '%s' "$view" | jq -r '.headRefName // ""')"
  title="$(printf '%s' "$view"  | jq -r '.title // ""')"
  key="$(jira_key_from "$branch" "$title")"

  printf '%s' "$view" | jq -c \
    --argjson acts "$acts" --arg repo "$repo" --arg owner "$owner" \
    --arg prAuthor "$pr_author" --arg prLogin "$pr_login" --arg key "$key" '
    {
      repo:          $repo,
      number:        .number,
      title:         .title,
      url:           .url,
      branch:        (.headRefName // null),
      prAuthorLogin: $prLogin,
      prAuthor:      $prAuthor,
      reviewStates:  ([$acts[] | select(.kind == "review") | .state] | unique),
      commentCount:  ([$acts[] | select(.kind != "review")] | length),
      at:            ($acts[0].at),
      jiraKey:       (if $key == "" then null else $key end),
      jiraUrl:       null
    }' >>"$WORK/contributed.jsonl"
done <"$WORK/review-candidates"

# ----------------------------------------------------------------- Claude sessions
#
# Filtered on entry timestamps rather than file mtime: a session resumed today still holds
# yesterday's work, and one written yesterday may not have been touched since. Only
# titles and metadata are read — never message bodies, which is what keeps transcript
# content out of a message bound for a team channel.

: >"$WORK/sessions.jsonl"
if [[ -d "$SESSIONS_DIR" ]]; then
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    dir="$(basename "$(dirname "$file")")"
    # Throwaway working directories: scratchpads and temp checkouts, never real work.
    case "$dir" in
      -private-tmp-claude-501-*|-private-var-folders-*|-tmp-*) continue ;;
    esac
    jq -s -c \
      --arg from "$FROM" --arg to "$TO" --arg file "$file" \
      --argjson min "$MIN_MESSAGES" '
      def inwin($t): $t != null and ($t | type) == "string" and $t >= $from and $t <= $to;
      # A session title is generated from whatever was in the transcript, so it can carry a
      # credential the user pasted while debugging — one real title in this repo was an
      # actual Slack bot token. Everything downstream of here is bound for a team channel,
      # so scrub the well-known secret shapes before they can ever reach it.
      def redact:
        if . == null then null else
          gsub("xox[abprse]-[A-Za-z0-9-]+";                      "[redacted]")
          | gsub("gh[pousr]_[A-Za-z0-9]{16,}";                   "[redacted]")
          | gsub("sk-[A-Za-z0-9_-]{16,}";                        "[redacted]")
          | gsub("AKIA[0-9A-Z]{16}";                             "[redacted]")
          | gsub("eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}";     "[redacted]")
          | gsub("-----BEGIN[A-Z ]*PRIVATE KEY-----";            "[redacted]")
          | gsub("[A-Za-z0-9_-]{40,}";                           "[redacted]")
        end;
      {
        session:      ($file | split("/") | last | sub("\\.jsonl$"; "")),
        aiTitle:      ([.[] | select(.type == "ai-title") | .aiTitle] | last | redact),
        lastPrompt:   ([.[] | select(.type == "last-prompt") | .lastPrompt] | last
                        | if . == null then null else (.[0:300] | redact) end),
        cwd:          ([.[] | select(.cwd != null) | .cwd] | last),
        gitBranch:    ([.[] | select(.gitBranch != null and .gitBranch != "") | .gitBranch] | last),
        messageCount: ([.[] | select((.type == "user" or .type == "assistant")
                          and (.isSidechain // false) == false and inwin(.timestamp))] | length),
        at:           ([.[] | select(inwin(.timestamp)) | .timestamp] | sort | first)
      }
      # Below the threshold a session is a stray question or a mistaken open, not work.
      | select(.messageCount >= $min)
      | . + {repo: (if .cwd == null then null else (.cwd | split("/") | last) end),
             relatedPr: null}' "$file" 2>/dev/null >>"$WORK/sessions.jsonl" \
      || note "session transcript $file could not be parsed"
  done < <(find "$SESSIONS_DIR" -mindepth 2 -maxdepth 2 -name '*.jsonl' 2>/dev/null)
else
  note "sessions directory $SESSIONS_DIR does not exist; no session material collected"
fi

# ------------------------------------------------------------------------- assemble
#
# relatedPr is set where a session's branch or Jira key matches a PR already collected.
# Marking beats dropping: the session often explains why the PR happened, and the render
# step can fold the two into one bullet — but nothing should read as two achievements.

jq -n \
  --slurpfile created     <(cat "$WORK/created.jsonl") \
  --slurpfile contributed <(cat "$WORK/contributed.jsonl") \
  --slurpfile sessions    <(cat "$WORK/sessions.jsonl") \
  --rawfile   notes       "$WORK/notes" \
  --arg from "$FROM" --arg to "$TO" --arg org "$ORG" --arg login "$LOGIN" \
  --argjson excluded "$(printf '%s\n' "${EXCLUDE_REPOS[@]+"${EXCLUDE_REPOS[@]}"}" \
    | jq -R 'select(length > 0)' | jq -s .)" '
  ($created     // []) as $c |
  ($contributed // []) as $r |
  ($sessions    // []) as $s |
  ($c + $r) as $prs |
  {
    window: {from: $from, to: $to, org: $org, login: $login},
    created: ($c | sort_by(.at)),
    contributed: ($r | sort_by(.at)),
    sessions: ($s
      | map(select(.repo == null or (.repo | IN($excluded[])) == false))
      | map(. as $sess
          | ($prs | map(select(. as $pr
              | $sess.gitBranch != null
                and ($pr.branch == $sess.gitBranch
                     or ($pr.jiraKey != null
                         and ($sess.gitBranch | startswith($pr.jiraKey))))
            )) | first) as $match
          | . + {relatedPr: (if $match == null then null
                             else {repo: $match.repo, number: $match.number} end)})
      | sort_by(.at)),
    repos: ($prs | map(.repo) | unique),
    # Meetings come from the calendar, which has no CLI — the skill fills this in after
    # collection (SKILL.md step 6). The key is emitted empty so the renderer can rely on it
    # existing whether or not the calendar was reachable.
    meetings: [],
    notes: ($notes | split("\n") | map(select(length > 0)))
  }' >"$WORK/out.json"

if [[ -n "$OUT" ]]; then
  mkdir -p "$(dirname "$OUT")" 2>/dev/null
  cp "$WORK/out.json" "$OUT" || die "could not write $OUT"
  printf '%s\n' "$OUT"
else
  cat "$WORK/out.json"
fi
