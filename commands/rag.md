---
description: Design RAG (Retrieval-Augmented Generation) pipelines. Use when building knowledge bases, document Q&A, or semantic search systems.
---

# /craftsman:rag - Retrieval-Augmented Generation Design

Design production-ready RAG pipelines following best practices.

## RAG Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        RAG PIPELINE                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐       │
│  │   INGESTION  │───▶│   RETRIEVAL  │───▶│  GENERATION  │       │
│  └──────────────┘    └──────────────┘    └──────────────┘       │
│                                                                  │
│  Documents → Chunks   Query → Vectors    Context → LLM → Answer │
│  → Embeddings →       → Similar Chunks   → Response             │
│  Vector Store                                                    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Three Pipelines

### 1. Ingestion Pipeline

```python
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain.embeddings import OpenAIEmbeddings
from langchain.vectorstores import PGVector

# Chunking Strategy
text_splitter = RecursiveCharacterTextSplitter(
    chunk_size=1000,        # Characters per chunk
    chunk_overlap=200,      # Overlap for context
    separators=["\n\n", "\n", ". ", " ", ""],
)

# Embedding Model
embeddings = OpenAIEmbeddings(
    model="text-embedding-3-small",  # Cost-effective
    # model="text-embedding-3-large", # Higher quality
)

# Vector Store
vectorstore = PGVector.from_documents(
    documents=chunks,
    embedding=embeddings,
    collection_name="knowledge_base",
    connection_string=DATABASE_URL,
)
```

### 2. Retrieval Pipeline

```python
from langchain.retrievers import ContextualCompressionRetriever
from langchain.retrievers.document_compressors import LLMChainExtractor

# Base Retriever
retriever = vectorstore.as_retriever(
    search_type="similarity",  # or "mmr" for diversity
    search_kwargs={"k": 5},    # Top K results
)

# Optional: Contextual Compression
compressor = LLMChainExtractor.from_llm(llm)
compression_retriever = ContextualCompressionRetriever(
    base_compressor=compressor,
    base_retriever=retriever,
)
```

### 3. Generation Pipeline

```python
from langchain.chains import RetrievalQA
from langchain.chat_models import ChatOpenAI

llm = ChatOpenAI(
    model="gpt-4-turbo-preview",
    temperature=0,  # Deterministic for factual answers
)

qa_chain = RetrievalQA.from_chain_type(
    llm=llm,
    chain_type="stuff",  # or "map_reduce" for long contexts
    retriever=retriever,
    return_source_documents=True,
)
```

## Chunking Strategies

| Strategy | Use Case | Chunk Size |
|----------|----------|------------|
| Fixed | General text | 500-1000 chars |
| Sentence | Precise retrieval | 1-3 sentences |
| Paragraph | Structured docs | Natural breaks |
| Semantic | Technical docs | Topic boundaries |
| Recursive | Mixed content | Adaptive |

## Vector Database Comparison

| Database | Pros | Cons | Best For |
|----------|------|------|----------|
| **pgvector** | PostgreSQL native, ACID | Scale limits | Small-medium, existing PG |
| **Pinecone** | Managed, fast | Cost, vendor lock | Production, scale |
| **Weaviate** | Hybrid search | Complexity | Complex queries |
| **Chroma** | Simple, local | Not for prod | Development, prototypes |
| **Qdrant** | Fast, filtering | Self-host | Performance critical |

## Design Checklist

```markdown
## RAG Design: [Project Name]

### 1. Data Source Analysis
- [ ] Document types: [PDF, Markdown, HTML, etc.]
- [ ] Total volume: [X documents, Y MB]
- [ ] Update frequency: [Real-time, Daily, Weekly]
- [ ] Quality: [Clean, Needs preprocessing]

### 2. Chunking Strategy
- [ ] Strategy: [Recursive, Semantic, etc.]
- [ ] Chunk size: [X characters]
- [ ] Overlap: [Y characters]
- [ ] Metadata: [Title, Source, Date, etc.]

### 3. Embedding Choice
- [ ] Model: [text-embedding-3-small, etc.]
- [ ] Dimensions: [1536, 3072, etc.]
- [ ] Cost estimate: [$X per 1M tokens]

### 4. Vector Store
- [ ] Database: [pgvector, Pinecone, etc.]
- [ ] Index type: [HNSW, IVF, etc.]
- [ ] Hosting: [Self-hosted, Managed]

### 5. Retrieval Strategy
- [ ] Search type: [Similarity, MMR, Hybrid]
- [ ] Top K: [3-10]
- [ ] Reranking: [Yes/No]
- [ ] Filtering: [Metadata filters]

### 6. Generation
- [ ] Model: [GPT-4, Claude, etc.]
- [ ] Temperature: [0 for factual, 0.7 for creative]
- [ ] Context window: [Token limit]
- [ ] Fallback: [When no relevant docs found]
```

## Common Pitfalls

| Pitfall | Solution |
|---------|----------|
| Chunks too small | Increase size, lose context |
| Chunks too large | Decrease, add overlap |
| Wrong embedding model | Match to domain (code, medical, etc.) |
| No metadata | Add source, date, section |
| No evaluation | Implement retrieval metrics |

## Evaluation Metrics

```python
# Retrieval Quality
- Recall@K: % of relevant docs in top K
- Precision@K: % of top K that are relevant
- MRR: Mean Reciprocal Rank

# Generation Quality
- Faithfulness: Does answer match sources?
- Relevance: Does answer address query?
- Groundedness: Is answer supported by context?
```

## Process

1. **Understand the use case** (Q&A, search, chatbot)
2. **Analyze data sources**
3. **Choose chunking strategy**
4. **Select embedding model**
5. **Design vector store schema**
6. **Implement retrieval pipeline**
7. **Configure generation**
8. **Set up evaluation**
9. **Deploy and monitor**
