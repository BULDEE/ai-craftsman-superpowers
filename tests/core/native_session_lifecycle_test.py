"""Session lifecycle consumers must share the host's bound store."""
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class NativeSessionLifecycleTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.package_temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.package_temp.cleanup)
        cls.plugin = Path(cls.package_temp.name) / 'plugin'
        shutil.copytree(ROOT, cls.plugin, ignore=shutil.ignore_patterns('.git', '__pycache__'))

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for name in ('home/.claude', 'native', 'parent', 'project'):
            (self.root / name).mkdir(parents=True)
        self.env = {
            'PATH': os.environ.get('PATH', os.defpath), 'HOME': str(self.root / 'home'),
            'CRAFTSMAN_RUNTIME_HOME': str(self.root / 'home'),
            'CLAUDE_PLUGIN_ROOT': str(self.plugin),
            'CLAUDE_PLUGIN_OPTION_STRICTNESS': 'strict',
            'CLAUDE_PLUGIN_OPTION_AGENT_HOOKS': 'false',
        }
        self.native = self.root / 'native'
        self.parent = self.root / 'parent'

    def select_host(self, host):
        for key in ('CODEX_SESSION_ID', 'GROK_SESSION_ID', 'CLAUDE_CODE_SESSION_ID'):
            self.env.pop(key, None)
        self.host = host
        self.env[{'codex': 'CODEX_SESSION_ID', 'grok': 'GROK_SESSION_ID',
                  'claude-code': 'CLAUDE_CODE_SESSION_ID'}[host]] = 'outer'

    def payload(self, **fields):
        payload = {'session_id': 'child', 'cwd': str(self.root / 'project'), **fields}
        if self.host == 'grok':
            payload.update(workspaceRoot=str(self.root / 'project'), hookEventName='session_start')
        if self.host == 'claude-code':
            payload.update(prompt_id='native-claude')
        if self.host == 'codex':
            payload.update(model='codex', transcript_path=None)
        return payload

    def run_hook(self, name, **fields):
        return subprocess.run(['bash', str(self.plugin / 'hooks' / name)],
                              input=json.dumps(self.payload(**fields)), env=self.env,
                              cwd=self.root / 'project', text=True, capture_output=True, timeout=90)

    def bind(self, identity='child', store=None):
        subprocess.run(['python3', str(self.plugin / 'hooks/lib/runtime_paths.py'), 'bind',
                        self.host, identity, str(self.plugin), str(store or self.native)],
                       env=self.env, check=True, capture_output=True)

    def binding(self):
        directory = '.claude' if self.host == 'claude-code' else '.' + self.host
        return self.root / 'home' / directory / 'craftsman/sessions/child.json'

    def test_start_uses_native_alias_and_payload_identity(self):
        for host, alias in [('codex', 'PLUGIN_DATA'), ('grok', 'GROK_PLUGIN_DATA'), ('claude-code', 'CLAUDE_PLUGIN_DATA')]:
            with self.subTest(host=host):
                self.select_host(host)
                self.env[alias] = str(self.native)
                result = self.run_hook('session-start.sh')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(self.binding().read_text())['data'], str(self.native))
                self.assertTrue((self.native / 'session-start-ts-child').is_file())
                self.assertFalse((self.native / 'session-start-ts-outer').exists())
                self.env.pop(alias)

    def test_start_preserves_binding_and_never_initializes_parent_database(self):
        self.select_host('codex')
        self.bind()
        self.bind('outer', self.parent)
        self.env.update(CLAUDE_PLUGIN_DATA=str(self.parent), CLAUDE_CODE_SESSION_ID='parent')
        result = self.run_hook('session-start.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.binding().read_text())['data'], str(self.native))
        self.assertTrue((self.native / 'metrics.db').is_file())
        self.assertEqual(list(self.parent.iterdir()), [])

    def test_lifecycle_consumers_share_binding_despite_parent_environment(self):
        self.select_host('grok')
        self.bind()
        self.bind('outer', self.parent)
        self.env.update(CLAUDE_PLUGIN_DATA=str(self.parent), CLAUDE_CODE_SESSION_ID='parent')
        state = self.native / 'session-state-child.json'
        sentinel = self.parent / state.name
        sentinel.write_text('{"parent_sentinel":true}')
        state.write_text('{"verified":true,"design_used":true,"blocked_violations":{"Example.php":["PHP001"]}}')
        (self.native / 'session-writes-child').write_text('Example.php\n')
        (self.native / 'session-violations-child').write_text('blocked\n')
        for hook in ('pre-compact-save.sh', 'post-compact-verify.sh'):
            result = self.run_hook(hook)
            self.assertIn('systemMessage', result.stdout, result.stderr)
        fixture = json.loads((ROOT / 'tests/fixtures/hosts/grok/1.0.30/post-tool-use.bash.pytest-missing-exit1.json').read_text())
        fixture.pop('session_id', None)
        fixture.pop('cwd', None)
        failed = self.run_hook('post-bash-test-verify.sh', **fixture)
        self.assertEqual(failed.returncode, 2, failed.stdout + failed.stderr)
        self.assertFalse(json.loads(state.read_text())['verified'])
        self.assertTrue((self.native / 'test-failures.log').is_file())
        completed = self.run_hook('task-completed-verify.sh', task={'subject': 'Implement endpoint'})
        self.assertEqual(completed.returncode, 2, completed.stdout + completed.stderr)
        ended = self.run_hook('session-metrics.sh', reason='exit')
        self.assertEqual(ended.returncode, 0, ended.stderr)
        with sqlite3.connect(self.native / 'metrics.db') as database:
            self.assertEqual(database.execute('SELECT writes_count, violations_blocked FROM sessions').fetchall(), [(1, 1)])
        self.assertFalse(state.exists())
        self.assertFalse((self.native / 'session-writes-child').exists())
        self.assertEqual(sentinel.read_text(), '{"parent_sentinel":true}')
        self.assertEqual(list(self.parent.iterdir()), [sentinel])

    def test_prompt_recovery_writes_design_state_to_native_store(self):
        self.select_host('grok')
        self.env['GROK_PLUGIN_DATA'] = str(self.native)
        result = self.run_hook('bias-detector.sh', prompt='/craftsman:design Create account')
        self.assertEqual(result.returncode, 0, result.stderr)
        state = self.native / 'session-state-child.json'
        self.assertTrue(state.exists(), result.stdout + result.stderr)
        self.assertTrue(json.loads(state.read_text())['design_used'])
        self.assertFalse((self.root / 'home/.claude/plugins/data/craftsman').exists())

    def test_unbound_native_start_does_not_invent_claude_storage(self):
        self.select_host('codex')
        result = self.run_hook('session-start.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.binding().exists())
        self.assertFalse(list((self.root / 'home/.claude').iterdir()))
        self.assertNotIn('Metrics: initialized', result.stdout)

    def test_new_native_session_cannot_adopt_foreign_claude_store(self):
        self.select_host('grok')
        self.env.update(CLAUDE_PLUGIN_DATA=str(self.parent), CLAUDE_CODE_SESSION_ID='parent')
        result = self.run_hook('session-start.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.binding().exists())
        self.assertEqual(list(self.parent.iterdir()), [])

    def test_native_metrics_do_not_adopt_legacy_claude_database(self):
        self.select_host('codex')
        self.env['PLUGIN_DATA'] = str(self.native)
        legacy = self.root / 'home/.claude/plugins/data/craftsman/metrics.db'
        legacy.parent.mkdir(parents=True)
        with sqlite3.connect(legacy) as database:
            database.execute('CREATE TABLE parent_sentinel (value TEXT)')
        result = self.run_hook('session-start.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        with sqlite3.connect(self.native / 'metrics.db') as database:
            self.assertEqual(database.execute("SELECT name FROM sqlite_master WHERE name='parent_sentinel'").fetchall(), [])

    def test_payload_host_ignores_foreign_grok_data_alias(self):
        for host, alias in [('codex', 'PLUGIN_DATA'), ('claude-code', 'CLAUDE_PLUGIN_DATA')]:
            with self.subTest(host=host):
                self.select_host(host)
                self.env.update(GROK_SESSION_ID='foreign', GROK_PLUGIN_DATA=str(self.parent))
                self.env[alias] = str(self.native)
                result = self.run_hook('tool-failure-tracker.sh', tool_name='Bash', error='failed')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue((self.native / 'session-state-child.json').exists())
                self.assertEqual(list(self.parent.iterdir()), [])
                self.env.pop(alias)
                (self.native / 'session-state-child.json').unlink()

    def test_missing_python_never_treats_unresolved_writes_as_zero(self):
        self.select_host('claude-code')
        self.env['CLAUDE_PLUGIN_DATA'] = str(self.native)
        (self.native / 'session-writes-child').write_text('Example.php\n')
        (self.native / 'session-state-child.json').write_text('{"verified":false}')
        binaries = self.root / 'bin'
        binaries.mkdir()
        for tool in ('bash', 'dirname', 'cat', 'jq', 'tr', 'cut', 'wc', 'grep', 'sed', 'awk'):
            (binaries / tool).symlink_to(shutil.which(tool))
        self.env['PATH'] = str(binaries)
        result = self.run_hook('task-completed-verify.sh', task={'subject': 'Implement endpoint'})
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        command = ('source "$CLAUDE_PLUGIN_ROOT/hooks/lib/channel-cache.sh"; '
                   'source "$CLAUDE_PLUGIN_ROOT/hooks/lib/circuit-breaker.sh"; '
                   'printf "%s|%s" "$(_cache_entry_file sentry key)" "$(_cb_state_file sentry)"')
        cache = subprocess.run(['bash', '-c', command], env=self.env, text=True, capture_output=True)
        self.assertEqual(cache.returncode, 0, cache.stderr)
        self.assertEqual(cache.stdout, '|')

    def test_pre_write_caches_use_payload_binding_before_parent_environment(self):
        self.select_host('codex')
        self.bind()
        self.bind('outer', self.parent)
        self.env.update(CLAUDE_PLUGIN_DATA=str(self.parent), CLAUDE_CODE_SESSION_ID='parent')
        result = self.run_hook('pre-write-check.sh', tool_name='Write', tool_input={
            'file_path': str(self.root / 'project/Example.php'), 'content': '<?php\nclass Example {}\n',
        })
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn('PHP002', result.stdout + result.stderr)
        self.assertEqual(list(self.parent.iterdir()), [])
        self.assertTrue(list(self.native.iterdir()))

    def test_failure_tracker_binds_before_writing_state(self):
        self.select_host('codex')
        self.bind()
        self.env['CLAUDE_PLUGIN_DATA'] = str(self.parent)
        result = self.run_hook('tool-failure-tracker.sh', tool_name='Bash', error='failed')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads((self.native / 'session-state-child.json').read_text())['tool_failure_count'], 1)
        self.assertEqual(list(self.parent.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
