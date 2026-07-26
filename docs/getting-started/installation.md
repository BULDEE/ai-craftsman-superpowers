# Installation

## Prerequisites

- [Claude Code CLI](https://claude.ai/code) v1.0.33 or later
- Run `claude --version` to verify

## Quick Install (Recommended)

```bash
# 1. Add the marketplace
/plugin marketplace add BULDEE/ai-craftsman-superpowers

# 2. Install the plugin
/plugin install craftsman@BULDEE-ai-craftsman-superpowers

# 3. Restart Claude Code
exit
claude
```

## Verify Installation

```bash
# Open plugin manager
/plugin

# Go to "Installed" tab to see craftsman plugin
# You should see:
#   craftsman Plugin · ai-craftsman-superpowers · ✔ enabled
```

## Try Your First Skill

```bash
# Start designing with DDD methodology
/craftsman:design
I need to create a User entity for authentication

# Or debug an issue systematically
/craftsman:debug
My API returns 500 on login
```

## Troubleshooting

### Skills not loading

```bash
# Clear plugin cache and reinstall
rm -rf ~/.claude/plugins/cache/ai-craftsman-superpowers

# Restart Claude Code
exit
claude

# Reinstall
/plugin uninstall craftsman@BULDEE-ai-craftsman-superpowers
/plugin install craftsman@BULDEE-ai-craftsman-superpowers
```

## Next Steps

- [First Steps](./first-steps.md) - Your first skill usage
- [Core Concepts](./concepts.md) - Understanding the architecture
