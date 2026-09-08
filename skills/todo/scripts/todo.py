#!/usr/bin/env python3
"""CRUD over a project's TODO.md checklist. See ../SKILL.md for the command contract."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import urlsplit

ITEM_RE = re.compile(r"^(?:[-*]|\d+\.) \[([ xX])\] (.*)$")
SUBITEM_RE = re.compile(r"^   [a-z]\. \[([ xX])\] (.*)$")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*?)\s*$")
ISSUE_KEY_RE = re.compile(r"\b([A-Z][A-Z0-9]*-\d+)\b")
HEADER = "# TODO\n"
SECTION_LEVEL = 2
SUB_INDENT = "   "


@dataclass
class SubItem:
    line_idx: int
    checked: bool
    text: str


@dataclass
class TopItem:
    line_idx: int
    checked: bool
    text: str
    subitems: list[SubItem] = field(default_factory=list)


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


def find_top_items(lines: list[str]) -> list[TopItem]:
    """Returns every top-level checklist item, in file order, each carrying its sub-items.

    Headings are invisible here on purpose: item numbers stay positional over the whole file, so
    inserting a section heading never renumbers the items below it. A legacy `-`/`*` bullet still
    counts as a top-level item so old TODO.md files keep working, but any line this script writes
    uses the numbered `N. [ ]` form (see `renumber_all`).

    A run of `SUBITEM_RE` lines immediately following a top-level item's own line — no blank line,
    no other content in between — belongs to that item as its sub-items. Anything else
    (indentation without the checkbox marker, a blank line, prose) ends the run.
    """
    items: list[TopItem] = []
    i = 0
    while i < len(lines):
        m = ITEM_RE.match(lines[i].rstrip("\r\n"))
        if not m:
            i += 1
            continue
        top = TopItem(line_idx=i, checked=m.group(1).lower() == "x", text=m.group(2))
        i += 1
        while i < len(lines):
            sm = SUBITEM_RE.match(lines[i].rstrip("\r\n"))
            if not sm:
                break
            top.subitems.append(SubItem(line_idx=i, checked=sm.group(1).lower() == "x", text=sm.group(2)))
            i += 1
        items.append(top)
    return items


def renumber_all(lines: list[str]) -> None:
    """Rewrites every checklist line in place: top items as `N. [ ]`, sub-items as `letter. [ ]`.

    Called after any insertion, since that's the only operation that can shift what id a line
    other than the one just touched should have.
    """
    for n, top in enumerate(find_top_items(lines), start=1):
        mark = "x" if top.checked else " "
        lines[top.line_idx] = f"{n}. [{mark}] {top.text}\n"
        for k, sub in enumerate(top.subitems):
            letter = chr(ord("a") + k)
            if letter > "z":
                sys.exit(f"item {n} has more than 26 sub-items; letters run out past 'z'")
            sub_mark = "x" if sub.checked else " "
            lines[sub.line_idx] = f"{SUB_INDENT}{letter}. [{sub_mark}] {sub.text}\n"


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


def parse_id(s: str) -> tuple[int, str | None]:
    """Parses a `show`/`done`/`undone` id: a bare top-level number, or `N.letter` for a sub-item."""
    m = re.fullmatch(r"(\d+)(?:\.([a-z]))?", s)
    if not m:
        sys.exit(f"invalid item id: {s!r} (expected a number, or number.letter like 4.a)")
    return int(m.group(1)), m.group(2)


def _resolve(items: list[TopItem], top_n: int, sub_letter: str | None) -> tuple[TopItem, SubItem | None]:
    if not 1 <= top_n <= len(items):
        sys.exit(f"item {top_n} does not exist ({len(items)} item(s) total)")
    top = items[top_n - 1]
    if sub_letter is None:
        return top, None
    idx = ord(sub_letter) - ord("a")
    if not 0 <= idx < len(top.subitems):
        sys.exit(f"item {top_n} has no sub-item {sub_letter!r} ({len(top.subitems)} sub-item(s))")
    return top, top.subitems[idx]


def _ref_suffix(ref: str | None) -> str:
    if not ref:
        return ""
    if "://" in ref:
        segments = [s for s in urlsplit(ref).path.split("/") if s]
        label = segments[-1] if segments else ref
        return f" ([{label}]({ref}))"
    return f" ({ref})"


def cmd_add(path: Path, text: str, ref: str | None, section: str | None, under: int | None) -> None:
    lines = read_lines(path)
    if not lines:
        lines = [HEADER, "\n"]
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"

    if under is not None:
        if section is not None:
            sys.exit("--under and --section are mutually exclusive")
        items = find_top_items(lines)
        if not 1 <= under <= len(items):
            sys.exit(f"item {under} does not exist ({len(items)} item(s) total)")
        top = items[under - 1]
        insert_at = top.subitems[-1].line_idx + 1 if top.subitems else top.line_idx + 1
        lines.insert(insert_at, f"{SUB_INDENT}a. [ ] {text}{_ref_suffix(ref)}\n")
        renumber_all(lines)
        path.write_text("".join(lines), encoding="utf-8")
        new_top = find_top_items(lines)[under - 1]
        letter = chr(ord("a") + len(new_top.subitems) - 1)
        print(f"added #{under}.{letter}: {text}{_ref_suffix(ref)}")
        return

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
    n = next(k for k, top in enumerate(find_top_items(lines), start=1) if top.line_idx == insert_at)
    print(f"added #{n}: {text}{_ref_suffix(ref)}{note}")


def cmd_list(path: Path) -> None:
    items = find_top_items(read_lines(path))
    if not items:
        print("no items in TODO.md")
        return
    for n, top in enumerate(items, start=1):
        mark = "x" if top.checked else " "
        print(f"{n}. [{mark}] {top.text}")
        for k, sub in enumerate(top.subitems):
            letter = chr(ord("a") + k)
            sub_mark = "x" if sub.checked else " "
            print(f"{SUB_INDENT}{letter}. [{sub_mark}] {sub.text}")


def cmd_next(path: Path) -> None:
    items = find_top_items(read_lines(path))
    for n, top in enumerate(items, start=1):
        if not top.checked:
            print(f"{n}. {top.text}")
            return
    print("no pending items")


def cmd_show(path: Path, id_str: str) -> None:
    top_n, sub_letter = parse_id(id_str)
    items = find_top_items(read_lines(path))
    top, sub = _resolve(items, top_n, sub_letter)
    if sub is not None:
        print(sub.text)
        return
    print(top.text)
    for k, s in enumerate(top.subitems):
        letter = chr(ord("a") + k)
        print(f"  {letter}. {s.text}")


def cmd_done(path: Path, id_str: str, ref: str | None) -> None:
    lines = read_lines(path)
    top_n, sub_letter = parse_id(id_str)
    items = find_top_items(lines)
    top, sub = _resolve(items, top_n, sub_letter)

    if sub is None:
        lines[top.line_idx] = f"{top_n}. [x] {top.text}{_ref_suffix(ref)}\n"
        for k, s in enumerate(top.subitems):
            if not s.checked:
                letter = chr(ord("a") + k)
                lines[s.line_idx] = f"{SUB_INDENT}{letter}. [x] {s.text}{_ref_suffix(ref)}\n"
        path.write_text("".join(lines), encoding="utf-8")
        print(f"done #{top_n}: {top.text}{_ref_suffix(ref)}")
        return

    idx = ord(sub_letter) - ord("a")
    lines[sub.line_idx] = f"{SUB_INDENT}{sub_letter}. [x] {sub.text}{_ref_suffix(ref)}\n"
    all_checked = all(k == idx or s.checked for k, s in enumerate(top.subitems))
    if all_checked and not top.checked:
        lines[top.line_idx] = f"{top_n}. [x] {top.text}\n"
    path.write_text("".join(lines), encoding="utf-8")
    print(f"done #{top_n}.{sub_letter}: {sub.text}{_ref_suffix(ref)}")


def cmd_undone(path: Path, id_str: str) -> None:
    lines = read_lines(path)
    top_n, sub_letter = parse_id(id_str)
    items = find_top_items(lines)
    top, sub = _resolve(items, top_n, sub_letter)

    if sub is None:
        lines[top.line_idx] = f"{top_n}. [ ] {top.text}\n"
        for k, s in enumerate(top.subitems):
            letter = chr(ord("a") + k)
            lines[s.line_idx] = f"{SUB_INDENT}{letter}. [ ] {s.text}\n"
        path.write_text("".join(lines), encoding="utf-8")
        print(f"undone #{top_n}: {top.text}")
        return

    lines[sub.line_idx] = f"{SUB_INDENT}{sub_letter}. [ ] {sub.text}\n"
    if top.checked:
        lines[top.line_idx] = f"{top_n}. [ ] {top.text}\n"
    path.write_text("".join(lines), encoding="utf-8")
    print(f"undone #{top_n}.{sub_letter}: {sub.text}")


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
    p_add.add_argument("--under", type=int, default=None,
                       help="parent item number to file this item under as a lettered sub-item")

    sub.add_parser("list")
    sub.add_parser("next")

    p_show = sub.add_parser("show")
    p_show.add_argument("n", help="item id: a number (4) or a sub-item (4.a)")

    p_done = sub.add_parser("done")
    p_done.add_argument("n", help="item id: a number (4) or a sub-item (4.a)")
    p_done.add_argument("ref", nargs="?", default=None)

    p_undone = sub.add_parser("undone")
    p_undone.add_argument("n", help="item id: a number (4) or a sub-item (4.a)")

    args = parser.parse_args()
    path = find_todo_path()

    if args.command == "add":
        cmd_add(path, args.text, args.ref, args.section, args.under)
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
