# Example: Quick Setup on a Symfony Project

## Prompt

```
/craftsman:setup --quick
```

## Context

- Project has `composer.json` (Symfony 7.4)
- No `package.json`
- Git user: `Alexandre Mallet`
- No existing `.craft-config.yml` in the project
- An existing repository: 412 commits, no `.craftsman-baseline.json` yet

## Expected Behavior

### Auto-Detection

```
Detecting project stack...
  composer.json found → PHP/Symfony detected
  package.json not found → No Node/React
  stack → symfony
  git config user.name → Alexandre Mallet
```

### Config Generation

Creates `.craft-config.yml` in the project, format v4, with no `strictness`
line: the plugin derives it (`config_default_strictness`).

```yaml
# .craft-config.yml, format v4 (schemas/craft-config.schema.json)
v: 4
stack: symfony
guided: false
```

### Baseline

```
$ bash "$(craftsman-path bin/craftsman-ci)" baseline src
Scanning to record what is already there...
...
Done. A violation already recorded here is reported but no longer blocks.
A new one, or one more of the same rule in the same file, still does.
```

### Validation and Read-Back

```
$ bash -c 'source "$(craftsman-path hooks/lib/config.sh)"; config_validate .craft-config.yml && echo "stack=$(config_stack) strictness=$(config_strictness)"'
stack=symfony strictness=strict
```

`strict` because the mark now exists: an existing repository without one would
read back `moderate`, and the summary says whichever the resolver answered.

### Summary Output

```
Quick Setup Complete!

  Name: Alexandre Mallet (from git config)
  Stack: symfony
  Strictness: strict
  Biases: all enabled
  Baseline: taken, inherited debt reports as warnings

Config saved to .craft-config.yml (this project)
Run /craftsman:setup for full customization (situational questions, DISC profile)
```

## When to Use

- First time installing the plugin
- Trying out the plugin quickly
- CI environments where interactive setup is impossible
- When you want sensible defaults and plan to customize later
