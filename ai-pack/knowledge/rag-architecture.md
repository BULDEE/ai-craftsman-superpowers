# RAG Architecture - Retrieval-Augmented Generation

## What is RAG?

RAG combines retrieval systems with generative AI to produce accurate, contextual responses grounded in specific data sources.

## Problems Solved

| Problem | How RAG Solves It |
|---------|-------------------|
| Hallucinations | Grounds responses in retrieved facts |
| Outdated knowledge | Uses current data sources |
| Private data access | Queries internal documents |
| Domain expertise | Leverages specialized corpora |

## The 3 Pipelines

### 1. Ingestion Pipeline

```
[Documents] → Extract → Clean → Chunk → Embed → Load → [Vector DB]
```

| Stage | Purpose | Tools |
|-------|---------|-------|
| Extract | Parse PDFs, HTML, docs | unstructured, PyMuPDF |
| Clean | Remove noise, normalize | regex, spaCy |
| Chunk | Split into semantic units | LangChain splitters |
| Embed | Convert to vectors | OpenAI, Sentence Transformers |
| Load | Store in vector DB | pgvector, Pinecone, Qdrant |

**Chunking Strategies:**
- Fixed size (512 tokens) - simple, consistent
- Semantic (by paragraph/section) - preserves meaning
- Recursive (split large, keep small) - balanced
- Overlap (50-100 tokens) - prevents context loss

### 2. Retrieval Pipeline

```
[Query] → Embed → Similarity Search → Rerank → [Top-K Documents]
```

| Stage | Purpose | Techniques |
|-------|---------|------------|
| Query Embedding | Same model as ingestion | Consistency critical |
| Similarity Search | Find closest vectors | Cosine, Euclidean, Dot Product |
| Rerank | Improve relevance | Cross-encoders, MMR |
| Top-K Selection | Balance recall/precision | Typically 3-10 docs |

**Distance Metrics:**
- **Cosine**: Direction similarity (most common for text)
- **Euclidean**: Absolute distance
- **Dot Product**: Magnitude + direction

### 3. Generation Pipeline

```
[Query + Context] → Prompt Template → LLM → [Response]
```

**Prompt Template Pattern:**
```
You are an expert assistant.

Context from knowledge base:
{retrieved_documents}

User question: {query}

Answer based ONLY on the context above.
If the answer is not in the context, say "I don't have that information."
```

## Quality Metrics

| Metric | What it Measures |
|--------|------------------|
| Retrieval Precision | % of retrieved docs that are relevant |
| Retrieval Recall | % of relevant docs that were retrieved |
| Answer Faithfulness | Is answer grounded in context? |
| Answer Relevance | Does answer address the question? |

## Anti-Patterns

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| Too large chunks | Diluted relevance | Use 256-512 tokens |
| No overlap | Lost context at boundaries | Add 50-100 token overlap |
| Wrong embedding model | Semantic mismatch | Match model to domain |
| No reranking | Noise in context | Add cross-encoder reranker |
| No evaluation | Unknown quality | Implement RAGAS metrics |

## Decision Matrix

| Scenario | Recommended Approach |
|----------|---------------------|
| General Q&A | Standard RAG, cosine similarity |
| Code search | Code-specific embeddings, larger chunks |
| Multi-document reasoning | Iterative retrieval, chain-of-thought |
| Real-time updates | Streaming ingestion, cache invalidation |
| High precision required | Hybrid search (vector + BM25) |
