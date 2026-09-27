# Example: Plugin Diagnostic for Missing PHPStan

## Prompt

```
/craftsman:healthcheck
PHPStan never triggers when I save PHP files. What is wrong?
```

## Expected Behavior

### Phase 1: Environment Scan

```markdown
## Plugin Diagnostic

### Core Plugin
- Plugin version: 3.1.0
- Plugin loaded: yes
- Hooks registered: 8/8

### Hook Status
| Hook                  | Status | Latency |
|-----------------------|--------|---------|
| post-write-check.sh   | active | 42ms    |
| bias-detector.sh       | active | 18ms    |
| session-metrics.sh     | active | 31ms    |
| subagent-quality-gate  | active | 27ms    |

### Pack Detection
- symfony pack: loaded
- react pack: loaded
```

### Phase 2: Root Cause Analysis

```markdown
## PHPStan Analysis

**Level 2 static analysis is configured but not executing.**

### Checks Performed
1. PHPStan binary lookup: `vendor/bin/phpstan` -- **not found**
2. `phpstan` on PATH -- not found
3. `phpstan.neon` config: `./phpstan.neon` -- present (the gate does not use it: it pins its own configuration, so a repository cannot inject bootstrap code)
4. Pack validator: symfony pack expects `vendor/bin/phpstan`
5. Consent: `trust_project_tools` in `~/.claude/.craft-config.yml` -- absent

### Root Cause
Two things stand between PHPStan and your saves. It is not installed, and even once it is, Level 2 runs a project's own analysers only when the machine owner has allowed it in `~/.claude/.craft-config.yml` (`trust_project_tools: true`): those binaries and the config they discover are code the repository ships. A project `.craft-config.yml` cannot grant it. Without both, the gate degrades to Level 1 (regex only).

### Fix, part 1 (installing)
```

```bash
composer require --dev phpstan/phpstan phpstan/phpstan-symfony
```

### Phase 3: Post-Fix Verification

Installed is not running. Check the consent with the predicate the gate itself uses:

#### Check the consent

```bash
bash -c 'source "$(craftsman-path hooks/lib/config.sh)"; config_trust_project_tools && echo "trusted" || echo "not trusted"'
```

```markdown
## After Installing PHPStan

- `vendor/bin/phpstan` -- found (v2.1.0)
- Consent: **not trusted**
- Level 2 (static analysis): **installed, not authorized**

Level 2 would run PHPStan from this repository's vendor/, which executes code the
repository ships. Allowing it applies to every repository this machine opens.
Do you want to allow it? If so, add `trust_project_tools: true` to
~/.claude/.craft-config.yml, or approve that write when you are asked: the gate
hands every write to a .craft-config.yml to you, and refuses it outright where
it cannot ask.
```

The decision is the user's. Stop here until they answer: without consent the verdict stays "installed, not authorized", and that is a correct final state.

Once they have added the line, the consent check prints `trusted`. That is still a setting, not a run. Observe one, through the gate's own dispatcher, on a scratch file PHPStan must flag (run it from the project root, where `vendor/bin/phpstan` is):

#### Observe a run

```bash
probe="${TMPDIR:-/tmp}/craftsman-level2-probe.php"
printf '<?php\nfunction probe(): int\n{\n    return $total;\n}\n' > "$probe"
bash -c 'source "$(craftsman-path hooks/lib/config.sh)"; source "$(craftsman-path hooks/lib/pack-loader.sh)"; source "$(craftsman-path hooks/lib/static-analysis.sh)"; pack_loader_init; sa_analyze_file "$1"' _ "$probe"
rm -f "$probe"
```

```markdown
## Level 2 Verified

- Consent: trusted (`trust_project_tools: true`, written by you)
- Probe: a `PHPSTAN002` finding on line 4 (undefined variable `$total`) -- PHPStan ran through the gate

### Quality Gate Levels
- Level 1 (regex): active
- Level 2 (static analysis): **active**, observed on the probe above -- was inactive
- Level 3 (architecture): inactive -- deptrac not installed (optional)
```

An empty probe output means Level 2 did not report on a file it must flag (no consent, no binary, or an analyser stopped by its time budget): report that, never "active".

## Test This Example

1. Open Claude Code in a project without PHPStan installed
2. Run `/craftsman:healthcheck`
3. Describe the symptom
4. Verify Claude scans the environment, identifies the missing binary, and provides the install command
5. Verify Claude checks `trust_project_tools`, leaves the consent to you, and calls Level 2 active only after the probe shows a finding
