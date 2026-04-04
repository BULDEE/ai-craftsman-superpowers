import { createHash } from "node:crypto";
import { readFile, stat } from "node:fs/promises";

export interface FileHash {
  readonly hash: string;
  readonly size: number;
}

export async function hashFile(filePath: string): Promise<FileHash> {
  const buffer = await readFile(filePath);
  const hash = createHash("sha256").update(buffer).digest("hex");
  const stats = await stat(filePath);

  return { hash, size: stats.size };
}
