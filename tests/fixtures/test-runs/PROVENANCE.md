# Test runner output fixtures

What real test runners print, captured on 2026-10-20 to decide which passing
runs tested nothing (CR-255). `tests/core/test-verify-loop.sh` replays each
file as the `stdout` or `stderr` of a Claude Code Bash `tool_response`, in the
shape of `tests/fixtures/hosts/claude-code/2.1.272/post-tool-use.bash.python-tests-passed.json`.

## Capture method

One throwaway directory per runner. Each command ran once; stdout and stderr
were saved apart, because jest writes its summary to stderr. Every run here
exited 0. Redactions, applied uniformly:

- the capture directory becomes `/work`
- ANSI colour codes are removed (`NO_COLOR=1` was also set)
- PHPUnit's `Time:` and `Memory:` line and pytest's duration are fixed values

Nothing else is edited.

## Versions

| Runner | Version | Command |
|---|---|---|
| npm | 11.19.0 (node v26.7.0) | `npm test` |
| pnpm | 10.28.2 | `pnpm test` |
| jest | 29.7.0 | `jest --rootDir t`, `jest --passWithNoTests --rootDir t` |
| vitest | 3.2.7 | `vitest run --root v`, `vitest run --passWithNoTests --root v` |
| mocha | 10.8.2 | `mocha "m/*.js"` |
| pytest | 9.1.1 (Python 3.13.11, through `uvx`) | `pytest -p no:cacheprovider`, with `-q` for the quiet file |
| PHPUnit | 12.5.40 (PHP 8.5.9) | `vendor/bin/phpunit tests` |

## Files

Runs that tested nothing, and must grant no verification evidence:

- `npm-echo-ok`, `npm-true`: `"test": "echo ok"` and `"test": "true"`
- `pnpm-exit-0`: `"test": "exit 0"`
- `jest-no-tests`, `vitest-no-tests`: no test file, `--passWithNoTests`
- `jest-all-skipped`, `vitest-all-skipped`: one `test.skip` and one `describe.skip`
- `mocha-all-skipped`: two `it.skip`
- `pytest-all-skipped`, `pytest-all-skipped-quiet`: two `@pytest.mark.skip`
- `phpunit-no-tests`: an empty `tests/` directory
- `phpunit-all-skipped`: two `markTestSkipped`
- `phpunit-no-assertions`: two tests that assert nothing

Runs that tested something, and must keep granting it:

- `npm-script-runs-jest`: `"test": "jest --rootDir t"` over a passing test
- `jest-passed-and-skipped`, `vitest-passed-and-skipped`, `pytest-passed-and-skipped`,
  `phpunit-passed-and-skipped`: one passing test next to skipped ones
- `jest-focused`: a `test.only` next to a skipped file. It prints what a
  partial skip prints, which is why a focused test is not caught here.
- `mocha-ten-passing`: ten passing tests (`10 passing` must not read as `0 passing`)

Not captured, so not declared: yarn, bats, shellspec, go test, cargo test.
`go test ./...` and `cargo test` print "no test files" and "running 0 tests"
for single packages or doc-tests inside an otherwise real run, so a per-line
marker would refuse real runs.
