# ADR-0003: SQLite over pgvector for Vector Storage

## Status

Accepted

## Date

2025-02-03

## Context

The RAG system needs a vector database to store embeddings and perform similarity search. Options considered:

1. **pgvector**: PostgreSQL extension, production-grade
2. **SQLite + in-memory search**: Lightweight, portable
3. **Chroma**: Purpose-built vector DB
4. **Pinecone/Qdrant**: Managed vector DBs

Key constraints:
- Must work without external infrastructure
- Portable (single file)
- Fast cold start for MCP server
- Corpus size: ~1000 chunks (small)

## Decision

We chose **SQLite with embeddings stored as BLOBs** and **in-memory cosine similarity search**.

```typescript
// Store embedding as BLOB
const buffer = Buffer.from(new Float32Array(embedding).buffer);
db.prepare("INSERT INTO chunks (content, embedding) VALUES (?, ?)").run(text, buffer);

// Search: load all embeddings, compute cosine distance in JS
const allEmbeddings = db.prepare("SELECT id, embedding FROM chunks").all();
const scored = allEmbeddings.map(row => ({
  id: row.id,
  distance: cosineDistance(queryEmbedding, parseEmbedding(row.embedding))
}));
```

## Consequences

### Positive

- **Zero infrastructure**: No database server to run
- **Portable**: Single `knowledge.db` file (~2.5MB)
- **Instant cold start**: SQLite opens in milliseconds
- **Simple backup**: Copy one file
- **No native extensions**: Pure JS cosine calculation

### Negative

- **Not scalable**: O(n) search, not suitable for >10K chunks
- **Memory usage**: All embeddings loaded in RAM (~4.6MB for 603 chunks)
- **No ANN index**: Brute force search (acceptable for small corpus)

### Neutral

- Performance is excellent for our use case (~5ms search)
- Can migrate to sqlite-vec extension later if needed

## Alternatives Considered

### Alternative 1: pgvector (PostgreSQL)

**Pros:**
- Production-grade
- HNSW index for fast ANN search
- Scales to millions of vectors

**Rejected because:**
- Requires PostgreSQL running
- Heavier setup (docker or local install)
- Overkill for 600 chunks
- Slower cold start

### Alternative 2: Chroma

**Pros:**
- Purpose-built for RAG
- Nice Python API
- Automatic persistence

**Rejected because:**
- Python dependency (MCP server is Node.js)
- Heavier footprint
- Another process to manage

### Alternative 3: sqlite-vec / sqlite-vss

**Pros:**
- Native vector search in SQLite
- Efficient indexing

**Rejected because:**
- Requires native extension compilation
- Portability issues across platforms
- Complex installation for end users

### Alternative 4: In-memory only (no persistence)

**Pros:**
- Simplest implementation

**Rejected because:**
- Must re-embed on every startup
- Wastes Ollama compute
- Slow startup

## Scaling Strategy

If corpus grows beyond 10K chunks:

1. **Short term**: Add sqlite-vec extension
2. **Medium term**: Migrate to pgvector
3. **Long term**: Consider managed solution (Pinecone)

Current threshold: Brute force acceptable up to ~50K chunks with sub-second latency.

## References

- [SQLite Documentation](https://sqlite.org/docs.html)
- [better-sqlite3](https://github.com/WiseLibs/better-sqlite3)
- [pgvector](https://github.com/pgvector/pgvector)
- [Choosing a Vector Database](https://www.pinecone.io/learn/vector-database/)
