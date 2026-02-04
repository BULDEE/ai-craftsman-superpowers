# ADR-0004: 3P Agent Pattern for Agent Design

## Status

Accepted

## Date

2025-02-03

## Context

When designing AI agents (LLM-based autonomous systems), multiple architectural patterns exist:

1. **ReAct**: Reasoning + Acting loop
2. **Chain of Thought**: Step-by-step reasoning
3. **3P Pattern**: Perceive → Plan → Perform
4. **OODA Loop**: Observe → Orient → Decide → Act

We needed a structured approach for:
- Teaching agent design in the `/craftsman:agent-design` skill
- Reviewing agent implementations
- Building our own agents (code reviewers)

## Decision

We adopted the **3P Pattern (Perceive → Plan → Perform)** as our canonical agent architecture.

```
┌─────────────────────────────────────────────────────────┐
│                    AGENT SYSTEM                          │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐          │
│  │ PERCEIVE │ →  │   PLAN   │ →  │ PERFORM  │          │
│  └──────────┘    └──────────┘    └──────────┘          │
│       ↑                                  │              │
│       └──────────── feedback ────────────┘              │
└─────────────────────────────────────────────────────────┘
```

Each phase has clear responsibilities:

| Phase | Responsibility |
|-------|----------------|
| Perceive | Input processing, NLU, context retrieval |
| Plan | Goal decomposition, tool selection, strategy |
| Perform | Execution, result capture, state update |

## Consequences

### Positive

- **Clear separation**: Each phase testable independently
- **Debuggable**: Know exactly where failures occur
- **Teachable**: Easy to explain to developers
- **Universal**: Applies to any agent type
- **Extensible**: Can add sub-phases without restructuring

### Negative

- **Overhead**: Simple agents might not need full 3P
- **Rigidity**: Some agents benefit from fluid boundaries
- **Learning curve**: Developers must internalize the pattern

### Neutral

- Compatible with other patterns (ReAct fits inside Plan-Perform)
- Can be implemented iteratively (single pass or multi-turn)

## Pattern Details

### Perceive Phase

```typescript
interface PerceiveResult {
  intent: Intent;           // What user wants
  entities: Entity[];       // Extracted parameters
  context: RetrievedContext; // Relevant memory/docs
  state: EnvironmentState;  // Current situation
}
```

### Plan Phase

```typescript
interface PlanResult {
  goal: string;
  steps: Step[];
  tools: ToolSelection[];
  strategy: "sequential" | "parallel" | "conditional";
  validation: PlanValidation;
}
```

### Perform Phase

```typescript
interface PerformResult {
  outputs: ToolOutput[];
  stateChanges: StateChange[];
  errors: Error[];
  feedback: Feedback; // Loops back to Perceive
}
```

## Alternatives Considered

### Alternative 1: ReAct (Reasoning + Acting)

```
Thought → Action → Observation → Thought → ...
```

**Pros:**
- Simpler loop
- Well-documented in research

**Rejected as primary pattern because:**
- Less structured for complex agents
- Harder to separate concerns
- Planning implicit rather than explicit

**Note:** ReAct is used *within* our Plan-Perform phases.

### Alternative 2: OODA Loop

```
Observe → Orient → Decide → Act
```

**Pros:**
- Military-proven
- Fast decision cycles

**Rejected because:**
- "Orient" is vague for software
- Less mapping to LLM capabilities
- Harder to implement tooling

### Alternative 3: No Pattern (Ad-hoc)

Let each agent define its own structure.

**Rejected because:**
- Inconsistent implementations
- Harder to review
- No shared vocabulary
- Reinventing the wheel

## Real-World Application

Our code review agents follow 3P:

```
ai-reviewer:
  PERCEIVE: Read files, extract code patterns, load rules
  PLAN: Identify what to check, prioritize by severity
  PERFORM: Generate review comments, produce verdict
```

## References

- [Manus AI 3P Architecture](https://manus.ai/architecture) (source of pattern)
- [ReAct: Synergizing Reasoning and Acting](https://arxiv.org/abs/2210.03629)
- [LangChain Agents](https://python.langchain.com/docs/modules/agents/)
- [OODA Loop](https://en.wikipedia.org/wiki/OODA_loop)
