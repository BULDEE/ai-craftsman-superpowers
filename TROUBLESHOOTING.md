# Troubleshooting

## Table of Contents

- [Commands not appearing in autocompletion](#commands-not-appearing-in-autocompletion)
- [Skills not loading](#skills-not-loading)
- [Check for errors](#check-for-errors)
- [Hooks not running](#hooks-not-running)
- [Agent hooks disabled but still seeing API calls](#agent-hooks-disabled-but-still-seeing-api-calls)

## Commands not appearing in autocompletion

**Symptom:** `/cra<TAB>` doesn't suggest craftsman commands, but they work when typed fully.

**Cause:** Version mismatch between `plugin.json` and `marketplace.json` prevents cache updates.

**Fix:**
```bash
# Force update the plugin
claude plugin update craftsman@ai-craftsman-superpowers

# If still not working, clear cache and reinstall
rm -rf ~/.claude/plugins/cache/ai-craftsman-superpowers
claude plugin install craftsman@ai-craftsman-superpowers

# Restart Claude Code
exit
claude
```

## Skills not loading

**Symptom:** pack-specific commands or agents (e.g. `/craftsman:rag`, `backend-craftsman`) don't appear even though the pack is enabled in config.

**Cause:** pack symlinks are created dynamically by `pack-loader.sh` on `SessionStart`. If that hook didn't run (interrupted session, cache corruption), the symlinks are missing.

**Fix:**
```bash
# Clear plugin cache
rm -rf ~/.claude/plugins/cache

# Restart Claude Code
exit
claude

# Reinstall plugin
/plugin uninstall craftsman@BULDEE-ai-craftsman-superpowers
/plugin install craftsman@BULDEE-ai-craftsman-superpowers
```

## Check for errors

```bash
# Open plugin manager
/plugin

# Go to "Errors" tab
# Check for missing dependencies or path issues
```

## Hooks not running

Verify hooks are enabled in your scope:
1. `/plugin` → "Installed" tab
2. Select craftsman plugin
3. Check "Hooks enabled" status

## Agent hooks disabled but still seeing API calls

**Symptom:** you set `agent_hooks: false` but Claude Code still makes Haiku calls on Write/Edit.

**Cause:** config change requires a session restart to take effect, or the setting was applied at project scope while the plugin is loaded at user scope (or vice versa).

**Fix:**
```bash
# Check where the setting is actually applied
/plugin

# Restart to pick up the new config
exit
claude
```

If the problem persists, see [SECURITY.md](SECURITY.md#data--network-transparency) for the full list of what triggers network calls, and verify with:
```bash
grep -r "curl\|wget\|fetch\|http" hooks/
# Should return nothing (hooks are 100% local)
```
