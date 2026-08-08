# Commands Reference

Complete reference for all available commands.

> **Note:** As of v4.0.0, every workflow lives in `skills/<name>/SKILL.md` with frontmatter-controlled invocation (fork, agent binding, dynamic context). See [ADR-0017](../adr/0017-skills-over-commands.md) for rationale.

## Core Pack (Always Enabled)

### /craftsman:design

**Purpose**: Design domain entities, value objects, and aggregates using DDD principles.

**When to use**:
- Creating new domain concepts
- Modeling business rules
- Deciding between Entity vs Value Object

**Process**:
1. Understand - Clarify requirements and invariants
2. Challenge - Explore alternatives
3. Recommend - Propose design with trade-offs
4. Implement - Generate code after approval

**Example**:
```
> /craftsman:design
Create a Money value object for handling currency amounts
```

---

### /craftsman:debug

**Purpose**: Systematic debugging using the ReAct pattern.

**When to use**:
- Investigating bugs
- Understanding unexpected behavior
- Root cause analysis

**Process**:
1. Gather information
2. Form hypotheses
3. Test each hypothesis
4. Identify root cause
5. Recommend fix

**Example**:
```
> /craftsman:debug
The checkout process fails silently for some users.
No error in logs, payment not processed.
```

---

### /craftsman:test

**Purpose**: Design test strategies and generate tests.

**When to use**:
- Adding tests to existing code
- Defining test strategy for new features
- Improving test coverage

**Methodology**: Fowler/Martin test pyramid

**Example**:
```
> /craftsman:test
Add tests for the Order aggregate.
Focus on state transitions and invariants.
```

---

### /craftsman:refactor

**Purpose**: Systematic code improvement without changing behavior.

**When to use**:
- Code smells identified
- After making something work
- Technical debt reduction

**Process**:
1. Identify refactoring opportunity
2. Ensure test coverage
3. Apply refactoring pattern
4. Verify behavior unchanged

**Example**:
```
> /craftsman:refactor
The OrderService has too many responsibilities.
Extract payment handling.
```

---

### /craftsman:plan

**Purpose**: Break complex tasks into actionable steps.

**When to use**:
- Multi-day features
- Unclear implementation path
- Team coordination needed

**Example**:
```
> /craftsman:plan
Implement user authentication with OAuth2.
Need Google and GitHub providers.
```

---

### /craftsman:challenge

**Purpose**: Review and question architectural decisions.

**When to use**:
- Before major implementation
- Reviewing others' designs
- Validating assumptions

**Example**:
```
> /craftsman:challenge
We're planning to use microservices.
Currently have 3 developers and 1 product.
```

---

### /craftsman:spec

**Purpose**: Write formal specifications (BDD/TDD style).

**When to use**:
- Clarifying requirements
- Before implementation
- Acceptance criteria needed

**Example**:
```
> /craftsman:spec
Specify the password reset flow.
Include email verification and expiration.
```

---

### /craftsman:git

**Purpose**: Safe git operations with guardrails.

**When to use**:
- Complex git operations
- Merge conflicts
- Branch management

**Example**:
```
> /craftsman:git
Rebase feature branch onto main.
Resolve any conflicts preserving feature changes.
```

---

## Scaffolding (Unified)

### /craftsman:scaffold

**Purpose**: Unified scaffolder for all types. Replaces the former standalone `/craftsman:entity`, `/craftsman:usecase`, `/craftsman:component`, and `/craftsman:hook` commands.

**Supported Types**:

| Type | Pack | What It Generates |
|------|------|-------------------|
| `entity` | Symfony | DDD entity, Identity VO, Domain events, Unit tests |
| `usecase` | Symfony | Command DTO, Handler, Output DTO, Unit tests |
| `component` | React | Component file, Test file, Storybook story, Export index |
| `hook` | React | Hook file with typing, Query/mutation config, Error handling |
| `api-resource` | Symfony | API Platform resource with State Provider |
| `pack` | Core | New community pack structure |

**Examples**:
```
> /craftsman:scaffold entity
Create Product entity with SKU, name, price, stock.

> /craftsman:scaffold usecase
PlaceOrder - validates stock and creates order

> /craftsman:scaffold component
ProductCard - shows image, name, price, add to cart

> /craftsman:scaffold hook
useProducts - fetches paginated product list
```

---

## AI Pack

### /craftsman:rag

**Purpose**: Design RAG (Retrieval-Augmented Generation) pipelines.

