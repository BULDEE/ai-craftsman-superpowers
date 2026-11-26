"""Paths, configuration and process helpers shared by every factory module.

The factory keeps one directory per repository, `.craftsman-factory/`, in the
main checkout. It is excluded through `.git/info/exclude`, so installing the
factory commits nothing to the repository it works on.
"""
from __future__ import annotations

import copy
import json
import os
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parents[4]
PACK_ROOT = Path(__file__).resolve().parents[2]
STATE_DIRNAME = '.craftsman-factory'
MARKER = '<!-- craftsman-factory -->'
COMMAND_TIMEOUT = 120

DEFAULTS = {
    'v': 1,
    'queue': {
        'kind': 'github',
        'label': 'factory',
        'needs_info_label': 'factory:needs-info',
        'needs_human_label': 'factory:needs-human',
        'linear': {'team': '', 'transport': 'api'},
    },
    'forge': {'kind': 'github', 'base_branch': 'main'},
    'concurrency': 1,
    'max_rounds': 3,
    # Commands run in the job's worktree, in order. `setup` prepares a fresh
    # checkout, `checks` are the repository's own tests: the gate fails without
    # any, because no verdict is not a clean verdict.
    'setup': [],
    'checks': [],
    'allow_no_checks': False,
    'check_timeout_seconds': 1800,
    'protected_paths': [],
    'reviewer_models': {'low': 'haiku', 'medium': 'sonnet', 'high': 'opus'},
    'review_labels': {'skim': 'review:skim', 'standard': 'review:standard', 'deep': 'review:deep'},
    'confidence': {
        'thresholds': {'skim': 80, 'standard': 55},
        'weights': {
            'risk_medium': 15, 'risk_high': 35,
            'surface_security': 20, 'surface_domain': 10, 'surface_ui': 5,
            'spec_generated_on_domain': 15,
            'extra_round': 10,
            'diff_over_200_lines': 10, 'diff_over_500_lines': 20, 'over_10_files': 10,
            'test_skip_added': 25, 'test_file_deleted': 25, 'no_test_changed': 10,
            'ignore_marker_added': 15,
            'ci_warning': 2, 'ci_warning_cap': 10,
            'reviewer_medium': 10, 'reviewer_low': 25,
            'resynced': 5,
        },
    },
    # USD per million tokens. The Haiku line was checked against a measured
    # headless call; the others come from published list prices and are the
    # first thing to correct when a cost looks wrong. The figure is an
    # estimate either way: Claude Code computes cost client-side.
    'prices_usd_per_mtok': {
        'claude-fable-5-2': {'input': 10.0, 'output': 50.0, 'cache_write_5m': 12.5, 'cache_write_1h': 20.0, 'cache_read': 0.25},
        'claude-opus-5-5': {'input': 4.0, 'output': 20.0, 'cache_write_5m': 5.0, 'cache_write_1h': 8.0, 'cache_read': 0.20},
        'claude-sonnet-5-5': {'input': 2.0, 'output': 10.0, 'cache_write_5m': 2.5, 'cache_write_1h': 4.0, 'cache_read': 0.20},
        'claude-haiku-5-5': {'input': 0.10, 'output': 0.50, 'cache_write_5m': 0.125, 'cache_write_1h': 0.20, 'cache_read': 0.01},
    },
}


class Refused(Exception):
    """A move the factory will not make. The message says why."""


def now() -> str:
    return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def _execute(command: list[str], cwd: object, stdin: object, timeout: int) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(command, cwd=cwd, input=stdin, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError as error:
        raise Refused(f'`{command[0]}` is not installed or not on PATH') from error
    except subprocess.TimeoutExpired as error:
        raise Refused(f'`{" ".join(command[:3])}` did not answer within {timeout}s') from error


def run(command: list[str], cwd: object = None, check: bool = True) -> subprocess.CompletedProcess:
    result = _execute(command, cwd, None, COMMAND_TIMEOUT)
    if check and result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise Refused(f'`{" ".join(command)}` failed: {detail}')
    return result


def run_with_input(command: list[str], cwd: object, stdin: str) -> subprocess.CompletedProcess:
    result = _execute(command, cwd, stdin, COMMAND_TIMEOUT)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise Refused(f'`{" ".join(command)}` failed: {detail}')
    return result


def run_long(command: list[str], cwd: object, timeout: int) -> subprocess.CompletedProcess:
    """A check or a setup command: its exit code is the answer, never an error."""
    return _execute(command, cwd, None, timeout)


def git(cwd: Path | str, *arguments: str, check: bool = True) -> str:
    return run(['git', *arguments], cwd=cwd, check=check).stdout


def repo_root(start: Path | str | None = None) -> Path:
    """The MAIN checkout, also when called from inside a job's worktree."""
    override = os.environ.get('CRAFTSMAN_FACTORY_REPO')
    if override:
        return Path(override).resolve()
    common = git(start or os.getcwd(), 'rev-parse', '--path-format=absolute', '--git-common-dir').strip()
    return Path(common).parent.resolve()


def state_dir(repo: Path) -> Path:
    return repo / STATE_DIRNAME


def data_dir() -> Path:
    """Machine-wide factory data: the index of repositories and the page."""
    override = os.environ.get('CRAFTSMAN_FACTORY_DATA')
    if override:
        return Path(override)
    resolved = run(['python3', str(PLUGIN_ROOT / 'hooks/lib/runtime_paths.py'), 'data'], check=False)
    base = resolved.stdout.strip() if resolved.returncode == 0 and resolved.stdout.strip() else \
        os.path.expanduser('~/.claude/plugins/data/craftsman')
    return Path(base) / 'factory'


def metrics_db() -> Path:
    override = os.environ.get('CRAFTSMAN_FACTORY_DB')
    if override:
        return Path(override)
    return data_dir().parent / 'metrics.db'


def write_atomically(target: Path, content: str) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=target.parent, suffix='.tmp')
    try:
        with os.fdopen(descriptor, 'w') as handle:
            handle.write(content)
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def write_json(target: Path, value: object) -> None:
    write_atomically(target, json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def read_json(source: Path, default: object = None) -> object:
    try:
        return json.loads(source.read_text())
    except (FileNotFoundError, ValueError):
        return default


def _merge(base: dict, override: dict) -> dict:
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            _merge(base[key], value)
        else:
            base[key] = value
    return base


def load_config(repo: Path) -> dict:
    config = copy.deepcopy(DEFAULTS)
    override = read_json(state_dir(repo) / 'config.json', {})
    if not isinstance(override, dict):
        raise Refused(f'{STATE_DIRNAME}/config.json is not a JSON object')
    return _merge(config, override)


def routing() -> dict:
    return json.loads((PACK_ROOT / 'routing.json').read_text())


def first_line(path: Path) -> str:
    try:
        with path.open() as handle:
            return handle.readline().strip()
    except FileNotFoundError:
        return ''


def _header_lines(path: Path) -> list[str]:
    try:
        text = path.read_text()
    except FileNotFoundError:
        return []
    return text.partition('\n\n')[0].splitlines()


def header_value(path: Path, key: str) -> str:
    """`KEY: value` from the header block that opens a job file."""
    for line in _header_lines(path):
        name, _, value = line.partition(':')
        if name.strip().upper() == key.upper():
            return value.strip()
    return ''


def body_after_header(path: Path) -> str:
    text = path.read_text()
    _, _, body = text.partition('\n\n')
    return body.strip()
