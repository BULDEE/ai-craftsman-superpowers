#!/usr/bin/env tsx

import { readdir, readFile, stat } from "fs/promises";
import { join, basename, dirname, extname } from "path";
import { fileURLToPath } from "url";
import { existsSync } from "fs";
import pdf from "pdf-parse";

import { VectorStore } from "../src/db/vector-store.js";
import { OpenAIEmbeddingProvider } from "../src/embeddings/provider.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const PLUGIN_NAME = "ai-craftsman-superpowers";

interface ChunkResult {
  readonly content: string;
  readonly page: number;
  readonly index: number;
}

const CHUNK_SIZE = 500;
const CHUNK_OVERLAP = 100;

async function checkOllamaRunning(): Promise<boolean> {
  try {
    const response = await fetch("http://localhost:11434/api/tags");
    return response.ok;
  } catch {
    return false;
  }
}

function printSetupInstructions(): void {
  console.log("\n" + "=".repeat(60));
  console.log("SETUP REQUIRED: Ollama is not running");
  console.log("=".repeat(60));
  console.log("\nTo use the Knowledge RAG MCP, follow these steps:\n");
  console.log("1. Install Ollama:");
  console.log("   macOS:  brew install ollama");
  console.log("   Linux:  curl -fsSL https://ollama.ai/install.sh | sh\n");
  console.log("2. Pull the embedding model:");
  console.log("   ollama pull nomic-embed-text\n");
  console.log("3. Start Ollama server (keep running in a terminal):");
  console.log("   ollama serve\n");
  console.log("4. Run this indexer again:");
  console.log("   npm run index:ollama\n");
  console.log("5. Restart Claude Code to connect the MCP server\n");
  console.log("=".repeat(60) + "\n");
}

async function main(): Promise<void> {
  const provider = process.env.EMBEDDING_PROVIDER ?? "ollama";
  const cwd = process.cwd();

  // Check Ollama is running for ollama provider
  if (provider === "ollama") {
    const ollamaRunning = await checkOllamaRunning();
    if (!ollamaRunning) {
      printSetupInstructions();
      process.exit(1);
    }
  }

  // Create store with auto-detection (project vs global)
  const store = VectorStore.create(cwd);
  const location = store.getLocation();

  // Allow override via CLI argument
  const sourceDir = process.argv[2] ?? location.knowledgeDir;

  // Validate source directory exists
  if (!existsSync(sourceDir)) {
    console.error("=".repeat(60));
    console.error("ERROR: Knowledge directory not found");
    console.error("=".repeat(60));
    console.error(`\nExpected: ${sourceDir}\n`);
    if (location.type === "project") {
      console.error(`Create the folder and add your documents:`);
      console.error(`  mkdir -p .claude/${PLUGIN_NAME}/knowledge`);
      console.error(`  cp your-docs.pdf .claude/${PLUGIN_NAME}/knowledge/\n`);
    } else {
      console.error(`Add documents to the global knowledge folder:`);
      console.error(`  ${location.knowledgeDir}\n`);
    }
    process.exit(1);
  }

  console.log("=".repeat(60));
  console.log("Knowledge Base Indexer");
  console.log("=".repeat(60));
  console.log(`Mode: ${location.type.toUpperCase()} knowledge base`);
  console.log(`Embedding provider: ${provider}`);
  console.log(`Source directory: ${sourceDir}`);
  console.log(`Database: ${location.dbPath}`);
  console.log(`Chunk size: ${CHUNK_SIZE} chars`);
  console.log(`Chunk overlap: ${CHUNK_OVERLAP} chars`);
  console.log("");

  store.initialize();

  const embeddings = OpenAIEmbeddingProvider.create();

  console.log("Clearing existing data...");
  store.clear();

  const files = await readdir(sourceDir);
  const supportedFiles = files.filter((f) => {
    const ext = extname(f).toLowerCase();
    return ext === ".pdf" || ext === ".md" || ext === ".txt";
  });

  console.log(`Found ${supportedFiles.length} files to index\n`);

  let totalChunks = 0;
  let totalTokensEstimate = 0;

  for (const filename of supportedFiles) {
    const filepath = join(sourceDir, filename);
    const ext = extname(filename).toLowerCase();
    console.log(`Processing: ${filename}`);

    try {
      let text: string;
      let pageCount: number;

      if (ext === ".pdf") {
        const buffer = await readFile(filepath);
        const data = await pdf(buffer);
        pageCount = data.numpages;
        text = data.text;
      } else {
        // Markdown or text file
        text = await readFile(filepath, "utf-8");
        pageCount = 1;
      }

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
  console.log(`Total documents: ${supportedFiles.length}`);
  console.log(`Total chunks: ${totalChunks}`);
  console.log(`Estimated tokens embedded: ~${totalTokensEstimate.toLocaleString()}`);
  console.log(`Estimated cost: ~$${((totalTokensEstimate / 1_000_000) * 0.02).toFixed(4)}`);
  console.log("");
  console.log("=".repeat(60));
  console.log("NEXT STEPS");
  console.log("=".repeat(60));
  console.log("\n1. Ensure Ollama is running: ollama serve");
  console.log("\n2. Restart Claude Code to connect the MCP server");
  console.log("\n3. Use the knowledge base with:");
  console.log("   - search_knowledge tool: Search for specific topics");
  console.log("   - list_knowledge_sources tool: List indexed documents");
  console.log("\n" + "=".repeat(60) + "\n");
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
