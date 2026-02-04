# ADR-0006: Project-Specific Knowledge Base

## Status

Accepted

## Date

2026-02-04

## Context

The Knowledge RAG MCP server initially supported only a global knowledge base stored in `ai-pack/knowledge/`. This created limitations:

1. **No project isolation** - All projects shared the same knowledge base
2. **Irrelevant results** - Searching returned content from unrelated domains
3. **No customization** - Users couldn't add project-specific documentation
4. **Onboarding friction** - New team members couldn't benefit from project context

Users needed the ability to maintain project-specific knowledge that:
- Lives within the project repository
- Can be version-controlled with the project
- Is automatically detected without configuration
- Falls back to global knowledge when not present

## Decision

Implement automatic detection of project-specific knowledge with the following convention:

```
project-root/
└── .claude/
    └── ai-craftsman-superpowers/
        └── knowledge/
            ├── docs.pdf
            ├── specs.md
            └── .index/
                └── knowledge.db
```

### Detection Priority

1. **Project** - Check `{cwd}/.claude/ai-craftsman-superpowers/knowledge/`
2. **Global** - Fall back to `ai-pack/knowledge/`

### Key Design Decisions

#### Folder naming: `ai-craftsman-superpowers` over `craftsman`

Using the full plugin name provides:
- Clear identification of which plugin uses the folder
- No conflicts with other plugins
- Consistency with marketplace naming

#### Index location: `.index/` subdirectory

Storing the database in `.index/` subdirectory:
- Keeps generated files separate from source documents
- Easy to gitignore (`.claude/ai-craftsman-superpowers/knowledge/.index/`)
- Allows documents to be committed while excluding the database

#### Auto-detection over configuration

Using convention over configuration:
- Zero setup required for users
- Works immediately when folder is created
- No environment variables or config files needed

## Consequences

### Positive

- **Project isolation** - Each project has its own knowledge context
- **Team collaboration** - Knowledge can be committed and shared
- **Relevant results** - Searches return project-specific content
- **Graceful fallback** - Global knowledge still available when no project knowledge exists

### Negative

- **Indexing required per project** - Each project needs its own indexing run
- **Storage duplication** - Common knowledge may be indexed multiple times
- **Discovery** - Users need to learn the folder convention

### Neutral

- **No merge** - Project and global knowledge are not combined (design choice for clarity)

## Alternatives Considered

### Environment variable for DB path

```bash
KNOWLEDGE_DB_PATH=/path/to/custom.db
```

Rejected: Requires manual configuration, not portable, doesn't integrate with project structure.

### Merge multiple knowledge sources

Combine project + global results in searches.

Rejected: Added complexity, potential for confusion about result sources, harder to debug relevance issues.

### Configuration file

```yaml
# .claude/knowledge.yaml
sources:
  - ./docs
  - ../shared-knowledge
```

Rejected: Over-engineering for the common case. The convention-based approach covers 90% of use cases.

## Related

- [ADR-0002: Ollama over OpenAI](./0002-ollama-over-openai.md)
- [ADR-0003: SQLite over pgvector](./0003-sqlite-over-pgvector.md)
- [ADR-0005: Knowledge-First Architecture](./0005-knowledge-first-architecture.md)
