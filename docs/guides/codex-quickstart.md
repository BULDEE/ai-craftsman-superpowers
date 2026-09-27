# Codex Quickstart

Craftsman for [Codex](https://developers.openai.com/codex) in five minutes. For
the other hosts, see the [main README](../../README.md#install). What Codex
loads and observes is recorded in
[`hooks/host-capabilities.json`](../../hooks/host-capabilities.json), row
`codex`, with its provenance in
[`tests/fixtures/hosts/PROVENANCE.md`](../../tests/fixtures/hosts/PROVENANCE.md).

## What you get

| Capability | On Codex |
|------------|----------|
| Write gate before disk | yes, on `apply_patch` (V4A patches, multi-file, moves) |
| `ask` decision | not offered by the host: the gate denies instead |
| Test evidence (grant and revoke) | no: the shell event carries no exit code, so a test run grants and revokes nothing |
| Skills | 22, loaded from the native manifest |
| Agents | the 12 missions ship as files; named roles are optional (see [Agent roles](#agent-roles)) |
| Config protection | a change that relaxes the gate is refused before disk |

## Install

Prerequisites: Codex 0.155.1 or later (the version the matrix records), plus
`python3` 3.9+, `bash`, `jq`, `sqlite3` and `git`.

```bash
codex plugin marketplace add BULDEE/ai-craftsman-superpowers
codex plugin add craftsman@ai-craftsman-superpowers
codex          # then /hooks: review and trust the craftsman handlers
```

The native entry point is `.codex-plugin/plugin.json`, catalogued by
`.agents/plugins/marketplace.json`. No Claude import is required.

**Installing does not trust the hooks.** Until you review them in `/hooks`,
the 14 handlers are loaded and reported `untrusted`, and they do not run.
This is the step people miss: an installed, enabled, untrusted gate refuses
nothing.

## Verify it works

Ask Codex to run the craftsman `healthcheck` skill. Its host row reads the
`codex` entry of the capability matrix and says which step is still missing.

Then provoke a refusal on purpose: ask Codex to create
`src/Domain/Order.ts` containing `export const load = (x: any) => x;`. The
patch must be refused (TS001) and the file must not appear on disk.

## Agent roles

Codex's role loader reads configuration directories, not the plugin manifest,
so named plugin roles are not loaded by installing. The shipped `agents/`
missions work for generic subagent dispatch. To register them as named roles,
export them once (optional):

```bash
bash /path/to/ai-craftsman-superpowers/ci/craftsman-ci.sh export \
  --target codex-agents --into "${CODEX_HOME:-$HOME/.codex}/agents"
```

## Limits

- The gate judges `apply_patch`. A file written by a shell command
  (`printf > file`, `sed -i`, a script) is not gated before disk: CI
  (`ci/craftsman-ci.sh`) catches it. The pre-push hook reads no file and only
  warns.
- `FileChanged`, `PostToolUseFailure` and `TaskCompleted` are not fired by
  this host, so external-edit tracking, failed-tool tracking and the
  evidence gate before a task completes do not run there.
- A background hook cannot wake an idle Codex session.

## Upgrade and uninstall

```bash
codex plugin marketplace upgrade
codex plugin remove craftsman@ai-craftsman-superpowers
```

After an upgrade, open `/hooks` again and check the handlers are still
trusted.
