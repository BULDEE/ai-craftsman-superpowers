from itertools import product
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'hooks/lib'))
import session_state
import runtime_paths


class RuntimePathsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.process_path = os.environ.get('PATH', os.defpath)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = patch.dict(os.environ, {}, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)
        original = os.path.expanduser
        mock = patch('os.path.expanduser', side_effect=lambda p: str(self.root) + p[1:] if p.startswith('~') else original(p))
        mock.start()
        self.addCleanup(mock.stop)
        (self.root / '.claude').mkdir()
        (self.root / '.claude/craftsman-session-state-path').write_text('/stale/claude/session-state.json')

    def test_explicit_native_store_beats_legacy_bridge(self) -> None:
        os.environ.update(CODEX_SESSION_ID='codex-child', CLAUDE_CODE_SESSION_ID='claude-parent', PLUGIN_DATA=str(self.root / 'codex'))
        self.assertEqual(session_state._resolve_session_state_path(), str(self.root / 'codex/session-state-codex-child.json'))

    def test_grok_session_beats_parent_host_identity(self) -> None:
        os.environ.update(GROK_SESSION_ID='grok-child', CODEX_SESSION_ID='codex-parent', GROK_PLUGIN_DATA=str(self.root / 'grok'))
        self.assertEqual(session_state._resolve_session_state_path(), str(self.root / 'grok/session-state-grok-child.json'))

    def test_codex_thread_id_is_a_session_identity(self) -> None:
        os.environ.update(CODEX_THREAD_ID='thread', PLUGIN_DATA=str(self.root / 'codex'))
        self.assertEqual(session_state._resolve_session_state_path(), str(self.root / 'codex/session-state-thread.json'))

    def test_session_binding_survives_other_host_start(self) -> None:
        import runtime_paths
        runtime_paths.bind('codex', 'one', '/plugins/codex', str(self.root / 'one'))
        runtime_paths.bind('codex', 'two', '/plugins/codex', str(self.root / 'two'))
        runtime_paths.bind('grok', 'one', '/plugins/grok', str(self.root / 'grok'))
        os.environ['CODEX_SESSION_ID'] = 'one'
        session_state.handle_set_verified([])
        self.assertTrue(json.loads((self.root / 'one/session-state-one.json').read_text())['verified'])
        self.assertFalse((self.root / 'two/session-state-one.json').exists())
        self.assertFalse((self.root / 'grok/session-state-one.json').exists())

    def test_unbound_native_session_does_not_read_claude_bridge(self) -> None:
        os.environ['CODEX_SESSION_ID'] = 'missing'
        with self.assertRaises(RuntimeError):
            session_state._resolve_session_state_path()

    def test_binding_beats_inherited_data_environment(self) -> None:
        hosts = [('codex', 'CODEX_SESSION_ID'), ('grok', 'GROK_SESSION_ID')]
        aliases = ('CRAFTSMAN_PLUGIN_DATA', 'GROK_PLUGIN_DATA', 'PLUGIN_DATA', 'CLAUDE_PLUGIN_DATA')
        for (runtime, identity_key), data_key in product(hosts, aliases):
            with self.subTest(runtime=runtime, data_key=data_key), patch.dict(os.environ, {
                identity_key: 'child', data_key: str(self.root / 'foreign'),
                'CLAUDE_CODE_SESSION_ID': 'parent',
            }, clear=True):
                runtime_paths.bind(runtime, 'child', '/plugin', str(self.root / runtime))
                (self.root / runtime / 'session-state-child.json').unlink(missing_ok=True)
                session_state.handle_set_verified([])
                self.assertTrue(json.loads((self.root / runtime / 'session-state-child.json').read_text())['verified'])
                self.assertFalse((self.root / 'foreign').exists())

    def test_binding_rejects_content_for_another_host_or_session(self) -> None:
        os.environ['CODEX_SESSION_ID'] = 'child'
        for field, foreign in [('host', 'grok'), ('session_id', 'parent')]:
            with self.subTest(field=field):
                runtime_paths.bind('codex', 'child', '/plugin', '/codex/data')
                target = runtime_paths.binding_path('codex', 'child')
                binding = json.loads(target.read_text())
                binding[field] = foreign
                target.write_text(json.dumps(binding))
                os.environ['CLAUDE_PLUGIN_DATA'] = '/foreign/data'
                with self.assertRaisesRegex(RuntimeError, 'identity mismatch'):
                    runtime_paths.data_dir()

    def run_grok_prompt(self, with_data: bool = True, data_key: str = 'CLAUDE_PLUGIN_DATA') -> None:
        plugin = Path(__file__).resolve().parents[2]
        env = {'PATH': self.process_path, 'HOME': str(self.root),
               'CRAFTSMAN_RUNTIME_HOME': str(self.root), 'GROK_SESSION_ID': 'outer',
               'CLAUDE_PLUGIN_ROOT': str(plugin)}
        if with_data:
            env[data_key] = str(self.root / 'native-data')
        payload = {'workspaceRoot': str(self.root), 'hookEventName': 'user_prompt_submit',
                   'session_id': 'native', 'prompt': 'Read the current status.'}
        result = subprocess.run(['bash', str(plugin / 'hooks/bias-detector.sh')],
                                input=json.dumps(payload), text=True, capture_output=True,
                                env=env, cwd=self.root)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_grok_prompt_recovers_native_binding_without_session_start(self) -> None:
        self.run_grok_prompt()
        os.environ['GROK_SESSION_ID'] = 'native'
        self.assertEqual(session_state._resolve_session_state_path(), str(self.root / 'native-data/session-state-native.json'))
        self.assertFalse((self.root / '.grok/craftsman/sessions/outer.json').exists())
        self.assertEqual((self.root / '.claude/craftsman-session-state-path').read_text(), '/stale/claude/session-state.json')

    def test_grok_prompt_without_native_store_does_not_bind_claude_default(self) -> None:
        self.run_grok_prompt(with_data=False)
        os.environ['GROK_SESSION_ID'] = 'native'
        with self.assertRaises(RuntimeError):
            session_state._resolve_session_state_path()

    def test_grok_prompt_preserves_existing_binding_despite_inherited_store(self) -> None:
        runtime_paths.bind('grok', 'native', '/plugin', str(self.root / 'bound-data'))
        self.run_grok_prompt()
        target = runtime_paths.binding_path('grok', 'native')
        self.assertEqual(json.loads(target.read_text())['data'], str(self.root / 'bound-data'))

    def test_grok_prompt_recovers_each_explicit_data_alias(self) -> None:
        for key in ('GROK_PLUGIN_DATA', 'PLUGIN_DATA', 'CRAFTSMAN_PLUGIN_DATA'):
            with self.subTest(key=key):
                target = runtime_paths.binding_path('grok', 'native')
                target.unlink(missing_ok=True)
                self.run_grok_prompt(data_key=key)
                self.assertEqual(json.loads(target.read_text())['data'], str(self.root / 'native-data'))

    def hook_environment(self, runtime: str) -> dict[str, str]:
        return {'PATH': self.process_path, 'HOME': str(self.root),
                'CRAFTSMAN_RUNTIME_HOME': str(self.root),
                f'{runtime.upper()}_SESSION_ID': 'child',
                'CLAUDE_PLUGIN_ROOT': str(Path(__file__).resolve().parents[2]),
                'CLAUDE_PLUGIN_OPTION_STRICTNESS': 'strict',
                'CRAFTSMAN_HEADLESS_VERIFY': '1'}

    def test_unbound_native_gate_still_blocks_and_accepts_clean_control(self) -> None:
        plugin = Path(__file__).resolve().parents[2]
        foreign = self.root / '.claude/plugins/data/craftsman'
        foreign.mkdir(parents=True)
        sentinel = foreign / 'session-state-parent.json'
        sentinel.write_text('{"verified": true}')
        contents = [("<?php\nclass Example { public function setName($name) {} }\n", 2),
                    ("<?php\ndeclare(strict_types=1);\nfinal class Example {}\n", 0)]
        hooks = ('post-write-check.sh', 'pre-write-check.sh')
        for runtime, (content, expected), hook in product(('codex', 'grok'), contents, hooks):
            with self.subTest(runtime=runtime, expected=expected, hook=hook):
                target = self.root / 'Example.php'
                target.write_text(content)
                payload = {'session_id': 'child', 'tool_name': 'Write',
                           'tool_input': {'file_path': str(target), 'content': content}}
                result = subprocess.run(['bash', str(plugin / 'hooks' / hook)],
                                        input=json.dumps(payload), text=True, capture_output=True,
                                        cwd=self.root, env=self.hook_environment(runtime))
                self.assert_gate_result(result, expected)
                self.assertEqual(list(foreign.glob('session-*')), [sentinel])
                self.assertEqual(sentinel.read_text(), '{"verified": true}')

    def test_post_write_state_uses_binding_before_parent_environment(self) -> None:
        plugin = Path(__file__).resolve().parents[2]
        for runtime in ('codex', 'grok'):
            with self.subTest(runtime=runtime):
                native = self.root / runtime
                native.mkdir()
                runtime_paths.bind(runtime, 'child', str(plugin), str(native))
                env = self.hook_environment(runtime)
                env['CLAUDE_PLUGIN_DATA'] = str(self.root / 'parent')
                content = "<?php\nclass Example {}\n"
                target = self.root / 'Example.php'
                target.write_text(content)
                payload = {'session_id': 'child', 'tool_name': 'Write',
                           'tool_input': {'file_path': str(target), 'content': content}}
                result = subprocess.run(['bash', str(plugin / 'hooks/post-write-check.sh')],
                                        input=json.dumps(payload), text=True, capture_output=True,
                                        cwd=self.root, env=env)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertTrue((native / 'session-state-child.json').is_file())
                self.assertIn(str(target), (native / 'session-writes-child').read_text())
                self.assertIn('blocked', (native / 'session-violations-child').read_text())
                self.assertFalse(list((self.root / 'parent').glob('session-*')))

    def assert_gate_result(self, result: subprocess.CompletedProcess, expected: int) -> None:
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        if expected == 2:
            self.assertIn('PHP001', result.stdout + result.stderr)
            self.assertIn('PHP002', result.stdout + result.stderr)
        self.assertNotIn('failed at line', result.stderr)
        self.assertFalse(list(self.root.rglob('metrics.db')))
        self.assertFalse(list(self.root.rglob('violations-queue.*')))

    def test_unbound_metrics_functions_are_inert_but_pure_helpers_work(self) -> None:
        script = '''set -eu
source "$CLAUDE_PLUGIN_ROOT/hooks/lib/metrics-db.sh"
[[ -z "$METRICS_DB" ]]
for function in metrics_init metrics_violations_queue_open metrics_violations_queue_flush \
    metrics_record_violation metrics_record_haiku_run metrics_haiku_last_finding_hash \
    metrics_haiku_previous_rules metrics_record_session metrics_violations_7d metrics_trend \
    metrics_record_correction metrics_haiku_report metrics_record_verdict metrics_acceptance_report \
    metrics_corrections_30d metrics_correction_trends metrics_correction_trends_global; do
    "$function"
done
[[ -n "$(metrics_file_pattern src/Example.php)" ]]
[[ -n "$(metrics_project_hash)" ]]
'''
        result = subprocess.run(['bash', '-c', script], text=True, capture_output=True,
                                cwd=self.root, env=self.hook_environment('codex'))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stderr, '')

    def test_metrics_source_uses_binding_before_parent_environment(self) -> None:
        plugin = Path(__file__).resolve().parents[2]
        runtime_paths.bind('codex', 'child', str(plugin), str(self.root / 'native'))
        env = self.hook_environment('codex')
        env['CLAUDE_PLUGIN_DATA'] = str(self.root / 'parent')
        result = subprocess.run(['bash', '-c', 'source "$CLAUDE_PLUGIN_ROOT/hooks/lib/metrics-db.sh"; printf "%s" "$METRICS_DB"'],
                                text=True, capture_output=True, cwd=self.root, env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, str(self.root / 'native/metrics.db'))


if __name__ == '__main__':
    unittest.main()