**Process**:
1. Requirements gathering (data, use case, quality)
2. Architecture decision (DB, embeddings, chunking)
3. Implementation (ingestion, retrieval, generation)
4. Testing strategy

**Example**:
```
> /craftsman:rag
Build RAG for customer support documentation.
500 markdown files, need high accuracy.
```

---

### /craftsman:mlops

**Purpose**: Audit ML projects for production readiness.

**Checks**:
- Automation level
- Versioning (code, data, model)
- Experiment tracking
- Testing coverage
- Monitoring setup
- Reproducibility

**Example**:
```
> /craftsman:mlops
Audit our recommendation model for production.
```

---

### /craftsman:agent-design

**Purpose**: Design AI agents using 3P pattern.

**Process**:
1. Mission definition
2. 3P architecture (Perceive/Plan/Perform)
3. Tool registry
4. Memory schema
5. Implementation
6. Safety & testing

**Example**:
```
> /craftsman:agent-design
Design a code review agent for GitHub PRs.
Check security, tests, and style.
```

---

## Quick Reference Table

Every skill declares the cheapest model tier that can do its job, and how hard
that model should think. Both are enforced for the turn the skill runs in, so a
review does not silently run on whatever model you happen to have selected. See
[Model Tiering Explained](../guides/model-tiering-explained.md) for the
reasoning and the four ways to override it.

### Who can start a skill

Most skills carry `disable-model-invocation: true`: they start only when **you**
type the slash command as the first thing in a prompt. Written mid-sentence
("then run /craftsman:design") it stays plain text, and Claude cannot start it
on your behalf. That is deliberate for anything that commits you to a direction.

Claude can start these itself, so it may offer and run them inside a longer
piece of work: `challenge`, `test`, `debug`, `team`, `rag`, `mlops`,
`agent-design`.

Everything else in the table below is yours to launch. `/craftsman:workflow`
knows the difference: it prints the exact command to paste and waits, rather
than pretending to start a step it cannot. See
[ADR-0017](../adr/0017-skills-over-commands.md#amendment---2026-07-29).

| Command | Pack | Purpose | Model | Effort |
|---------|------|---------|-------|--------|
| `/craftsman:design` | Core | DDD entity, value object, and aggregate design | `opus` | `high` |
| `/craftsman:debug` | Core | Systematic debugging (ReAct) | `opus` | `high` |
| `/craftsman:challenge` | Core | Architecture review and code challenge | `opus` | `high` |
| `/craftsman:refactor` | Core | Refactoring with behaviour preservation | `opus` | `high` |
| `/craftsman:plan` | Core | Task breakdown for multi-step work | `opus` | `xhigh` |
| `/craftsman:legacy` | Core | Legacy rescue: hotspots, characterization tests, strangler-fig | `opus` | `xhigh` |
| `/craftsman:team` | Core | Multi-agent orchestration | `opus` | `xhigh` |
| `/craftsman:parallel` | Core | Parallel agent orchestration | `opus` | `xhigh` |
| `/craftsman:spec` | Core | Specification-first development (BDD/TDD) | `sonnet` | `medium` |
| `/craftsman:test` | Core | Test strategy and authoring | `sonnet` | `medium` |
| `/craftsman:scaffold` | Core | Unified scaffolder (entity, usecase, component, hook, api-resource, pack) | `sonnet` | `medium` |
| `/craftsman:workflow` | Core | Guided development pipeline | `sonnet` | `medium` |
| `/craftsman:ci` | Core | CI/CD quality gate export | `sonnet` | `medium` |
| `/craftsman:verify` | Core | Evidence-based verification | `haiku` | `low` |
| `/craftsman:git` | Core | Git operations with destructive-command protection | `haiku` | `low` |
| `/craftsman:rag` | AI | RAG pipeline design | `opus` | `xhigh` |
| `/craftsman:mlops` | AI | MLOps production-readiness audit | `opus` | `xhigh` |
| `/craftsman:agent-design` | AI | Agent design (3P pattern) | `opus` | `xhigh` |
| `/craftsman:setup` | Utility | Interactive setup and onboarding | `sonnet` | `medium` |
| `/craftsman:metrics` | Utility | Quality metrics and local dashboard | `haiku` | `low` |
| `/craftsman:healthcheck` | Utility | Installation and runtime diagnostic | `haiku` | `low` |

Craftsman context is loaded at session start by `hooks/session-start.sh`, not by
a skill. A `session-init` skill existed alongside it until v4.4.0 and was
removed: nothing invoked it, and its command list had drifted from the shipped
one.
