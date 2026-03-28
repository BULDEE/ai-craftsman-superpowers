---
name: ci
description: Export craftsman quality rules to CI/CD pipeline and check integration status
trigger: /craftsman:ci
---

# /craftsman:ci — CI/CD Integration

Integrate Craftsman quality gates into your CI/CD pipeline.

## Subcommands

- `/craftsman:ci export` — Generate `.github/workflows/craftsman-quality-gate.yml`
- `/craftsman:ci status` — Show current CI integration status

---

## Execution

### If the user runs `/craftsman:ci export`:

1. Read `.craft-config.yml` if it exists to pick up `strictness` and `stack` settings.
2. Check for `composer.json` (PHP), `package.json` (Node.js), and `deptrac.yaml` to tailor the workflow.
3. Copy `ci/templates/craftsman-quality-gate.yml` into `.github/workflows/craftsman-quality-gate.yml`.
   - If `.github/workflows/` does not exist, create it.
   - If the file already exists, ask the user before overwriting.
4. Confirm the export with a summary:

```
Craftsman CI workflow exported to:
  .github/workflows/craftsman-quality-gate.yml

Detected stack: <stack>
Config: <strictness> strictness

Next steps:
  1. Commit and push: git add .github/workflows/craftsman-quality-gate.yml
  2. Open a PR to trigger the workflow
  3. Review docs/ci-integration.md for advanced configuration
```

### If the user runs `/craftsman:ci status`:

Check the following and report:

1. **Workflow file** — Does `.github/workflows/craftsman-quality-gate.yml` exist?
   - If yes: show `strictness` and `stack` from the embedded config, and the file's last modified date.
   - If no: suggest running `/craftsman:ci export`.

2. **craftsman-ci CLI** — Does `ci/craftsman-ci.sh` exist and is it executable?

3. **Config file** — Does `.craft-config.yml` exist?

4. **Stack detection** — Are `composer.json` / `package.json` / `deptrac.yaml` present?

Output a clear status table:

```
Craftsman CI Status
===================
Workflow file:   ✓ .github/workflows/craftsman-quality-gate.yml
craftsman-ci:    ✓ ci/craftsman-ci.sh (executable)
Config:          ✓ .craft-config.yml (strictness=strict, stack=fullstack)
Stack detected:  PHP (composer.json), Node.js (package.json)

Run /craftsman:ci export to generate the workflow if missing.
```

---

## Constraints

- Never modify `hooks/`, `agents/`, or `packs/` — CI is an additive integration layer.
- The exported workflow uses the same rules as the hooks; they must never diverge.
- If `ci/craftsman-ci.sh` is not present, warn the user — the workflow depends on it.
- All shell commands use `|| true` for optional tools (PHPStan, ESLint, deptrac) so the workflow degrades gracefully.
