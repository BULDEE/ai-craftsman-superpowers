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

**Phase 2 - The decision before the components:**

The first question is not which vector database. It is **whether to embed at
all**. A vector store is a read model, and like any read model it needs a
measured reason to exist - the same rule the persistence doctrine applies to a
denormalised SQL table. Skipping this question is how teams end up maintaining
an index lifecycle for a corpus that fits in a directory listing.

```
IS AN EMBEDDING INDEX JUSTIFIED?

Corpus is curated, stable, and named by humans
  → Deterministic lookup. Match on frontmatter/tags, let the model read
    the file. No index, no rebuild, no drift.
  → This is what the plugin does with its own knowledge/ bundle.

Queries are keyword-shaped over a mid-size corpus
  → Lexical index (SQLite FTS5, ripgrep). Cheap, exact, debuggable.

Corpus is large, heterogeneous, or churns; queries are fuzzy and
paraphrased; users cannot name what they are looking for
  → Embeddings earn their cost. Now pick the components.
```

Only the third branch reaches component selection:

```
COMPONENT DECISIONS (third branch only):

Vector DB: start with the store you already run (SQLite, pgvector)
REASON: One less service; migrate when measurement says so
TRADE-OFF: Re-platforming later costs a reindex

Embedding Model: local (Ollama) vs hosted
REASON: Local keeps private data in-house and costs nothing per query
TRADE-OFF: A local model runtime is a dependency every install must carry

Chunking: recursive, 512 tokens, 100 overlap
REASON: Preserves context across boundaries
TRADE-OFF: More chunks, more storage, more near-duplicate hits

Retrieval: vector + reranking
REASON: Reranking recovers the precision chunking loses
TRADE-OFF: Additional latency per query
```

### Retrieval tiers in practice

Real setups usually combine sources rather than picking one, because each
answers a different kind of question:

| Tier | Holds | Answers |
|---|---|---|
| Curated bundle (this plugin's `knowledge/`) | Doctrine you enforce, versioned in git, reviewed on write | "Which rule explains this block, and why does it exist?" |
| Team vault (Obsidian or similar, MCP-connected) | Organisational context, decisions, meeting output | "What did we decide about this, and when?" |
| Session memory (claude-mem or similar) | What happened in prior sessions | "What was I doing, and what did I already try?" |

The plugin consumes these as-is and never re-indexes them: its bundle is plain
Markdown on disk, so the same tools can read it too. See
[ADR-0024](../adr/0024-okf-knowledge-bundle.md) for the reasoning, including
why the plugin removed its own vector layer.

> Beware the "format X replaces RAG" framing that circulates whenever a new
> knowledge format ships. The Open Knowledge Format specification says nothing
> about vectors. Retrieval architecture is decided by your corpus and your
> queries, not by a format announcement.

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
> /craftsman:test

Test the CodeReviewAgent.
Include:
- Perceive phase with mock PR
- Plan phase tool selection
- Perform phase with mock tools
```

---

## Lesson 4: The Knowledge Bundle (OKF)

The plugin's methodology knowledge lives in `knowledge/` as an [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog) bundle: Markdown concepts with YAML frontmatter (`type`, `tags`, and the custom `rules` field that links enforcement rules to the concept explaining them).

Deterministic lookup, no embeddings:

```bash
# Which concept explains a rule the gate just flagged?
bash ~/.claude/craftsman-knowledge.sh by-rule LAYER004

# Everything about persistence
bash ~/.claude/craftsman-knowledge.sh by-tag persistence
```

To extend it, add a Markdown file with frontmatter under `knowledge/` (or your project's own bundle) and it becomes routable immediately: no re-indexing step exists because there is no index. Lesson 1 (RAG pipeline design) still applies when YOU build retrieval products; the plugin itself does not need one for 35 curated files.

## Lesson 5: Extending the Plugin

The plugin ships no MCP server as of v4.0.0 ([ADR-0024](../adr/0024-okf-knowledge-bundle.md)),
so there is no server to extend and no build step to run. Extension happens
through the plugin's own surfaces instead:

| You want to add | Where it goes | Picked up |
|---|---|---|
| A new workflow | `skills/<name>/SKILL.md` | `/reload-plugins` |
| A new specialist | `agents/<name>.md` | `/reload-plugins` |
| Language rules | `packs/<pack>/hooks/*-validator.sh` | Next hook run |
| Reference material | `knowledge/<topic>.md` with frontmatter | Immediately, no indexing |
| A whole language | A new pack - see [Creating Packs](../creating-packs.md) | Pack loader |

Each surface is validated in CI, so a malformed skill or agent fails the build
rather than silently not loading.


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
