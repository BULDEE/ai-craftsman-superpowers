#!/usr/bin/env tsx

/**
 * Tests for VectorStore knowledge location detection
 *
 * Run with: npx tsx tests/vector-store.test.ts
 */

import { strict as assert } from "node:assert";
import { mkdirSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { VectorStore } from "../src/db/vector-store.js";

const PLUGIN_NAME = "ai-craftsman-superpowers";
const TEST_DIR = join(tmpdir(), `knowledge-rag-test-${Date.now()}`);

interface TestContext {
  readonly projectDir: string;
  readonly globalDir: string;
}

function setup(): TestContext {
  const projectDir = join(TEST_DIR, "project");
  const globalDir = join(TEST_DIR, "global");

  mkdirSync(projectDir, { recursive: true });
  mkdirSync(globalDir, { recursive: true });

  return { projectDir, globalDir };
}

function cleanup(): void {
  if (existsSync(TEST_DIR)) {
    rmSync(TEST_DIR, { recursive: true, force: true });
  }
}

function createProjectKnowledge(projectDir: string): void {
  const knowledgePath = join(projectDir, ".claude", PLUGIN_NAME, "knowledge");
  mkdirSync(knowledgePath, { recursive: true });
  writeFileSync(join(knowledgePath, "test.md"), "# Test Document\n\nTest content.");
}

async function testGlobalKnowledgeDetection(): Promise<void> {
  const { projectDir } = setup();

  try {
    // Project without .claude/ai-craftsman-superpowers/knowledge/ folder
    const store = VectorStore.create(projectDir);
    const location = store.getLocation();

    assert.equal(location.type, "global", "Should detect global knowledge when no project folder exists");
    assert.ok(
      location.dbPath.includes(".claude/ai-craftsman-superpowers/knowledge/knowledge.db"),
      "DB path should be in ~/.claude/ai-craftsman-superpowers/knowledge/"
    );

    store.close();
    console.log("✓ testGlobalKnowledgeDetection passed");
  } finally {
    cleanup();
  }
}

async function testProjectKnowledgeDetection(): Promise<void> {
  const { projectDir } = setup();

  try {
    // Create project knowledge folder
    createProjectKnowledge(projectDir);

    const store = VectorStore.create(projectDir);
    const location = store.getLocation();

    assert.equal(location.type, "project", "Should detect project knowledge when folder exists");
    assert.ok(
      location.knowledgeDir.includes(`.claude/${PLUGIN_NAME}/knowledge`),
      "Knowledge dir should be in .claude/ai-craftsman-superpowers/knowledge"
    );
    assert.ok(
      location.dbPath.includes(`.claude/${PLUGIN_NAME}/knowledge/.index/knowledge.db`),
      "DB should be in .index subfolder"
    );

    store.close();
    console.log("✓ testProjectKnowledgeDetection passed");
  } finally {
    cleanup();
  }
}

async function testIndexDirectoryCreation(): Promise<void> {
  const { projectDir } = setup();

  try {
    createProjectKnowledge(projectDir);

    const indexPath = join(projectDir, ".claude", PLUGIN_NAME, "knowledge", ".index");
    assert.ok(!existsSync(indexPath), ".index should not exist before VectorStore.create()");

    const store = VectorStore.create(projectDir);
    const location = store.getLocation();

    assert.ok(existsSync(indexPath), ".index directory should be created by VectorStore.create()");
    assert.equal(location.type, "project");

    store.close();
    console.log("✓ testIndexDirectoryCreation passed");
  } finally {
    cleanup();
  }
}

async function testDatabaseOperations(): Promise<void> {
  const { projectDir } = setup();

  try {
    createProjectKnowledge(projectDir);

    const store = VectorStore.create(projectDir);
    store.initialize();

    // Insert test data
    const embedding = new Array(768).fill(0.1);
    store.insertChunk("Test content", "test.md", 1, 0, embedding);
    store.insertSource("test.md", "/path/to/test.md", 1);

    // Verify data
    const sources = store.listSources();
    assert.equal(sources.length, 1, "Should have one source");
    assert.equal(sources[0].name, "test.md");
    assert.equal(sources[0].chunks, 1);

    const stats = store.getStats();
    assert.equal(stats.totalChunks, 1);
    assert.equal(stats.totalSources, 1);

    // Test search
    const results = store.search(embedding, 5);
    assert.equal(results.length, 1);
    assert.equal(results[0].content, "Test content");
    assert.ok(results[0].relevance > 0.99, "Same embedding should have high relevance");

    store.close();
    console.log("✓ testDatabaseOperations passed");
  } finally {
    cleanup();
  }
}

async function testClearDatabase(): Promise<void> {
  const { projectDir } = setup();

  try {
    createProjectKnowledge(projectDir);

    const store = VectorStore.create(projectDir);
    store.initialize();

    // Insert and clear
    const embedding = new Array(768).fill(0.1);
    store.insertChunk("Test content", "test.md", 1, 0, embedding);
    store.insertSource("test.md", "/path/to/test.md", 1);

    store.clear();

    const stats = store.getStats();
    assert.equal(stats.totalChunks, 0, "Chunks should be cleared");
    assert.equal(stats.totalSources, 0, "Sources should be cleared");

    store.close();
    console.log("✓ testClearDatabase passed");
  } finally {
    cleanup();
  }
}

async function testProjectPriorityOverGlobal(): Promise<void> {
  const { projectDir } = setup();

  try {
    // First test without project knowledge
    let store = VectorStore.create(projectDir);
    assert.equal(store.getLocation().type, "global");
    store.close();

    // Add project knowledge
    createProjectKnowledge(projectDir);

    // Now it should detect project
    store = VectorStore.create(projectDir);
    assert.equal(store.getLocation().type, "project", "Project should take priority when folder exists");
    store.close();

    console.log("✓ testProjectPriorityOverGlobal passed");
  } finally {
    cleanup();
  }
}

async function runAllTests(): Promise<void> {
  console.log("\n=== VectorStore Knowledge Detection Tests ===\n");

  const tests = [
    testGlobalKnowledgeDetection,
    testProjectKnowledgeDetection,
    testIndexDirectoryCreation,
    testDatabaseOperations,
    testClearDatabase,
    testProjectPriorityOverGlobal,
  ];

  let passed = 0;
  let failed = 0;

  for (const test of tests) {
    try {
      await test();
      passed++;
    } catch (error) {
      failed++;
      console.error(`✗ ${test.name} failed:`);
      console.error(error);
    }
  }

  console.log(`\n=== Results: ${passed} passed, ${failed} failed ===\n`);

  if (failed > 0) {
    process.exit(1);
  }
}

runAllTests();
