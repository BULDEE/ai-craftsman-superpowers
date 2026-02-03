import Database from "better-sqlite3";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

export interface Chunk {
  readonly id: number;
  readonly content: string;
  readonly source: string;
  readonly page: number;
  readonly chunkIndex: number;
}

export interface SearchResult extends Chunk {
  readonly distance: number;
  readonly relevance: number;
}

export interface SourceInfo {
  readonly name: string;
  readonly pages: number;
  readonly chunks: number;
  readonly topics: string[];
}

interface ChunkWithEmbedding extends Chunk {
  readonly embedding: number[];
}

export class VectorStore {
  private readonly db: Database.Database;
  private readonly dimensions: number;
  private embeddingsCache: Map<number, number[]> | null = null;

  private constructor(db: Database.Database, dimensions: number) {
    this.db = db;
    this.dimensions = dimensions;
  }

  static create(dbPath?: string, dimensions: number = 768): VectorStore {
    const path = dbPath ?? join(__dirname, "../../data/knowledge.db");
    const db = new Database(path);
    db.pragma("journal_mode = WAL");
    return new VectorStore(db, dimensions);
  }

  initialize(): void {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS chunks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        source TEXT NOT NULL,
        page INTEGER NOT NULL,
        chunk_index INTEGER NOT NULL,
        embedding BLOB NOT NULL,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      );

      CREATE INDEX IF NOT EXISTS idx_chunks_source ON chunks(source);

      CREATE TABLE IF NOT EXISTS sources (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        path TEXT NOT NULL,
        pages INTEGER NOT NULL,
        indexed_at TEXT DEFAULT CURRENT_TIMESTAMP
      );
    `);
  }

  insertChunk(
    content: string,
    source: string,
    page: number,
    chunkIndex: number,
    embedding: number[]
  ): number {
    const stmt = this.db.prepare(`
      INSERT INTO chunks (content, source, page, chunk_index, embedding)
      VALUES (?, ?, ?, ?, ?)
    `);

    const embeddingBuffer = Buffer.from(new Float32Array(embedding).buffer);
    const result = stmt.run(content, source, page, chunkIndex, embeddingBuffer);

    this.embeddingsCache = null;

    return result.lastInsertRowid as number;
  }

  insertSource(name: string, path: string, pages: number): void {
    const stmt = this.db.prepare(`
      INSERT OR REPLACE INTO sources (name, path, pages, indexed_at)
      VALUES (?, ?, ?, CURRENT_TIMESTAMP)
    `);
    stmt.run(name, path, pages);
  }

  search(queryEmbedding: number[], topK: number = 5, sources?: string[]): SearchResult[] {
    this.loadEmbeddingsCache();

    const allChunks = this.getAllChunks(sources);

    const scored = allChunks.map((chunk) => {
      const embedding = this.embeddingsCache!.get(chunk.id);
      if (!embedding) {
        return { ...chunk, distance: Infinity, relevance: 0 };
      }

      const distance = this.cosineDistance(queryEmbedding, embedding);
      return {
        ...chunk,
        distance,
        relevance: 1 - distance,
      };
    });

    scored.sort((a, b) => a.distance - b.distance);

    return scored.slice(0, topK);
  }

  listSources(): SourceInfo[] {
    const stmt = this.db.prepare(`
      SELECT
        s.name,
        s.pages,
        COUNT(c.id) as chunks
      FROM sources s
      LEFT JOIN chunks c ON c.source = s.name
      GROUP BY s.name
      ORDER BY s.name
    `);

    const rows = stmt.all() as Array<{ name: string; pages: number; chunks: number }>;

    return rows.map((row) => ({
      ...row,
      topics: this.extractTopics(row.name),
    }));
  }

  getStats(): { totalChunks: number; totalSources: number } {
    const chunksStmt = this.db.prepare("SELECT COUNT(*) as count FROM chunks");
    const sourcesStmt = this.db.prepare("SELECT COUNT(*) as count FROM sources");

    const chunks = (chunksStmt.get() as { count: number }).count;
    const sources = (sourcesStmt.get() as { count: number }).count;

    return { totalChunks: chunks, totalSources: sources };
  }

  clear(): void {
    this.db.exec(`
      DELETE FROM chunks;
      DELETE FROM sources;
    `);
    this.embeddingsCache = null;
  }

  close(): void {
    this.db.close();
  }

  private loadEmbeddingsCache(): void {
    if (this.embeddingsCache !== null) return;

    this.embeddingsCache = new Map();

    const stmt = this.db.prepare("SELECT id, embedding FROM chunks");
    const rows = stmt.all() as Array<{ id: number; embedding: Buffer }>;

    for (const row of rows) {
      const floatArray = new Float32Array(
        row.embedding.buffer,
        row.embedding.byteOffset,
        row.embedding.length / 4
      );
      this.embeddingsCache.set(row.id, Array.from(floatArray));
    }
  }

  private getAllChunks(sources?: string[]): Chunk[] {
    let query = `
      SELECT id, content, source, page, chunk_index as chunkIndex
      FROM chunks
    `;

    const params: string[] = [];

    if (sources && sources.length > 0) {
      const placeholders = sources.map(() => "?").join(",");
      query += ` WHERE source IN (${placeholders})`;
      params.push(...sources);
    }

    const stmt = this.db.prepare(query);
    return stmt.all(...params) as Chunk[];
  }

  private cosineDistance(a: number[], b: number[]): number {
    let dotProduct = 0;
    let normA = 0;
    let normB = 0;

    for (let i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    const magnitude = Math.sqrt(normA) * Math.sqrt(normB);
    if (magnitude === 0) return 1;

    const similarity = dotProduct / magnitude;
    return 1 - similarity;
  }

  private extractTopics(filename: string): string[] {
    const topics: string[] = [];
    const lower = filename.toLowerCase();

    if (lower.includes("rag") || lower.includes("retrieval")) topics.push("RAG");
    if (lower.includes("mlops") || lower.includes("ml operations")) topics.push("MLOps");
    if (lower.includes("vector") || lower.includes("embedding")) topics.push("Vector DB");
    if (lower.includes("microservice")) topics.push("Microservices");
    if (lower.includes("cqrs") || lower.includes("command")) topics.push("CQRS");
    if (lower.includes("event")) topics.push("Event-Driven");
    if (lower.includes("solid")) topics.push("SOLID");
    if (lower.includes("design pattern")) topics.push("Design Patterns");
    if (lower.includes("api") || lower.includes("rest") || lower.includes("graphql")) topics.push("API");
    if (lower.includes("auth")) topics.push("Authentication");
    if (lower.includes("database") || lower.includes("sql")) topics.push("Database");
    if (lower.includes("cache") || lower.includes("cdn")) topics.push("Caching");
    if (lower.includes("ai") || lower.includes("llm")) topics.push("AI/LLM");
    if (lower.includes("agent") || lower.includes("manus")) topics.push("Agents");

    return topics.length > 0 ? topics : ["General"];
  }
}
