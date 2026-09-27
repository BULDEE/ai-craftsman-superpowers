"""Resolve skill state from the native hook's per-session binding."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import sys


_INHERITED_IDS = (
    ('grok', 'GROK_SESSION_ID'), ('codex', 'CODEX_SESSION_ID'),
    ('codex', 'CODEX_THREAD_ID'), ('claude-code', 'CLAUDE_CODE_SESSION_ID'),
)


def _clean(raw: str) -> str:
    return re.sub(r'[^A-Za-z0-9_-]', '', raw)[:64]


def _nested() -> tuple[str, str] | None:
    """The innermost session when several hosts' ids are inherited.

    A session started from another host's shell carries both ids, and a fixed
    order named the parent whenever the parent's host came first (review of
    4.12.0, CR-204 F6). A child binds after its parent, so when two or more
    inherited ids have a binding, the most recent binding is this session.
    """
    bound = []
    for runtime, key in _INHERITED_IDS:
        identity = _clean(os.environ.get(key, ''))
        if identity and binding_path(runtime, identity).is_file():
            bound.append((binding_path(runtime, identity).stat().st_mtime, runtime, identity))
    if len(bound) < 2:
        return None
    _, runtime, identity = max(bound)
    return runtime, identity


def session_id() -> str:
    if os.environ.get('CRAFTSMAN_SESSION_ID'):
        return _clean(os.environ['CRAFTSMAN_SESSION_ID'])
    nested = _nested()
    if nested:
        return nested[1]
    raw = next((os.environ[key] for _, key in _INHERITED_IDS if os.environ.get(key)), '')
    return _clean(raw)


def host() -> str:
    bound = os.environ.get('CRAFTSMAN_SESSION_HOST')
    if bound in ('codex', 'grok', 'claude-code'):
        return bound
    if not os.environ.get('CRAFTSMAN_SESSION_ID'):
        nested = _nested()
        if nested:
            return nested[0]
    if os.environ.get('GROK_SESSION_ID') or os.environ.get('GROK_HOOK_EVENT'):
        return 'grok'
    if os.environ.get('CODEX_SESSION_ID') or os.environ.get('CODEX_THREAD_ID'):
        return 'codex'
    return 'claude-code'


def binding_path(runtime: str, identity: str) -> Path:
    directory = {'codex': '.codex', 'grok': '.grok', 'claude-code': '.claude'}[runtime]
    return Path(os.environ.get('CRAFTSMAN_RUNTIME_HOME', os.path.expanduser('~'))) / directory / 'craftsman/sessions' / (identity + '.json')


def bind(runtime: str, identity: str, root: str, data: str) -> None:
    import tempfile

    identity = re.sub(r'[^A-Za-z0-9_-]', '', identity)[:64]
    if runtime not in ('codex', 'grok', 'claude-code') or not identity:
        return
    target = binding_path(runtime, identity)
    target.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=target.parent)
    try:
        with os.fdopen(descriptor, 'w') as handle:
            json.dump({'host': runtime, 'session_id': identity, 'root': root, 'data': data}, handle)
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def bound_data(runtime: str, identity: str) -> str:
    if not identity:
        return ''
    target = binding_path(runtime, identity)
    if not target.is_file():
        return ''
    binding = json.loads(target.read_text())
    if binding.get('host') != runtime or binding.get('session_id') != identity:
        raise RuntimeError('Craftsman session binding identity mismatch')
    return binding['data']


def data_dir() -> str:
    runtime, identity = host(), session_id()
    bound = bound_data(runtime, identity)
    if bound:
        return bound
    aliases = {
        'codex': ('PLUGIN_DATA', 'CLAUDE_PLUGIN_DATA'),
        'grok': ('GROK_PLUGIN_DATA', 'PLUGIN_DATA', 'CLAUDE_PLUGIN_DATA'),
        'claude-code': ('CLAUDE_PLUGIN_DATA',),
    }
    for key in ('CRAFTSMAN_PLUGIN_DATA', *aliases[runtime]):
        if key == 'CLAUDE_PLUGIN_DATA' and runtime != 'claude-code':
            parent = os.environ.get('CLAUDE_CODE_SESSION_ID')
            if parent and parent != identity:
                continue
        if os.environ.get(key):
            return os.environ[key]
    if runtime != 'claude-code':
        raise RuntimeError(f'No Craftsman data binding for {runtime} session {identity}; start a session with trusted plugin hooks')
    bridge = Path(os.path.expanduser('~/.claude/craftsman-session-state-path'))
    if bridge.is_file() and bridge.read_text().strip():
        return str(Path(bridge.read_text().strip()).parent)
    return os.path.expanduser('~/.claude/plugins/data/craftsman')


def cache_dir() -> str:
    try:
        return data_dir()
    except (RuntimeError, ValueError, OSError, KeyError):
        directory = binding_path(host(), 'cache').parent.parent / 'cache'
        return str(directory)


def state_path() -> str:
    identity = session_id()
    name = f'session-state-{identity}.json' if identity else 'session-state.json'
    return str(Path(data_dir()) / name)


def emit_context() -> None:
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        payload = {}
    raw = payload.get('session_id', '') if isinstance(payload, dict) else ''
    identity = re.sub(r'[^A-Za-z0-9_-]', '', str(raw or ''))[:64]
    if identity:
        os.environ['CRAFTSMAN_SESSION_ID'] = identity
    try:
        data = data_dir()
    except (RuntimeError, ValueError, OSError, KeyError):
        data = ''
    cache = data or cache_dir()
    sys.stdout.write('\0'.join((session_id(), data, cache)) + '\0')


def sweep(days: str = '7') -> None:
    """Drop bindings of sessions that ended: nothing else removes them."""
    import time

    limit = time.time() - int(days) * 86400
    for runtime in ('codex', 'grok', 'claude-code'):
        for binding in binding_path(runtime, 'x').parent.glob('*.json'):
            try:
                if binding.lstat().st_mtime < limit:
                    binding.unlink()
            except OSError:
                continue


def main(arguments: list[str]) -> int:
    if arguments[0] == 'context':
        emit_context()
        return 0
    if arguments[0] == 'sweep':
        sweep(*arguments[1:2])
        return 0
    if arguments[0] == 'bind':
        bind(*arguments[1:5])
        return 0
    paths = {'host': host, 'data': data_dir, 'cache': cache_dir, 'state': state_path, 'metrics': lambda: str(Path(data_dir()) / 'metrics.db')}
    print(paths[arguments[0]]())
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv[1:]))
    except (RuntimeError, ValueError, OSError, KeyError, IndexError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        sys.exit(1)
