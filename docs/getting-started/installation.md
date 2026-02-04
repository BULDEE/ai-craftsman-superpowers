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

## Optional: Knowledge Base RAG

The plugin includes an optional MCP server for RAG over local documents.

> **Note:** The plugin is fully functional without this. Skip if you don't need local RAG.

### Prerequisites for RAG

- Node.js 20+
- [Ollama](https://ollama.ai)

### Setup RAG

```bash
# 1. Install Ollama
brew install ollama  # macOS
# curl -fsSL https://ollama.ai/install.sh | sh  # Linux

# 2. Pull embedding model & start server
ollama pull nomic-embed-text
ollama serve  # Keep running in background

# 3. Build MCP server
cd ~/.claude/plugins/marketplaces/ai-craftsman-superpowers/ai-pack/mcp/knowledge-rag
npm install && npm run build

# 4. Create knowledge directory
mkdir -p ~/.claude/ai-craftsman-superpowers/knowledge

# 5. Add your documents
cp ~/your-docs/*.pdf ~/.claude/ai-craftsman-superpowers/knowledge/

# 6. Index knowledge base
npm run index:ollama
```

### Configure MCP

Add to `~/.claude/settings.local.json`:

```json
{
  "mcpServers": {
    "knowledge-rag": {
      "command": "node",
      "args": ["/Users/YOUR_USERNAME/.claude/plugins/marketplaces/ai-craftsman-superpowers/ai-pack/mcp/knowledge-rag/dist/src/index.js"]
    }
  }
}
```

> Replace `YOUR_USERNAME` with your actual username.

Restart Claude Code. You should see:
```
knowledge-rag MCP · ✔ connected
```

### Verify RAG

```bash
# In Claude Code
> Search my knowledge base for "clean architecture"
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

### MCP server not connecting

```bash
# 1. Check Ollama is running
curl http://localhost:11434/api/tags

# 2. Check build exists
ls ~/.claude/plugins/marketplaces/ai-craftsman-superpowers/ai-pack/mcp/knowledge-rag/dist/src/index.js

# 3. Test manually
cd ~/.claude/plugins/marketplaces/ai-craftsman-superpowers/ai-pack/mcp/knowledge-rag
node dist/src/index.js
# Should start without errors (Ctrl+C to stop)

# 4. Rebuild if needed
npm run build
```

### Knowledge base empty

```bash
# Check database location
ls ~/.claude/ai-craftsman-superpowers/knowledge/

# Re-index
cd ~/.claude/plugins/marketplaces/ai-craftsman-superpowers/ai-pack/mcp/knowledge-rag
npm run index:ollama
```

## Next Steps

- [First Steps](./first-steps.md) - Your first skill usage
- [Core Concepts](./concepts.md) - Understanding the architecture
- [Local RAG Guide](../guides/local-rag-ollama.md) - Detailed RAG setup
