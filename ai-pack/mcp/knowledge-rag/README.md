# Knowledge RAG MCP Server

MCP server for RAG (Retrieval-Augmented Generation) over local AI/Architecture knowledge base.

## Features

- **Project-specific knowledge** - Auto-detects `.claude/ai-craftsman-superpowers/knowledge/` in your project
- **Global fallback** - Uses `~/.claude/ai-craftsman-superpowers/knowledge/` if no project knowledge exists
- **Multi-format support** - PDF, Markdown, and TXT files
- **Local embeddings** - Ollama for 100% private, offline operation
- **Zero cost** - No API fees, runs entirely on your machine

## Quick Start

### Prerequisites

- Node.js 20+
- Ollama

### Installation

```bash
# 1. Install Ollama
brew install ollama  # macOS
# curl -fsSL https://ollama.ai/install.sh | sh  # Linux

# 2. Pull embedding model
ollama pull nomic-embed-text

# 3. Start Ollama server (keep running)
ollama serve

# 4. Navigate to MCP directory
# If installed via plugin marketplace:
cd ~/.claude/plugins/marketplaces/ai-craftsman-superpowers/ai-pack/mcp/knowledge-rag
# If cloned locally:
# cd /path/to/ai-craftsman-superpowers/ai-pack/mcp/knowledge-rag

# 5. Install dependencies & build
npm install && npm run build

# 6. Create global knowledge directory
mkdir -p ~/.claude/ai-craftsman-superpowers/knowledge

# 7. Add your documents
cp ~/Desktop/your-docs/*.pdf ~/.claude/ai-craftsman-superpowers/knowledge/

# 8. Index knowledge base
npm run index:ollama
```

### Configure Claude Code

Add to `~/.claude/settings.local.json`:

**If installed via plugin marketplace:**
```json
{
  "mcpServers": {
    "knowledge-rag": {
      "command": "node",
      "args": ["~/.claude/plugins/marketplaces/ai-craftsman-superpowers/ai-pack/mcp/knowledge-rag/dist/src/index.js"]
    }
  }
}
```

**If cloned locally:**
```json
{
  "mcpServers": {
    "knowledge-rag": {
      "command": "node",
      "args": ["/path/to/ai-craftsman-superpowers/ai-pack/mcp/knowledge-rag/dist/src/index.js"]
    }
  }
}
```

Then restart Claude Code.

> **Note:** Replace `~` with your actual home directory path (e.g., `/Users/username` on macOS).

## Project-Specific Knowledge

Create a knowledge base specific to your project:

```bash
# In your project root
mkdir -p .claude/ai-craftsman-superpowers/knowledge

# Add your documents
cp specs.pdf architecture.md .claude/ai-craftsman-superpowers/knowledge/

# Index (run from your project directory)
npx tsx /path/to/ai-pack/mcp/knowledge-rag/scripts/index-pdfs.ts
```

### Project Structure

```
your-project/
├── .claude/
│   └── ai-craftsman-superpowers/
│       └── knowledge/              # Your documents here
│           ├── specs.pdf
│           ├── architecture.md
│           └── .index/             # Auto-generated
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
2. **Global** - `~/.claude/ai-craftsman-superpowers/knowledge/` (user home)

The MCP server automatically uses project knowledge when available.

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

### Environment Variables

```bash
# Ollama configuration (optional - defaults shown)
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_EMBED_MODEL=nomic-embed-text
```

### Supported Embedding Models

| Model | Dimensions | Notes |
|-------|------------|-------|
| `nomic-embed-text` | 768 | Default, good balance |
| `mxbai-embed-large` | 1024 | Higher quality |
| `all-minilm` | 384 | Faster, smaller |
| `snowflake-arctic-embed` | 1024 | High quality |

To use a different model:

```bash
ollama pull mxbai-embed-large
OLLAMA_EMBED_MODEL=mxbai-embed-large npm run index:ollama
```

## Architecture

```
~/.claude/ai-craftsman-superpowers/
└── knowledge/                      # Global knowledge (user default)
    ├── your-documents.pdf
    ├── notes.md
    └── knowledge.db                # SQLite + embeddings

ai-pack/mcp/knowledge-rag/
├── src/
│   ├── index.ts                    # MCP server entry
│   ├── db/vector-store.ts          # SQLite + auto-detection
│   ├── embeddings/provider.ts      # Ollama provider
│   └── tools/                      # search_knowledge, list_sources
├── scripts/
│   └── index-pdfs.ts               # Indexing script
└── tests/
    └── vector-store.test.ts        # Test suite

your-project/
└── .claude/ai-craftsman-superpowers/
    └── knowledge/                  # Project-specific (takes priority)
        ├── project-docs.pdf
        └── .index/knowledge.db
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

# Pull if missing
ollama pull nomic-embed-text
```

### MCP not connecting in Claude Code

1. Verify build: `ls dist/src/index.js`
2. Test manually: `node dist/src/index.js` (should start without errors)
3. Restart Claude Code after configuration changes

### Database issues

```bash
# Reset global database
rm ~/.claude/ai-craftsman-superpowers/knowledge/knowledge.db*
npm run index:ollama

# Reset project database
rm .claude/ai-craftsman-superpowers/knowledge/.index/knowledge.db*
# Then re-index from project directory
```

### Project knowledge not detected

Ensure you're running Claude Code from the project root where `.claude/ai-craftsman-superpowers/knowledge/` exists.

### Empty search results

The server logs warnings on startup:
- `WARNING: Knowledge base is empty` - Run indexer first
- `WARNING: Ollama not responding` - Start Ollama with `ollama serve`

## Development

### Run tests

```bash
npm test
```

### Build

```bash
npm run build
```

## References

- [Ollama Documentation](https://ollama.ai/docs)
- [MCP Protocol](https://modelcontextprotocol.io)
