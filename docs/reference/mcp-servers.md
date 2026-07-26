# MCP Servers

The plugin ships **no MCP server** since v4.0.0 ([ADR-0024](../adr/0024-okf-knowledge-bundle.md)).

The former `knowledge-rag` server (Ollama embeddings over local documents) was removed: the plugin's knowledge is a curated, git-versioned [OKF bundle](https://github.com/GoogleCloudPlatform/knowledge-catalog) with a deterministic rule-to-concept lookup, which needs no embedding pipeline, no local model runtime, and no background process. Your own memory tools (Obsidian vaults, claude-mem, or any MCP-connected knowledge source) integrate with Claude Code directly; the plugin consumes them rather than duplicating them.
