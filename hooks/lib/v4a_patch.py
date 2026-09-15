#!/usr/bin/env python3
"""The V4A patch grammar, as Codex 0.154.0 sends it in `tool_input.command`.

    *** Begin Patch
    *** Add File: <path>          followed by `+` lines
    *** Delete File: <path>
    *** Update File: <path>       optionally followed by `*** Move to: <path>`,
                                  then `@@ [anchor]` hunks of ` `/`-`/`+` lines,
                                  a hunk may end with `*** End of File`
    *** End Patch

Captured, not transcribed: tests/fixtures/hosts/codex/0.154.0. `parse` reads
a patch into (op, path, new_path, body) entries and raises ValueError for
anything the grammar does not name, since an unread patch is not a pass.
`apply_hunks` yields the file a hunk list would produce, or None when a hunk
cannot be placed, which the caller treats as a refusal.

A hunk is {"anchor": text after "@@" or "", "eof": bool, "lines": [...]}. The
anchor names the line the hunk sits under and End of File pins it to the
tail: both decide WHICH occurrence changes, and an applier that ignored them
edited the first match (review of 0c212d9, F4).
"""

from __future__ import annotations

BEGIN, END = "*** Begin Patch", "*** End Patch"
ADD, DELETE, UPDATE, MOVE = "*** Add File: ", "*** Delete File: ", "*** Update File: ", "*** Move to: "
EOF_MARK = "*** End of File"
HUNK_PREFIXES = (" ", "-", "+")


def parse(text: str) -> list:
    """(op, path, new_path, body) per file; op in add|delete|update|move."""
    lines = text.split("\n")
    if not lines or lines[0].strip() != BEGIN:
        raise ValueError("not a V4A patch: missing '*** Begin Patch'")
    entries: list = []
    index = 1
    while index < len(lines):
        line = lines[index]
        if line.strip() == END:
            return entries
        entry, index = _parse_entry(lines, index)
        entries.append(entry)
    raise ValueError("not a V4A patch: missing '*** End Patch'")


def _parse_entry(lines: list, index: int) -> tuple:
    line = lines[index]
    if line.startswith(ADD):
        return _parse_add(lines, index)
    if line.startswith(DELETE):
        return ("delete", line[len(DELETE):].strip(), None, []), index + 1
    if line.startswith(UPDATE):
        return _parse_update(lines, index)
    raise ValueError(f"unreadable patch line {line!r}")


def _parse_add(lines: list, index: int) -> tuple:
    path, body = lines[index][len(ADD):].strip(), []
    index += 1
    while index < len(lines) and not lines[index].startswith("*** "):
        if not lines[index].startswith("+"):
            raise ValueError(f"Add File {path}: line without '+' prefix")
        body.append(lines[index][1:])
        index += 1
    return ("add", path, None, body), index


def _parse_update(lines: list, index: int) -> tuple:
    path, new_path = lines[index][len(UPDATE):].strip(), None
    index += 1
    if index < len(lines) and lines[index].startswith(MOVE):
        new_path, index = lines[index][len(MOVE):].strip(), index + 1
    hunks: list = []
    while index < len(lines) and not _is_file_header(lines[index]):
        _read_hunk_line(hunks, lines[index], path)
        index += 1
    return ("move" if new_path else "update", path, new_path, hunks), index


def _is_file_header(line: str) -> bool:
    return line.startswith("*** ") and not line.startswith(EOF_MARK)


def _new_hunk(anchor: str = "") -> dict:
    return {"anchor": anchor, "eof": False, "lines": []}


def _read_hunk_line(hunks: list, line: str, path: str) -> None:
    if line.startswith("@@"):
        hunks.append(_new_hunk(line[2:].strip()))
        return
    if line.startswith(EOF_MARK):
        if hunks:
            hunks[-1]["eof"] = True
        return
    if line == "":
        if hunks:
            hunks[-1]["lines"].append(" ")
        return
    if line[:1] not in HUNK_PREFIXES:
        raise ValueError(f"Update File {path}: unreadable hunk line {line!r}")
    if not hunks:
        hunks.append(_new_hunk())
    hunks[-1]["lines"].append(line)


# ---------------------------------------------------------------------------
# Applying hunks to the current file
# ---------------------------------------------------------------------------

def _locate(src: list, before: list, start: int, end: int) -> int:
    """First index in [start, end) where `before` matches: exact, then ignoring
    trailing whitespace, then surrounding whitespace, the three passes Codex's
    own applier tolerates, so a patch it would land is one we judge."""
    for normalise in (str.__str__, str.rstrip, str.strip):
        window = [normalise(text) for text in before]
        for index in range(start, end - len(before) + 1):
            if [normalise(text) for text in src[index:index + len(before)]] == window:
                return index
    return -1


def _anchor_index(src: list, anchor: str, start: int) -> int:
    for index in range(start, len(src)):
        if src[index].strip() == anchor:
            return index
    return -1


def _tail_index(src: list, before: list, start: int) -> int:
    """Where an End of File hunk sits: the last match of `before`, the trailing
    "" a final newline leaves being part of the tail."""
    for end in (len(src), len(src) - 1 if src and src[-1] == "" else len(src)):
        index = end - len(before)
        while index >= start:
            if _locate(src, before, index, end) == index:
                return index
            index -= 1
    return -1


def _hunk_position(src: list, hunk: dict, before: list, cursor: int) -> int:
    """The index the hunk replaces from, or -1 when it cannot be placed.

    An `@@ anchor` names the line the hunk sits UNDER: the hunk is located
    strictly after it, and when the anchor text occurs several times the first
    occurrence under which the hunk fits wins. The first cut located the hunk
    from the anchor line itself, so `@@ pass` above a docstring `pass` edited
    the docstring where the real applier edited the code (challenge review of
    e2acf22, F3).
    """
    if not hunk["anchor"]:
        return _positioned(src, hunk, before, cursor)
    anchored = _anchor_index(src, hunk["anchor"], cursor)
    while anchored >= 0:
        position = _positioned(src, hunk, before, anchored + 1)
        if position >= 0:
            return position
        anchored = _anchor_index(src, hunk["anchor"], anchored + 1)
    return -1


def _positioned(src: list, hunk: dict, before: list, start: int) -> int:
    if not before:
        return len(src) if hunk["eof"] else start
    if hunk["eof"]:
        return _tail_index(src, before, start)
    return _locate(src, before, start, len(src))


def apply_hunks(current: str, hunks: list) -> str | None:
    """The file after the hunks, or None when a hunk cannot be placed.

    None is a refusal, not a fallback: a hunk that deletes a suppression
    comment and does not locate would otherwise be judged on its added lines
    alone, which is nothing (review of 0c212d9, F2).
    """
    src = current.split("\n")
    out: list = []
    cursor = 0
    for hunk in hunks:
        before = [text[1:] for text in hunk["lines"] if text[:1] in (" ", "-")]
        after = [text[1:] for text in hunk["lines"] if text[:1] in (" ", "+")]
        position = _hunk_position(src, hunk, before, cursor)
        if position < 0:
            return None
        out.extend(src[cursor:position])
        out.extend(after)
        cursor = position + len(before)
    out.extend(src[cursor:])
    return "\n".join(out)
