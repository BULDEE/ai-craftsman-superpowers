#!/usr/bin/env python3
"""
Shared session-state management for craftsman hooks.

Provides atomic read/write operations for session-state.json,
eliminating duplication across hook scripts.

Usage from bash hooks:
    python3 "$ROOT_DIR/hooks/lib/session_state.py" <command> [args...]

Commands:
    read <state_path> <key> [default]                              - Read a key from session state
    read-json <state_path>                                         - Dump full state as JSON
    write <state_path> <json_data>                                 - Atomically write full state
    merge <state_path> <key> <json_value>                          - Atomically merge a key into state
    append <state_path> <list_key> <json_item> [max_entries]       - Atomically append to list
    increment <state_path> <counter_key>                           - Atomically increment a counter
    check-flag <state_path> <key>                                  - Print 'true'/'false' for boolean key
    record-violation <state_path> <file> <directory> <rules_json> [--detect]
                                                                   - Replace the file's pending verdicts (an
                                                                     empty list clears them) and track patterns;
                                                                     --detect also prints the cross-file patterns
    detect-patterns <state_path>                                   - Detect cross-file patterns
    pre-compact <state_path>                                       - Save session context before compaction
    post-compact <state_path>                                      - Verify state recovery after compaction
    get-previous-violations <state_path> <file>                    - Get previously blocked rules for a file
    read-session-metrics <state_path>                              - Read the subagent count and the agent types
    set-verified                                                   - Set verified=true (auto-resolves path via bridge file)
"""

import json
import os
import re
import sys
import tempfile

CROSS_FILE_PATTERN_THRESHOLD = 3
DIRECTORY_PATTERN_THRESHOLD = 2


def read_state(state_path: str) -> dict:
    try:
        with open(state_path) as state_file:
            return json.load(state_file)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def write_state_atomically(state_path: str, state: dict) -> None:
    parent_directory = os.path.dirname(state_path)
    os.makedirs(parent_directory, exist_ok=True)
    file_descriptor, temporary_path = tempfile.mkstemp(dir=parent_directory, suffix='.tmp')
    try:
        with os.fdopen(file_descriptor, 'w') as temporary_file:
            json.dump(state, temporary_file)
        os.rename(temporary_path, state_path)
    except Exception:
        try:
            os.unlink(temporary_path)
        except OSError:
            pass
        raise


def _track_violation_patterns(patterns: dict, violated_rules: list, directory: str, file_path: str) -> None:
    for rule_identifier in violated_rules:
        directory_grouping = patterns.setdefault(rule_identifier, {})
        files_in_directory = directory_grouping.setdefault(directory, [])
        if file_path not in files_in_directory:
            files_in_directory.append(file_path)


def _find_cross_file_patterns(violation_patterns: dict) -> list[str]:
    detected_patterns = []

    for rule_identifier, directory_mapping in violation_patterns.items():
        unique_files = set()
        for files_in_directory in directory_mapping.values():
            unique_files.update(files_in_directory)

        if len(unique_files) >= CROSS_FILE_PATTERN_THRESHOLD:
            detected_patterns.append(
                f'PATTERN:{rule_identifier}:{len(unique_files)} files'
            )

        for directory, files_in_directory in directory_mapping.items():
            is_meaningful_directory = directory not in ('', '.')
            if len(files_in_directory) >= DIRECTORY_PATTERN_THRESHOLD and is_meaningful_directory:
                detected_patterns.append(
                    f'DIR_PATTERN:{rule_identifier}:{directory}:{len(files_in_directory)} files'
                )

    return detected_patterns


# -- CLI Command Handlers --

def handle_read(arguments: list[str]) -> None:
    state_path, key = arguments[0], arguments[1]
    default_value = arguments[2] if len(arguments) > 2 else ''
    state = read_state(state_path)
    value = state.get(key, default_value)
    if isinstance(value, (dict, list)):
        print(json.dumps(value))
    else:
        print(value)


def handle_read_json(arguments: list[str]) -> None:
    state = read_state(arguments[0])
    json.dump(state, sys.stdout)


def handle_write(arguments: list[str]) -> None:
    state_path, data = arguments[0], json.loads(arguments[1])
    write_state_atomically(state_path, data)


def handle_merge(arguments: list[str]) -> None:
    state_path, key, value = arguments[0], arguments[1], json.loads(arguments[2])
    state = read_state(state_path)
    state[key] = value
    write_state_atomically(state_path, state)


def handle_append(arguments: list[str]) -> None:
    state_path, list_key, item = arguments[0], arguments[1], json.loads(arguments[2])
    max_entries = int(arguments[3]) if len(arguments) > 3 else None
    state = read_state(state_path)
    entries = state.setdefault(list_key, [])
    entries.append(item)
    if max_entries and len(entries) > max_entries:
        entries[:] = entries[-max_entries:]
    write_state_atomically(state_path, state)


