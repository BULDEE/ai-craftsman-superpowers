---
description: "Manage the AI/Architecture knowledge base — add, sync, list, status, remove documents. Use when needing to update indexed sources or check knowledge base health."
effort: quick
---

# /craftsman:knowledge — Knowledge Base Management

Manage the knowledge base used by the `search_knowledge` MCP tool.

## Usage

| Command | Description |
|---------|-------------|
| `/craftsman:knowledge add <path>` | Copy a file into the KB and index it |
| `/craftsman:knowledge sync` | Incremental sync — index new/modified, remove orphans |
| `/craftsman:knowledge list` | List all indexed sources with stats |
| `/craftsman:knowledge status` | Healthcheck — Ollama, DB, pending files |
| `/craftsman:knowledge remove <source>` | Remove a source from the DB |

## Implementation

The knowledge base lives at `~/.claude/ai-craftsman-superpowers/knowledge/`. The `.index/knowledge.db` SQLite database stores embeddings.

### For all subcommands

1. Bootstrap dependencies if needed:

```bash
MCP_DIR="${CLAUDE_PLUGIN_ROOT}/packs/ai-ml/mcp/knowledge-rag"
if [[ ! -d "$MCP_DIR/node_modules" ]]; then
  cd "$MCP_DIR" && npm install --silent && cd -
fi
```

2. Run the CLI with the appropriate mode using the Bash tool:

```bash
cd "${CLAUDE_PLUGIN_ROOT}/packs/ai-ml/mcp/knowledge-rag" && npx tsx scripts/cli.ts <mode> [args]
```

### `add <path>`

1. Verify the file path exists (resolve relative paths from user's working directory)
2. Run: `npx tsx scripts/cli.ts add "<absolute-path>"`
3. Report: "Added: filename.pdf (N chunks, Xs)"

### `sync`

1. Run: `npx tsx scripts/cli.ts sync`
2. Parse the JSON output and display a summary:
   - Added: N files (M chunks)
   - Updated: N files (re-indexed M chunks)
   - Removed: N orphans
   - Skipped: N files (unchanged)
   - Duration: Xs

### `list`

1. Run: `npx tsx scripts/cli.ts list`
2. Format the JSON output as a readable table showing source name, chunks count, and topics

### `status`

1. Run: `npx tsx scripts/cli.ts status`
2. Display formatted status:
   - Location, type (global/project)
   - Ollama running or not
   - DB stats (chunks, sources, size)
   - Pending files (new/modified) with names
   - Orphan sources (in DB but file deleted)

### `remove <source>`

1. Run: `npx tsx scripts/cli.ts remove "<source-name>"`
2. Report: "Removed: filename.pdf (N chunks deleted)"
3. Note: this removes from DB only. The file remains in the knowledge directory unless the user deletes it manually.
