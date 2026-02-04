# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.2] - 2025-02-04

### Added

- **New Skill: `/craftsman:source-verify`**: Verify AI tool capabilities against official documentation
  - Mandatory verification protocol before making capability assessments
  - Quick reference URLs for all Claude Code documentation
  - Anti-patterns for avoiding false claims
  - Bias protection for confirmation, anchoring, and authority biases
- **ADR-004: Official Documentation Verification**: Decision record requiring source verification
  - Establishes mandatory consultation of official docs before assessments
  - Provides verification checklist for capability claims
  - Documents the February 2025 incident as motivation

### Fixed

- **PostToolUse Hook Matcher**: Changed from `Write` to `Write|Edit` to validate all file modifications
  - Previously only Write tool was validated, missing 50% of file changes
  - Edit tool modifications now trigger the same validation rules
- **Knowledge RAG README**: Fixed MCP configuration path (`~/.mcp.json` instead of `settings.local.json`)

### Changed

- **post-write-check.sh**: Updated header to reflect Write|Edit support
  - Script now explicitly documents PostToolUse trigger for both tools

## [2.1.1] - 2025-02-04

### Changed

- **Repository Restructure**: Moved plugin content to root for Anthropic marketplace compatibility
  - `skills/`, `agents/`, `hooks/`, `knowledge/` now at repository root
  - Removed nested `plugins/craftsman/` structure
- **Hook Security**: Updated paths to use `$CLAUDE_PLUGIN_DIR` for portability
- **Hook Scripts**: Added `set -euo pipefail` and security headers
- **plugin.json**: Added `engines`, `categories`, `bugs` fields for marketplace

### Added

- **SECURITY.md**: Comprehensive security documentation for marketplace review
- **README Sections**: Added "Security", "Known Limitations", "Pre-Installation Verification"

### Fixed

- **License Consistency**: Aligned plugin.json license with Apache-2.0 (was MIT)

## [2.1.0] - 2025-02-04

### Added

- **Knowledge Base Consolidation**: Merged canonical examples and stack-specifics into plugin
- **Mandatory Canonical Loading**: Skills now require loading canonical examples before generating code
  - `/craftsman:entity` loads `php-entity.php`, `php-value-object.php`
  - `/craftsman:usecase` loads `php-usecase.php`
  - `/craftsman:component` loads `ts-react-component.tsx`, `ts-branded-type.ts`
  - `/craftsman:hook` loads `ts-tanstack-hook.ts`, `ts-branded-type.ts`
- **Sponsors Section**: Added BULDEE and Time Hacking Limited as sponsors
- **RAG Documentation**: Complete guide for local RAG with Ollama (recommended) and OpenAI (alternative)
- **MCP Server Scripts**: Added `npm run index:ollama` and `npm run index:openai` commands

### Changed

- **Knowledge Base Location**: Now exclusively in `plugins/craftsman/knowledge/`
- **MCP Server README**: Rewritten with Ollama-first approach and clear setup instructions

### Removed

- Duplicate knowledge base in `~/.claude/knowledge/` (migrated to plugin)

## [2.0.0] - 2025-02-03

### Added

- **18 Skills**: Complete methodology skills for DDD, debugging, planning, testing
- **5 Specialized Agents**: Architecture, Security, Symfony, React, AI reviewers
- **Hooks System**: Bias detection and post-write code validation
- **Model Tiering**: Haiku/Sonnet/Opus strategy for optimal cost/quality
- **Knowledge Base**: Patterns, principles, anti-patterns documentation
- **Framework Packs**: Symfony/PHP, React/TypeScript, AI/ML engineering

### Skills by Category

**Core Methodology (10)**
- `/craftsman:design` - DDD design with challenge phases
- `/craftsman:debug` - Systematic debugging (ReAct pattern)
- `/craftsman:plan` - Structured planning & execution
- `/craftsman:challenge` - Architecture review
- `/craftsman:verify` - Evidence-based verification
- `/craftsman:spec` - Specification-first (TDD/BDD)
- `/craftsman:refactor` - Systematic refactoring
- `/craftsman:test` - Pragmatic testing
- `/craftsman:git` - Safe git workflow
- `/craftsman:parallel` - Parallel agent orchestration

**Symfony/PHP (2)**
- `/craftsman:entity` - DDD entity scaffolding
- `/craftsman:usecase` - Use case with command/handler

**React/TypeScript (2)**
- `/craftsman:component` - React component scaffolding
- `/craftsman:hook` - TanStack Query hook scaffolding

**AI/ML (3)**
- `/craftsman:rag` - RAG pipeline design
- `/craftsman:mlops` - MLOps audit
- `/craftsman:agent-design` - AI agent design (3P pattern)

## [1.0.0] - 2025-01-15

### Added

- Initial release
- Core skills: design, debug, plan, challenge
- Basic hooks for bias detection
- Knowledge base with SOLID, DDD patterns

---

## Links

- [GitHub Repository](https://github.com/BULDEE/ai-craftsman-superpowers)
- [Documentation](https://github.com/BULDEE/ai-craftsman-superpowers/tree/main/docs)
- [Issue Tracker](https://github.com/BULDEE/ai-craftsman-superpowers/issues)
