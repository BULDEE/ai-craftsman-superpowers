---
name: session-init
description: Internal skill for session initialization. Loads craftsman context.
disable-model-invocation: true
---

# Craftsman Session Initialized

Welcome to **AI Craftsman Superpowers**. Your coding assistant is now operating with senior craftsman methodology.

## Available Skills

| Skill | Purpose |
|-------|---------|
| `/craftsman:design` | DDD design with challenge phases |
| `/craftsman:debug` | Systematic debugging (ReAct pattern) |
| `/craftsman:plan` | Structured planning & execution |
| `/craftsman:challenge` | Architecture review |
| `/craftsman:verify` | Evidence-based verification |
| `/craftsman:spec` | Specification-first (TDD/BDD) |
| `/craftsman:refactor` | Systematic refactoring |
| `/craftsman:test` | Pragmatic testing |
| `/craftsman:git` | Safe git workflow |
| `/craftsman:parallel` | Parallel agent orchestration |

## Stack-Specific Skills

**Symfony/PHP:**
- `/craftsman:entity` - Scaffold DDD entity
- `/craftsman:usecase` - Scaffold use case

**React/TypeScript:**
- `/craftsman:component` - Scaffold component
- `/craftsman:hook` - Scaffold TanStack Query hook

**AI/ML:**
- `/craftsman:rag` - Design RAG pipeline
- `/craftsman:mlops` - MLOps audit
- `/craftsman:agent-design` - Agent 3P pattern
- `/craftsman:source-verify` - Verify AI capabilities

**Utility:**
- `/craftsman:scaffold` - Generate context agent from code
- `/craftsman:agent-create` - Create bounded context agent

## Bias Protection Active

The following biases are being monitored:
- **Acceleration** → Will warn if rushing to code
- **Scope Creep** → Will warn if adding features beyond scope
- **Over-Optimization** → Will warn if premature abstraction

## Code Rules Enforced

**PHP:**
- `declare(strict_types=1)` required
- `final class` required
- No public setters
- No `new DateTime()` (use Clock)

**TypeScript:**
- No `any` types
- Named exports only
- No non-null assertions

---

Ready to build quality software. How can I help?
