import type { VectorStore, SourceInfo } from "../db/vector-store.js";

export interface ListSourcesOutput {
  readonly sources: ReadonlyArray<SourceInfo>;
  readonly stats: {
    readonly totalSources: number;
    readonly totalChunks: number;
  };
}

export class ListSourcesTool {
  private readonly store: VectorStore;

  private constructor(store: VectorStore) {
    this.store = store;
  }

  static create(store: VectorStore): ListSourcesTool {
    return new ListSourcesTool(store);
  }

  execute(): ListSourcesOutput {
    const sources = this.store.listSources();
    const stats = this.store.getStats();

    return {
      sources,
      stats: {
        totalSources: stats.totalSources,
        totalChunks: stats.totalChunks,
      },
    };
  }

  static readonly schema = {
    name: "list_knowledge_sources",
    description: `List all documents in the AI/Architecture knowledge base.

Returns information about each indexed document including:
- Document name
- Number of pages
- Number of indexed chunks
- Main topics covered

Use this tool to discover what knowledge is available before searching.`,
    inputSchema: {
      type: "object" as const,
      properties: {},
      required: [],
    },
  };
}
