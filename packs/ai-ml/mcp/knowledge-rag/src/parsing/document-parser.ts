import { readFile } from "node:fs/promises";
import { extname } from "node:path";
import pdf from "pdf-parse";

export const CHUNK_SIZE = 500;
export const CHUNK_OVERLAP = 100;
export const SUPPORTED_EXTENSIONS = new Set([".pdf", ".md", ".txt"]);

export interface ChunkResult {
  readonly content: string;
  readonly page: number;
  readonly index: number;
}

export async function parseFile(filePath: string): Promise<{ text: string; pageCount: number }> {
  const ext = extname(filePath).toLowerCase();

  if (ext === ".pdf") {
    const buffer = await readFile(filePath);
    const data = await pdf(buffer);
    return { text: data.text, pageCount: data.numpages };
  }

  const text = await readFile(filePath, "utf-8");
  return { text, pageCount: 1 };
}

export function chunkText(text: string, chunkSize: number, overlap: number): ChunkResult[] {
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