def handle_list_upsert(arguments: list[str]) -> None:
    """list-upsert <file> <list_key> <field> <item json> [max]: replace the entry
    whose <field> equals the item's, else append; the list is capped at max."""
    state_path, list_key, field, item = arguments[0], arguments[1], arguments[2], json.loads(arguments[3])
    max_entries = int(arguments[4]) if len(arguments) > 4 else None
    state = read_state(state_path)
    entries = state.setdefault(list_key, [])
    entries[:] = [entry for entry in entries if not (isinstance(entry, dict) and entry.get(field) == item.get(field))]
    entries.append(item)
    if max_entries and len(entries) > max_entries:
        entries[:] = entries[-max_entries:]
    write_state_atomically(state_path, state)


def handle_list_remove(arguments: list[str]) -> None:
    """list-remove <file> <list_key> <field> <value>: drop every entry whose <field> equals <value>."""
    state_path, list_key, field, value = arguments[0], arguments[1], arguments[2], arguments[3]
    state = read_state(state_path)
    entries = state.get(list_key)
    if not isinstance(entries, list):
        return
    entries[:] = [entry for entry in entries if not (isinstance(entry, dict) and entry.get(field) == value)]
    write_state_atomically(state_path, state)


def handle_increment(arguments: list[str]) -> None:
    state_path, counter_key = arguments[0], arguments[1]
    state = read_state(state_path)
    state[counter_key] = state.get(counter_key, 0) + 1
    write_state_atomically(state_path, state)
    print(state[counter_key])


def handle_check_flag(arguments: list[str]) -> None:
    state_path, flag_key = arguments[0], arguments[1]
    state = read_state(state_path)
    print('true' if state.get(flag_key, False) else 'false')


def handle_record_violation(arguments: list[str]) -> None:
    """Record, and with `--detect` also print the cross-file patterns.

    The hook always detected right after recording, from a second interpreter
    start that re-read the state this one had just written. The state is in
    hand here; printing the patterns from it is the same answer one process
    earlier.
    """
    state_path, file_path, directory = arguments[0], arguments[1], arguments[2]
    violated_rules = json.loads(arguments[3])
    state = read_state(state_path)
    # The pending verdicts for THIS file, replaced on every write: a rule no
    # longer in the list was answered (fixed or ignored) by the hook before
    # this call, once, and must not be answered again on the next write. An
    # empty list clears the key, so a settled file leaves nothing behind.
    pending = state.setdefault('blocked_violations', {})
    if violated_rules:
        pending[file_path] = violated_rules
    else:
        pending.pop(file_path, None)
    violation_patterns = state.setdefault('patterns', {})
    _track_violation_patterns(violation_patterns, violated_rules, directory, file_path)
    write_state_atomically(state_path, state)
    if '--detect' in arguments[4:]:
        for pattern_description in _find_cross_file_patterns(violation_patterns):
            print(pattern_description)


def handle_detect_patterns(arguments: list[str]) -> None:
    state = read_state(arguments[0])
    violation_patterns = state.get('patterns', {})
    detected_patterns = _find_cross_file_patterns(violation_patterns)
    for pattern_description in detected_patterns:
        print(pattern_description)


def _pluralize(count: int, singular: str, plural_form: str = None) -> str:
    form = plural_form or singular + 's'
    return f'{count} {singular}' if count == 1 else f'{count} {form}'


def _build_compact_summary(state: dict) -> str:
    blocked_violations = state.get('blocked_violations', {})
    violation_patterns = state.get('patterns', {})
    tool_failure_count = state.get('tool_failure_count', 0)
    subagent_count = state.get('subagent_count', 0)

    summary_parts = []
    if blocked_violations:
        total_violations = sum(len(rules) for rules in blocked_violations.values())
        summary_parts.append(
            f'{_pluralize(total_violations, "active violation")} '
            f'across {_pluralize(len(blocked_violations), "file")}'
        )
    if violation_patterns:
        summary_parts.append(f'{_pluralize(len(violation_patterns), "cross-file pattern")} tracked')
    if tool_failure_count:
        summary_parts.append(f'{_pluralize(tool_failure_count, "tool failure")} this session')
    if subagent_count:
        summary_parts.append(f'{_pluralize(subagent_count, "subagent completion")}')

    return ' | '.join(summary_parts) if summary_parts else 'clean session'


def handle_pre_compact(arguments: list[str]) -> None:
    import datetime
    state_path = arguments[0]
    state = read_state(state_path)
    if not state:
        return

    state['last_compact'] = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    state['compact_count'] = state.get('compact_count', 0) + 1
    compact_summary = _build_compact_summary(state)
    state['pre_compact_summary'] = compact_summary
    write_state_atomically(state_path, state)

    if compact_summary != 'clean session':
        print(compact_summary)


def _assess_violation_state(blocked_violations: dict, pre_compact_summary: str) -> str:
    total_violations = sum(len(rules) for rules in blocked_violations.values()) if blocked_violations else 0
    if total_violations > 0:
        return f'Violations preserved: {total_violations} | STATE OK'
    if pre_compact_summary and 'violation' in pre_compact_summary.lower():
        return 'WARNING: violations may have been lost during compaction'
    return 'STATE OK'


