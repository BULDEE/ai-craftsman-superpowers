# Master Guide (Architects)

This is the final level. You'll learn to extend the system itself: create skills, build agents, design knowledge architectures, and contribute back.

## What You'll Learn

- [x] Creating custom skills
- [x] Building production agents
- [x] Designing knowledge architectures
- [x] Contributing to the ecosystem
- [x] Advanced customization

## Prerequisites

- Completed all previous guides
- Deep understanding of the plugin architecture
- Experience building AI systems

---

## Lesson 1: Creating Custom Skills

### Skill Anatomy

```
skill-name/
└── SKILL.md
```

A skill file has:

```markdown
---
name: skill-name
description: When to use this skill
---

# /skill-name - Title

## Context
What knowledge to load

## Process (MANDATORY)
Phases to follow

## Constraints
Rules to enforce

## Bias Protection
Guard against tendencies
```

### Example: /security-review Skill

```markdown
---
name: security-review
description: Use when reviewing code for security vulnerabilities. OWASP Top 10 focused.
---

# /security-review - Security Audit

You are a Senior Security Engineer. You DON'T just find bugs—you assess RISK.

## Context

Load:
- OWASP Top 10 reference
- Project's security policies
- Previous security incidents

## Process (MANDATORY)

### Phase 1: Threat Model

Before reviewing code, establish:

1. What assets are we protecting?
2. Who are the threat actors?
3. What's the attack surface?

Output a threat model summary.

### Phase 2: Systematic Review

Check for each OWASP Top 10:

1. Injection (SQL, Command, LDAP)
2. Broken Authentication
3. Sensitive Data Exposure
4. XML External Entities (XXE)
5. Broken Access Control
6. Security Misconfiguration
7. Cross-Site Scripting (XSS)
8. Insecure Deserialization
9. Known Vulnerabilities
10. Insufficient Logging

For each, output:
- [ ] Checked
- Finding (if any)
- Severity (Critical/High/Medium/Low)
- Remediation

### Phase 3: Report

```
SECURITY REVIEW REPORT

Scope: [Files reviewed]
Date: [Date]

CRITICAL FINDINGS:
1. [Finding with line reference]

HIGH FINDINGS:
1. [Finding]

RECOMMENDATIONS:
1. [Priority action]

VERDICT: [PASS | CONDITIONAL PASS | FAIL]
```

## Bias Protection

- **acceleration**: Complete ALL OWASP checks. Don't skip "unlikely" vulnerabilities.
- **over_confidence**: Low severity ≠ no risk. Document everything.
```

### Registering Skills

Add to `plugin.json`:

```json
{
  "packs": {
    "security": {
      "description": "Security-focused skills",
      "skills": ["security-pack/skills/security-review"]
    }
  }
}
```

---

## Lesson 2: Building Production Agents

### Agent Architecture

```
agents/
└── my-agent.md
```

An agent file defines:

```markdown
# Agent: Agent Name

## Mission
One sentence purpose

## Mindset
Key questions to always ask

## Checklist
What to verify

## Report Format
How to output findings

## Severity Levels
How to categorize issues
```

### Example: Cost Optimization Agent

