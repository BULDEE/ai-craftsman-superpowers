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
    record-violation <state_path> <file> <directory> <rules_json>  - Record violation with pattern tracking
    detect-patterns <state_path>                                   - Detect cross-file patterns
    pre-compact <state_path>                                       - Save session context before compaction
    post-compact <state_path>                                      - Verify state recovery after compaction
    get-previous-violations <state_path> <file>                    - Get previously blocked rules for a file
    read-session-metrics <state_path>                              - Read agent/team/task counts for metrics
"""

import json
import os
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
    state_path, file_path, directory = arguments[0], arguments[1], arguments[2]
    violated_rules = json.loads(arguments[3])
    state = read_state(state_path)
    state.setdefault('blocked_violations', {})[file_path] = violated_rules
    violation_patterns = state.setdefault('patterns', {})
    _track_violation_patterns(violation_patterns, violated_rules, directory, file_path)
    write_state_atomically(state_path, state)


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
    state_path = arguments[0]
    state = read_state(state_path)
    agent_invocation_count = state.get('agent_invocations', 0)
    team_type = state.get('team_type', '')
    completed_task_count = len(state.get('completed_tasks', []))
    print(agent_invocation_count)
    print(team_type)
    print(completed_task_count)


COMMAND_HANDLERS = {
    'read': handle_read,
    'read-json': handle_read_json,
    'write': handle_write,
    'merge': handle_merge,
    'append': handle_append,
    'increment': handle_increment,
    'check-flag': handle_check_flag,
    'record-violation': handle_record_violation,
    'detect-patterns': handle_detect_patterns,
    'pre-compact': handle_pre_compact,
    'post-compact': handle_post_compact,
    'get-previous-violations': handle_get_previous_violations,
    'read-session-metrics': handle_read_session_metrics,
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
