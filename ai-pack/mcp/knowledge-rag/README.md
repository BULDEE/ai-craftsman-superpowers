# Knowledge RAG MCP Server

MCP server for RAG (Retrieval-Augmented Generation) over local AI/Architecture knowledge base.

> **Recommendation:** Use Ollama for embeddings (local, free, private). OpenAI API is supported but not recommended for privacy-sensitive projects.

## Embedding Options

| Option | Command | Privacy | Cost |
|--------|---------|---------|------|
| **Ollama** (recommended) | `npm run index:ollama` | ✅ 100% local | Free |
| OpenAI API | `npm run index:openai` | ❌ Cloud | ~$0.02/1M tokens |

## Setup

### Option A: Ollama (Recommended)

```bash
# 1. Install Ollama
brew install ollama  # macOS
# curl -fsSL https://ollama.ai/install.sh | sh  # Linux

# 2. Pull embedding model
ollama pull nomic-embed-text

# 3. Start Ollama server
ollama serve

# 4. Install dependencies
npm install

# 5. Build TypeScript
npm run build

# 6. Index knowledge base with Ollama
npm run index:ollama
```

### Option B: OpenAI API (Quick Start)

```bash
# 1. Set API key
export OPENAI_API_KEY=sk-...

# 2. Install dependencies
npm install

# 3. Build TypeScript
npm run build

# 4. Index knowledge base with OpenAI
npm run index:openai
```

## Usage

The MCP server exposes two tools:

### search_knowledge

Search the knowledge base for relevant information.

```json
{
  "query": "What are the 3 pipelines in RAG?",
  "top_k": 5,
  "sources": ["RAG Fundamentals.pdf"]
}
```

### list_knowledge_sources

List all indexed documents.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    Knowledge RAG Architecture                     │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│   plugins/craftsman/knowledge/                                    │
│   ├── canonical/         ──┐                                      │
│   ├── anti-patterns/       │                                      │
│   ├── patterns.md          ├──► Chunking ──► Embeddings ──► DB    │
│   ├── principles.md        │         │           │          │     │
│   └── ...                ──┘         │      [Ollama or      │     │
│                                      │       OpenAI]        │     │
│                                      │           │          │     │
│                                      └───────────┴──────────┘     │
│                                                   │                │
│   Claude Code ◄──────────────────────────────────┘                │
│       │                                                           │
│       └── MCP: search_knowledge, list_knowledge_sources           │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

## Topics Covered

The knowledge base includes:

- **Design Patterns** - Factory, Strategy, Observer, etc.
- **DDD Patterns** - Entity, Value Object, Aggregate, Repository
- **SOLID Principles** - With PHP/TypeScript examples
- **Clean Architecture** - Layer separation, dependency rules
- **Event-Driven** - Event sourcing, CQRS
- **Microservices** - Patterns and anti-patterns
- **Canonical Examples** - Golden standard code (PHP, TypeScript)
- **Anti-Patterns** - What to avoid with explanations

## Configuration

### Environment Variables

```bash
# Ollama (default)
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_EMBED_MODEL=nomic-embed-text

# OpenAI (alternative)
OPENAI_API_KEY=sk-...
OPENAI_EMBED_MODEL=text-embedding-3-small
```

### Adding to Claude Code

Add to your `.mcp.json`:

```json
{
  "knowledge-rag": {
    "command": "node",
    "args": ["path/to/ai-craftsman-superpowers/ai-pack/mcp/knowledge-rag/dist/index.js"]
  }
}
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

## References

- [Local RAG Setup Guide](../../../docs/guides/local-rag-ollama.md)
- [ADR-0002: Ollama over OpenAI](../../../docs/adr/0002-ollama-over-openai.md)
- [Ollama Documentation](https://ollama.ai/docs)