```markdown
# Agent: Cloud Cost Optimizer

## Mission

Review infrastructure code for cost optimization opportunities. Identify waste, suggest right-sizing, and recommend reserved capacity.

## Mindset

> "The cheapest resource is the one you don't use."

```
┌─────────────────────────────────────────────────────────────┐
│                 COST OPTIMIZER MINDSET                       │
├─────────────────────────────────────────────────────────────┤
│  1. Is this resource actually used?                          │
│  2. Is it sized correctly for the workload?                  │
│  3. Could we use spot/preemptible instead?                   │
│  4. Is there a cheaper region/zone?                          │
│  5. Are we leveraging reserved capacity?                     │
└─────────────────────────────────────────────────────────────┘
```

## Review Checklist

### Compute
- [ ] Instance right-sizing (CPU/memory utilization)
- [ ] Spot instance opportunities
- [ ] Reserved instance coverage
- [ ] Auto-scaling configuration
- [ ] Idle resources

### Storage
- [ ] Storage class optimization (hot/cold/archive)
- [ ] Unused volumes
- [ ] Snapshot lifecycle
- [ ] Data transfer costs

### Network
- [ ] NAT gateway usage
- [ ] Data transfer between regions
- [ ] Load balancer optimization
- [ ] CDN configuration

### Database
- [ ] Instance right-sizing
- [ ] Reserved capacity
- [ ] Read replicas necessity
- [ ] Backup retention

## Severity Levels

### CRITICAL (>$1000/month savings)
Immediate action required. Significant waste identified.

### HIGH ($100-$1000/month)
Should address within sprint.

### MEDIUM ($10-$100/month)
Plan for next quarter.

### LOW (<$10/month)
Nice to have, backlog.

## Report Format

```markdown
## Cost Optimization Review

### Executive Summary
- Current estimated monthly cost: $X
- Potential savings identified: $Y (Z%)
- Quick wins: [List]

### CRITICAL
1. **[Resource]** - $X/month potential savings
   - Current: [Configuration]
   - Recommended: [Change]
   - Implementation: [Steps]

### HIGH
...

### Savings Roadmap
| Action | Savings | Effort | Timeline |
|--------|---------|--------|----------|
| ...    | $X/mo   | Low    | Week 1   |

### VERDICT
[ ] OPTIMIZED - No significant waste
[ ] OPPORTUNITIES - Savings available
[ ] CRITICAL WASTE - Immediate action needed
```
```

---

## Lesson 3: Knowledge Architecture

### Designing Knowledge Structures

As an architect, you design how knowledge is organized:

```
knowledge/
├── principles/           # Universal truths
│   ├── solid.md
│   ├── dry.md
│   └── yagni.md
├── patterns/            # Reusable solutions
│   ├── creational/
│   ├── structural/
│   └── behavioral/
├── canonical/           # Golden examples
│   ├── entity.php
│   ├── value-object.php
│   └── use-case.php
├── anti-patterns/       # What NOT to do
│   ├── god-class.md
│   └── anemic-domain.md
└── domain-specific/     # Your domain
    ├── e-commerce/
    └── fintech/
```

### Knowledge Layering

```
┌─────────────────────────────────────────────────────────────────┐
│                    KNOWLEDGE HIERARCHY                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────┐                                            │
│  │ Project Rules   │  Highest specificity                       │
│  │ (CLAUDE.md)     │  "In THIS project, we do X"                │
│  └────────┬────────┘                                            │
│           │                                                      │
│  ┌────────▼────────┐                                            │
│  │ Domain Knowledge│  Domain-specific patterns                  │
│  │ (e-commerce/)   │  "In e-commerce, we do Y"                  │
│  └────────┬────────┘                                            │
│           │                                                      │
│  ┌────────▼────────┐                                            │
│  │ Stack Knowledge │  Technology patterns                       │
│  │ (symfony-pack)  │  "In Symfony, we do Z"                     │
│  └────────┬────────┘                                            │
│           │                                                      │
│  ┌────────▼────────┐                                            │
│  │ Core Principles │  Universal truths                          │
│  │ (SOLID, DDD)    │  "Always do W"                             │
│  └─────────────────┘                                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### RAG Knowledge Strategy

For large knowledge bases:

```
┌─────────────────────────────────────────────────────────────────┐
│                    RAG STRATEGY                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ALWAYS IN CONTEXT:                                             │
│  • Project CLAUDE.md (rules)                                    │
│  • Current skill instructions                                   │
│                                                                  │
│  RETRIEVED ON DEMAND:                                           │
│  • Pattern details (via search_knowledge)                       │
│  • Code examples (via search_knowledge)                         │
│  • Historical decisions (via search_knowledge)                  │
│                                                                  │
│  NEVER IN CONTEXT:                                              │
│  • Full documentation (too large)                               │
│  • All patterns at once (dilutes relevance)                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Lesson 4: Contributing Back

