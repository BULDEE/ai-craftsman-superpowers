#!/usr/bin/env tsx

import { VectorStore } from "../src/db/vector-store.js";
import { sync, addFile, removeSource, status } from "../src/sync/incremental-indexer.js";

const [mode, ...args] = process.argv.slice(2);

async function main(): Promise<void> {
  const store = VectorStore.create();
  store.initialize();

  switch (mode) {
    case "sync":
    case undefined: {
      const report = await sync(store);
      console.log(JSON.stringify(report, null, 2));
      break;
    }

    case "add": {
      const filePath = args[0];
      if (!filePath) {
        console.error("Usage: cli.ts add <file-path>");
        process.exit(1);
      }
      const result = await addFile(store, filePath);
      console.log(JSON.stringify(result, null, 2));
      break;
    }

    case "remove": {
      const sourceName = args[0];
      if (!sourceName) {
        console.error("Usage: cli.ts remove <source-name>");
        process.exit(1);
      }
      const deletedChunks = await removeSource(store, sourceName);
      console.log(JSON.stringify({ source: sourceName, deletedChunks }, null, 2));
      break;
    }

    case "status": {
      const report = await status(store);
      console.log(JSON.stringify(report, null, 2));
      break;
    }

    case "list": {
      const sources = store.listSources();
      const stats = store.getStats();
      console.log(JSON.stringify({ sources, stats }, null, 2));
      break;
    }

    case "rebuild": {
      console.error("[rebuild] Clearing database...");
      store.clear();
      const report = await sync(store);
      console.log(JSON.stringify(report, null, 2));
      break;
    }

    default:
      console.error(`Unknown mode: ${mode}`);
      console.error("Usage: cli.ts [sync|add|remove|status|list|rebuild]");
      process.exit(1);
  }

  store.close();
}

main().catch((err) => {
  console.error(`Fatal: ${err.message}`);
  process.exit(1);
});
