export interface EmbeddingProvider {
  embed(text: string): Promise<number[]>;
  embedBatch(texts: string[]): Promise<number[][]>;
  readonly dimensions: number;
  readonly baseUrl: string;
}

interface OllamaEmbeddingResponse {
  embedding: number[];
}

const MODEL_DIMENSIONS: Record<string, number> = {
  "nomic-embed-text": 768,
  "mxbai-embed-large": 1024,
  "all-minilm": 384,
  "snowflake-arctic-embed": 1024,
};

export class OllamaEmbeddingProvider implements EmbeddingProvider {
  readonly baseUrl: string;
  private readonly model: string;
  readonly dimensions: number;

  private constructor(baseUrl: string, model: string, dimensions: number) {
    this.baseUrl = baseUrl;
    this.model = model;
    this.dimensions = dimensions;
  }

  static create(
    model?: string,
    baseUrl?: string
  ): OllamaEmbeddingProvider {
    const resolvedModel = model ?? process.env.OLLAMA_EMBED_MODEL ?? "nomic-embed-text";
    const resolvedBaseUrl = baseUrl ?? process.env.OLLAMA_BASE_URL ?? "http://localhost:11434";
    const dimensions = MODEL_DIMENSIONS[resolvedModel] ?? 768;

    return new OllamaEmbeddingProvider(resolvedBaseUrl, resolvedModel, dimensions);
  }

  async embed(text: string): Promise<number[]> {
    const response = await fetch(`${this.baseUrl}/api/embeddings`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: this.model,
        prompt: text,
      }),
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Ollama embedding failed: ${error}`);
    }

    const data = (await response.json()) as OllamaEmbeddingResponse;
    return data.embedding;
  }

  async embedBatch(texts: string[]): Promise<number[][]> {
    const results = await Promise.all(
      texts.map((text) => this.embed(text))
    );
    return results;
  }
}
