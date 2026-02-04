# Local RAG Setup with Ollama

This guide explains how to set up a local RAG (Retrieval-Augmented Generation) knowledge base using Ollama for embeddings and local LLM inference.

> **Recommendation:** We recommend **Ollama** (local, free, private) over OpenAI API (cloud, paid). See [ADR-0002: Ollama over OpenAI](../adr/0002-ollama-over-openai.md) for rationale.

## Embedding Options

| Option | Privacy | Cost | Setup | Recommended |
|--------|---------|------|-------|-------------|
| **Ollama** (local) | ✅ 100% private | Free | Medium | ✅ Yes |
| OpenAI API | ❌ Cloud | ~$0.0001/1K tokens | Easy | For quick start only |

## Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Local RAG Architecture                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Documents ──► Chunking ──► Embeddings ──► Vector DB           │
│       │                          │              │                │
│       │                    [Ollama]        [Chroma/Qdrant]       │
│       │                          │              │                │
│       └──────────────────────────┴──────────────┘                │
│                                  │                               │
│                             Query ──► Context ──► LLM Response   │
│                                                    [Ollama]      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- macOS, Linux, or Windows (WSL2)
- 8GB+ RAM (16GB recommended for larger models)
- Python 3.10+
- ~10GB disk space for models

## Step 1: Install Ollama

### macOS

```bash
# Using Homebrew
brew install ollama

# Or download from https://ollama.ai
```

### Linux

```bash
curl -fsSL https://ollama.ai/install.sh | sh
```

### Verify Installation

```bash
ollama --version
# ollama version 0.1.x
```

## Step 2: Pull Required Models

### Embedding Model

```bash
# Recommended: nomic-embed-text (fast, good quality)
ollama pull nomic-embed-text

# Alternative: mxbai-embed-large (higher quality, slower)
ollama pull mxbai-embed-large
```

### Chat Model

```bash
# For code understanding (recommended)
ollama pull codellama:13b

# For general use
ollama pull llama3:8b

# Smaller, faster option
ollama pull phi3:mini
```

### Verify Models

```bash
ollama list
# NAME                    SIZE
# nomic-embed-text:latest 274 MB
# codellama:13b          7.4 GB
```

## Step 3: Start Ollama Server

```bash
# Start server (runs on port 11434)
ollama serve

# Verify it's running
curl http://localhost:11434/api/tags
```

## Step 4: Set Up Python Environment

```bash
# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # Linux/macOS
# .venv\Scripts\activate   # Windows

# Install dependencies
pip install langchain langchain-community chromadb ollama
```

## Step 5: Create RAG Pipeline

### Basic Setup

