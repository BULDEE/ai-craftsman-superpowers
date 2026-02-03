# Vector Databases

## What are Vectors?

Vectors are numerical representations of semantic meaning. They capture the "essence" of text, images, or other data as coordinates in high-dimensional space.

```
"king" → [0.2, 0.8, -0.1, 0.5, ...]  (1536 dimensions for OpenAI)
"queen" → [0.3, 0.7, -0.2, 0.6, ...]  (similar direction)
"car" → [-0.5, 0.1, 0.9, -0.3, ...]  (different region)
```

## Why Vector DBs?

| Traditional DB | Vector DB |
|----------------|-----------|
| Exact match: "SELECT WHERE title = 'X'" | Semantic match: "Find similar to X" |
| Keyword search | Meaning search |
| Structured queries | Similarity queries |

## Core Operations

### 1. Indexing (Insert)
```python
db.insert(id="doc1", vector=[0.2, 0.8, ...], metadata={"source": "wiki"})
```

### 2. Similarity Search (Query)
```python
results = db.search(query_vector=[0.3, 0.7, ...], top_k=5)
# Returns: [(doc1, 0.95), (doc7, 0.89), ...]
```

### 3. Filtered Search
```python
results = db.search(
    query_vector=[...],
    filter={"source": "wiki", "date": {"$gt": "2024-01-01"}},
    top_k=5
)
```

## Distance Metrics

| Metric | Formula | Best For |
|--------|---------|----------|
| Cosine | 1 - (A·B)/(‖A‖‖B‖) | Text similarity |
| Euclidean | √Σ(Ai-Bi)² | Image features |
| Dot Product | A·B | When magnitude matters |

**Rule of thumb:** Use cosine for text embeddings.

## Index Types

| Index | Speed | Accuracy | Memory |
|-------|-------|----------|--------|
| Flat (brute force) | Slow | 100% | Low |
| IVF (inverted file) | Fast | ~95% | Medium |
| HNSW (graph-based) | Very fast | ~99% | High |
| PQ (product quantization) | Very fast | ~90% | Very low |

## Vector DB Comparison

| Database | Type | Best For |
|----------|------|----------|
| **pgvector** | PostgreSQL extension | Already using Postgres, <1M vectors |
| **Pinecone** | Managed SaaS | Production, zero-ops |
| **Weaviate** | Open source | Hybrid search, GraphQL |
| **Qdrant** | Open source | High performance, filtering |
| **Milvus** | Open source | Large scale, distributed |
| **Chroma** | Open source | Prototyping, local dev |

## pgvector Quick Start

```sql
-- Enable extension
CREATE EXTENSION vector;

-- Create table with vector column
CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    content TEXT,
    embedding vector(1536),
    metadata JSONB
);

-- Create index (HNSW recommended)
CREATE INDEX ON documents
USING hnsw (embedding vector_cosine_ops);

-- Insert
INSERT INTO documents (content, embedding, metadata)
VALUES ('Hello world', '[0.1, 0.2, ...]', '{"source": "test"}');

-- Search (cosine similarity)
SELECT id, content, 1 - (embedding <=> '[0.15, 0.25, ...]') AS similarity
FROM documents
ORDER BY embedding <=> '[0.15, 0.25, ...]'
LIMIT 5;
```

## Embedding Models

| Model | Dimensions | Quality | Speed |
|-------|------------|---------|-------|
| OpenAI text-embedding-3-small | 1536 | High | Fast |
| OpenAI text-embedding-3-large | 3072 | Highest | Medium |
| Sentence Transformers | 384-768 | Good | Very fast |
| Cohere embed-v3 | 1024 | High | Fast |

## Use Cases

| Use Case | Implementation |
|----------|----------------|
| Semantic search | Query embedding → similarity search |
| RAG | Retrieve context → feed to LLM |
| Recommendations | Find similar items |
| Deduplication | Cluster similar documents |
| Anomaly detection | Find distant vectors |

## Best Practices

1. **Normalize vectors** before storing (most DBs do this automatically)
2. **Use appropriate index** - HNSW for quality, IVF for scale
3. **Tune parameters** - ef_construction, m for HNSW
4. **Batch operations** - Insert in batches of 100-1000
5. **Monitor recall** - Test accuracy vs brute force periodically
6. **Plan for scale** - Choose DB based on expected volume
