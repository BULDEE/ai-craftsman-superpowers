import { readdir, readFile, copyFile } from "node:fs/promises";
import { join, extname, basename } from "node:path";
import { existsSync } from "node:fs";
import pdf from "pdf-parse";

import { VectorStore } from "../db/vector-store.js";
import { OllamaEmbeddingProvider } from "../embeddings/provider.js";
import { hashFile, type FileHash } from "./hasher.js";

const CHUNK_SIZE = 500;
const CHUNK_OVERLAP = 100;
const SUPPORTED_EXTENSIONS = new Set([".pdf", ".md", ".txt"]);

interface ChunkResult {
  readonly content: string;
  readonly page: number;
  readonly index: number;
}

export interface SyncReport {
  readonly added: string[];
  readonly updated: string[];
  readonly removed: string[];
  readonly skipped: string[];
  readonly errors: Array<{ file: string; error: string }>;
  readonly durationMs: number;
}

export interface StatusReport {
  readonly totalSources: number;
  readonly totalChunks: number;
  readonly dbSizeBytes: number;
  readonly pending: Array<{ file: string; reason: "new" | "modified" }>;
  readonly orphans: string[];
  readonly ollamaRunning: boolean;
  readonly lastSync: string | null;
}

async function checkOllamaRunning(): Promise<boolean> {
  try {
    const response = await fetch("http://localhost:11434/api/tags", {
      signal: AbortSignal.timeout(2000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

function listSupportedFiles(dir: string, files: string[]): string[] {
  return files.filter((f) => SUPPORTED_EXTENSIONS.has(extname(f).toLowerCase()));
}

async function parseFile(filePath: string): Promise<{ text: string; pageCount: number }> {
  const ext = extname(filePath).toLowerCase();

  if (ext === ".pdf") {
    const buffer = await readFile(filePath);
    const data = await pdf(buffer);
    return { text: data.text, pageCount: data.numpages };
  }

  const text = await readFile(filePath, "utf-8");
  return { text, pageCount: 1 };
}

function chunkText(text: string, chunkSize: number, overlap: number): ChunkResult[] {
  const chunks: ChunkResult[] = [];
  const cleaned = text
    .replace(/\r\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .replace(/[ \t]+/g, " ")
    .trim();

  const paragraphs = cleaned.split(/\n\n+/);
  let currentChunk = "";
  let currentPage = 1;
  let chunkIndex = 0;

  for (const paragraph of paragraphs) {
    const trimmed = paragraph.trim();
    if (!trimmed) continue;

    if (trimmed.match(/^page\s*\d+/i)) {
      const match = trimmed.match(/\d+/);
      if (match) currentPage = parseInt(match[0], 10);
      continue;
    }

    if (currentChunk.length + trimmed.length + 1 <= chunkSize) {
      currentChunk += (currentChunk ? "\n\n" : "") + trimmed;
    } else {
      if (currentChunk) {
        chunks.push({ content: currentChunk.trim(), page: currentPage, index: chunkIndex++ });
      }

      if (trimmed.length > chunkSize) {
        const words = trimmed.split(/\s+/);
        currentChunk = "";
        for (const word of words) {
          if (currentChunk.length + word.length + 1 <= chunkSize) {
            currentChunk += (currentChunk ? " " : "") + word;
          } else {
            if (currentChunk) {
              chunks.push({ content: currentChunk.trim(), page: currentPage, index: chunkIndex++ });
            }
            const overlapStart = Math.max(0, currentChunk.length - overlap);
            const overlapText = currentChunk.slice(overlapStart);
            currentChunk = overlapText + (overlapText ? " " : "") + word;
          }
        }
      } else {
        const overlapStart = Math.max(0, currentChunk.length - overlap);
        const overlapText = currentChunk.slice(overlapStart);
        currentChunk = overlapText + (overlapText ? "\n\n" : "") + trimmed;
      }
    }
  }

  if (currentChunk.trim()) {
    chunks.push({ content: currentChunk.trim(), page: currentPage, index: chunkIndex });
  }

  return chunks.filter((c) => c.content.length >= 50);
}

async function indexFile(
  filePath: string,
  fileName: string,
  fileHash: FileHash,
  store: VectorStore,
  embeddings: OllamaEmbeddingProvider
): Promise<number> {
  const { text, pageCount } = await parseFile(filePath);
  const chunks = chunkText(text, CHUNK_SIZE, CHUNK_OVERLAP);
  const chunkTexts = chunks.map((c) => c.content);
  const chunkEmbeddings = await embeddings.embedBatch(chunkTexts);

  for (let i = 0; i < chunks.length; i++) {
    store.insertChunk(chunks[i].content, fileName, chunks[i].page, chunks[i].index, chunkEmbeddings[i]);
  }

  store.insertSource(fileName, filePath, pageCount, fileHash.hash, fileHash.size);
  return chunks.length;
}

export async function sync(store: VectorStore): Promise<SyncReport> {
  const start = Date.now();
  const location = store.getLocation();
  const knowledgeDir = location.knowledgeDir;

  const ollamaRunning = await checkOllamaRunning();
  if (!ollamaRunning) {
    throw new Error("Ollama is not running. Start it with: ollama serve");
  }

  const embeddings = OllamaEmbeddingProvider.create();
  const allFiles = await readdir(knowledgeDir);
  const supportedFiles = listSupportedFiles(knowledgeDir, allFiles);
  const existingHashes = store.getAllSourceHashes();

  const added: string[] = [];
  const updated: string[] = [];
  const skipped: string[] = [];
  const errors: Array<{ file: string; error: string }> = [];

  for (const fileName of supportedFiles) {
    const filePath = join(knowledgeDir, fileName);
    try {
      const fileHash = await hashFile(filePath);
      const existing = existingHashes.get(fileName);

      if (existing && existing.hash === fileHash.hash) {
        skipped.push(fileName);
        existingHashes.delete(fileName);
        continue;
      }

      if (existing) {
        store.deleteBySource(fileName);
        await indexFile(filePath, fileName, fileHash, store, embeddings);
        updated.push(fileName);
      } else {
        await indexFile(filePath, fileName, fileHash, store, embeddings);
        added.push(fileName);
      }

      existingHashes.delete(fileName);
      console.error(`[sync] ${existing ? "Updated" : "Added"}: ${fileName}`);
    } catch (err) {
      errors.push({ file: fileName, error: err instanceof Error ? err.message : String(err) });
      console.error(`[sync] Error: ${fileName} — ${err instanceof Error ? err.message : err}`);
    }
  }

  const removed: string[] = [];
  for (const [orphanName] of existingHashes) {
    store.deleteBySource(orphanName);
    removed.push(orphanName);
    console.error(`[sync] Removed orphan: ${orphanName}`);
  }

  return { added, updated, removed, skipped, errors, durationMs: Date.now() - start };
}

export async function addFile(store: VectorStore, sourcePath: string): Promise<{ fileName: string; chunks: number }> {
  const ollamaRunning = await checkOllamaRunning();
  if (!ollamaRunning) {
    throw new Error("Ollama is not running. Start it with: ollama serve");
  }

  if (!existsSync(sourcePath)) {
    throw new Error(`File not found: ${sourcePath}`);
  }

  const ext = extname(sourcePath).toLowerCase();
  if (!SUPPORTED_EXTENSIONS.has(ext)) {
    throw new Error(`Unsupported file type: ${ext}. Supported: .pdf, .md, .txt`);
  }

  const location = store.getLocation();
  const fileName = basename(sourcePath);
  const destPath = join(location.knowledgeDir, fileName);

  if (sourcePath !== destPath) {
    await copyFile(sourcePath, destPath);
  }

  const existing = store.getSourceHash(fileName);
  if (existing) {
    store.deleteBySource(fileName);
  }

  const embeddings = OllamaEmbeddingProvider.create();
  const fileHash = await hashFile(destPath);
  const chunks = await indexFile(destPath, fileName, fileHash, store, embeddings);

  return { fileName, chunks };
}

export async function removeSource(store: VectorStore, sourceName: string): Promise<number> {
  const existingHash = store.getSourceHash(sourceName);
  if (!existingHash) {
    throw new Error(`Source not found in database: ${sourceName}`);
  }

  return store.deleteBySource(sourceName);
}

export async function status(store: VectorStore): Promise<StatusReport> {
  const location = store.getLocation();
  const stats = store.getStats();
  const existingHashes = store.getAllSourceHashes();
  const ollamaRunning = await checkOllamaRunning();

  const allFiles = existsSync(location.knowledgeDir) ? await readdir(location.knowledgeDir) : [];
  const supportedFiles = listSupportedFiles(location.knowledgeDir, allFiles);

  const pending: Array<{ file: string; reason: "new" | "modified" }> = [];
  const filesSeen = new Set<string>();

  for (const fileName of supportedFiles) {
    filesSeen.add(fileName);
    const filePath = join(location.knowledgeDir, fileName);
    const fileHash = await hashFile(filePath);
    const existing = existingHashes.get(fileName);

    if (!existing) {
      pending.push({ file: fileName, reason: "new" });
    } else if (existing.hash !== fileHash.hash) {
      pending.push({ file: fileName, reason: "modified" });
    }
  }

  const orphans: string[] = [];
  for (const [name] of existingHashes) {
    if (!filesSeen.has(name)) {
      orphans.push(name);
    }
  }

  let dbSizeBytes = 0;
  try {
    const { statSync } = await import("node:fs");
    dbSizeBytes = statSync(location.dbPath).size;
  } catch {
    // DB file may not exist yet
  }

  let lastSync: string | null = null;
  try {
    const sources = store.listSources();
    if (sources.length > 0) {
      lastSync = "available";
    }
  } catch {
    // ignore
  }

  return { totalSources: stats.totalSources, totalChunks: stats.totalChunks, dbSizeBytes, pending, orphans, ollamaRunning, lastSync };
}