```python
#!/usr/bin/env python3
"""Local RAG pipeline with Ollama."""

from langchain_community.document_loaders import DirectoryLoader, TextLoader
from langchain_community.embeddings import OllamaEmbeddings
from langchain_community.llms import Ollama
from langchain_community.vectorstores import Chroma
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain.chains import RetrievalQA

# Configuration
OLLAMA_BASE_URL = "http://localhost:11434"
EMBEDDING_MODEL = "nomic-embed-text"
CHAT_MODEL = "codellama:13b"
DOCS_DIR = "./knowledge"
PERSIST_DIR = "./vectorstore"


def create_vectorstore(docs_dir: str, persist_dir: str) -> Chroma:
    """Create or load vector store from documents."""

    # Load documents
    loader = DirectoryLoader(
        docs_dir,
        glob="**/*.md",
        loader_cls=TextLoader,
        loader_kwargs={"encoding": "utf-8"},
    )
    documents = loader.load()
    print(f"Loaded {len(documents)} documents")

    # Split into chunks
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=1000,
        chunk_overlap=200,
        separators=["\n## ", "\n### ", "\n\n", "\n", " ", ""],
    )
    chunks = splitter.split_documents(documents)
    print(f"Split into {len(chunks)} chunks")

    # Create embeddings
    embeddings = OllamaEmbeddings(
        base_url=OLLAMA_BASE_URL,
        model=EMBEDDING_MODEL,
    )

    # Create and persist vector store
    vectorstore = Chroma.from_documents(
        documents=chunks,
        embedding=embeddings,
        persist_directory=persist_dir,
    )
    vectorstore.persist()
    print(f"Vector store created at {persist_dir}")

    return vectorstore


def load_vectorstore(persist_dir: str) -> Chroma:
    """Load existing vector store."""
    embeddings = OllamaEmbeddings(
        base_url=OLLAMA_BASE_URL,
        model=EMBEDDING_MODEL,
    )
    return Chroma(
        persist_directory=persist_dir,
        embedding_function=embeddings,
    )


def create_qa_chain(vectorstore: Chroma) -> RetrievalQA:
    """Create question-answering chain."""
    llm = Ollama(
        base_url=OLLAMA_BASE_URL,
        model=CHAT_MODEL,
        temperature=0.1,
    )

    retriever = vectorstore.as_retriever(
        search_type="mmr",  # Maximum Marginal Relevance
        search_kwargs={"k": 5, "fetch_k": 10},
    )

    return RetrievalQA.from_chain_type(
        llm=llm,
        chain_type="stuff",
        retriever=retriever,
        return_source_documents=True,
    )


def main():
    """Main entry point."""
    import sys

    # Create or load vector store
    if "--rebuild" in sys.argv:
        vectorstore = create_vectorstore(DOCS_DIR, PERSIST_DIR)
    else:
        try:
            vectorstore = load_vectorstore(PERSIST_DIR)
            print("Loaded existing vector store")
        except Exception:
            vectorstore = create_vectorstore(DOCS_DIR, PERSIST_DIR)

    # Create QA chain
    qa = create_qa_chain(vectorstore)

    # Interactive query loop
    print("\n🔍 Local RAG ready. Type 'quit' to exit.\n")
    while True:
        query = input("Question: ").strip()
        if query.lower() in ("quit", "exit", "q"):
            break
        if not query:
            continue

        result = qa.invoke({"query": query})
        print(f"\n📝 Answer:\n{result['result']}\n")
        print("📚 Sources:")
        for doc in result["source_documents"][:3]:
            print(f"  - {doc.metadata.get('source', 'unknown')}")
        print()


if __name__ == "__main__":
    main()
```

### Save as `scripts/local-rag.py`

## Step 6: Index Your Knowledge Base

```bash
# Index the knowledge directory
python scripts/local-rag.py --rebuild

# Output:
# Loaded 15 documents
# Split into 87 chunks
# Vector store created at ./vectorstore
```

## Step 7: Query Your Knowledge Base

```bash
python scripts/local-rag.py

# 🔍 Local RAG ready. Type 'quit' to exit.
#
# Question: What is the Entity pattern in DDD?
#
# 📝 Answer:
# An Entity in DDD is an object with a unique identity that persists
# through time and different states. Unlike Value Objects, Entities
# are distinguished by their identity rather than their attributes...
#
# 📚 Sources:
#   - knowledge/patterns.md
#   - knowledge/principles.md
```

## Configuration Options

### Embedding Models Comparison

| Model | Size | Speed | Quality | Use Case |
|-------|------|-------|---------|----------|
| `nomic-embed-text` | 274 MB | Fast | Good | General purpose |
| `mxbai-embed-large` | 1.3 GB | Medium | High | Technical docs |
| `all-minilm` | 46 MB | Very Fast | Fair | Resource-constrained |

### Chat Models Comparison

| Model | Size | Speed | Quality | Use Case |
|-------|------|-------|---------|----------|
| `phi3:mini` | 2.2 GB | Fast | Good | Quick answers |
| `llama3:8b` | 4.7 GB | Medium | High | General use |
| `codellama:13b` | 7.4 GB | Slow | Very High | Code understanding |
| `codellama:34b` | 19 GB | Very Slow | Excellent | Complex analysis |

### Chunking Strategy

```python
# For code
splitter = RecursiveCharacterTextSplitter(
    chunk_size=1500,
    chunk_overlap=200,
    separators=["\nclass ", "\ndef ", "\n\n", "\n", " "],
)

# For documentation
splitter = RecursiveCharacterTextSplitter(
    chunk_size=1000,
    chunk_overlap=200,
    separators=["\n## ", "\n### ", "\n\n", "\n", " "],
)
```

## Integration with Claude Code

### Using RAG in Skills

The `/craftsman:rag` skill can help you design custom RAG pipelines. Ask:

```
/craftsman:rag
I want to create a knowledge base for our company's internal documentation.
```

### Adding to CLAUDE.md

Add your local RAG endpoint to project context:

