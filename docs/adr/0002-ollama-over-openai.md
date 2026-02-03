# ADR-0002: Ollama over OpenAI for Local RAG

## Status

Accepted

## Date

2025-02-03

## Context

The knowledge-rag MCP server requires an embedding model to convert text chunks into vectors for similarity search. Two main options existed:

1. **OpenAI Embeddings API**: Cloud-based, high quality
2. **Ollama Local Embeddings**: Self-hosted, free, private

Key considerations:
- Privacy of indexed documents
- Cost at scale
- Latency requirements
- Offline capability
- Setup complexity

## Decision

We chose **Ollama with nomic-embed-text** model for embeddings.

```typescript
// Local embedding via Ollama
const response = await fetch("http://localhost:11434/api/embeddings", {
  method: "POST",
  body: JSON.stringify({ model: "nomic-embed-text", prompt: text })
});
```

Configuration:
- Model: `nomic-embed-text` (768 dimensions)
- Server: `http://localhost:11434`
- Zero API keys required

## Consequences

### Positive

- **Zero cost**: No per-token charges
- **Privacy**: Documents never leave the machine
- **Offline**: Works without internet
- **Fast**: ~50ms per embedding (local GPU)
- **No API keys**: Simpler setup and distribution

### Negative

- **Setup required**: User must install Ollama + pull model
- **Resource usage**: ~500MB model in memory
- **Quality**: Slightly lower than OpenAI text-embedding-3-large
- **No batching API**: Sequential embedding (slower for large corpus)

### Neutral

- 768 dimensions vs 1536 (OpenAI) - acceptable for our corpus size
- Model can be swapped (mxbai-embed-large for higher quality)

## Alternatives Considered

### Alternative 1: OpenAI text-embedding-3-small

**Pros:**
- Higher quality embeddings
- Native batch API
- No local setup

**Rejected because:**
- Requires API key management
- Cost: $0.02/1M tokens (adds up with re-indexing)
- Privacy concerns with sensitive documents
- Network dependency

### Alternative 2: Sentence Transformers (Python)

**Pros:**
- High quality open models
- Flexible

**Rejected because:**
- Requires Python runtime
- Heavier dependencies
- Slower cold start
- MCP server is Node.js

### Alternative 3: Hybrid (Ollama local, OpenAI fallback)

**Pros:**
- Best of both worlds

**Rejected because:**
- Complexity of dual configuration
- Inconsistent embeddings between providers
- YAGNI for current use case

## Performance Benchmarks

| Provider | Latency (single) | Batch 100 | Quality (MTEB) |
|----------|------------------|-----------|----------------|
| OpenAI small | 100ms | 200ms | 62.3 |
| Ollama nomic | 50ms | 5000ms | 59.4 |
| Ollama mxbai | 80ms | 8000ms | 64.4 |

For 603 chunks, total indexing time: ~30s (acceptable for one-time operation).

## References

- [Ollama Embedding Models](https://ollama.com/library)
- [nomic-embed-text](https://huggingface.co/nomic-ai/nomic-embed-text-v1)
- [MTEB Leaderboard](https://huggingface.co/spaces/mteb/leaderboard)
- [OpenAI Embeddings](https://platform.openai.com/docs/guides/embeddings)
