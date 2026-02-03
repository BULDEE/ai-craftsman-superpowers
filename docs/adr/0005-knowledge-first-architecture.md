# ADR-0005: Knowledge-First Architecture

## Status

Accepted

## Date

2025-02-03

## Context

AI coding assistants typically suffer from:

1. **Hallucination**: Generating plausible but incorrect patterns
2. **Inconsistency**: Different answers for same questions
3. **Context loss**: Forgetting project conventions mid-session
4. **Generic advice**: Not tailored to specific stack/patterns

Question: How do we make Claude Code consistently apply senior-level expertise?

## Decision

We adopted a **Knowledge-First Architecture** where curated knowledge bases inform every interaction.

```
┌────────────────────────────────────────────────────────────────┐
│                    KNOWLEDGE LAYERS                             │
├────────────────────────────────────────────────────────────────┤
│  Layer 1: CLAUDE.md          → Project-specific rules          │
│  Layer 2: Pack Knowledge     → Domain patterns (Symfony, React)│
│  Layer 3: Core Knowledge     → Universal principles (SOLID)    │
│  Layer 4: RAG Knowledge Base → Indexed expert content          │
└────────────────────────────────────────────────────────────────┘
                              │
                              ↓
                    ┌─────────────────┐
                    │  Claude Code    │
                    │  + Skills       │
                    │  + Agents       │
                    └─────────────────┘
```

### Knowledge Types

| Type | Location | Purpose |
|------|----------|---------|
| Canonical | `knowledge/canonical/` | Golden examples to copy |
| Anti-patterns | `knowledge/anti-patterns/` | What NOT to do |
| Principles | `knowledge/principles.md` | SOLID, DRY, YAGNI |
| Patterns | `knowledge/patterns.md` | Design patterns reference |
| RAG Index | `mcp/knowledge-rag/` | Searchable expert content |

## Consequences

### Positive

- **Consistency**: Same patterns applied every time
- **Grounding**: Answers based on curated knowledge, not training data
- **Updatable**: Knowledge evolves without model retraining
- **Auditable**: Can trace advice to source documents
- **Transferable**: Team shares same knowledge base

### Negative

- **Maintenance**: Knowledge must be kept current
- **Curation effort**: Someone must curate quality content
- **Storage**: RAG index adds ~3MB per corpus

### Neutral

- Skills reference knowledge (coupling is intentional)
- Knowledge is stack-specific (separate packs)

## Knowledge Hierarchy

When conflicts arise, resolution order:

```
1. Explicit user instruction (highest priority)
2. Project CLAUDE.md
3. Global ~/.claude/CLAUDE.md
4. Pack knowledge (symfony-pack, react-pack)
5. Core knowledge
6. RAG search results (lowest priority)
```

## RAG Integration

The `knowledge-rag` MCP server provides semantic search over expert content:

```typescript
// Skill can query knowledge base
const results = await searchKnowledge({
  query: "Event sourcing vs event notification",
  top_k: 3
});
// Returns relevant chunks from indexed PDFs
```

This allows skills to:
- Cite sources for recommendations
- Provide deeper explanations on demand
- Access up-to-date patterns not in training data

## Alternatives Considered

### Alternative 1: Rely on Model Training Data

Trust Claude's training to provide good patterns.

**Rejected because:**
- Training data is outdated (cutoff)
- Inconsistent quality across domains
- No project-specific customization
- Can't audit source of advice

### Alternative 2: Fine-tuned Model

Train custom model on our patterns.

**Rejected because:**
- Expensive and slow to update
- Requires ML expertise
- Vendor lock-in
- Can't easily A/B test changes

### Alternative 3: Prompt-Only (No External Knowledge)

Put everything in prompts and CLAUDE.md.

**Rejected because:**
- Context window limits
- No semantic search
- All knowledge always loaded (wasteful)
- Can't scale to large corpora

## Knowledge Curation Process

1. **Identify**: Find authoritative source (book, article, expert)
2. **Extract**: Pull key patterns and principles
3. **Structure**: Format as markdown with examples
4. **Validate**: Test with real coding tasks
5. **Index**: Add to RAG if searchable access needed
6. **Maintain**: Review quarterly for updates

## References

- [RAG: Retrieval-Augmented Generation](https://arxiv.org/abs/2005.11401)
- [Knowledge Graphs for LLMs](https://www.microsoft.com/en-us/research/publication/knowledge-graphs-llms/)
- [Domain-Driven Design Reference](https://www.domainlanguage.com/ddd/reference/)
