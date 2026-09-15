# Craftsman for GitHub Copilot (CLI, VS Code, cloud agent)

Status: **documented contract implemented, no surface qualified.** No Copilot
consumer was available on the machine that wrote this adapter; every fixture
under `tests/fixtures/hosts/copilot/documented/` is transcribed from the
[GitHub hooks reference](https://docs.github.com/en/copilot/reference/hooks-reference)
(read 2026-09-15), and the suites prove the adapter honours that contract,
not that a Copilot surface behaves as documented.

## What it is

Three verbs against the shared core (ADR-0029), translated at the edge:

| File | Role |
|------|------|
| `translate.py` | Copilot envelope (camelCase or PascalCase, `toolArgs` possibly a JSON string) and tool names (`create`, `edit`, `str_replace_editor`, `apply_patch`, `bash`) into the core's Write / Edit / apply_patch / Bash payload. Names `craftsman_host: copilot` and the surface (`cli`, or `cloud` when `COPILOT_AGENT_PROMPT` is set). |
| `pre-tool-use.sh` | `gate`: config-protection.sh then pre-write-check.sh on the translated payload; a refusal is exit 2 with a top-level `permissionDecision: deny` (documented as deny on both surfaces; `ask` is deny in the cloud and is never emitted). A gate that cannot run exits non-zero, which the reference makes fail-closed for preToolUse. Filters tools itself, for a surface that ignores matchers. |
| `post-tool-use.sh` | post-write-check.sh on the landed file; findings return as `additionalContext` (the documented model channel, capped at 10 KB by the host), a blocking one also on stderr with exit 2 (logged, the write stands). |
| `hooks.json` | The `.github/hooks/*.json` file, PascalCase form, `Edit|Write` matcher, `timeoutSec: 60`: a hook TIMEOUT is documented as fail-open on every event, so the budget stays far above the gates' measured latency. |

`record` is the core's: post-write-check.sh writes the same `metrics.db`
rows with the session the payload names. `inject` is not implemented for
Copilot (no SessionStart handler shipped yet).

## Deploying

```bash
# in the target repository
mkdir -p .github/hooks
sed "s|\${CRAFTSMAN_ROOT}|/path/to/ai-craftsman-superpowers|g" adapters/copilot/hooks.json > .github/hooks/craftsman.json
```

The cloud agent loads `.github/hooks/*.json` only, runs on Linux with an
ephemeral filesystem and a firewall that reaches GitHub hosts only: the plugin
has to be in the repository (vendored, or checked out by a setup step) and
`metrics.db` written there is lost with the job unless exported.

## Qualification still open

Per surface, with the consumer:

1. **CLI**: install `copilot`, add a `cat >> capture.jsonl` hook on
   `preToolUse` and `postToolUse` in `.github/hooks/`, run one write and one
   shell command, and put the payloads under `tests/fixtures/hosts/copilot/<version>/`
   with their provenance. The argument names of `create`/`edit` are the first
   thing to confirm.
2. **VS Code**: the hooks guide says the Claude format is recognised and
   `matcher` values are ignored, and tools keep VS Code names and arguments
   (`create_file`, `filePath`): add those names to `translate.py` from a
   capture, never from the guide alone.
3. **Cloud agent**: same capture through an `http` hook or a committed
   artifact, since the filesystem is discarded; confirm `ask` is deny and
   that a preToolUse exit 2 denies.

A green suite here is the documented contract; a surface is qualified when
its capture replaces the `documented/` fixtures and the suite is still green.
