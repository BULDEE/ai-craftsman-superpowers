"""The deterministic gate: is this branch fit to be read by a reviewer?

Four judges, none of them a model:

1. protected paths - the branch may not modify the configuration of the tools
   that judge it (the packs' `protected_configs`) nor the factory's own state;
2. the rules engine - `ci/craftsman-ci.sh --changed-only`, the same validators
   and the same severity resolution as the hooks and the CI pipeline;
3. the repository's checks - the commands in the factory config, run in the
   job's worktree; a run that executed no test grants nothing;
4. the tests themselves - a test skipped or deleted by the branch is recorded
   for the reviewer and for the confidence score. It does not fail the gate:
   a feature legitimately retires a test, and only a reader can tell.

No verdict is not a clean verdict: a judge that could not answer fails the gate.
"""
from __future__ import annotations

import fnmatch
import hashlib
import json
import re
from pathlib import Path

from . import registry
from .base import PLUGIN_ROOT, STATE_DIRNAME, git, run_long, write_atomically, write_json

CI_TIMEOUT = 900
# The rules engine reads these from the tree it judges. A branch that adds or
# edits one is relaxing its own judge, so ANY change to one fails the gate,
# an addition included (a new directory-level file is how a rule is relaxed).
RULE_FILES = ('.craft-rules.yml', '.craft-config.yml')
# Spelled in two parts: written whole, this file would count as carrying one.
IGNORE_MARKER = 'craftsman-' + 'ignore'
LOG_TAIL = 60
TEST_PATH = re.compile(r'(^|/)(tests?|specs?|__tests__)(/|$)|(test|spec)[^/]*$', re.IGNORECASE)


def changed_files(worktree: str, base: str) -> list[tuple]:
    """(status letter, path) for every file the branch touches."""
    listing = git(worktree, 'diff', '--name-status', f'origin/{base}...HEAD')
    rows = []
    for line in listing.splitlines():
        status, *paths = line.split('\t')
        if paths:
            rows.append((status[0], paths[-1], paths[0]))
    return rows


def lines_changed(worktree: str, base: str) -> int:
    total = 0
    for row in git(worktree, 'diff', '--numstat', f'origin/{base}...HEAD').splitlines():
        added, removed, *_ = row.split('\t')
        total += sum(int(count) for count in (added, removed) if count.isdigit())
    return total


def _protected_patterns(config: dict) -> list[str]:
    return [f'{STATE_DIRNAME}/*', *registry.capability('protected_configs'), *config['protected_paths']]


def protected_hits(changes: list[tuple], config: dict) -> list[str]:
    patterns = [pattern.lower() for pattern in _protected_patterns(config)]
    hits = []
    for status, path, original in changes:
        if Path(path).name in RULE_FILES:
            hits.append(f'{status} {path} (the rules this branch is judged by)')
            continue
        if status == 'A':
            continue
        name = original.lower()
        if any(fnmatch.fnmatch(name, pattern) or fnmatch.fnmatch(Path(name).name, pattern) for pattern in patterns):
            hits.append(f'{status} {original}')
    return hits


def rules_engine(worktree: str, base: str) -> dict:
    """The rules engine's verdict on the files the branch changed."""
    result = run_long(['bash', str(PLUGIN_ROOT / 'ci/craftsman-ci.sh'), '--format', 'json',
                       '--changed-only', '--base', f'origin/{base}', '.'], worktree, CI_TIMEOUT)
    try:
        report = json.loads(result.stdout)
    except ValueError:
        tail = (result.stderr or result.stdout).strip().splitlines()[-5:]
        return {'verdict': False, 'blocking': [], 'warnings': [], 'error': ' / '.join(tail) or 'no output'}
    findings = report.get('violations', [])
    blocking = [finding for finding in findings if finding.get('severity') != 'warning']
    return {'verdict': True, 'blocking': blocking,
            'warnings': [finding for finding in findings if finding.get('severity') == 'warning'], 'error': ''}


