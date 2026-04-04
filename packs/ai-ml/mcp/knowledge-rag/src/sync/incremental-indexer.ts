import { readdir, copyFile, stat } from "node:fs/promises";
import { join, extname, basename, resolve } from "node:path";
import { existsSync, statSync } from "node:fs";

import { VectorStore } from "../db/vector-store.js";
import { OllamaEmbeddingProvider } from "../embeddings/provider.js";
import { hashFile, type FileHash } from "./hasher.js";
import { parseFile, chunkText, type ChunkResult, CHUNK_SIZE, CHUNK_OVERLAP, SUPPORTED_EXTENSIONS } from "../parsing/document-parser.js";

export type { ChunkResult };

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

function listSupportedFiles(files: string[]): string[] {
  return files.filter((f) => SUPPORTED_EXTENSIONS.has(extname(f).toLowerCase()));
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

  const ollamaRunning = await OllamaEmbeddingProvider.checkRunning();
  if (!ollamaRunning) {
    throw new Error("Ollama is not running. Start it with: ollama serve");
  }

  const embeddings = OllamaEmbeddingProvider.create();
  const allFiles = await readdir(knowledgeDir);
  const supportedFiles = listSupportedFiles(allFiles);
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
        const tempName = `__reindex__${fileName}`;
        try {
          await indexFile(filePath, tempName, fileHash, store, embeddings);
          store.deleteBySource(fileName);
          store.renameSource(tempName, fileName);
          updated.push(fileName);
        } catch (reindexErr) {
          store.deleteBySource(tempName);
          throw reindexErr;
        }
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
  const ollamaRunning = await OllamaEmbeddingProvider.checkRunning();
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

  if (resolve(sourcePath) !== resolve(destPath)) {
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
  const ollamaRunning = await OllamaEmbeddingProvider.checkRunning();

  const allFiles = existsSync(location.knowledgeDir) ? await readdir(location.knowledgeDir) : [];
  const supportedFiles = listSupportedFiles(allFiles);

  const pending: Array<{ file: string; reason: "new" | "modified" }> = [];
  const filesSeen = new Set<string>();

  for (const fileName of supportedFiles) {
    filesSeen.add(fileName);
    const filePath = join(location.knowledgeDir, fileName);
    const { size } = await stat(filePath);
    const existing = existingHashes.get(fileName);

    if (!existing) {
      pending.push({ file: fileName, reason: "new" });
    } else if (existing.size !== size) {
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
    dbSizeBytes = statSync(location.dbPath).size;
  } catch {
    // DB file may not exist yet
  }

  const lastSync: string | null = null;

  return { totalSources: stats.totalSources, totalChunks: stats.totalChunks, dbSizeBytes, pending, orphans, ollamaRunning, lastSync };
}
