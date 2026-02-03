# Skills Reference

Complete reference for all available skills.

## Core Pack (Always Enabled)

### /design

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
> /design
Create a Money value object for handling currency amounts
```

---

### /debug

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
> /debug
The checkout process fails silently for some users.
No error in logs, payment not processed.
```

---

### /test

**Purpose**: Design test strategies and generate tests.

**When to use**:
- Adding tests to existing code
- Defining test strategy for new features
- Improving test coverage

**Methodology**: Fowler/Martin test pyramid

**Example**:
```
> /test
Add tests for the Order aggregate.
Focus on state transitions and invariants.
```

---

### /refactor

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
> /refactor
The OrderService has too many responsibilities.
Extract payment handling.
```

---

### /plan

**Purpose**: Break complex tasks into actionable steps.

**When to use**:
- Multi-day features
- Unclear implementation path
- Team coordination needed

**Example**:
```
> /plan
Implement user authentication with OAuth2.
Need Google and GitHub providers.
```

---

### /challenge

**Purpose**: Review and question architectural decisions.

**When to use**:
- Before major implementation
- Reviewing others' designs
- Validating assumptions

**Example**:
```
> /challenge
We're planning to use microservices.
Currently have 3 developers and 1 product.
```

---

### /spec

**Purpose**: Write formal specifications (BDD/TDD style).

**When to use**:
- Clarifying requirements
- Before implementation
- Acceptance criteria needed

**Example**:
```
> /spec
Specify the password reset flow.
Include email verification and expiration.
```

---

### /git

**Purpose**: Safe git operations with guardrails.

**When to use**:
- Complex git operations
- Merge conflicts
- Branch management

**Example**:
```
> /git
Rebase feature branch onto main.
Resolve any conflicts preserving feature changes.
```

---

## Symfony Pack

### /craft entity

**Purpose**: Scaffold DDD entity with all components.

**Generates**:
- Entity class (final, private constructor)
- Identity Value Object
- Domain events
- Unit tests

**Example**:
```
> /craft entity
Create Product entity with SKU, name, price, stock.
```

---

### /craft usecase

**Purpose**: Scaffold application use case.

**Generates**:
- Command DTO
- Handler class
- Output DTO
- Unit tests

**Example**:
```
> /craft usecase
PlaceOrder - validates stock and creates order
```

---

## React Pack

### /craft component

**Purpose**: Scaffold React component with TypeScript.

**Generates**:
- Component file
- Test file
- Storybook story (optional)
- Export index

**Example**:
```
> /craft component
ProductCard - shows image, name, price, add to cart
```

---

### /craft hook

**Purpose**: Scaffold TanStack Query hook.

**Generates**:
- Hook file with proper typing
- Query/mutation configuration
- Error handling

**Example**:
```
> /craft hook
useProducts - fetches paginated product list
```

---

## AI Pack

### /craft rag

**Purpose**: Design RAG (Retrieval-Augmented Generation) pipelines.

**Process**:
1. Requirements gathering (data, use case, quality)
2. Architecture decision (DB, embeddings, chunking)
3. Implementation (ingestion, retrieval, generation)
4. Testing strategy

**Example**:
```
> /craft rag
Build RAG for customer support documentation.
500 markdown files, need high accuracy.
```

---

### /craft mlops

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
> /craft mlops
Audit our recommendation model for production.
```

---

### /craft agent

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
> /craft agent
Design a code review agent for GitHub PRs.
Check security, tests, and style.
```

---

## Quick Reference Table

| Skill | Pack | Purpose |
|-------|------|---------|
| `/design` | Core | DDD entity design |
| `/debug` | Core | Systematic debugging |
| `/test` | Core | Test strategy |
| `/refactor` | Core | Code improvement |
| `/plan` | Core | Task breakdown |
| `/challenge` | Core | Architecture review |
| `/spec` | Core | Specifications |
| `/git` | Core | Git operations |
| `/craft entity` | Symfony | Entity scaffolding |
| `/craft usecase` | Symfony | Use case scaffolding |
| `/craft component` | React | Component scaffolding |
| `/craft hook` | React | Hook scaffolding |
| `/craft rag` | AI | RAG pipeline design |
| `/craft mlops` | AI | MLOps audit |
| `/craft agent` | AI | Agent design |