def _compile(expression: str) -> object:
    """A pack's marker as a pattern, None when Python cannot read it."""
    try:
        return re.compile(expression)
    except re.error:
        return None


def _compile_all(expressions: list[str]) -> list:
    return [pattern for pattern in map(_compile, expressions) if pattern is not None]


def _empty_run(output: str) -> str:
    """The line that says a green run executed no test, '' when it ran some."""
    patterns = _compile_all(registry.capability('empty_run_markers'))
    for line in output.splitlines():
        if any(pattern.search(line) for pattern in patterns):
            return line.strip()
    return ''


def _run_one(command: str, worktree: str, timeout: int) -> dict:
    result = run_long(['bash', '-c', command], worktree, timeout)
    output = result.stdout + result.stderr
    empty = _empty_run(output) if result.returncode == 0 else ''
    return {'command': command, 'exit': result.returncode, 'empty': empty, 'output': output,
            'passed': result.returncode == 0 and not empty}


def repository_checks(worktree: str, config: dict) -> list[dict]:
    return [_run_one(command, worktree, config['check_timeout_seconds']) for command in config['checks']]


def _added_lines(worktree: str, base: str) -> list[tuple]:
    """(path, line) for every line the branch adds."""
    diff = git(worktree, 'diff', '--unified=0', f'origin/{base}...HEAD')
    current, rows = '', []
    for line in diff.splitlines():
        if line.startswith('+++ '):
            current = line[6:] if line.startswith('+++ b/') else ''
            continue
        if line.startswith('+') and current:
            rows.append((current, line[1:]))
    return rows


def skip_markers() -> dict:
    """{language: compiled patterns} for what a skipped test looks like, from the packs' manifests."""
    declared = registry.capability_by_language('test_skip_markers')
    return {language: _compile_all(markers) for language, markers in declared.items()}


def tests_touched(worktree: str, base: str, changes: list[tuple]) -> dict:
    """What the branch did to the tests: skipped, deleted, or left alone."""
    markers = skip_markers()
    skips = []
    added = _added_lines(worktree, base)
    for path, line in added:
        patterns = markers.get(registry.language_of(path), [])
        if any(pattern.search(line) for pattern in patterns):
            skips.append(f'{path}: {line.strip()[:120]}')
    ignores = [f'{path}: {line.strip()[:120]}' for path, line in added if IGNORE_MARKER in line]
    deleted = [path for status, path, _ in changes if status == 'D' and TEST_PATH.search(path)]
    test_changed = any(TEST_PATH.search(path) for status, path, _ in changes if status != 'D')
    source_changed = any(registry.language_of(path) and not TEST_PATH.search(path) for _, path, _ in changes)
    return {'skips': skips, 'deleted': deleted, 'ignores': ignores,
            'test_changed': test_changed, 'source_changed': source_changed}


def _signature(result: dict) -> str:
    """What failed, order-free: two rounds with the same signature made no progress."""
    parts = sorted(result['protected'])
    parts += sorted(f'{finding.get("rule")}@{finding.get("file")}' for finding in result['rules']['blocking'])
    parts += sorted(check['command'] for check in result['checks'] if not check['passed'])
    if not result['rules']['verdict']:
        parts.append('rules-engine-no-verdict')
    if result['no_checks']:
        parts.append('no-checks')
    return hashlib.sha1('\n'.join(parts).encode()).hexdigest()[:12] if parts else ''


def evaluate(worktree: str, config: dict) -> dict:
    base = config['forge']['base_branch']
    changes = changed_files(worktree, base)
    result = {
        'commit': git(worktree, 'rev-parse', 'HEAD').strip(),
        'files': [path for _, path, _ in changes],
        'lines_changed': lines_changed(worktree, base),
        'protected': protected_hits(changes, config),
        'rules': rules_engine(worktree, base),
        'checks': repository_checks(worktree, config),
        'tests': tests_touched(worktree, base, changes),
        'no_checks': not config['checks'] and not config['allow_no_checks'],
    }
    result['passed'] = (not result['protected'] and result['rules']['verdict'] and not result['rules']['blocking']
                        and all(check['passed'] for check in result['checks']) and not result['no_checks'])
    result['signature'] = _signature(result)
    return result