### Creating a New Pack

```bash
# Structure
my-pack/
├── skills/
│   └── my-skill/
│       └── SKILL.md
├── agents/
│   └── my-agent.md
├── knowledge/
│   ├── canonical/
│   └── anti-patterns/
└── templates/
    └── bounded-context.template.md
```

Update `plugin.json`:

```json
{
  "packs": {
    "my-pack": {
      "description": "My custom pack",
      "required": false,
      "skills": ["my-pack/skills/my-skill"],
      "agents": ["my-pack/agents/my-agent.md"],
      "knowledge": ["my-pack/knowledge/*"]
    }
  }
}
```

### Publishing

```bash
# Fork the repository
# Add your pack
# Submit PR with:
# - Description of pack purpose
# - Documentation
# - Example usage
```

---

## Lesson 5: Advanced Customization

### Custom MCP Server

Build specialized tools:

```typescript
// finance-mcp/src/tools/calculate-irr.ts
export class CalculateIRRTool {
  static readonly schema = {
    name: "calculate_irr",
    description: "Calculate Internal Rate of Return for cash flows",
    inputSchema: {
      type: "object",
      properties: {
        cashFlows: {
          type: "array",
          items: { type: "number" },
          description: "Array of cash flows (negative = outflow)"
        }
      },
      required: ["cashFlows"]
    }
  };

  execute(input: { cashFlows: number[] }): { irr: number } {
    // Newton-Raphson IRR calculation
    return { irr: this.calculateIRR(input.cashFlows) };
  }
}
```

### Bias Profiles

Create custom bias profiles:

```yaml
# .craft-config.yml
profiles:
  cautious-architect:
    biases:
      - premature_abstraction
      - gold_plating
      - analysis_paralysis
    responses:
      premature_abstraction: "STOP: Do we have 3+ use cases for this abstraction?"
      gold_plating: "STOP: Is this required for the current story?"
      analysis_paralysis: "STOP: We have enough info. Make a decision."

  move-fast-engineer:
    biases:
      - acceleration
      - scope_creep
      - skip_tests
    responses:
      acceleration: "STOP: Write the test first."
      scope_creep: "STOP: Is this in the PR scope?"
      skip_tests: "STOP: No merge without tests."
```

### Workflow Automation

Create automated workflows:

```yaml
# .craft-workflows.yml
workflows:
  new-feature:
    steps:
      - skill: /spec
        prompt: "Write specification for: {feature}"
      - skill: /design
        prompt: "Design based on specification"
      - skill: /test
        prompt: "Write tests for the design"
      - agent: architecture-reviewer
        prompt: "Review the design"

  bug-fix:
    steps:
      - skill: /debug
        prompt: "Investigate: {bug_description}"
      - skill: /test
        prompt: "Add regression test"
      - agent: security-reviewer
        prompt: "Check for security implications"
```

---

## The Master Craftsman Manifesto

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│                 THE AI-AUGMENTED CRAFTSMAN                       │
│                                                                  │
│  We are not replaced by AI. We are amplified.                   │
│                                                                  │
│  We use AI to:                                                   │
│  • Think deeper, not faster                                      │
│  • Challenge assumptions, not skip them                          │
│  • Write better code, not more code                              │
│  • Learn continuously, not stagnate                              │
│                                                                  │
│  We remain responsible for:                                      │
│  • Architectural decisions                                       │
│  • Business understanding                                        │
│  • Quality standards                                             │
│  • Ethical considerations                                        │
│                                                                  │
│  The tool amplifies who we are.                                  │
│  Become someone worth amplifying.                                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## You Are Now a Master

You can:

- [x] Create skills that encode expertise
- [x] Build agents that automate review
- [x] Design knowledge architectures
- [x] Extend the system with MCP servers
- [x] Contribute back to the community

The journey continues. Every project teaches something new. Encode that learning. Share it with others.

**Welcome to the craft.**
