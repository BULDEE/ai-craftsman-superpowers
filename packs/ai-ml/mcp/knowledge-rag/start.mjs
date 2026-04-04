#!/usr/bin/env node

/**
 * Conditional launcher for knowledge-rag MCP server.
 *
 * - If "ai-ml" is NOT in CLAUDE_PLUGIN_OPTION_packs → runs a no-op MCP server
 *   (valid protocol, zero tools, zero errors in Claude Code).
 * - If "ai-ml" IS enabled → auto-installs deps, auto-builds, starts the real server.
 *
 * Uses only Node.js builtins so it works before npm install.
 */

import { createInterface } from "node:readline";
import { execSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

const packs = (process.env.CLAUDE_PLUGIN_OPTION_packs || "")
  .split(",")
  .map((p) => p.trim())
  .filter(Boolean);

if (!packs.includes("ai-ml")) {
  runNoopServer();
} else {
  await bootstrapAndRun();
}

// ---------------------------------------------------------------------------
// No-op MCP server — valid JSON-RPC/MCP protocol, zero capabilities
// ---------------------------------------------------------------------------
function runNoopServer() {
  const { stdin, stdout } = process;
  stdin.setEncoding("utf8");

  let buffer = "";

  stdin.on("data", (chunk) => {
    buffer += chunk;
    drain();
  });

  function drain() {
    while (true) {
      const headerEnd = buffer.indexOf("\r\n\r\n");
      if (headerEnd === -1) return;

      const header = buffer.substring(0, headerEnd);
      const match = header.match(/Content-Length:\s*(\d+)/i);
      if (!match) {
        buffer = buffer.substring(headerEnd + 4);
        continue;
      }

      const contentLength = parseInt(match[1], 10);
      const bodyStart = headerEnd + 4;

      if (buffer.length < bodyStart + contentLength) return;

      const body = buffer.substring(bodyStart, bodyStart + contentLength);
      buffer = buffer.substring(bodyStart + contentLength);

      try {
        const request = JSON.parse(body);
        handleRequest(request);
      } catch {
        // Malformed JSON — skip
      }
    }
  }

  function handleRequest(request) {
    if (request.method === "initialize") {
      respond(request.id, {
        protocolVersion: "2024-11-05",
        capabilities: {},
        serverInfo: { name: "knowledge-rag", version: "0.0.0" },
      });
    } else if (request.method === "notifications/initialized") {
      // Notification — no response needed
    } else if (request.method === "tools/list") {
      respond(request.id, { tools: [] });
    } else if (request.id !== undefined) {
      respond(request.id, {});
    }
  }

  function respond(id, result) {
    const payload = JSON.stringify({ jsonrpc: "2.0", id, result });
    const message = `Content-Length: ${Buffer.byteLength(payload)}\r\n\r\n${payload}`;
    stdout.write(message);
  }
}

// ---------------------------------------------------------------------------
// Bootstrap: install deps, build, then start the real server
// ---------------------------------------------------------------------------
async function bootstrapAndRun() {
  const nodeModules = join(__dirname, "node_modules");
  const distIndex = join(__dirname, "dist", "src", "index.js");

  if (!existsSync(nodeModules)) {
    console.error("[knowledge-rag] Installing dependencies...");
    execSync("npm install --silent", { cwd: __dirname, stdio: "ignore" });
  }

  if (!existsSync(distIndex)) {
    console.error("[knowledge-rag] Building TypeScript...");
    execSync("npm run build --silent", { cwd: __dirname, stdio: "ignore" });
  }

  await import(distIndex);
}
