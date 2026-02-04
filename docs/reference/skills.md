# Commands Reference

Complete reference for all available commands.

> **Note:** As of v1.0.0, all user-invocable workflows are now in `commands/` instead of `skills/`. See [ADR-0007](../adr/0007-commands-over-skills.md) for rationale.

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

## Symfony Pack

### /craftsman:entity

**Purpose**: Scaffold DDD entity with all components.

**Generates**:
- Entity class (final, private constructor)
- Identity Value Object
- Domain events
- Unit tests

**Example**:
```
> /craftsman:entity
Create Product entity with SKU, name, price, stock.
```

---

### /craftsman:usecase

**Purpose**: Scaffold application use case.

**Generates**:
- Command DTO
- Handler class
- Output DTO
- Unit tests

**Example**:
```
> /craftsman:usecase
PlaceOrder - validates stock and creates order
```

---

## React Pack

### /craftsman:component

**Purpose**: Scaffold React component with TypeScript.

**Generates**:
- Component file
- Test file
- Storybook story (optional)
- Export index

**Example**:
```
> /craftsman:component
ProductCard - shows image, name, price, add to cart
```

---

### /craftsman:hook

**Purpose**: Scaffold TanStack Query hook.

**Generates**:
- Hook file with proper typing
- Query/mutation configuration
- Error handling

**Example**:
```
> /craftsman:hook
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

| Command | Pack | Purpose |
|---------|------|---------|
| `/craftsman:design` | Core | DDD entity design |
| `/craftsman:debug` | Core | Systematic debugging |
| `/craftsman:test` | Core | Test strategy |
| `/craftsman:refactor` | Core | Code improvement |
| `/craftsman:plan` | Core | Task breakdown |
| `/craftsman:challenge` | Core | Architecture review |
| `/craftsman:spec` | Core | Specifications |
| `/craftsman:git` | Core | Git operations |
| `/craftsman:verify` | Core | Evidence-based verification |
| `/craftsman:parallel` | Core | Parallel agent orchestration |
| `/craftsman:entity` | Symfony | Entity scaffolding |
| `/craftsman:usecase` | Symfony | Use case scaffolding |
| `/craftsman:component` | React | Component scaffolding |
| `/craftsman:hook` | React | Hook scaffolding |
| `/craftsman:rag` | AI | RAG pipeline design |
| `/craftsman:mlops` | AI | MLOps audit |
| `/craftsman:agent-design` | AI | Agent design |
| `/craftsman:source-verify` | AI | Verify AI capabilities |
| `/craftsman:scaffold` | Utility | Generate context agent |
| `/craftsman:agent-create` | Utility | Create bounded agent |
