# MCP Servers Reference

MCP (Model Context Protocol) servers extend Claude Code with custom tools.

## What is MCP?

MCP allows external services to expose tools that Claude can use:

```
┌─────────────┐     tool call      ┌─────────────────┐
│ Claude Code │ ←────────────────→ │   MCP Server    │
│             │     result         │                 │
└─────────────┘                    └─────────────────┘
```

---

## knowledge-rag

**Purpose**: Semantic search over indexed documents.

**Location**: `ai-pack/mcp/knowledge-rag/`

### Tools Provided

#### search_knowledge

Search the knowledge base for relevant information.

**Input**:
```json
{
  "query": "What are the MLOps principles?",
  "top_k": 5,
  "sources": ["MLOps Fundamentals.pdf"]
}
```

**Output**:
```markdown
## Knowledge Base Search Results
**Query:** What are the MLOps principles?
**Found:** 5 relevant chunks

### Result 1 (94% match)
**Source:** MLOps Fundamentals.pdf (page 3)

The 6 core MLOps principles are:
1. Automation - From manual to continuous training
2. Versioning - Track code, data, and models
...
```

#### list_knowledge_sources

List all indexed documents.

**Input**: None

**Output**:
```markdown
## Knowledge Base Sources
**Total:** 21 documents, 603 chunks

| Document | Pages | Chunks | Topics |
|----------|-------|--------|--------|
| RAG Fundamentals.pdf | 8 | 34 | RAG |
| MLOps Fundamentals.pdf | 14 | 62 | MLOps |
...
```

### Configuration

**Global** (`~/.claude/settings.local.json`):
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

**Per-project** (`~/.claude.json`):
```json
{
  "projects": {
    "/path/to/project": {
      "mcpServers": {
        "knowledge-rag": {
          "command": "node",
          "args": ["/path/to/dist/index.js"]
        }
      }
    }
  }
}
```

### Architecture

```
knowledge-rag/
├── src/
│   ├── index.ts           # MCP server entry (stdio)
│   ├── tools/
│   │   ├── search-knowledge.ts
│   │   └── list-sources.ts
│   ├── db/
│   │   └── vector-store.ts  # SQLite + cosine search
│   └── embeddings/
│       └── provider.ts      # Ollama integration
├── scripts/
│   └── index-pdfs.ts      # One-time indexing
└── dist/src/              # Compiled output
    └── index.js           # Entry point

# Database locations (auto-detected):
# Project: .claude/ai-craftsman-superpowers/knowledge/.index/knowledge.db
# Global:  ~/.claude/ai-craftsman-superpowers/knowledge/knowledge.db
```

### Setup

```bash
# Install dependencies
cd ai-pack/mcp/knowledge-rag
npm install

# Build
npm run build

# Pull embedding model
ollama pull nomic-embed-text

# Index documents
npm run index /path/to/pdfs

# Verify
ls -la data/knowledge.db
```

### Customization

#### Change Embedding Model

Edit `src/embeddings/provider.ts`:

```typescript
static create(
  model: string = "mxbai-embed-large",  // Higher quality
  baseUrl: string = "http://localhost:11434"
): OllamaEmbeddingProvider {
```

Update dimensions in `src/db/vector-store.ts`:

```typescript
static create(dbPath?: string, dimensions: number = 1024): VectorStore {
```

Rebuild and re-index.

#### Add Custom Tool

1. Create tool in `src/tools/`:

```typescript
// src/tools/summarize-source.ts
export class SummarizeSourceTool {
  static readonly schema = {
    name: "summarize_source",
    description: "Get summary of a specific document",
    inputSchema: {
      type: "object",
      properties: {
        source: { type: "string" }
      },
      required: ["source"]
    }
  };

  execute(input: { source: string }): { summary: string } {
    // Implementation
  }
}
```

2. Register in `src/index.ts`:

```typescript
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    SearchKnowledgeTool.schema,
    ListSourcesTool.schema,
    SummarizeSourceTool.schema  // Add here
  ]
}));
```

3. Rebuild: `npm run build`

---

## Creating Custom MCP Servers

### Template

```typescript
#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

const server = new Server(
  { name: "my-server", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

// List available tools
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [{
    name: "my_tool",
    description: "What this tool does",
    inputSchema: {
      type: "object",
      properties: {
        param: { type: "string", description: "Parameter" }
      },
      required: ["param"]
    }
  }]
}));

// Handle tool calls
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name === "my_tool") {
    const result = doSomething(args.param);
    return {
      content: [{ type: "text", text: result }]
    };
  }

  throw new Error(`Unknown tool: ${name}`);
});

// Start server
const transport = new StdioServerTransport();
await server.connect(transport);
```

### Best Practices

1. **Clear descriptions**: Claude selects tools based on descriptions
2. **Validate inputs**: Check parameters before processing
3. **Handle errors**: Return helpful error messages
4. **Format output**: Use markdown for readability
5. **Limit response size**: Don't overwhelm context window

---

## Troubleshooting

### Server not connecting

```bash
# Check if Ollama is running
curl http://localhost:11434/api/tags

# Test server manually
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | node dist/index.js
```

### Empty search results

```bash
# Check database exists
ls -la data/knowledge.db

# Check chunk count
sqlite3 data/knowledge.db "SELECT COUNT(*) FROM chunks"

# Re-index if needed
npm run index
```

### Slow searches

For large knowledge bases (>10K chunks):
- Consider adding sqlite-vec extension
- Implement result caching
- Pre-filter by source when possible
