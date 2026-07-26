# ADR-0024: Knowledge as an OKF Bundle with Deterministic Lookup

## Status

Accepted - Supersedes [ADR-0002](0002-ollama-over-openai.md) and [ADR-0003](0003-sqlite-over-pgvector.md)

## Date

2026-07-26

## Context

The plugin shipped an optional MCP server (`knowledge-rag`) that embedded local documents via Ollama into a SQLite vector store. Adversarial review (2026-07-26) found:

- The `mcpServers` block sat in the root plugin manifest, so **every installation** spawned the Node server, needed 115 MB of `node_modules`, and depended on `http://localhost:11434` - whether or not the ai-ml pack was active. The plugin reference offers no per-pack scoping for MCP servers.
- The primary author no longer uses it; external memory tools (Obsidian vaults, claude-mem) cover the exploratory-retrieval need better.
- It contradicted our own v4.1 doctrine (`knowledge/persistence/data-modeling-decisions.md`): vector stores are read models chosen for a measured reason; 35 curated Markdown files need none.

Meanwhile Google Cloud published the **Open Knowledge Format** (v0.2, [spec](https://github.com/GoogleCloudPlatform/knowledge-catalog)): knowledge as a git-versioned directory of Markdown concepts with YAML frontmatter (`type` required; `title`, `description`, `tags`, `status` optional; reserved `index.md`). Our `knowledge/` directory already was that pattern, minus the frontmatter and minus any routing: skills referenced knowledge files by hardcoded path.

Verification note: the "OKF replaces RAG" framing circulating in blog posts is **not** in Google's spec or announcement, which never mention vectors. The decision below is our own reasoning, not an appeal to that authority.

## Decision

1. **Remove the RAG layer entirely**: the MCP server, its pack.yml declaration, the root-manifest `mcpServers` block, the Ollama dependency, the `/craftsman:knowledge` management skill, and the healthcheck probes for Ollama.
2. **Formalize `knowledge/` as an OKF v0.2 bundle**: every concept file carries frontmatter with `type`, `title`, `description`, `tags`, plus a custom `rules` field listing the enforcement rules the concept explains. A root `index.md` declares `okf_version: "0.2"`.
3. **Route deterministically**: `knowledge_lookup.py` resolves rule -> concept and tag -> concepts by exact frontmatter match. A quality-gate block can point at the doctrine that explains it. No embeddings, no index to rebuild, no fallback search: 35 curated files do not need one.
4. **External memory stays external**: Obsidian vaults, claude-mem, and other MCP-connected sources are consumed as-is. The plugin's bundle is plain Markdown on disk, so those tools can read it too; the plugin never re-indexes them.

## Consequences

### Positive

- Every installation sheds a Node process, 115 MB of dependencies, and a localhost service dependency.
- Knowledge becomes routable by data instead of hardcoded paths: adding a concept file makes it reachable the moment it declares its rules and tags.
- The bundle is consumable by any OKF-aware or Markdown-aware tool, including the user's own vaults.
- The plugin practices the persistence doctrine it enforces.

### Negative

- Users who had adopted the RAG server lose it (v4.0.0 breaking change; documented in MIGRATION.md). The 3.9.x line retains it.
- Exact-match lookup does not answer fuzzy questions ("how do I structure modules?"); that remains the job of the model reading the bundle, which is what it already did.

### Neutral

- ADR-0002 (Ollama over OpenAI) and ADR-0003 (SQLite over pgvector) were the right calls **within** the RAG premise; this ADR retires the premise itself.
- Security: a knowledge base written by agents is an indirect-prompt-injection surface (known OKF-ecosystem critique). Our learned-instinct skills are exactly that kind of write, and the mandatory human review of ADR-0020 is the mitigation: nothing enters the bundle without an explicit approval.

## Alternatives Considered

### Alternative 1: Keep the server as opt-in

Move the MCP declaration behind an install step. Rejected: keeps 115 MB and a maintenance surface for a feature its own author abandoned, and every future refactor must drag it along.

### Alternative 2: Replace vectors with a lexical index (SQLite FTS5)

Rejected as YAGNI: 35 files fit in a single directory listing; frontmatter match plus the model's own reading covers retrieval without any index lifecycle.

## References

- OKF specification: https://github.com/GoogleCloudPlatform/knowledge-catalog
- Google Cloud announcement (2026-06-12): https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing
- ADR-0020 (human review as injection mitigation), ADR-0019 (established tooling first)