def handle_post_compact(arguments: list[str]) -> None:
    state_path = arguments[0]
    state = read_state(state_path)
    if not state:
        return

    compact_count = state.get('compact_count', 0)
    pre_compact_summary = state.get('pre_compact_summary', '')

    if compact_count == 0 and not pre_compact_summary:
        return

    recovery_parts = [f'Compaction #{compact_count} completed']
    if pre_compact_summary:
        recovery_parts.append(f'Pre-compact state: {pre_compact_summary}')

    violation_assessment = _assess_violation_state(state.get('blocked_violations', {}), pre_compact_summary)
    recovery_parts.append(violation_assessment)

    tool_failure_count = state.get('tool_failure_count', 0)
    if tool_failure_count:
        recovery_parts.append(f'Tool failures tracked: {tool_failure_count}')

    print(' | '.join(recovery_parts))


def handle_get_previous_violations(arguments: list[str]) -> None:
    state_path, file_path = arguments[0], arguments[1]
    state = read_state(state_path)
    previous_rules = state.get('blocked_violations', {}).get(file_path, [])
    print(' '.join(previous_rules))


def handle_read_session_metrics(arguments: list[str]) -> None:
    """Counts for the session row, read from the keys hooks actually write.

    This read `agent_invocations`, `team_type` and `completed_tasks`, three
    keys no hook has ever written, so sessions.agents_spawned held [] on every
    row. The subagent gate writes `subagent_count` and `subagent_activity` on
    every SubagentStop: those are the same facts under the names that exist.
    """
    state_path = arguments[0]
    state = read_state(state_path)
    activity = state.get('subagent_activity', [])
    agent_types = sorted({
        entry.get('agent_type', '') for entry in activity if isinstance(entry, dict)
    } - {''})
    print(state.get('subagent_count', 0))
    print(','.join(agent_types))


def _shared_state_path() -> str:
    """The shared session-state.json, from the bridge file session-start.sh
    writes for skills in the Bash tool (without CLAUDE_PLUGIN_DATA), else the
    default data directory."""
    bridge = os.path.expanduser('~/.claude/craftsman-session-state-path')
    if os.path.isfile(bridge):
        with open(bridge) as bridge_file:
            return bridge_file.read().strip()
    return os.path.join(
        os.environ.get('CLAUDE_PLUGIN_DATA', os.path.expanduser('~/.claude/plugins/data/craftsman')),
        'session-state.json',
    )


def _environment_session_id() -> str:
    """The id the hook bound from its payload (CRAFTSMAN_SESSION_ID, see
    hooks/lib/session-files.sh) or, for a skill in a host's Bash tool, the
    INNERMOST host's variable: CODEX_SESSION_ID (measured equal to the hook
    payload's session_id on codex-cli 0.154.0) before CLAUDE_CODE_SESSION_ID,
    because a Codex session started from a Claude Code Bash tool inherits the
    Claude one and the verify wrapper then granted the evidence to the parent
    Claude session (challenge review of e2acf22, F5)."""
    raw = (os.environ.get('CRAFTSMAN_SESSION_ID')
           or os.environ.get('CODEX_SESSION_ID')
           or os.environ.get('CLAUDE_CODE_SESSION_ID', ''))
    return re.sub(r'[^A-Za-z0-9_-]', '', raw)[:64]


def _resolve_session_state_path() -> str:
    """This session's state file: the shared file's directory, the bound id."""
    shared = _shared_state_path()
    session_id = _environment_session_id()
    if not session_id:
        return shared
    return os.path.join(os.path.dirname(shared), f'session-state-{session_id}.json')


def handle_set_verified(arguments: list[str]) -> None:
    """Set verified=true in session state.

    The path is the argument when given (the hook already resolved this
    session's file from the payload it received); otherwise it is resolved
    from the bridge file and the environment, for skills running in the Bash
    tool.
    """
    import datetime

    state_path = arguments[0] if arguments else _resolve_session_state_path()
    state = read_state(state_path)
    state['verified'] = True
    state['verified_at'] = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    write_state_atomically(state_path, state)
    print(f'verified=true at {state_path}')


COMMAND_HANDLERS = {
    'read': handle_read,
    'read-json': handle_read_json,
    'write': handle_write,
    'merge': handle_merge,
    'append': handle_append,
    'list-upsert': handle_list_upsert,
    'list-remove': handle_list_remove,
    'increment': handle_increment,
    'check-flag': handle_check_flag,
    'record-violation': handle_record_violation,
    'detect-patterns': handle_detect_patterns,
    'pre-compact': handle_pre_compact,
    'post-compact': handle_post_compact,
    'get-previous-violations': handle_get_previous_violations,
    'read-session-metrics': handle_read_session_metrics,
    'set-verified': handle_set_verified,
}

if __name__ == '__main__':
    available_commands = '|'.join(COMMAND_HANDLERS)
    if len(sys.argv) < 2 or sys.argv[1] not in COMMAND_HANDLERS:
        print(f"Usage: {sys.argv[0]} <{available_commands}> [args...]", file=sys.stderr)
        sys.exit(1)
    try:
        COMMAND_HANDLERS[sys.argv[1]](sys.argv[2:])
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
