#!/usr/bin/env tsx

import { readdir, readFile } from "fs/promises";
import { join, basename } from "path";
import pdf from "pdf-parse";

import { VectorStore } from "../src/db/vector-store.js";
import { OpenAIEmbeddingProvider } from "../src/embeddings/provider.js";

interface ChunkResult {
  readonly content: string;
  readonly page: number;
  readonly index: number;
}

const CHUNK_SIZE = 500;
const CHUNK_OVERLAP = 100;
const DEFAULT_SOURCE_DIR = "***REDACTED_PATH***";

async function main(): Promise<void> {
  const sourceDir = process.argv[2] ?? DEFAULT_SOURCE_DIR;

  console.log("=".repeat(60));
  console.log("Knowledge Base Indexer");
  console.log("=".repeat(60));
  console.log(`Source directory: ${sourceDir}`);
  console.log(`Chunk size: ${CHUNK_SIZE} chars`);
  console.log(`Chunk overlap: ${CHUNK_OVERLAP} chars`);
  console.log("");

  const store = VectorStore.create();
  store.initialize();

  const embeddings = OpenAIEmbeddingProvider.create();

  console.log("Clearing existing data...");
  store.clear();

  const files = await readdir(sourceDir);
  const pdfFiles = files.filter((f) => f.toLowerCase().endsWith(".pdf"));

  console.log(`Found ${pdfFiles.length} PDF files\n`);

  let totalChunks = 0;
  let totalTokensEstimate = 0;

  for (const filename of pdfFiles) {
    const filepath = join(sourceDir, filename);
    console.log(`Processing: ${filename}`);

    try {
      const buffer = await readFile(filepath);
      const data = await pdf(buffer);

      const pageCount = data.numpages;
      const text = data.text;

      console.log(`  - Pages: ${pageCount}`);
      console.log(`  - Characters: ${text.length}`);

      const chunks = chunkText(text, CHUNK_SIZE, CHUNK_OVERLAP);
      console.log(`  - Chunks: ${chunks.length}`);

      const chunkTexts = chunks.map((c) => c.content);
      console.log(`  - Generating embeddings...`);

      const chunkEmbeddings = await embeddings.embedBatch(chunkTexts);

      console.log(`  - Storing in database...`);

      for (let i = 0; i < chunks.length; i++) {
        store.insertChunk(
          chunks[i].content,
          filename,
          chunks[i].page,
          chunks[i].index,
          chunkEmbeddings[i]
        );
      }

      store.insertSource(filename, filepath, pageCount);

      totalChunks += chunks.length;
      totalTokensEstimate += Math.ceil(text.length / 4);

      console.log(`  - Done\n`);
    } catch (error) {
      console.error(`  - Error: ${error instanceof Error ? error.message : error}\n`);
    }
  }

  store.close();

  console.log("=".repeat(60));
  console.log("Indexing Complete");
  console.log("=".repeat(60));
  console.log(`Total documents: ${pdfFiles.length}`);
  console.log(`Total chunks: ${totalChunks}`);
  console.log(`Estimated tokens embedded: ~${totalTokensEstimate.toLocaleString()}`);
  console.log(`Estimated cost: ~$${((totalTokensEstimate / 1_000_000) * 0.02).toFixed(4)}`);
  console.log("");
}

function chunkText(
  text: string,
  chunkSize: number,
  overlap: number
): ChunkResult[] {
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
      if (match) {
        currentPage = parseInt(match[0], 10);
      }
      continue;
    }

    if (currentChunk.length + trimmed.length + 1 <= chunkSize) {
      currentChunk += (currentChunk ? "\n\n" : "") + trimmed;
    } else {
      if (currentChunk) {
        chunks.push({
          content: currentChunk.trim(),
          page: currentPage,
          index: chunkIndex++,
        });
      }

      if (trimmed.length > chunkSize) {
        const words = trimmed.split(/\s+/);
        currentChunk = "";

        for (const word of words) {
          if (currentChunk.length + word.length + 1 <= chunkSize) {
            currentChunk += (currentChunk ? " " : "") + word;
          } else {
            if (currentChunk) {
              chunks.push({
                content: currentChunk.trim(),
                page: currentPage,
                index: chunkIndex++,
              });
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
    chunks.push({
      content: currentChunk.trim(),
      page: currentPage,
      index: chunkIndex,
    });
  }

  return chunks.filter((c) => c.content.length >= 50);
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
