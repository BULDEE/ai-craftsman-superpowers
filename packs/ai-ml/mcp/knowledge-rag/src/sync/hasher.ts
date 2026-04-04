import { createHash } from "node:crypto";
import { stat } from "node:fs/promises";
import { createReadStream } from "node:fs";

export interface FileHash {
  readonly hash: string;
  readonly size: number;
}

export async function hashFile(filePath: string): Promise<FileHash> {
  const stats = await stat(filePath);
  const hash = createHash("sha256");
  const stream = createReadStream(filePath);

  for await (const chunk of stream) {
    hash.update(chunk);
  }

  return { hash: hash.digest("hex"), size: stats.size };
}
