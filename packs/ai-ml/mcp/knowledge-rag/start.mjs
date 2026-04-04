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
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";

const __dirname = dirname(fileURLToPath(import.meta.url));

checkForConflictingConfig();

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
// Detect conflicting "knowledge-rag" entries in ~/.claude.json and ~/.mcp.json
// ---------------------------------------------------------------------------
function checkForConflictingConfig() {
  checkClaudeJson();
  checkMcpJson();
}

function checkClaudeJson() {
  try {
    const claudeJsonPath = join(homedir(), ".claude.json");
    if (!existsSync(claudeJsonPath)) return;

    const raw = readFileSync(claudeJsonPath, "utf8");
    if (!raw.includes('"knowledge-rag"')) return;

    const data = JSON.parse(raw);
    const projects = data.projects || {};

    for (const [projectPath, config] of Object.entries(projects)) {
      const mcpServers = config?.mcpServers || {};
      if ("knowledge-rag" in mcpServers) {
        console.error(
          `[knowledge-rag] WARNING: Conflicting MCP config detected in ~/.claude.json`
        );
        console.error(
          `[knowledge-rag]   Project "${projectPath}" has a manual "knowledge-rag" MCP entry.`
        );
        console.error(
          `[knowledge-rag]   This conflicts with the plugin-managed server and may cause failures.`
        );
        console.error(
          `[knowledge-rag]   Fix: Remove the "knowledge-rag" key from mcpServers in ~/.claude.json`
        );
      }
    }
  } catch {
    // Non-critical — do not block startup
  }
}

function checkMcpJson() {
  try {
    const mcpJsonPath = join(homedir(), ".mcp.json");
    if (!existsSync(mcpJsonPath)) return;

    const raw = readFileSync(mcpJsonPath, "utf8");
    if (!raw.includes('"knowledge-rag"')) return;

    const data = JSON.parse(raw);
    const mcpServers = data?.mcpServers || {};

    if ("knowledge-rag" in mcpServers) {
      console.error(
        `[knowledge-rag] WARNING: Conflicting MCP config detected in ~/.mcp.json`
      );
      console.error(
        `[knowledge-rag]   A manual "knowledge-rag" entry overrides the plugin-managed server.`
      );
      console.error(
        `[knowledge-rag]   Fix: Remove the "knowledge-rag" key from ~/.mcp.json`
      );
    }
  } catch {
    // Non-critical — do not block startup
  }
}

// ---------------------------------------------------------------------------
// No-op MCP server — valid JSON-RPC/MCP protocol (NDJSON), zero capabilities
// ---------------------------------------------------------------------------
function runNoopServer() {
  const { stdin, stdout } = process;
  stdin.setEncoding("utf8");

  const rl = createInterface({ input: stdin });

  rl.on("line", (line) => {
    const trimmed = line.trim();
    if (!trimmed) return;

    try {
      const request = JSON.parse(trimmed);
      handleRequest(request);
    } catch {
      // Malformed JSON — skip
    }
  });

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
    stdout.write(payload + "\n");
  }
}

// ---------------------------------------------------------------------------
// Bootstrap: install deps, build, then start the real server
// ---------------------------------------------------------------------------
async function bootstrapAndRun() {
  const nodeModules = join(__dirname, "node_modules");
  const distIndex = join(__dirname, "dist", "src", "index.js");

  try {
    if (!existsSync(nodeModules)) {
      console.error("[knowledge-rag] Installing dependencies...");
      execSync("npm install --silent", { cwd: __dirname, stdio: "pipe" });
    }

    if (!existsSync(distIndex)) {
      console.error("[knowledge-rag] Building TypeScript...");
      execSync("npm run build --silent", { cwd: __dirname, stdio: "pipe" });
    }
  } catch (err) {
    console.error(`[knowledge-rag] Bootstrap failed: ${err.message}`);
    if (err.stderr) console.error(`[knowledge-rag] stderr: ${err.stderr}`);
    process.exit(1);
  }

  await import(distIndex);
}
