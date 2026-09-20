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


class RuntimePathsTest(unittest.TestCase):
    def setUp(self):
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

    def test_explicit_native_store_beats_legacy_bridge(self):
        os.environ.update(CODEX_SESSION_ID='codex-child', CLAUDE_CODE_SESSION_ID='claude-parent', CLAUDE_PLUGIN_DATA=str(self.root / 'codex'))
        self.assertEqual(session_state._resolve_session_state_path(), str(self.root / 'codex/session-state-codex-child.json'))

    def test_grok_session_beats_parent_host_identity(self):
        os.environ.update(GROK_SESSION_ID='grok-child', CODEX_SESSION_ID='codex-parent', GROK_PLUGIN_DATA=str(self.root / 'grok'))
        self.assertEqual(session_state._resolve_session_state_path(), str(self.root / 'grok/session-state-grok-child.json'))

    def test_codex_thread_id_is_a_session_identity(self):
        os.environ.update(CODEX_THREAD_ID='thread', PLUGIN_DATA=str(self.root / 'codex'))
        self.assertEqual(session_state._resolve_session_state_path(), str(self.root / 'codex/session-state-thread.json'))

    def test_session_binding_survives_other_host_start(self):
        import runtime_paths
        runtime_paths.bind('codex', 'one', '/plugins/codex', str(self.root / 'one'))
        runtime_paths.bind('codex', 'two', '/plugins/codex', str(self.root / 'two'))
        runtime_paths.bind('grok', 'one', '/plugins/grok', str(self.root / 'grok'))
        os.environ['CODEX_SESSION_ID'] = 'one'
        session_state.handle_set_verified([])
        self.assertTrue(json.loads((self.root / 'one/session-state-one.json').read_text())['verified'])
        self.assertFalse((self.root / 'two/session-state-one.json').exists())
        self.assertFalse((self.root / 'grok/session-state-one.json').exists())

    def test_unbound_native_session_does_not_read_claude_bridge(self):
        os.environ['CODEX_SESSION_ID'] = 'missing'
        with self.assertRaises(RuntimeError):
            session_state._resolve_session_state_path()

    def run_grok_prompt(self, with_data=True):
        plugin = Path(__file__).resolve().parents[2]
        env = {'PATH': self.process_path, 'HOME': str(self.root),
               'CRAFTSMAN_RUNTIME_HOME': str(self.root), 'GROK_SESSION_ID': 'outer',
               'CLAUDE_PLUGIN_ROOT': str(plugin)}
        if with_data:
            env['CLAUDE_PLUGIN_DATA'] = str(self.root / 'native-data')
        payload = {'workspaceRoot': str(self.root), 'hookEventName': 'user_prompt_submit',
                   'session_id': 'native', 'prompt': 'Read the current status.'}
        result = subprocess.run(['bash', str(plugin / 'hooks/bias-detector.sh')],
                                input=json.dumps(payload), text=True, capture_output=True,
                                env=env, cwd=self.root)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_grok_prompt_recovers_native_binding_without_session_start(self):
        self.run_grok_prompt()
        os.environ['GROK_SESSION_ID'] = 'native'
        self.assertEqual(session_state._resolve_session_state_path(), str(self.root / 'native-data/session-state-native.json'))
        self.assertFalse((self.root / '.grok/craftsman/sessions/outer.json').exists())
        self.assertEqual((self.root / '.claude/craftsman-session-state-path').read_text(), '/stale/claude/session-state.json')

    def test_grok_prompt_without_native_store_does_not_bind_claude_default(self):
        self.run_grok_prompt(with_data=False)
        os.environ['GROK_SESSION_ID'] = 'native'
        with self.assertRaises(RuntimeError):
            session_state._resolve_session_state_path()


if __name__ == '__main__':
    unittest.main()
