# Installation

## Prerequisites

- [Claude Code CLI](https://claude.ai/code) installed
- Node.js 20+ (for MCP server)
- [Ollama](https://ollama.com/) (for local RAG)

## Quick Install

```bash
# 1. Install the plugin
claude plugins install git@github.com:BULDEE/ai-craftsman-superpowers.git

# 2. Restart Claude Code
# Close and reopen your terminal

# 3. Run setup wizard (first time only)
claude
# The wizard will guide you through configuration
```

## Manual Install

If you prefer manual setup:

```bash
# Clone the repository
git clone git@github.com:BULDEE/ai-craftsman-superpowers.git ~/.claude/plugins/ai-craftsman-superpowers

# Install MCP server dependencies
cd ~/.claude/plugins/ai-craftsman-superpowers/ai-pack/mcp/knowledge-rag
npm install
npm run build

# Pull embedding model
ollama pull nomic-embed-text

# Index knowledge base (optional - if you have PDFs to index)
npm run index
```

## Configuration

After installation, configure your profile in `~/.claude/.craft-config.yml`:

```yaml
profile:
  name: "Your Name"
  disc_type: "DI"  # Your DISC profile (optional)
  biases:
    - acceleration    # Tendency to code before thinking
    - scope_creep     # Adding features not asked for

packs:
  core: true      # Always enabled
  symfony: true   # Enable for PHP/Symfony projects
  react: true     # Enable for React projects
  ai: true        # Enable for AI/ML projects
```

## Verify Installation

```bash
# Start Claude Code
claude

# Try a skill
> /design
# Should show the design skill prompt

# Check knowledge base (if RAG installed)
> List my knowledge sources
# Should show indexed documents
```

## Troubleshooting

### Plugin not found

```bash
# Check installed plugins
claude plugins list

# Reinstall if needed
claude plugins uninstall ai-craftsman-superpowers
claude plugins install git@github.com:BULDEE/ai-craftsman-superpowers.git
```

### MCP server not connecting

```bash
# Check if Ollama is running
curl http://localhost:11434/api/tags

# Check if model is installed
ollama list
# Should show nomic-embed-text

# Rebuild MCP server
cd ai-pack/mcp/knowledge-rag
npm run build
```

### Knowledge base empty

```bash
# Re-index PDFs
cd ai-pack/mcp/knowledge-rag
npm run index

# Check database
ls -la data/knowledge.db
# Should be ~2-3MB
```

## Next Steps

- [First Steps](./first-steps.md) - Your first skill usage
- [Core Concepts](./concepts.md) - Understanding the architecture
