# 3P Agent Architecture Pattern

## Overview

The 3P Pattern (Perceive → Plan → Perform) is a structured approach to building software agents that interact with their environment through a clear cognitive loop.

```
┌─────────────────────────────────────────────────────────┐
│                    AGENT SYSTEM                          │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐          │
│  │ PERCEIVE │ →  │   PLAN   │ →  │ PERFORM  │          │
│  └──────────┘    └──────────┘    └──────────┘          │
│       ↑                                  │              │
│       └──────────── feedback ────────────┘              │
└─────────────────────────────────────────────────────────┘
                         │
                         ↓
                  ┌─────────────┐
                  │ ENVIRONMENT │
                  └─────────────┘
```

## The 3 Phases

### 1. PERCEIVE - Information Gathering

**Purpose:** Understand the current state of the environment and user intent.

| Component | Function |
|-----------|----------|
| Input Processing | Parse user messages, API responses, events |
| NLU (Natural Language Understanding) | Extract intent, entities, sentiment |
| Context Retrieval | Fetch relevant memory, documents |
| State Assessment | Determine current environment state |

**Key Activities:**
- Intent classification ("What does the user want?")
- Entity extraction ("What are the parameters?")
- Context loading ("What do I already know?")
- Environment sensing ("What's the current state?")

**Example:**
```
User: "Book a flight to Paris next Friday"

Perceived:
- Intent: book_flight
- Entities: destination=Paris, date=next_friday
- Context: user_preferences, previous_bookings
- State: no_active_booking
```

### 2. PLAN - Strategy Formation

**Purpose:** Decompose goals into actionable steps and select appropriate tools.

| Component | Function |
|-----------|----------|
| Goal Decomposition | Break complex goals into subtasks |
| Tool Selection | Choose which tools/APIs to use |
| Parameterization | Determine tool inputs |
| Orchestration | Order and parallelize tasks |

**Planning Strategies:**

| Strategy | When to Use |
|----------|-------------|
| Sequential | Tasks depend on previous results |
| Parallel | Independent tasks |
| Conditional | Branching based on outcomes |
| Iterative | Refinement loops |

**Example:**
```
Goal: Book flight to Paris next Friday

Plan:
1. Search available flights (Parallel)
   - Tool: flight_search_api
   - Params: dest=CDG, date=2024-01-12
2. Filter by user preferences
   - Tool: preference_filter
   - Params: max_stops=1, class=economy
3. Present options to user
   - Tool: response_formatter
4. IF user selects → Book
   - Tool: booking_api
```

### 3. PERFORM - Execution

**Purpose:** Execute the plan and handle results.

| Component | Function |
|-----------|----------|
| Tool Invocation | Call APIs, run functions |
| Sandbox Execution | Safe code execution |
| Result Capture | Store outputs |
| State Update | Modify environment/memory |
| Error Handling | Recover from failures |

**Execution Patterns:**

| Pattern | Description |
|---------|-------------|
| Fire and forget | Execute, don't wait |
| Synchronous | Execute, wait for result |
| Retry with backoff | Handle transient failures |
| Circuit breaker | Fail fast on repeated errors |
| Compensation | Rollback on failure |

## Core Components

### Intelligence Engine

The "brain" that coordinates the 3P loop.

```
┌────────────────────────────────────┐
│        INTELLIGENCE ENGINE          │
├────────────────────────────────────┤
│ • LLM (GPT-4, Claude, etc.)        │
│ • Reasoning (Chain-of-thought)     │
│ • Decision making                   │
│ • Self-reflection                   │
└────────────────────────────────────┘
```

### Tools

External capabilities the agent can invoke.

| Tool Type | Examples |
|-----------|----------|
| APIs | REST endpoints, GraphQL |
| Functions | Python functions, bash commands |
| Databases | SQL queries, vector search |
| Services | Email, calendar, messaging |

**Tool Definition Pattern:**
```yaml
name: flight_search
description: Search for available flights
parameters:
  destination:
    type: string
    required: true
  date:
    type: date
    required: true
  max_stops:
    type: integer
    default: 2
returns:
  type: array
  items: Flight
```

### Memory

Persistent state across interactions.

| Memory Type | Duration | Use Case |
|-------------|----------|----------|
| Working | Single turn | Current task context |
| Short-term | Session | Conversation history |
| Long-term | Persistent | User preferences, facts |
| Episodic | Persistent | Past interactions |

### Environment

The external world the agent operates in.

```
┌─────────────────────────────────────┐
│           ENVIRONMENT                │
├─────────────────────────────────────┤
│ • File system                        │
│ • Databases                          │
│ • External APIs                      │
│ • User interface                     │
│ • Other agents                       │
└─────────────────────────────────────┘
```

## Design Checklist

### Perceive Layer
- [ ] Clear input schema defined
- [ ] Intent classification implemented
- [ ] Entity extraction working
- [ ] Context retrieval optimized
- [ ] Error states handled

### Plan Layer
- [ ] Goal decomposition logic
- [ ] Tool registry defined
- [ ] Parameterization validation
- [ ] Fallback strategies
- [ ] Plan validation before execution

### Perform Layer
- [ ] All tools implemented and tested
- [ ] Sandboxing for code execution
- [ ] Result validation
- [ ] State persistence
- [ ] Comprehensive error handling

### Cross-Cutting
- [ ] Logging at each phase
- [ ] Metrics collection
- [ ] Rate limiting
- [ ] Security boundaries
- [ ] Human-in-the-loop triggers

## Anti-Patterns

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| No planning | Chaotic execution | Always generate plan first |
| Blind execution | No validation | Verify before acting |
| No memory | Repeated questions | Implement persistence |
| Tool sprawl | Too many tools | Curate and document |
| No boundaries | Security risks | Define clear permissions |

## Example: Claude Code Agent

```
PERCEIVE:
- User message: "Fix the bug in auth.py"
- Files read: auth.py, tests/test_auth.py
- Context: Previous conversation, CLAUDE.md

PLAN:
1. Analyze error (Read tool)
2. Identify root cause (Grep/Read)
3. Design fix (internal reasoning)
4. Implement fix (Edit tool)
5. Verify (Bash - run tests)

PERFORM:
1. Execute Read(auth.py) → parse result
2. Execute Grep(error pattern) → find occurrences
3. Generate fix based on findings
4. Execute Edit(auth.py, fix) → apply
5. Execute Bash(pytest) → verify
6. Report result to user
```
