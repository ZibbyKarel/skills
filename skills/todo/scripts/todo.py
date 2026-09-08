#!/usr/bin/env python3
"""CRUD over a project's TODO.md checklist. See ../SKILL.md for the command contract."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlsplit

ITEM_RE = re.compile(r"^(?:[-*]|\d+\.) \[([ xX])\] (.*)$")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*?)\s*$")
ISSUE_KEY_RE = re.compile(r"\b([A-Z][A-Z0-9]*-\d+)\b")
HEADER = "# TODO\n"
SECTION_LEVEL = 2


def find_todo_path() -> Path:
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        )
        root = Path(out.stdout.strip())
    except (subprocess.CalledProcessError, FileNotFoundError):
        root = Path.cwd()
    return root / "TODO.md"


def read_lines(path: Path) -> list[str]:
    if not path.exists():
        return []
    return path.read_text(encoding="utf-8").splitlines(keepends=True)


def find_items(lines: list[str]) -> list[tuple[int, bool, str]]:
    """Returns (line_index, checked, text) for every checklist line, in file order.

    Headings are invisible here on purpose: item numbers stay positional over the whole file, so
    inserting a section heading never renumbers the items below it. A legacy `-`/`*` bullet still
    counts as an item so old TODO.md files keep working, but any line this script writes uses the
    numbered `N. [ ]` form (see `renumber_all`).
    """
    items = []
    for i, line in enumerate(lines):
        m = ITEM_RE.match(line.rstrip("\r\n"))
        if m:
            items.append((i, m.group(1).lower() == "x", m.group(2)))
    return items


def renumber_all(lines: list[str]) -> None:
    """Rewrites every checklist line in place as `N. [ ]`/`N. [x]`, N counting file order.

    Called after any insertion, since that's the only operation that can shift what number a
    line other than the one just touched should have.
    """
    for n, (idx, checked, text) in enumerate(find_items(lines), start=1):
        mark = "x" if checked else " "
        lines[idx] = f"{n}. [{mark}] {text}\n"


def _heading(line: str) -> tuple[int, str] | None:
    """Returns (level, text) for a Markdown ATX heading line, else None."""
    m = HEADING_RE.match(line.rstrip("\r\n"))
    if not m:
        return None
    return len(m.group(1)), m.group(2)


def _section_matches(existing: str, wanted: str) -> bool:
    """A section is identified by the issue key in its heading, falling back to its exact text.

    The key is what survives a reworded epic title, which is why `zibby:plan-to-backlog` puts it
    in the heading in the first place.
    """
    wanted_key = ISSUE_KEY_RE.search(wanted)
    if wanted_key:
        return wanted_key.group(1) in ISSUE_KEY_RE.findall(existing)
    return existing.strip() == wanted.strip()


def find_section(lines: list[str], section: str) -> tuple[int, int] | None:
    """Returns (heading_index, insert_index) for the named section, or None if it isn't there.

    `insert_index` is where a new item belongs: after the section's last item, before the blank
    lines that separate it from whatever heading comes next.
    """
    for i, line in enumerate(lines):
        head = _heading(line)
        if not head or not _section_matches(head[1], section):
            continue
        level = head[0]
        end = len(lines)
        for j in range(i + 1, len(lines)):
            nxt = _heading(lines[j])
            if nxt and nxt[0] <= level:
                end = j
                break
        while end > i + 1 and lines[end - 1].strip() == "":
            end -= 1
        return i, end
    return None


def cmd_add(path: Path, text: str, ref: str | None, section: str | None) -> None:
    lines = read_lines(path)
    if not lines:
        lines = [HEADER, "\n"]
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"

    item = f"- [ ] {text}{_ref_suffix(ref)}\n"
    note = ""

    if section is None:
        insert_at = len(lines)
        lines.append(item)
    else:
        found = find_section(lines, section)
        if found:
            insert_at = found[1]
            lines.insert(insert_at, item)
        else:
            heading = section.strip().lstrip("#").strip()
            if lines[-1].strip() != "":
                lines.append("\n")
            lines.append(f"{'#' * SECTION_LEVEL} {heading}\n")
            lines.append("\n")
            insert_at = len(lines)
            lines.append(item)
            note = f" (new section: {heading})"

    renumber_all(lines)
    path.write_text("".join(lines), encoding="utf-8")
    n = next(k for k, (idx, _, _) in enumerate(find_items(lines), start=1) if idx == insert_at)
    print(f"added #{n}: {text}{_ref_suffix(ref)}{note}")


def cmd_list(path: Path) -> None:
    items = find_items(read_lines(path))
    if not items:
        print("no items in TODO.md")
        return
    for n, (_, checked, text) in enumerate(items, start=1):
        mark = "x" if checked else " "
        print(f"{n}. [{mark}] {text}")


def cmd_next(path: Path) -> None:
    items = find_items(read_lines(path))
    for n, (_, checked, text) in enumerate(items, start=1):
        if not checked:
            print(f"{n}. {text}")
            return
    print("no pending items")


def cmd_show(path: Path, n: int) -> None:
    items = find_items(read_lines(path))
    if not 1 <= n <= len(items):
        sys.exit(f"item {n} does not exist ({len(items)} item(s) total)")
    print(items[n - 1][2])


def _ref_suffix(ref: str | None) -> str:
    if not ref:
        return ""
    if "://" in ref:
        segments = [s for s in urlsplit(ref).path.split("/") if s]
        label = segments[-1] if segments else ref
        return f" ([{label}]({ref}))"
    return f" ({ref})"


def cmd_done(path: Path, n: int, ref: str | None) -> None:
    lines = read_lines(path)
    items = find_items(lines)
    if not 1 <= n <= len(items):
        sys.exit(f"item {n} does not exist ({len(items)} item(s) total)")
    line_idx, _, text = items[n - 1]
    lines[line_idx] = f"{n}. [x] {text}{_ref_suffix(ref)}\n"
    path.write_text("".join(lines), encoding="utf-8")
    print(f"done #{n}: {text}{_ref_suffix(ref)}")


def cmd_undone(path: Path, n: int) -> None:
    lines = read_lines(path)
    items = find_items(lines)
    if not 1 <= n <= len(items):
        sys.exit(f"item {n} does not exist ({len(items)} item(s) total)")
    line_idx, _, text = items[n - 1]
    lines[line_idx] = f"{n}. [ ] {text}\n"
    path.write_text("".join(lines), encoding="utf-8")
    print(f"undone #{n}: {text}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p_add = sub.add_parser("add")
    p_add.add_argument("text")
    p_add.add_argument("--ref", default=None,
                       help="a URL or plain reference appended to the item, same format as `done`")
    p_add.add_argument("--section", default=None,
                       help="heading text to file the item under; matched by the issue key it "
                            "contains, and created at the end of the file if absent")

    sub.add_parser("list")
    sub.add_parser("next")

    p_show = sub.add_parser("show")
    p_show.add_argument("n", type=int)

    p_done = sub.add_parser("done")
    p_done.add_argument("n", type=int)
    p_done.add_argument("ref", nargs="?", default=None)

    p_undone = sub.add_parser("undone")
    p_undone.add_argument("n", type=int)

    args = parser.parse_args()
    path = find_todo_path()

    if args.command == "add":
        cmd_add(path, args.text, args.ref, args.section)
    elif args.command == "list":
        cmd_list(path)
    elif args.command == "next":
        cmd_next(path)
    elif args.command == "show":
        cmd_show(path, args.n)
    elif args.command == "done":
        cmd_done(path, args.n, args.ref)
    elif args.command == "undone":
        cmd_undone(path, args.n)


if __name__ == "__main__":
    main()
