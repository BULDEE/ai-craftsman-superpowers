# Agents Reference

Agents are specialized reviewers that audit code against standards.

## How to Use Agents

Agents are invoked automatically during code review or explicitly:

```
> Review this PR with the architecture-reviewer agent

> Run ai-reviewer on the ML pipeline code
```

---

## Core Pack

### architecture-reviewer

**Mission**: Review code against Clean Architecture principles.

**Checks**:
- Dependencies point inward (domain has no external imports)
- Domain layer purity
- Use case single responsibility
- Controller thinness
- Infrastructure isolation

**Severity Levels**:

| Level | Examples |
|-------|----------|
| BLOCKING | Domain imports infrastructure, business logic in controller |
| MUST FIX | Anemic domain, primitive obsession |
| IMPROVE | Missing value objects, unclear naming |

**Report Format**:
```markdown
## Architecture Review

### BLOCKING
1. **src/Domain/User.php:15** - Imports Doctrine EntityManager
   - Impact: Domain coupled to infrastructure
   - Fix: Inject repository interface instead

### VERDICT
[ ] APPROVE
[x] REQUEST_CHANGES
[ ] BLOCK
```

---

## Symfony Pack

### symfony-reviewer

**Mission**: Review PHP/Symfony code against DDD best practices.

**Checks**:
- Final classes (except Doctrine entities)
- Private constructors with static factories
- No public setters
- Strict types declaration
- Value objects for domain primitives
- Domain events for state changes

**Stack-Specific**:
- Doctrine mapping correctness
- Symfony service configuration
- Messenger handler patterns

---

### security-pentester

**Mission**: Security audit focused on web vulnerabilities.

**Checks**:
- OWASP Top 10
- SQL injection
- XSS vulnerabilities
- CSRF protection
- Authentication/authorization
- Input validation
- Sensitive data exposure

---

## React Pack

### react-reviewer

**Mission**: Review React/TypeScript code against best practices.

**Checks**:
- No `any` types
- Proper hook dependencies
- Component size and responsibility
- State management patterns
- Performance (memo, useCallback usage)
- Accessibility

---

## AI Pack

### ai-reviewer

**Mission**: Review AI/ML code for production best practices.

**Domains**:

#### RAG Pipelines
- Chunking strategy and overlap
- Embedding model consistency
- Retrieval configuration
- Prompt grounding

#### MLOps
- Data versioning
- Experiment tracking
- Model testing
- Monitoring setup
- Reproducibility (seeds)

#### Agent Architecture
- 3P separation (Perceive/Plan/Perform)
- Tool definitions
- Memory management
- Safety boundaries

**Critical Checks**:
- [ ] No hardcoded API keys
- [ ] Error handling on LLM calls
- [ ] Bounded token usage
- [ ] Input validation
- [ ] Reproducibility

**Report Format**:
```markdown
## AI/ML Code Review

### BLOCKING
1. **src/rag/config.py:23** - Hardcoded API key
   - Risk: Security
   - Fix: Use environment variable

### METRICS AUDIT
| Metric | Status |
|--------|--------|
| Reproducibility | ⚠ No seeds |
| Observability | ✓ Logging OK |
| Testability | ✗ No tests |
| Security | ✗ Key exposed |

### VERDICT
[ ] APPROVE
[ ] REQUEST_CHANGES
[x] BLOCK
```

---

## Agent Output Format

All agents produce reports with:

1. **Scope**: What was reviewed
2. **Findings by severity**: BLOCKING > MUST FIX > IMPROVE
3. **Positive patterns**: What was done well
4. **Verdict**: APPROVE / REQUEST_CHANGES / BLOCK

## Creating Custom Agents

See [Master Guide](../guides/master.md) for creating your own agents.

Template:
```markdown
# Agent: [Name]

## Mission
[One sentence purpose]

## Mindset
[Key questions to ask]

## Checklist
[What to verify]

## Severity Levels
[How to categorize]

## Report Format
[Output template]
```