def _check_line(check: dict) -> str:
    if check['empty']:
        return f'- `{check["command"]}`: exit 0 but no test ran (`{check["empty"]}`), which proves nothing'
    return f'- `{check["command"]}`: {"passed" if check["passed"] else "failed with exit " + str(check["exit"])}'


def _summary(result: dict) -> list[str]:
    rules = result['rules']
    lines = [f'Commit {result["commit"][:7]}, {len(result["files"])} file(s) changed']
    lines.append('Protected paths: ' + ('changed: ' + ', '.join(result['protected']) if result['protected'] else 'untouched'))
    if not rules['verdict']:
        lines.append(f'Rules engine gave no verdict ({rules["error"]}): treated as a failure')
    else:
        lines.append(f'Rules engine: {len(rules["blocking"])} blocking, {len(rules["warnings"])} warning(s)')
    if result['no_checks']:
        lines.append('No check is configured: nothing proves this branch works')
    else:
        failed = [check for check in result['checks'] if not check['passed']]
        lines.append(f'Checks: {len(result["checks"]) - len(failed)} of {len(result["checks"])} passed')
    tests = result['tests']
    if tests['skips'] or tests['deleted']:
        lines.append(f'Tests touched: {len(tests["skips"])} skip marker(s) added, {len(tests["deleted"])} test file(s) deleted')
    if tests['ignores']:
        lines.append(f'{len(tests["ignores"])} rule ignore marker(s) added: each one is a decision a human must confirm')
    return lines


def _findings_section(findings: list[dict]) -> str:
    if not findings:
        return 'None.'
    return '\n'.join(f'- {finding.get("rule")} {finding.get("file")}:{finding.get("line")} {finding.get("message", "")}'
                     for finding in findings)


def render(result: dict) -> str:
    tests = result['tests']
    sections = [
        f'GATE: {"PASS" if result["passed"] else "FAIL"}', f'COMMIT: {result["commit"]}',
        f'SIGNATURE: {result["signature"] or "-"}', '',
        '## Summary', *[f'- {line}' for line in _summary(result)], '',
        '## Protected paths', '\n'.join(f'- {hit}' for hit in result['protected']) or 'None changed.', '',
        '## Rules engine (blocking)', _findings_section(result['rules']['blocking']), '',
        '## Rules engine (warnings)', _findings_section(result['rules']['warnings']), '',
        '## Checks', '\n'.join(_check_line(check) for check in result['checks']) or 'None configured.', '',
        '## Tests touched',
        '\n'.join([f'- skip added: {skip}' for skip in tests['skips']]
                  + [f'- test file deleted: {path}' for path in tests['deleted']]) or 'No test was skipped or deleted.', '',
        '## Rule ignore markers added',
        '\n'.join(f'- {ignore}' for ignore in tests['ignores']) or 'None.',
    ]
    for check in result['checks']:
        if check['passed']:
            continue
        tail = '\n'.join(check['output'].rstrip().splitlines()[-LOG_TAIL:])
        sections += ['', f'## Output of `{check["command"]}` (last {LOG_TAIL} lines)', '', '```', tail, '```']
    return '\n'.join(sections) + '\n'


def write(result: dict, round_dir: Path, name: str = 'checks') -> None:
    log = '\n\n'.join(f'$ {check["command"]}\n{check["output"]}' for check in result['checks'])
    write_atomically(round_dir / f'{name}.log', log)
    stored = dict(result, checks=[{key: value for key, value in check.items() if key != 'output'}
                                  for check in result['checks']])
    write_json(round_dir / f'{name}.json', stored)
    write_atomically(round_dir / f'{name}.md', render(result))
