# Example: Internal Documentation Q&A System

## Prompt

```
/craftsman:rag
We want to build an internal Q&A system over our company's technical docs, onboarding guides, and API specs. Designers should be able to ask in plain English and get accurate answers with sources.
About 100 files, around 5 MB, in Markdown and OpenAPI, updated most days. We already run PostgreSQL.
```

## Expected Behavior

The skill works through its process (use case, data sources, chunking,
embedding, vector store, retrieval, generation, evaluation) and fills its
Design Checklist. Each decision carries a reason; figures the user did not give
are marked as estimates to confirm.

### 1. Data Source Analysis

```markdown
## RAG Design: Internal Docs Q&A

Use case: document Q&A with cited sources, for non-engineers.

- Document types: Markdown (onboarding, ADRs, guides), OpenAPI (API specs)
- Total volume: about 100 documents, about 5 MB (given by the user)
- Update frequency: daily, so ingestion must be incremental per file
- Quality: clean text; OpenAPI needs a structure-aware split, not a text split
```

### 2. Chunking Strategy

```markdown
- Strategy: Recursive for Markdown (headings, then paragraphs, then sentences);
  one chunk per operation for OpenAPI (path + method + parameters + responses)
- Chunk size: 1000 characters for Markdown, the skill's default
- Overlap: 200 characters
- Metadata: source file, heading path, document type, last modified date

Reason: a fixed-size split would cut an endpoint's parameters from its
responses; one operation per chunk keeps the unit a designer asks about.
```

### 3. Embedding Choice

```markdown
- Model: text-embedding-3-small
- Dimensions: 1536
- Cost estimate: about 1.3M tokens for a full embed (5 MB at roughly 4
  characters per token); check the provider's current price per 1M tokens

Reason: the corpus is small, so a full re-embed is cheap and the model can be
changed later. text-embedding-3-large is the alternative if the evaluation
shows recall below target.
```

### 4. Vector Store

```markdown
- Database: pgvector
- Index type: HNSW
- Hosting: the existing PostgreSQL (self-hosted)

Reason: PostgreSQL is already operated and backed up, and the skill's comparison
places pgvector at small to medium scale, which 100 documents are. HNSW
over IVF because IVF lists are trained on existing data and this table starts
empty.
```

```sql
CREATE TABLE doc_chunks (
    id BIGSERIAL PRIMARY KEY,
    source_file TEXT NOT NULL,
    heading_path TEXT NOT NULL,
    doc_type TEXT NOT NULL,
    content TEXT NOT NULL,
    embedding vector(1536) NOT NULL,
    source_updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX ON doc_chunks USING hnsw (embedding vector_cosine_ops);
```

Re-ingesting a file deletes its rows by `source_file` and inserts the new
chunks, so a deleted section never keeps answering.

### 5. Retrieval Strategy

```markdown
- Search type: MMR, so five chunks from one long guide do not crowd out the API spec
- Top K: 5
- Reranking: No, until the evaluation shows precision below target
- Filtering: optional doc_type filter (API only, onboarding only)
```

### 6. Generation

```markdown
- Model: Claude, or the model the team already has access to
- Temperature: 0, factual answers
- Context window: 5 chunks of about 1000 characters leave ample room
- Fallback: when retrieval returns nothing relevant, answer "I cannot find
  this in the documentation" and list the closest sources; never answer
  from the model's own knowledge

System prompt: answer only from the provided chunks, cite the source file
and heading for every claim, and say so when the chunks do not answer.
```

### Evaluation Plan

```markdown
- Test set: 30 real questions collected from designers, each with the source
  section that answers it, written by the doc owners
- Retrieval: Recall@5 and MRR on that set, the numbers that decide the embedding and retrieval choices
- Generation: faithfulness (every claim is in a cited chunk) and relevance,
  reviewed by hand on the same 30 questions
- Targets are set by the team before the first run and kept with the test set,
  so a later change to chunking or the model is judged against the same bar
```

## Key Points

- The Design Checklist is filled section by section, and each choice states its
  reason and the alternative it rejected
- Only the user's own figures appear as facts; token counts are estimates with
  the arithmetic shown, and prices are checked against the provider
- OpenAPI is chunked by operation, Markdown by heading, because the unit of
  retrieval should be the unit a reader asks about
- The fallback refuses to answer outside the documentation, which is what makes
  "answers with sources" true
- Reranking and a larger embedding model are deferred, not rejected: the
  evaluation set decides whether they are needed
