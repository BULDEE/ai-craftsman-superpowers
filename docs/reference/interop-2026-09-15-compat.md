# Host compatibility, as measured on 2026-09-15

Branch `feat/interop-host-adapters` (from `784091f`). This table says what
was PROVEN, by which instrument, on which version. A row that says
"documented" was not seen on a wire; a row that says "captured" or "e2e" was.
Nothing here is a badge: a host is compatible for the rows it has, and no
more. Evidence: `tests/fixtures/hosts/PROVENANCE.md`,
`docs/reference/interop-2026-09-15-evidence/`, and the suites named.

Levels of proof, from weakest to strongest:

- **documented**: read in the vendor's reference, transcribed to a fixture
  marked as such; the suite proves the adapter honours the text.
- **captured**: the real CLI sent the payload to a `cat >> file` hook; the
  suite runs the real hook on that payload.
- **e2e**: the real CLI, driven by a prompt, ran the real hook and the effect
  was observed (file present or absent on disk, row in `metrics.db`, text
  delivered to the model).

| Capability | Claude Code 2.1.272 | Codex CLI 0.154.0 | Copilot CLI / VS Code / cloud | Hermes |
|---|---|---|---|---|
| Write refused before disk (LAYER001, PHP002) | e2e (existing) | **e2e**: `codex exec`, `apply_patch` refused, valid class written, `phpstan.neon` refused | documented (`create`, `edit`, `str_replace_editor` translated; exit 2 = deny) | e2e (existing, `pre-tool-call.sh`) |
| Multi-file patch, move, anchors, EOF | n/a (Write/Edit are single-file) | captured + unit (real V4A capture; 7 review findings each with a witness) | documented (`apply_patch` tool routed to the same reader) | UNJUDGED refusal (unchanged) |
| Gate's own config (`.craft-rules.yml`) | `ask` (captured host, supported) | **deny** (ask documented as unsupported) | deny (ask = deny in cloud, documented) | deny (existing) |
| Test run grants/revokes verification evidence | **e2e**: PostToolUse = pass, PostToolUseFailure `Exit code N` = fail, background run pending until TaskOutput | captured: shell output is a bare string, **exit code not observable**, state `unknown`, nothing granted or revoked | documented: `tool_result.result_type` success/failure (no exit code) | n/a (`pre_verify` runs the suite itself) |
| Session identity from the payload | e2e (SessionEnd finds its own files) | **e2e**: Codex launched from a Claude Code Bash tool inherits the parent's `CLAUDE_CODE_SESSION_ID` and still files under its own id | documented (`sessionId` / `session_id` translated) | existing |
| Skills discovered (22) | existing | **captured** (`codex debug prompt-input`): symlinked SKILL.md absent, regular copy present; learned skill in `.agents/skills` listed | not measured | n/a |
| Agents / roles | native | roles exported (`craftsman-ci export --target codex-agents [--into DIR]`); `~/.codex/agents/` observed offered to `spawn_agent`; project `.codex/agents/` **not offered** in three `codex exec` runs (ephemeral, persistent, project trusted via `-c`) | documented as different profile formats, not projected | n/a |
| Review context (`craftsman-context review`) | injected lines kept | **e2e**: Codex ran the collector from the skill and returned the right verdict | not measured | n/a |
| Semantic review backend | `claude -p` (existing) | **e2e**: `agent-ddd-verifier` through `codex exec`, one HAIKU_LAYER row, backend recorded | not implemented (no backend) | n/a |
| Events loaded | 12 of 12 (documented) | 11 kinds, **not** TaskCompleted / PostToolUseFailure / FileChanged (generated schema) | documented list, not measured | n/a |
| Subagent gate | captured (`agent_transcript_path`) | null transcript: judges nothing (stated) | not measured | n/a |
| Sentry request at Stop | captured Stop payload; handoff on next prompt | captured Stop payload | not measured | n/a |
| `agent_hooks: false` reaches the consumer | e2e (fake CLI records the call) | via the global file (no plugin options) | via the global file | n/a |
| Fresh install from the built archive | e2e (`tests/meta/test-fresh-install.sh`) | same tree | same tree | same tree |
| Delivery of a background finding | asyncRewake on exit 2 | at the next safe point, no wake of an idle session (documented) | `additionalContext` (documented) | conclusion gate |

## Independent verification (2026-09-15, on d08e0ec)

Codex 0.154.0 and Grok 1.0.30 ran `docs/reference/interop-2026-09-15-verify-prompt.md`
in isolated clones (reports: `interop-2026-09-15-evidence/verify-*.txt`). Both:
CHANGES_REQUIRED. Both confirmed the suites (275/0 with an isolated HOME), the
five red guardrails, and every "captured" and "script direct" row above; neither
could exercise the model-driven rows (no credentials in the isolated HOME, and
Grok's sandbox refused `codex exec`), so those rows rest on this campaign's own
e2e runs. The fourteen findings they raised were all reproduced and fixed with
a witness: symlinked parents or skill directories carrying a write out of the
project (instincts, roles, doctrine), a landed Update patch re-applied and
reported unvalidated, a compound shell command's result read as the runner's,
a host's own hook wiring (`.codex/hooks.json`, `.github/hooks/*.json`) not
treated as gate machinery, a `DDD_VIOLATIONS` reply with nothing readable read
as clean and closing earlier findings, a poisoned empty registry cache trusted
for a month, the Copilot adapter defaulting to Claude Code's data tree, the
standalone CI test reading the developer's real HOME, mixed line endings
normalised, and a raw `patch` body listed as touching nothing.

## Open, with the action that closes each

- A real `spawn_agent` of a `craftsman-*` role: project-level `.codex/agents/`
  was not offered in three `codex exec` runs on 0.154.0 (ephemeral,
  persistent, project trusted), so the roles have to reach
  `~/.codex/agents/` (`craftsman-ci export --target codex-agents --into
  "$HOME/.codex/agents"`), which is the user's installation and was not
  written by this campaign; run that, then ask a session for `list_agents`.
- Codex plugin-bundled hook environment (`PLUGIN_ROOT`, options): only a
  project hook was captured; install the built archive as a Codex plugin and
  capture one PreToolUse.
- Copilot, every surface: `tests/fixtures/hosts/copilot/documented/PROVENANCE.md`
  names the capture that replaces the documented fixtures.
- Codex shell exit codes: not observable on 0.154.0; the verification loop
  grants nothing there by design. Re-measure on each Codex release.
- A Claude Code background test run the model never polls stays pending.
- Grok as a host: not started (separate audit, as agreed). Grok as a review
  backend: not implemented; the port takes a backend in one function.
