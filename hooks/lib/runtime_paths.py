"""Resolve skill state from the native hook's per-session binding."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import sys
import tempfile


def session_id() -> str:
    raw = next((os.environ[key] for key in (
        'CRAFTSMAN_SESSION_ID', 'GROK_SESSION_ID', 'CODEX_SESSION_ID',
        'CODEX_THREAD_ID', 'CLAUDE_CODE_SESSION_ID',
    ) if os.environ.get(key)), '')
    return re.sub(r'[^A-Za-z0-9_-]', '', raw)[:64]


def host() -> str:
    bound = os.environ.get('CRAFTSMAN_SESSION_HOST')
    if bound in ('codex', 'grok', 'claude-code'):
        return bound
    if os.environ.get('GROK_SESSION_ID') or os.environ.get('GROK_HOOK_EVENT'):
        return 'grok'
    if os.environ.get('CODEX_SESSION_ID') or os.environ.get('CODEX_THREAD_ID'):
        return 'codex'
    return 'claude-code'


def binding_path(runtime: str, identity: str) -> Path:
    directory = {'codex': '.codex', 'grok': '.grok', 'claude-code': '.claude'}[runtime]
    return Path(os.environ.get('CRAFTSMAN_RUNTIME_HOME', os.path.expanduser('~'))) / directory / 'craftsman/sessions' / (identity + '.json')


def bind(runtime: str, identity: str, root: str, data: str) -> None:
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


def data_dir() -> str:
    for key in ('CRAFTSMAN_PLUGIN_DATA', 'GROK_PLUGIN_DATA', 'PLUGIN_DATA', 'CLAUDE_PLUGIN_DATA'):
        if os.environ.get(key):
            return os.environ[key]
    runtime, identity = host(), session_id()
    if identity:
        target = binding_path(runtime, identity)
        if target.is_file():
            binding = json.loads(target.read_text())
            if binding.get('host') != runtime or binding.get('session_id') != identity:
                raise RuntimeError('Craftsman session binding identity mismatch')
            return binding['data']
    if runtime != 'claude-code':
        raise RuntimeError(f'No Craftsman data binding for {runtime} session {identity}; start a session with trusted plugin hooks')
    bridge = Path(os.path.expanduser('~/.claude/craftsman-session-state-path'))
    if bridge.is_file() and bridge.read_text().strip():
        return str(Path(bridge.read_text().strip()).parent)
    return os.path.expanduser('~/.claude/plugins/data/craftsman')


def state_path() -> str:
    identity = session_id()
    name = f'session-state-{identity}.json' if identity else 'session-state.json'
    return str(Path(data_dir()) / name)


def main(arguments: list[str]) -> int:
    if arguments[0] == 'bind':
        bind(*arguments[1:5])
        return 0
    paths = {'data': data_dir, 'state': state_path, 'metrics': lambda: str(Path(data_dir()) / 'metrics.db')}
    print(paths[arguments[0]]())
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv[1:]))
    except (RuntimeError, ValueError, OSError, KeyError, IndexError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        sys.exit(1)
