# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-02-04

### Added

**19 Skills with `craftsman:*` namespace**

All skills use consistent `/craftsman:*` naming convention for better discoverability and ecosystem coherence.

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

**AI/ML (4)**
- `/craftsman:rag` - RAG pipeline design
- `/craftsman:mlops` - MLOps audit
- `/craftsman:agent-design` - AI agent design (3P pattern)
- `/craftsman:source-verify` - Verify AI capabilities against official docs

**Utility (1)**
- `/craftsman:session-init` - Session initialization

**5 Specialized Agents**
- `architecture-reviewer` - Clean Architecture compliance
- `security-pentester` - Security vulnerability detection
- `symfony-reviewer` - Symfony/DDD best practices
- `react-reviewer` - React patterns and hooks
- `ai-reviewer` - RAG/MLOps/Agent best practices

**Hooks System**
- `bias-detector.sh` - Cognitive bias detection (UserPromptSubmit)
- `post-write-check.sh` - Code validation for Write|Edit tools

**Knowledge Base**
- Principles (SOLID, DRY, YAGNI, KISS)
- Patterns (DDD, Clean Architecture, Microservices)
- Canonical examples (PHP entities, TS components)
- Anti-patterns (Anemic domain, Prop drilling, Any type)
- AI-specific (RAG architecture, MLOps, Vector databases, 3P pattern)

**Optional MCP Server**
- `knowledge-rag` - Semantic search over local PDFs with Ollama embeddings

### Architecture

- **Consolidated structure**: Single `/skills/` directory for all skills
- **Single `/agents/` directory**: All reviewers in one place
- **Single `/knowledge/` directory**: All reference material centralized
- **Framework packs** contain only templates (no skill duplication)

---

## Links

- [GitHub Repository](https://github.com/BULDEE/ai-craftsman-superpowers)
- [Documentation](https://github.com/BULDEE/ai-craftsman-superpowers/tree/main/docs)
- [Issue Tracker](https://github.com/BULDEE/ai-craftsman-superpowers/issues)
