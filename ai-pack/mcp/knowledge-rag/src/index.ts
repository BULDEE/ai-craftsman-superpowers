#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

import { VectorStore } from "./db/vector-store.js";
import { OpenAIEmbeddingProvider } from "./embeddings/provider.js";
import { SearchKnowledgeTool } from "./tools/search-knowledge.js";
import { ListSourcesTool } from "./tools/list-sources.js";

async function main(): Promise<void> {
  const server = new Server(
    {
      name: "knowledge-rag",
      version: "1.0.0",
    },
    {
      capabilities: {
        tools: {},
      },
    }
  );

  const cwd = process.cwd();
  const store = VectorStore.create(cwd);
  const location = store.getLocation();

  // Log which knowledge base is being used (visible in debug logs)
  console.error(`[knowledge-rag] Using ${location.type} knowledge base`);
  console.error(`[knowledge-rag] DB: ${location.dbPath}`);

  const embeddings = OpenAIEmbeddingProvider.create();
  const searchTool = SearchKnowledgeTool.create(store, embeddings);
  const listTool = ListSourcesTool.create(store);

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: [SearchKnowledgeTool.schema, ListSourcesTool.schema],
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args } = request.params;

    try {
      switch (name) {
        case "search_knowledge": {
          const input = args as {
            query: string;
            top_k?: number;
            sources?: string[];
          };
          const result = await searchTool.execute(input);
          return {
            content: [
              {
                type: "text",
                text: formatSearchResults(result),
              },
            ],
          };
        }

        case "list_knowledge_sources": {
          const result = listTool.execute();
          return {
            content: [
              {
                type: "text",
                text: formatSourceList(result),
              },
            ],
          };
        }

        default:
          throw new Error(`Unknown tool: ${name}`);
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return {
        content: [
          {
            type: "text",
            text: `Error: ${message}`,
          },
        ],
        isError: true,
      };
    }
  });

  const transport = new StdioServerTransport();
  await server.connect(transport);

  process.on("SIGINT", () => {
    store.close();
    process.exit(0);
  });
}

function formatSearchResults(result: {
  query: string;
  results: ReadonlyArray<{
    content: string;
    source: string;
    page: number;
    relevance: number;
  }>;
  total: number;
}): string {
  if (result.total === 0) {
    return `No results found for query: "${result.query}"`;
  }

  const lines: string[] = [
    `## Knowledge Base Search Results`,
    `**Query:** ${result.query}`,
    `**Found:** ${result.total} relevant chunks`,
    "",
  ];

  result.results.forEach((r, i) => {
    lines.push(`### Result ${i + 1} (${Math.round(r.relevance * 100)}% match)`);
    lines.push(`**Source:** ${r.source} (page ${r.page})`);
    lines.push("");
    lines.push(r.content);
    lines.push("");
    lines.push("---");
    lines.push("");
  });

  return lines.join("\n");
}

function formatSourceList(result: {
  sources: ReadonlyArray<{
    name: string;
    pages: number;
    chunks: number;
    topics: string[];
  }>;
  stats: { totalSources: number; totalChunks: number };
}): string {
  const lines: string[] = [
    `## Knowledge Base Sources`,
    `**Total:** ${result.stats.totalSources} documents, ${result.stats.totalChunks} chunks`,
    "",
    "| Document | Pages | Chunks | Topics |",
    "|----------|-------|--------|--------|",
  ];

  result.sources.forEach((s) => {
    lines.push(
      `| ${s.name} | ${s.pages} | ${s.chunks} | ${s.topics.join(", ")} |`
    );
  });

  return lines.join("\n");
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
