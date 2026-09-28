# Grok Quickstart

Craftsman for [Grok](https://docs.x.ai/build) in five minutes. For the other
hosts, see the [main README](../../README.md#install). What Grok loads and
observes is recorded in
[`hooks/host-capabilities.json`](../../hooks/host-capabilities.json), row
`grok`, with its provenance in
[`tests/fixtures/hosts/PROVENANCE.md`](../../tests/fixtures/hosts/PROVENANCE.md).

## What you get

| Capability | On Grok |
|------------|---------|
| Write gate before disk | yes, on `write` and `search_replace` |
| `ask` decision | honoured |
| Test evidence (grant and revoke) | yes, the shell result carries an exit code |
| Skills | 22, shown as `/name` (see [Slash names](#slash-names)) |
| Agents | the 12 missions ship as ordinary files |
| Config protection | the gate refuses an edit of its own hook configuration |

## Install

Prerequisites: Grok 1.0.40 or later (the version the matrix records), plus
`python3` 3.9+, `bash`, `jq`, `sqlite3` and `git`.

```bash
git clone https://github.com/BULDEE/ai-craftsman-superpowers ~/src/ai-craftsman-superpowers
bash ~/src/ai-craftsman-superpowers/bin/craftsman-grok-install
```

The installer runs `grok plugin install <clone> --trust`, then writes the
global gate `~/.grok/hooks/craftsman.json`. It still writes the gate when the
plugin is already installed, so running it again is how you upgrade.

Why a second file: Grok lists a plugin's `hooks/hooks.json` as
`hookType: file` and a fresh process runs none of it (measured on 1.0.34 and
1.0.40, headless and interactive). The global file is generated from the same
manifest, so there is one list of handlers, not two. Global hooks need no
extra trust.

The same write, by hand:

```bash
bash ~/src/ai-craftsman-superpowers/ci/craftsman-ci.sh export --target grok-hooks --into ~/.grok/hooks
```

## Verify it works

```bash
bash ~/src/ai-craftsman-superpowers/bin/craftsman-healthcheck --report
```

Read the `write-gate` row. It is ok when the gate's owner marker matches this
install. It names the export command when the gate is missing, behind this
install, or written by another install (a second clone, an older version).

Then provoke a refusal on purpose: ask Grok to write
`src/Domain/Order.php` containing `use App\Infrastructure\OrderRepository;`.
The file must not appear on disk. The hook row shows `failed` with
`blocked: true`: that is how Grok renders exit code 2, a refusal, not a broken
hook.

## Slash names

Skills are `/name` (`/design`, `/challenge`, `/verify`, ...), except `/plan`,
`/loop` and `/workflow`, which Grok already owns: those three stay
`/craftsman:plan`, `/craftsman:loop` and `/craftsman:workflow`. A name another
plugin already owns is also shown as `/craftsman:name`.

## Limits

- The gate judges the host's write tools. A file written by a shell command
  (`printf > file`, `sed -i`, a script) is not gated before disk: CI
  (`ci/craftsman-ci.sh`) catches it. The pre-push hook reads no file and only
  warns.
- Grok's default hook timeout is 5 seconds and fail-open. The exported gate
  sets `timeout: 15` on every handler.
- A reload in `/hooks` activates the plugin handlers but does not replay the
  missed initial `SessionStart` (measured on 1.0.34). The global gate does not
  depend on that reload.
- A project `.grok/hooks` file runs only once the folder is trusted
  (`grok --trust` or `/hooks-trust`). Untrusted, it is skipped in silence.

## Uninstall

Check first which install wrote the gate. Remove it only if the printed root
is your clone:

```bash
jq -r '.craftsman.root' ~/.grok/hooks/craftsman.json
grok plugin uninstall craftsman
rm ~/.grok/hooks/craftsman.json
```
