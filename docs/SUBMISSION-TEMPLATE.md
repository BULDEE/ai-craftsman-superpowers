# Plugin Submission Template

**For submission to**: [https://clau.de/plugin-directory-submission](https://clau.de/plugin-directory-submission)

---

## Plugin Information

**Name**: AI Craftsman Superpowers

**Repository URL**: https://github.com/BULDEE/ai-craftsman-superpowers

**Version**: 1.5.0

**License**: Apache-2.0

---

## Author

**Name**: Alexandre Mallet

**GitHub**: [@woprrr](https://github.com/woprrr)

**Contact**: Via GitHub Issues

---

## Sponsors

- **[BULDEE](https://buldee.com)** - Building the future of AI-assisted development
- **[Time Hacking Limited](https://thelabio.com)** - Maximizing developer productivity

---

## Short Description (< 160 chars)

Senior craftsman methodology for Claude Code. DDD, Clean Architecture, TDD workflows that transform Claude into a disciplined software engineer.

---

## Full Description

### What it does

AI Craftsman Superpowers is a comprehensive Claude Code plugin that enforces senior engineering practices through 22 commands, 12 specialized agents, automated hooks (8 events + 4 agent hooks), and a curated knowledge base.

### Key Features

1. **Design-First Methodology**: `/craftsman:design` enforces DDD phases (Understand → Challenge → Recommend → Implement) before any code is written

2. **Systematic Debugging**: `/craftsman:debug` uses the ReAct pattern (Hypothesis → Action → Observation) to find root causes, not random fixes

3. **Bias Protection**: Automatic detection of cognitive biases (acceleration, scope creep, over-optimization) with actionable warnings

4. **Code Rule Enforcement**: 3-level validation (regex + static analysis + architecture) with blocking hooks. PHP (strict_types, final classes, no setters) and TypeScript (no any, named exports)

5. **12 Specialized Agents**: 5 reviewers (architecture, security, Symfony, React, AI) + 7 craftsmen (team-lead, backend, frontend, architect, AI engineer, UX director, doc-writer)

6. **Semantic Intelligence**: Agent hooks (Haiku) provide DDD verification, Sentry error context, architectural analysis, and final review beyond regex patterns

7. **Framework Scaffolding**: Ready-to-use templates for Symfony entities, React components, TanStack Query hooks

8. **Correction Learning**: Records when users fix Claude-generated code and injects trends at session start

### Why it's different

- **Not just prompts**: Combines skills, hooks, agents, and knowledge base
- **Battle-tested**: Based on 15+ years of craftsmanship experience
- **Pragmatic**: Balances DDD purity with real-world constraints
- **Framework-aware**: Specific patterns for Symfony, React, AI/ML

---

## Skills Overview

| Category | Commands | Count |
|----------|----------|-------|
| Core Methodology | design, debug, plan, challenge, verify, spec, refactor, test, git, parallel | 10 |
| Symfony/PHP | entity, usecase | 2 |
| React/TypeScript | component, hook | 2 |
| AI/ML | rag, mlops, agent-design | 3 |
| Utilities | source-verify, agent-create, scaffold, metrics, setup | 5 |
| **Total** | | **22** |

---

## Technical Requirements

- Claude Code v1.0.33+
- No external dependencies required
- Optional: Ollama for local RAG (recommended over OpenAI)

---

## Screenshots / Demo

> TODO: Add GIFs demonstrating:
> 1. `/craftsman:design` - DDD design flow
> 2. `/craftsman:debug` - ReAct debugging
> 3. Bias detection warning popup
> 4. Post-write validation feedback

---

## Links

- **Documentation**: [/docs](https://github.com/BULDEE/ai-craftsman-superpowers/tree/main/docs)
- **Examples**: [/examples](https://github.com/BULDEE/ai-craftsman-superpowers/tree/main/examples)
- **ADRs**: [/docs/adr](https://github.com/BULDEE/ai-craftsman-superpowers/tree/main/docs/adr)
- **Changelog**: [CHANGELOG.md](https://github.com/BULDEE/ai-craftsman-superpowers/blob/main/CHANGELOG.md)

---

## Social Proof / Traction

> TODO: Add metrics once available:
> - GitHub stars
> - Forks
> - Contributors
> - Testimonials

---

## Why Include in Official Directory?

1. **Unique Value**: Only plugin focused on senior craftsmanship methodology (DDD, Clean Architecture, TDD)

2. **Complete Solution**: Not just prompts - full ecosystem with hooks, agents, knowledge base

3. **Quality**: 42+ tests passing, 11 ADRs, comprehensive documentation

4. **Active Maintenance**: Regular updates, responsive to issues

5. **Community Benefit**: Helps developers write better code, not just faster code

---

## Commitment

We commit to:
- Responding to issues within 48 hours
- Maintaining compatibility with Claude Code updates
- Following Anthropic's plugin guidelines
- Not collecting any user data

---

*Submitted by Alexandre Mallet on behalf of the AI Craftsman Superpowers project*
*Sponsored by BULDEE and Time Hacking Limited*
