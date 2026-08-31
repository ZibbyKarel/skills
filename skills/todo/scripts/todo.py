#!/usr/bin/env python3
"""CRUD over a project's TODO.md checklist. See ../SKILL.md for the command contract."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlsplit

ITEM_RE = re.compile(r"^([-*]) \[([ xX])\] (.*)$")
HEADER = "# TODO\n"


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


def find_items(lines: list[str]) -> list[tuple[int, str, bool, str]]:
    """Returns (line_index, bullet_char, checked, text) for every checklist line, in file order."""
    items = []
    for i, line in enumerate(lines):
        m = ITEM_RE.match(line.rstrip("\r\n"))
        if m:
            items.append((i, m.group(1), m.group(2).lower() == "x", m.group(3)))
    return items


def cmd_add(path: Path, text: str) -> None:
    lines = read_lines(path)
    if not lines:
        lines = [HEADER, "\n"]
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    lines.append(f"- [ ] {text}\n")
    path.write_text("".join(lines), encoding="utf-8")
    items = find_items(lines)
    print(f"added #{len(items)}: {text}")


def cmd_list(path: Path) -> None:
    items = find_items(read_lines(path))
    if not items:
        print("no items in TODO.md")
        return
    for n, (_, _, checked, text) in enumerate(items, start=1):
        mark = "x" if checked else " "
        print(f"{n}. [{mark}] {text}")


def cmd_next(path: Path) -> None:
    items = find_items(read_lines(path))
    for n, (_, _, checked, text) in enumerate(items, start=1):
        if not checked:
            print(f"{n}. {text}")
            return
    print("no pending items")


def cmd_show(path: Path, n: int) -> None:
    items = find_items(read_lines(path))
    if not 1 <= n <= len(items):
        sys.exit(f"item {n} does not exist ({len(items)} item(s) total)")
    print(items[n - 1][3])


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
    line_idx, bullet, _, text = items[n - 1]
    lines[line_idx] = f"{bullet} [x] {text}{_ref_suffix(ref)}\n"
    path.write_text("".join(lines), encoding="utf-8")
    print(f"done #{n}: {text}{_ref_suffix(ref)}")


def cmd_undone(path: Path, n: int) -> None:
    lines = read_lines(path)
    items = find_items(lines)
    if not 1 <= n <= len(items):
        sys.exit(f"item {n} does not exist ({len(items)} item(s) total)")
    line_idx, bullet, _, text = items[n - 1]
    lines[line_idx] = f"{bullet} [ ] {text}\n"
    path.write_text("".join(lines), encoding="utf-8")
    print(f"undone #{n}: {text}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p_add = sub.add_parser("add")
    p_add.add_argument("text")

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
        cmd_add(path, args.text)
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
