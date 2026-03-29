import type { VectorStore, SearchResult } from "../db/vector-store.js";
import type { EmbeddingProvider } from "../embeddings/provider.js";

export interface SearchKnowledgeInput {
  readonly query: string;
  readonly top_k?: number;
  readonly sources?: string[];
}

export interface SearchKnowledgeOutput {
  readonly query: string;
  readonly results: ReadonlyArray<{
    readonly content: string;
    readonly source: string;
    readonly page: number;
    readonly relevance: number;
  }>;
  readonly total: number;
}

export class SearchKnowledgeTool {
  private readonly store: VectorStore;
  private readonly embeddings: EmbeddingProvider;

  private constructor(store: VectorStore, embeddings: EmbeddingProvider) {
    this.store = store;
    this.embeddings = embeddings;
  }

  static create(store: VectorStore, embeddings: EmbeddingProvider): SearchKnowledgeTool {
    return new SearchKnowledgeTool(store, embeddings);
  }

  async execute(input: SearchKnowledgeInput): Promise<SearchKnowledgeOutput> {
    const topK = input.top_k ?? 5;
    const queryEmbedding = await this.embeddings.embed(input.query);
    const results = this.store.search(queryEmbedding, topK, input.sources);

    return {
      query: input.query,
      results: results.map((r) => ({
        content: r.content,
        source: r.source,
        page: r.page,
        relevance: Math.round(r.relevance * 100) / 100,
      })),
      total: results.length,
    };
  }

  static readonly schema = {
    name: "search_knowledge",
    description: `Search the AI/Architecture knowledge base for relevant information.

The knowledge base contains expert content on:
- RAG (Retrieval-Augmented Generation)
- MLOps principles and practices
- Vector databases and embeddings
- Microservices patterns
- CQRS and Event-Driven Architecture
- SOLID principles
- Design patterns
- API design (REST, GraphQL)
- Authentication/Authorization
- Database scaling
- Caching strategies
- AI/LLM engineering

Use this tool when you need authoritative information on these topics.`,
    inputSchema: {
      type: "object" as const,
      properties: {
        query: {
          type: "string",
          description: "Natural language query to search for",
        },
        top_k: {
          type: "number",
          description: "Maximum number of results to return (default: 5, max: 10)",
          minimum: 1,
          maximum: 10,
        },
        sources: {
          type: "array",
          items: { type: "string" },
          description: "Optional: filter results to specific source documents",
        },
      },
      required: ["query"],
    },
  };
}
