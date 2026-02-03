# Knowledge RAG MCP Server

MCP server for RAG (Retrieval-Augmented Generation) over local AI/Architecture knowledge base.

## Setup

```bash
# Install dependencies
npm install

# Build TypeScript
npm run build

# Index PDFs (requires OPENAI_API_KEY)
export OPENAI_API_KEY=sk-...
npm run index
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
┌──────────────┐     ┌─────────────────────────────────────┐
│   21 PDFs    │ ──→ │        knowledge.db                  │
│   (source)   │     │  SQLite + vec0 (vector search)      │
└──────────────┘     └─────────────────────────────────────┘
                                    │
                                    ↓
┌──────────────┐     ┌─────────────────────────────────────┐
│ Claude Code  │ ←──→│     knowledge-rag MCP Server        │
│              │     │  - search_knowledge                 │
│              │     │  - list_knowledge_sources           │
└──────────────┘     └─────────────────────────────────────┘
```

## Topics Covered

- RAG (Retrieval-Augmented Generation)
- MLOps principles
- Vector databases
- Microservices patterns
- CQRS and Event-Driven Architecture
- SOLID principles
- Design patterns
- API design (REST, GraphQL)
- Authentication/Authorization
- Database scaling
- Caching strategies
- AI/LLM engineering
