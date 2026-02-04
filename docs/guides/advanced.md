# Advanced Guide (AI Engineers / MLOps)

This guide is for AI engineers, ML practitioners, and those building intelligent systems. We'll cover RAG pipelines, MLOps practices, and agent design.

## What You'll Learn

- [x] Designing RAG pipelines with /craftsman:rag
- [x] MLOps audit and implementation
- [x] Agent architecture with 3P pattern
- [x] Custom knowledge indexing
- [x] MCP server extension

## Prerequisites

- Completed [Intermediate Guide](./intermediate.md)
- Understanding of embeddings and vector search
- Familiarity with ML workflows

---

## Lesson 1: RAG Pipeline Design

### Understanding RAG

**RAG (Retrieval-Augmented Generation)** solves key LLM limitations:

| Problem | RAG Solution |
|---------|--------------|
| Hallucinations | Ground responses in retrieved facts |
| Outdated knowledge | Query current data sources |
| Private data | Access internal documents |
| Domain expertise | Leverage specialized corpora |

### The 3 Pipelines

```
INGESTION:   Documents → Chunk → Embed → Store
RETRIEVAL:   Query → Embed → Search → Rerank → Top-K
GENERATION:  Query + Context → Prompt → LLM → Response
```

### /craftsman:rag in Action

```
> /craftsman:rag

Build a RAG system for our technical documentation.
- 500 markdown files
- Users ask technical questions
- Need high accuracy
```

**Phase 1 - Requirements:**
```
Claude asks:
- What's the average document length?
- How often is content updated?
- What's the acceptable latency?
- Do you need source citations?
```

**Phase 2 - Architecture Decision:**
```
COMPONENT DECISIONS:

Vector DB: SQLite (in-memory search)
REASON: <500 docs, simplicity
TRADE-OFF: Won't scale past 10K

Embedding Model: nomic-embed-text (Ollama)
REASON: Local, free, good quality
TRADE-OFF: Slightly lower than OpenAI

Chunking: Recursive, 512 tokens, 100 overlap
REASON: Preserves context, good retrieval
TRADE-OFF: More chunks = more storage

Retrieval: Vector + Reranking
REASON: High accuracy needed
TRADE-OFF: Additional latency
```

**Phase 3 - Implementation:**

Generated structure:
```
src/rag/
├── ingestion/
│   ├── loader.py        # Load markdown files
│   ├── chunker.py       # Split into chunks
│   └── embedder.py      # Generate vectors
├── retrieval/
│   ├── searcher.py      # Vector similarity
│   └── reranker.py      # Cross-encoder rerank
├── generation/
│   ├── prompts.py       # Prompt templates
│   └── generator.py     # LLM interaction
└── pipeline.py          # Orchestration
```

### Advanced RAG Patterns

#### Hybrid Search (Vector + Keyword)

```
> /craftsman:rag

Add hybrid search combining vector similarity with BM25.
Some queries need exact keyword matching.
```

#### Multi-Index RAG

```
> /craftsman:rag

Build RAG with separate indexes for:
- Code documentation (technical)
- User guides (non-technical)
- API reference (structured)
```

#### Iterative Retrieval

```
> /craftsman:rag

Implement iterative retrieval for complex questions.
First retrieval informs second query.
```

---

## Lesson 2: MLOps Audit

### The 6 Principles

1. **Automation** - CI/CD for ML
2. **Versioning** - Code, data, models
3. **Experiment Tracking** - Hyperparameters, metrics
4. **Testing** - Unit, integration, model tests
5. **Monitoring** - Drift, performance, alerts
6. **Reproducibility** - Seeds, environment, configs

### /craftsman:mlops Audit

```
> /craftsman:mlops

Audit our recommendation system for production readiness.
```

**Output: MLOps Audit Report**
```
╔══════════════════════════════════════════════════════════════════╗
║                      MLOPS AUDIT REPORT                           ║
╠══════════════════════════════════════════════════════════════════╣
║ 1. AUTOMATION                                                     ║
║    Level: 1 (Pipeline, no CI/CD)                                 ║
║    Status: ⚠                                                     ║
║    Gap: Manual deployment to production                           ║
╠══════════════════════════════════════════════════════════════════╣
║ 2. VERSIONING                                                     ║
║    Code: ✓ Git                                                   ║
║    Data: ✗ No versioning                                         ║
║    Model: ⚠ Manual saves to S3                                   ║
╠══════════════════════════════════════════════════════════════════╣
║ 3. EXPERIMENT TRACKING                                            ║
║    Status: ✗                                                     ║
║    Gap: No tracking tool configured                               ║
╠══════════════════════════════════════════════════════════════════╣
║ OVERALL: 2/6 principles met                                       ║
║ MATURITY: Level 1 (Pipeline)                                      ║
╚══════════════════════════════════════════════════════════════════╝

RECOMMENDATIONS:
1. [CRITICAL] Add data versioning with DVC
2. [HIGH] Implement MLflow for experiment tracking
3. [HIGH] Add model testing before deployment
4. [MEDIUM] Set up monitoring dashboard
```

### Implementing Recommendations

```
> Based on the audit, implement DVC for data versioning.

> Add MLflow experiment tracking to the training script.

> Create a model testing suite with accuracy thresholds.
```

---

## Lesson 3: Agent Design (3P Pattern)

### The 3P Architecture

