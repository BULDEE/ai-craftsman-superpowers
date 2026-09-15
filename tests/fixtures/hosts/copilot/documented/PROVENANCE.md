# Copilot fixtures: DOCUMENTED, NOT CAPTURED

No GitHub Copilot consumer (CLI, VS Code, cloud agent) was available on the
machine that wrote these. Every file here is transcribed from
https://docs.github.com/en/copilot/reference/hooks-reference as read on
2026-09-15: the two envelopes (camelCase `sessionId`/`toolName`/`toolArgs`/
`toolResult`, PascalCase `session_id`/`tool_name`/`tool_input`/`tool_result`),
`toolArgs` possibly a JSON string, `tool_result.result_type` success or
failure, and the tool names `create`, `edit`, `str_replace_editor`, `bash`.

The ARGUMENT names of the file tools (`path`, `file_text`, `old_str`,
`new_str`) are the documented tool's and were not seen on a wire. A test
that passes on these files proves the adapter honours the documented
contract; it does not qualify a Copilot surface. The first real capture
(`copilot --help`, a `.github/hooks/*.json` with `cat >> file` on preToolUse
and postToolUse, one run on CLI, one in the cloud agent) goes to
`tests/fixtures/hosts/copilot/<version>/` and replaces this directory's
authority. Until then the healthcheck's host row says `unknown` for a raw
Copilot payload and `copilot` only for one the adapter translated.