```markdown
# Project Context

## Knowledge Base

Local RAG available at: http://localhost:11434
- Embedding model: nomic-embed-text
- Chat model: codellama:13b
- Index: ./vectorstore (rebuilt daily)

To query: `python scripts/local-rag.py`
```

## Troubleshooting

### Ollama not responding

```bash
# Check if running
curl http://localhost:11434/api/tags

# Restart
pkill ollama
ollama serve
```

### Out of memory

```bash
# Use smaller model
ollama pull phi3:mini

# Or limit context
llm = Ollama(model="codellama:13b", num_ctx=2048)
```

### Slow embedding

```bash
# Use faster model
EMBEDDING_MODEL = "all-minilm"

# Or reduce chunk size
chunk_size = 500
```

## Alternative: OpenAI Embeddings

If you prefer cloud-based embeddings (faster setup, but not private):

### Setup

```bash
# Set API key
export OPENAI_API_KEY=sk-...

# Install OpenAI package
pip install openai langchain-openai
```

### Code Change

```python
# Replace OllamaEmbeddings with OpenAIEmbeddings
from langchain_openai import OpenAIEmbeddings

embeddings = OpenAIEmbeddings(
    model="text-embedding-3-small",  # or text-embedding-3-large
    # api_key is read from OPENAI_API_KEY env var
)
```

### Cost Comparison

| Model | Cost per 1M tokens | Quality |
|-------|-------------------|---------|
| `text-embedding-3-small` | $0.02 | Good |
| `text-embedding-3-large` | $0.13 | High |
| Ollama `nomic-embed-text` | **Free** | Good |

> **Our recommendation:** Start with Ollama for privacy and cost. Use OpenAI only if you need faster initial setup or higher embedding quality for production.

## Knowledge Base Locations

The MCP server supports two knowledge base modes:

### 1. Project-Specific Knowledge (Recommended)

Create a knowledge base specific to your project:

```bash
# In your project root
mkdir -p .claude/ai-craftsman-superpowers/knowledge

# Add project-specific documents
cp specs.pdf architecture.md .claude/ai-craftsman-superpowers/knowledge/
```

**Structure:**

```
your-project/
├── .claude/
│   └── ai-craftsman-superpowers/
│       └── knowledge/              # Your documents
│           ├── specs.pdf
│           ├── architecture.md
│           └── .index/             # Auto-generated (gitignore)
│               └── knowledge.db
├── src/
└── ...
```

**Index project knowledge:**

```bash
# From your project directory
cd /path/to/your-project
npx tsx /path/to/ai-pack/mcp/knowledge-rag/scripts/index-pdfs.ts

# Output:
# Mode: PROJECT knowledge base
# Source directory: /path/to/your-project/.claude/ai-craftsman-superpowers/knowledge
# Database: /path/to/your-project/.claude/ai-craftsman-superpowers/knowledge/.index/knowledge.db
```

**Add to `.gitignore`:**

```
.claude/ai-craftsman-superpowers/knowledge/.index/
```

### 2. Global Plugin Knowledge (Fallback)

When no project knowledge exists, the MCP uses the plugin's global knowledge:

```
ai-pack/knowledge/
├── agent-3p-pattern.md
├── mlops-principles.md
├── rag-architecture.md
└── vector-databases.md
```

### Detection Priority

1. **Project** - `.claude/ai-craftsman-superpowers/knowledge/` in cwd
2. **Global** - `ai-pack/knowledge/` in plugin installation

See [ADR-0006: Project-Specific Knowledge](../adr/0006-project-specific-knowledge.md) for rationale.

## Using the MCP Server

The `ai-pack/mcp/knowledge-rag` MCP server provides RAG over the knowledge base:

```bash
cd ai-pack/mcp/knowledge-rag

# Install
npm install

# Build
npm run build

# Index global knowledge
npm run index:ollama

# Run tests
npm run test
```

See [ai-pack/mcp/knowledge-rag/README.md](../../ai-pack/mcp/knowledge-rag/README.md) for full MCP integration.

## References

- [Ollama Documentation](https://ollama.ai/docs)
- [LangChain + Ollama](https://python.langchain.com/docs/integrations/llms/ollama)
- [ChromaDB Documentation](https://docs.trychroma.com/)
- [ADR-001: Model Tiering](../adr/001-model-tiering.md)
- [ADR-0002: Ollama over OpenAI](../adr/0002-ollama-over-openai.md)