```
┌──────────┐    ┌──────────┐    ┌──────────┐
│ PERCEIVE │ →  │   PLAN   │ →  │ PERFORM  │
│          │    │          │    │          │
│ • Input  │    │ • Goals  │    │ • Execute│
│ • NLU    │    │ • Tools  │    │ • Results│
│ • Context│    │ • Order  │    │ • State  │
└──────────┘    └──────────┘    └──────────┘
      ↑                               │
      └───────── feedback ────────────┘
```

### /craftsman:agent-design in Action

```
> /craftsman:agent-design

Design a code review agent.
It should:
- Analyze pull requests
- Check for security issues
- Verify test coverage
- Suggest improvements
```

**Phase 1 - Mission Definition:**
```
AGENT: CodeReviewAgent
MISSION: Automatically review PRs for quality and security
ENVIRONMENT: GitHub (via API)
BOUNDARIES: Cannot merge, cannot access secrets
```

**Phase 2 - 3P Architecture:**
```
PERCEIVE:
├── Inputs: PR diff, file contents, commit messages
├── NLU: Understand PR purpose from description
├── Context: Load project rules (CLAUDE.md, ESLint)
└── State: Track review progress

PLAN:
├── Goals: Identify issues → Prioritize → Generate comments
├── Tools: read_file, search_code, check_security, run_tests
├── Strategy: Parallel analysis, sequential reporting
└── Validation: Verify findings before commenting

PERFORM:
├── Execution: Call tools with parameters
├── Results: Collect findings
├── State: Update review status
└── Output: Generate review with verdict
```

**Phase 3 - Tool Registry:**
```yaml
tools:
  - name: read_file
    description: Read file contents from PR
    parameters:
      path: { type: string, required: true }
    returns: { type: string }
    side_effects: none

  - name: check_security
    description: Scan code for security vulnerabilities
    parameters:
      files: { type: array, required: true }
    returns: { type: array, items: Vulnerability }
    side_effects: none

  - name: post_comment
    description: Post review comment on PR
    parameters:
      body: { type: string, required: true }
      line: { type: number }
    returns: { type: object }
    side_effects: external-call
    requires_approval: false
```

### Agent Testing

```
> /test

Test the CodeReviewAgent.
Include:
- Perceive phase with mock PR
- Plan phase tool selection
- Perform phase with mock tools
```

---

## Lesson 4: Custom Knowledge Indexing

### Adding Your Own Documents

The MCP supports two knowledge base modes:

**Option 1: Global Knowledge (shared across all projects)**

```bash
# 1. Add documents to global knowledge directory
mkdir -p ~/.claude/ai-craftsman-superpowers/knowledge
cp ~/new-papers/*.pdf ~/.claude/ai-craftsman-superpowers/knowledge/

# 2. Re-index
cd ai-pack/mcp/knowledge-rag
npm run index:ollama

# Output:
# Mode: GLOBAL knowledge base
# Processing: new-paper.pdf
#   - Pages: 15
#   - Chunks: 42
#   - Done
```

**Option 2: Project-Specific Knowledge (recommended)**

```bash
# 1. Create project knowledge directory
mkdir -p .claude/ai-craftsman-superpowers/knowledge

# 2. Add project-specific documents
cp specs.pdf architecture.md .claude/ai-craftsman-superpowers/knowledge/

# 3. Index from project root
npx tsx /path/to/ai-pack/mcp/knowledge-rag/scripts/index-pdfs.ts

# 4. Add to .gitignore
echo ".claude/ai-craftsman-superpowers/knowledge/.index/" >> .gitignore
```

### Custom Source Directory

```bash
# Index specific directory
npm run index:ollama /path/to/your/documents
```

### Verifying Indexation

```
> List my knowledge sources

# Shows all indexed documents with:
# - Document name
# - Page count
# - Chunk count
# - Topics detected
```

---

## Lesson 5: Extending MCP Server

### Adding New Tools

Edit `ai-pack/mcp/knowledge-rag/src/tools/`:

```typescript
// src/tools/summarize-source.ts
export class SummarizeSourceTool {
  static readonly schema = {
    name: "summarize_source",
    description: "Summarize a specific document from knowledge base",
    inputSchema: {
      type: "object",
      properties: {
        source: { type: "string", description: "Document name" }
      },
      required: ["source"]
    }
  };

  execute(input: { source: string }): SummaryOutput {
    const chunks = this.store.getChunksBySource(input.source);
    return { summary: this.generateSummary(chunks) };
  }
}
```

### Registering Tools

Edit `src/index.ts`:

```typescript
import { SummarizeSourceTool } from "./tools/summarize-source.js";

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    SearchKnowledgeTool.schema,
    ListSourcesTool.schema,
    SummarizeSourceTool.schema  // Add new tool
  ]
}));
```

### Rebuild and Test

```bash
npm run build
# Restart Claude Code
```

---

## Practice Exercises

### Exercise 1: Build a QA RAG

```
> /craftsman:rag

Build a customer support RAG system.
- Index: FAQ documents, support tickets, product docs
- Query: Customer questions
- Output: Answers with source links
```

### Exercise 2: MLOps Pipeline

```
> /craftsman:mlops

Design an MLOps pipeline for a fraud detection model.
Include: data versioning, experiment tracking, A/B testing.
```

### Exercise 3: Custom Agent

```
> /craftsman:agent-design

Design a documentation agent that:
- Monitors code changes
- Updates relevant documentation
- Creates new docs for new features
```

---

## Checklist: Ready for Master?

- [ ] Built a custom RAG pipeline
- [ ] Conducted MLOps audit
- [ ] Designed agent with 3P pattern
- [ ] Extended knowledge base
- [ ] Added custom MCP tools

Continue to: [Master Guide](./master.md)
