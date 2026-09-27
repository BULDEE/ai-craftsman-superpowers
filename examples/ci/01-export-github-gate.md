# Example: Export Craftsman Gate to GitHub Actions

## Prompt

```
/craftsman:ci export
I have a Symfony + React project and want the quality gate in CI to match the local hooks.
```

## Expected Behavior

### Export: the four steps the skill defines

1. Read `.craft-config.yml` if it exists, to pick up `strictness` and `stack`.
   Here it holds `strictness: strict` and `stack: fullstack`.
2. Check for `composer.json`, `package.json` and `deptrac.yaml`. All three are
   present in this project.
3. Copy `ci/templates/craftsman-quality-gate.yml` into
   `.github/workflows/craftsman-quality-gate.yml`, creating
   `.github/workflows/` if it is missing. If the file already exists, ask the
   user before overwriting it.
4. Print the confirmation summary.

The export is a copy of the shipped template, not a generated pipeline. An
excerpt of what lands in `.github/workflows/craftsman-quality-gate.yml`:

```yaml
name: Craftsman Quality Gate

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read
  pull-requests: write

jobs:
  quality:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4
        with:
          fetch-depth: 0

      - name: Setup PHP (if composer.json exists)
        if: ${{ hashFiles('composer.json') != '' }}
        uses: shivammathur/setup-php@f3e473d116dcccaddc5834248c87452386958240 # v2
        with:
          php-version: '8.3'
          tools: composer, phpstan

      # Setup Node.js, composer install and npm ci follow, each guarded by hashFiles()

      - name: Run craftsman-ci quality gate
        env:
          GH_TOKEN: ${{ github.token }}
          GITHUB_PR_NUMBER: ${{ github.event.pull_request.number }}
          CRAFTSMAN_SCOPE: ${{ github.event_name == 'pull_request' && '--changed-only' || '' }}
        run: |
          chmod +x ci/craftsman-ci.sh
          bash ci/craftsman-ci.sh ci --provider github $CRAFTSMAN_SCOPE
```

### Confirmation summary

The skill prints this fixed text, with the two placeholders filled from steps 1
and 2:

```
Craftsman CI workflow exported to:
  .github/workflows/craftsman-quality-gate.yml

Detected stack: fullstack
Config: strict strictness

Next steps:
  1. Commit and push: git add .github/workflows/craftsman-quality-gate.yml
  2. Open a PR to trigger the workflow
  3. Review docs/ci-integration.md for advanced configuration
```

If `ci/craftsman-ci.sh` is not present in the repository, the skill also warns
the user: the exported workflow calls it and cannot run without it.

### Second invocation: checking the integration

The skill defines one other subcommand, `status`. There is no `check` mode.

```
/craftsman:ci status
```

The skill checks four things: the workflow file (with the `strictness` and
`stack` from its embedded config and its last modified date, or a suggestion to
run `/craftsman:ci export` when it is missing), whether `ci/craftsman-ci.sh`
exists and is executable, whether `.craft-config.yml` exists, and which of
`composer.json`, `package.json` and `deptrac.yaml` are present. It reports them
as a status table:

```
Craftsman CI Status
===================
Workflow file:   ✓ .github/workflows/craftsman-quality-gate.yml
craftsman-ci:    ✓ ci/craftsman-ci.sh (executable)
Config:          ✓ .craft-config.yml (strictness=strict, stack=fullstack)
Stack detected:  PHP (composer.json), Node.js (package.json)

Run /craftsman:ci export to generate the workflow if missing.
```

## Key Points

- `export` copies `ci/templates/craftsman-quality-gate.yml` as it ships; the
  config read and the stack check feed the summary, and the skill never touches
  `hooks/`, `agents/` or `packs/`
- The workflow runs `craftsman-ci.sh ci --provider github`, which sources the
  same pack validators and rules engine as the hooks, so a finding carries the
  same severity locally and in CI
- On a pull request the template passes `--changed-only`, so only the files that
  differ from the base branch are validated; a push to `main` scans everything,
  which is why the checkout uses `fetch-depth: 0`
- The template declares least-privilege `permissions` (`contents: read`,
  `pull-requests: write`) and pins every action to a commit SHA
- PHP and Node.js setup steps are guarded by `hashFiles()`, so the same file
  works on a PHP-only, a Node-only or a fullstack repository
- `status` is read-only: it reports what exists and never regenerates the file
