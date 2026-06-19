#!/usr/bin/env python3
# =============================================================================
# Structural metrics for C-like sources (PHP, TypeScript/TSX, JS/JSX).
#
# Emits one "RULE|message" line per finding on stdout. The bash wrapper
# (structural.sh) routes each through add_violation, so severity is decided by
# the rules engine (warn-first rollout; see rules-engine.sh).
#
# Rules:
#   NEST001  control-flow nesting depth >= NEST_MAX inside a method (if/if/if)
#   LOC001   method body longer than LOC_MAX lines
#   GOD001   class longer than CLASS_LOC_MAX lines (god-class signal)
#   PARAM001 non-constructor function with more than PARAM_MAX parameters
#
# Brace/paren counting is done on a cleaned copy where string literals and
# comments are blanked (newlines preserved) so they never skew the depth.
# Object/array literals are NOT counted as control nesting: only braces whose
# header carries a control keyword count toward NEST001, which keeps the signal
# focused on real if/for/while pyramids rather than data structures.
#
# Conservative thresholds on purpose: this ships as advisory (warn) first to
# measure real noise before any escalation to block. Tune the constants below.
#
# The scanner functions stay single, sequential state machines on purpose:
# splitting them would scatter the brace/string state and hurt readability.
# craftsman-ignore: PY002
# =============================================================================
import re
import sys

NEST_MAX = 3          # 3 nested control blocks = the "if if if" smell
LOC_MAX = 50          # method body lines (blank/comment lines already blanked)
CLASS_LOC_MAX = 300   # class span in lines
PARAM_MAX = 3         # global rule: max 3 params (constructors are exempt)

CONTROL_HEAD_RE = re.compile(r'\b(if|for|foreach|while|switch|catch)\b\s*\(|\b(else|do|try|finally)\b')
FUNC_PHP_RE = re.compile(r'\bfunction\b\s*&?\s*(\w+)?\s*\(')
FUNC_TS_NAMED_RE = re.compile(r'\bfunction\b\s*\*?\s*(\w+)?\s*\(')
ARROW_RE = re.compile(r'=>\s*$')
CLASS_RE = re.compile(r'\b(class|trait)\s+(\w+)')


def clean(source):
    """Blank out string literals and comments, preserving newlines and length."""
    out = []
    cursor, length = 0, len(source)
    state = None  # None | 'line' | 'block' | "'" | '"' | '`'
    while cursor < length:
        char = source[cursor]
        peek = source[cursor + 1] if cursor + 1 < length else ''
        if state is None:
            if char == '/' and peek == '/':
                out.append('  '); cursor += 2; state = 'line'; continue
            if char == '/' and peek == '*':
                out.append('  '); cursor += 2; state = 'block'; continue
            if char in ("'", '"', '`'):
                out.append(' '); state = char; cursor += 1; continue
            out.append(char); cursor += 1; continue
        if state == 'line':
            out.append('\n' if char == '\n' else ' ')
            if char == '\n':
                state = None
            cursor += 1; continue
        if state == 'block':
            if char == '*' and peek == '/':
                out.append('  '); cursor += 2; state = None; continue
            out.append('\n' if char == '\n' else ' '); cursor += 1; continue
        # inside a string literal
        if char == '\\':
            out.append('  '); cursor += 2; continue
        if char == state:
            out.append(' '); state = None; cursor += 1; continue
        out.append('\n' if char == '\n' else ' '); cursor += 1; continue
    return ''.join(out)


def line_of(source, pos):
    return source.count('\n', 0, pos) + 1


def count_params(header):
    """Count top-level params in the LAST balanced (...) group of a func header."""
    end = header.rfind(')')
    if end == -1:
        return 0
    depth = 0
    start = -1
    for idx in range(end, -1, -1):
        char = header[idx]
        if char == ')':
            depth += 1
        elif char == '(':
            depth -= 1
            if depth == 0:
                start = idx
                break
    if start == -1:
        return 0
    inner = header[start + 1:end].strip()
    if not inner:
        return 0
    depth = 0
    params = 1
    for char in inner:
        if char in '([{':
            depth += 1
        elif char in ')]}':
            depth -= 1
        elif char == ',' and depth == 0:
            params += 1
    return params


def analyze(path, lang):
    try:
        with open(path, 'r', encoding='utf-8', errors='replace') as handle:
            raw = handle.read()
    except OSError:
        return []
    source = clean(raw)
    findings = []
    seen_nest = set()
    stack = []
    control_depth = 0
    header_start = 0
    func_name_re = FUNC_PHP_RE if lang == 'php' else FUNC_TS_NAMED_RE
    cursor, length = 0, len(source)
    while cursor < length:
        char = source[cursor]
        if char in ';}{':
            if char == '{':
                control_depth = _open_brace(source, cursor, header_start, lang, func_name_re, stack, control_depth, findings, seen_nest)
            elif char == '}':
                control_depth = _close_brace(source, cursor, stack, control_depth, findings)
            header_start = cursor + 1
        cursor += 1
    return findings


def _open_brace(source, pos, header_start, lang, func_name_re, stack, control_depth, findings, seen_nest):
    header = source[header_start:pos]
    kind, name = 'other', None
    if CLASS_RE.search(header):
        kind = 'class'
    elif func_name_re.search(header) or (lang != 'php' and ARROW_RE.search(header.rstrip())):
        kind = 'func'
        match = func_name_re.search(header)
        name = match.group(1) if match else None
        params = count_params(header)
        if name not in ('__construct', 'constructor') and params > PARAM_MAX:
            findings.append(('PARAM001', 'line %d: %s() has %d parameters (max %d): pass an object/DTO'
                             % (line_of(source, pos), name or 'closure', params, PARAM_MAX)))
    elif CONTROL_HEAD_RE.search(header):
        kind = 'control'
    if kind == 'control':
        control_depth += 1
        if control_depth >= NEST_MAX:
            line_num = line_of(source, pos)
            if line_num not in seen_nest:
                seen_nest.add(line_num)
                findings.append(('NEST001', 'line %d: control-flow nested %d levels deep: extract a method or use guard clauses'
                                 % (line_num, control_depth)))
    stack.append({'kind': kind, 'open': pos, 'name': name})
    return control_depth


def _close_brace(source, pos, stack, control_depth, findings):
    if not stack:
        return control_depth
    frame = stack.pop()
    span = line_of(source, pos) - line_of(source, frame['open'])
    if frame['kind'] == 'control':
        return max(0, control_depth - 1)
    if frame['kind'] == 'func' and span > LOC_MAX:
        findings.append(('LOC001', 'line %d: %s() body is %d lines (max %d): extract methods'
                         % (line_of(source, frame['open']), frame['name'] or 'closure', span, LOC_MAX)))
    elif frame['kind'] == 'class' and span > CLASS_LOC_MAX:
        findings.append(('GOD001', 'line %d: class spans %d lines (max %d): too many responsibilities, extract value objects/services'
                         % (line_of(source, frame['open']), span, CLASS_LOC_MAX)))
    return control_depth


def main():
    if len(sys.argv) < 3:
        return
    path, lang = sys.argv[1], sys.argv[2]
    for rule, message in analyze(path, lang):
        print('%s|%s' % (rule, message))


if __name__ == '__main__':
    main()
