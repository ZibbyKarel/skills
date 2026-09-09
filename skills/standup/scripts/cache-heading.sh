#!/usr/bin/env bash
# Writes one repo -> heading pair into standup.repos in the global config, without
# disturbing anything else in the file.
#
#   cache-heading.sh --repo partner-cli --heading "Shoptet addon CLI" [--config PATH]
#
# Editing YAML by hand is the drift surface this exists to remove: a heading cached by
# reflowing the file loses comments, reorders keys, or lands a comment on the wrong line
# (all three happened while building this skill). Insertion here is line-based and
# idempotent — an existing key keeps its current value, because a heading the user has
# corrected must not be overwritten by a regenerated one.
#
# Exit codes: 0 written or already present, 2 bad arguments, 4 config not writable,
#             5 config has no standup.repos block to write into.
set -uo pipefail

REPO=""
HEADING=""
CONFIG="${HOME}/.zibby/zibby-skills/config.yml"

die() { printf 'cache-heading.sh: %s\n' "$1" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)    REPO="${2:-}";    shift 2 ;;
    --heading) HEADING="${2:-}"; shift 2 ;;
    --config)  CONFIG="${2:-}";  shift 2 ;;
    -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         die "unknown argument: $1" ;;
  esac
done

[[ -n "$REPO"    ]] || die "--repo is required"
[[ -n "$HEADING" ]] || die "--heading is required"
[[ -f "$CONFIG"  ]] || die "config not found: $CONFIG"
[[ -w "$CONFIG"  ]] || { printf 'cache-heading.sh: CONFIG_UNWRITABLE: %s\n' "$CONFIG" >&2; exit 4; }
command -v python3 >/dev/null 2>&1 || die "python3 not on PATH"

REPO="$REPO" HEADING="$HEADING" CONFIG="$CONFIG" python3 - <<'PY'
import os, re, sys

repo    = os.environ["REPO"]
heading = os.environ["HEADING"]
path    = os.environ["CONFIG"]

with open(path, encoding="utf-8") as fh:
    lines = fh.readlines()

# Locate `standup:`, then `repos:` nested directly under it. Anything outside that block
# is off limits — this script has no business touching the rest of the file.
standup = next((i for i, l in enumerate(lines) if re.match(r"^standup:\s*$", l)), None)
if standup is None:
    print("cache-heading.sh: no standup: key in " + path, file=sys.stderr)
    raise SystemExit(5)

end = len(lines)
for i in range(standup + 1, len(lines)):
    if lines[i].strip() and not lines[i].startswith((" ", "\t")):
        end = i
        break

repos = None
for i in range(standup + 1, end):
    if re.match(r"^  repos:", lines[i]):
        repos = i
        break
if repos is None:
    print("cache-heading.sh: no standup.repos key in " + path, file=sys.stderr)
    raise SystemExit(5)

# `repos: {}` is the empty form; replace it with a block mapping, keeping any trailing comment.
comment = ""
m = re.match(r"^  repos:\s*(\{\s*\})?\s*(#.*)?$", lines[repos].rstrip("\n"))
if m:
    comment = ("  " + m.group(2)) if m.group(2) else ""
    lines[repos] = "  repos:" + comment + "\n"

# Existing entries in the block, so an already-cached heading is left exactly as it is.
last = repos
for i in range(repos + 1, end):
    entry = re.match(r"^    ([A-Za-z0-9._-]+):", lines[i])
    if entry:
        if entry.group(1) == repo:
            print(f"unchanged: {repo} is already cached as {lines[i].split(':', 1)[1].strip()}")
            raise SystemExit(0)
        last = i
    elif lines[i].strip() == "" or re.match(r"^\s*#", lines[i]):
        continue
    else:
        break

# Quote the heading only when YAML would otherwise misread it.
value = heading
if re.search(r'^[\s>|&*!%@`\[\]{}#-]|[:#]\s|["\']|\s$', heading) or heading == "":
    value = '"' + heading.replace('\\', '\\\\').replace('"', '\\"') + '"'

lines.insert(last + 1, f"    {repo}: {value}\n")

tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    fh.writelines(lines)
os.replace(tmp, path)
print(f"cached: {repo} -> {heading}")
PY
