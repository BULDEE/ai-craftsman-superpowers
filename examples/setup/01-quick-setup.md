# Example: Quick Setup on a Symfony Project

## Prompt

```
/craftsman:setup --quick
```

## Context

- Project has `composer.json` (Symfony 7.4)
- No `package.json`
- Git user: `Alexandre Mallet`
- No existing `.craft-config.yml`

## Expected Behavior

### Auto-Detection

```
Detecting project stack...
  composer.json found → PHP/Symfony detected
  package.json not found → No Node/React
  git config user.name → Alexandre Mallet
```

### Config Generation

Creates `~/.claude/.craft-config.yml`:

```yaml
version: "1.0"

profile:
  name: "Alexandre Mallet"
  disc_type: ""
  biases:
    - acceleration
    - scope_creep
    - over_optimization
    - dispersion

packs:
  core: true
  symfony: true
  react: false
  ai-ml: false

stack:
  php_version: "8.4"
  symfony_version: "7.4"
```

### Summary Output

```
Quick Setup Complete!

  Name: Alexandre Mallet (from git config)
  Stack: symfony
  Strictness: strict (default)
  Biases: all enabled
  Packs: core, symfony

Config saved to ~/.claude/.craft-config.yml
Run /craftsman:setup for full customization (DISC profile, pack versions, etc.)
```

## When to Use

- First time installing the plugin
- Trying out the plugin quickly
- CI environments where interactive setup is impossible
- When you want sensible defaults and plan to customize later
