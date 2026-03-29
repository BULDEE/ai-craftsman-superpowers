#!/usr/bin/env bash
# =============================================================================
# AI-ML Pack Setup — Installs MCP server dependencies
# Run: bash packs/ai-ml/scripts/setup.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_DIR="$(dirname "$SCRIPT_DIR")"
MCP_DIR="$PACK_DIR/mcp/knowledge-rag"

echo "AI-ML Pack Setup"
echo "================"

# Check Node.js
if ! command -v node &>/dev/null; then
    echo "ERROR: Node.js >= 20 is required for the knowledge-rag MCP server."
    echo "Install: https://nodejs.org/"
    exit 1
fi

NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
if [[ "$NODE_VERSION" -lt 20 ]]; then
    echo "ERROR: Node.js >= 20 required (found v${NODE_VERSION})."
    exit 1
fi

# Install MCP dependencies
if [[ -d "$MCP_DIR" ]]; then
    echo "Installing knowledge-rag MCP dependencies..."
    cd "$MCP_DIR"
    npm ci --production 2>/dev/null || npm install --production
    echo "Building TypeScript..."
    npx tsc 2>/dev/null || echo "WARN: TypeScript build failed. Using pre-built dist/ if available."
    echo "Done! knowledge-rag MCP server is ready."
else
    echo "WARN: MCP directory not found at $MCP_DIR"
fi
