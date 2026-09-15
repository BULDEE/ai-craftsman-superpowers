#!/usr/bin/env python3
"""Splice the craftsman doctrine block into an instruction file.

Usage: DOCTRINE_BLOCK=<block> doctrine_splice.py <file> <end marker>

The block comes through the environment (it holds newlines); the file keeps
everything outside the markers byte for byte, its line endings and its mode.
A begin marker without its end, two blocks, or an end before its begin is
refused with exit 3, never guessed (review of 95c431e, F1).
"""
import os, re, shutil, sys, tempfile
path, end = sys.argv[1], sys.argv[2]
block = os.environ["DOCTRINE_BLOCK"].rstrip("\n") + "\n"
begin_re = re.compile(r"^<!-- craftsman:doctrine:begin.*$", re.M)


def refuse(why):
    sys.stderr.write(f"craftsman: not exporting into {path}: {why}. Fix the markers by hand, then export again.\n")
    sys.exit(3)


def spliced(text):
    begins = list(begin_re.finditer(text))
    ends = [match.start() for match in re.finditer(re.escape(end), text)]
    if not begins and not ends:
        if text and not text.endswith("\n"):
            text += "\n"
        return text + ("\n" if text else "") + block
    if len(begins) != 1 or len(ends) != 1:
        refuse(f"{len(begins)} begin and {len(ends)} end marker(s), one of each expected")
    begin, end_at = begins[0], ends[0]
    if end_at < begin.end():
        refuse("the end marker comes before the begin marker")
    after = end_at + len(end)
    if text[after:after + 1] == "\n":
        after += 1
    return text[:begin.start()] + block + text[after:]


if os.path.isfile(path):
    with open(path, encoding="utf-8", newline="") as handle:
        raw = handle.read()
    crlf = raw.count("\r\n") > raw.count("\n") - raw.count("\r\n")
    text = spliced(raw.replace("\r\n", "\n"))
    if crlf:
        text = text.replace("\n", "\r\n")
else:
    text = block
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(path)) or ".", prefix=os.path.basename(path) + ".")
with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
    handle.write(text)
if os.path.isfile(path):
    shutil.copymode(path, tmp)
os.replace(tmp, path)
