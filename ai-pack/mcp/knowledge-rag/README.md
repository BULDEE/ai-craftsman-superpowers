# Knowledge RAG MCP Server

MCP server for RAG (Retrieval-Augmented Generation) over local AI/Architecture knowledge base.

> **Recommendation:** Use Ollama for embeddings (local, free, private). OpenAI API is supported but not recommended for privacy-sensitive projects.

## Features

- **Project-specific knowledge** - Auto-detects `.claude/ai-craftsman-superpowers/knowledge/` in your project
- **Global fallback** - Uses plugin's global knowledge base if no project knowledge exists
- **Multi-format support** - PDF, Markdown, and TXT files
- **Local embeddings** - Ollama for 100% private, offline operation

## Quick Start

### Prerequisites

- Node.js 20+
- Ollama (recommended) or OpenAI API key

### Installation

```bash
# 1. Install Ollama
brew install ollama  # macOS
# curl -fsSL https://ollama.ai/install.sh | sh  # Linux

# 2. Pull embedding model
ollama pull nomic-embed-text

# 3. Start Ollama server (keep running in a terminal)
ollama serve

# 4. Navigate to MCP directory
cd ai-pack/mcp/knowledge-rag

# 5. Install dependencies
npm install

# 6. Build TypeScript
npm run build

# 7. Index knowledge base
npm run index:ollama
```

## Project-Specific Knowledge

Create a knowledge base specific to your project:

```bash
# In your project root
mkdir -p .claude/ai-craftsman-superpowers/knowledge

# Add your documents
cp specs.pdf architecture.md .claude/ai-craftsman-superpowers/knowledge/

# Index (run from your project directory)
cd /path/to/your/project
npx tsx /path/to/ai-pack/mcp/knowledge-rag/scripts/index-pdfs.ts
```

### Structure

```
your-project/
├── .claude/
│   └── ai-craftsman-superpowers/
│       └── knowledge/              # Your documents here
│           ├── specs.pdf
│           ├── architecture.md
│           └── .index/             # Auto-generated (gitignore this)
│               └── knowledge.db
├── src/
└── ...
```

### .gitignore

Add to your project's `.gitignore`:

```
.claude/ai-craftsman-superpowers/knowledge/.index/
```

## Knowledge Detection Priority

1. **Project** - `.claude/ai-craftsman-superpowers/knowledge/` in current working directory
2. **Global** - `ai-pack/knowledge/` in the plugin installation

The MCP server automatically uses project knowledge when available.

## Embedding Options

| Option | Command | Privacy | Cost |
|--------|---------|---------|------|
| **Ollama** (recommended) | `npm run index:ollama` | 100% local | Free |
| OpenAI API | `npm run index:openai` | Cloud | ~$0.02/1M tokens |

### Using OpenAI (Alternative)

```bash
export OPENAI_API_KEY=sk-...
npm run index:openai
```

## MCP Tools

The server exposes two tools:

### search_knowledge

Search the knowledge base for relevant information.

```json
{
  "query": "What are the 3 pipelines in RAG?",
  "top_k": 5,
  "sources": ["rag-architecture.md"]
}
```

### list_knowledge_sources

List all indexed documents with metadata.

## Configuration

### Claude Code Integration

The MCP is auto-configured via `.mcp.json` when using the ai-craftsman plugin.

For manual setup, add to `~/.claude/settings.local.json`:

```json
{
  "mcpServers": {
    "knowledge-rag": {
      "command": "node",
      "args": ["/path/to/ai-pack/mcp/knowledge-rag/dist/src/index.js"]
    }
  }
}
```

### Environment Variables

```bash
# Ollama (default)
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_EMBED_MODEL=nomic-embed-text

# OpenAI (alternative)
OPENAI_API_KEY=sk-...
OPENAI_EMBED_MODEL=text-embedding-3-small
```

## Architecture

```
ai-pack/
├── knowledge/                      # Global knowledge (plugin default)
│   ├── agent-3p-pattern.md
│   ├── mlops-principles.md
│   └── ...
│
└── mcp/knowledge-rag/
    ├── src/
    │   ├── index.ts                # MCP server entry
    │   ├── db/vector-store.ts      # SQLite + auto-detection
    │   ├── embeddings/             # Ollama/OpenAI providers
    │   └── tools/                  # search_knowledge, list_sources
    ├── scripts/
    │   └── index-pdfs.ts           # Indexing script
    └── data/
        └── knowledge.db            # Global database

your-project/
└── .claude/ai-craftsman-superpowers/
    └── knowledge/                  # Project-specific knowledge
        ├── your-docs.pdf
        └── .index/knowledge.db     # Project database
```

## Troubleshooting

### Ollama not responding

```bash
# Check if running
curl http://localhost:11434/api/tags

# Restart
pkill ollama && ollama serve
```

### Index failed

```bash
# Check embedding model is available
ollama list | grep nomic-embed-text

# Or verify OpenAI key
echo $OPENAI_API_KEY
```

### MCP not connecting in Claude Code

1. Verify build: `ls dist/src/index.js`
2. Test manually: `node dist/src/index.js` (should start without errors)
3. Restart Claude Code after configuration changes

### Database issues

```bash
# Reset global database
rm data/knowledge.db*
npm run index:ollama

# Reset project database
rm .claude/ai-craftsman-superpowers/knowledge/.index/knowledge.db*
# Then re-index
```

### Project knowledge not detected

Ensure you're running Claude Code from the project root where `.claude/ai-craftsman-superpowers/knowledge/` exists.

## Topics Covered (Global)

The default knowledge base includes:

- **AI Agent Patterns** - 3P pattern (Perceive/Plan/Perform)
- **RAG Architecture** - Retrieval pipelines, chunking, embeddings
- **MLOps Principles** - Model lifecycle, monitoring, deployment
- **Vector Databases** - Comparison, selection criteria

## References

- [Ollama Documentation](https://ollama.ai/docs)
- [MCP Protocol](https://modelcontextprotocol.io)
