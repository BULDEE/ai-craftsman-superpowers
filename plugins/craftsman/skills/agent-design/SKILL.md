---
name: agent-design
description: |
  Design AI agents using the 3P pattern (Perceive/Plan/Perform).
  Use when building autonomous AI agents or workflows.

  ACTIVATES AUTOMATICALLY when detecting: "AI agent", "autonomous agent",
  "agent architecture", "tool use", "agent workflow", "3P pattern"
allowed-tools:
  - Read
  - Glob
  - Grep
  - Write
  - Edit
  - Task
  - AskUserQuestion
---

# Agent Design Skill - 3P Pattern Architecture

Design AI agents using the Perceive-Plan-Perform (3P) cognitive architecture.

## 3P Pattern Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     AGENT COGNITIVE LOOP                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│    ┌──────────┐      ┌──────────┐      ┌──────────┐             │
│    │ PERCEIVE │─────▶│   PLAN   │─────▶│ PERFORM  │             │
│    └──────────┘      └──────────┘      └──────────┘             │
│         │                                    │                   │
│         │            ┌──────────┐            │                   │
│         └────────────│ REFLECT  │◀───────────┘                   │
│                      └──────────┘                                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Phase 1: PERCEIVE

Gather and interpret information from the environment.

```python
class Perceiver:
    """Gathers context and interprets the environment."""

    def perceive(self, input: str, context: Context) -> Perception:
        return Perception(
            user_intent=self.extract_intent(input),
            entities=self.extract_entities(input),
            context_summary=self.summarize_context(context),
            constraints=self.identify_constraints(input),
            ambiguities=self.detect_ambiguities(input),
        )

    def extract_intent(self, input: str) -> Intent:
        """Classify user intent: question, command, clarification, etc."""
        pass

    def detect_ambiguities(self, input: str) -> list[Ambiguity]:
        """Identify unclear aspects requiring clarification."""
        pass
```

### Perception Checklist

- [ ] User intent identified
- [ ] Key entities extracted
- [ ] Context summarized
- [ ] Constraints recognized
- [ ] Ambiguities flagged (ask before assuming)

## Phase 2: PLAN

Devise a strategy to achieve the goal.

```python
class Planner:
    """Creates action plans based on perception."""

    def plan(self, perception: Perception, tools: list[Tool]) -> Plan:
        # 1. Break down into subtasks
        subtasks = self.decompose(perception.user_intent)

        # 2. Select tools for each subtask
        tool_assignments = self.assign_tools(subtasks, tools)

        # 3. Order by dependencies
        ordered_tasks = self.topological_sort(tool_assignments)

        # 4. Identify risks
        risks = self.assess_risks(ordered_tasks)

        return Plan(
            tasks=ordered_tasks,
            risks=risks,
            estimated_steps=len(ordered_tasks),
        )

    def decompose(self, intent: Intent) -> list[Subtask]:
        """Break complex goals into atomic subtasks."""
        pass
```

### Planning Checklist

- [ ] Goal decomposed into subtasks
- [ ] Tools selected for each subtask
- [ ] Dependencies identified
- [ ] Risks assessed
- [ ] Fallback strategies defined

## Phase 3: PERFORM

Execute the plan using available tools.

```python
class Performer:
    """Executes plan steps using tools."""

    def perform(self, plan: Plan, tools: ToolRegistry) -> list[Result]:
        results = []

        for task in plan.tasks:
            # Select tool
            tool = tools.get(task.tool_name)

            # Execute with error handling
            try:
                result = tool.execute(task.parameters)
                results.append(Result(task=task, output=result, status="success"))
            except ToolError as e:
                # Attempt recovery
                recovery = self.recover(task, e, tools)
                results.append(recovery)

            # Reflect after each step
            self.reflect(task, results[-1])

        return results
```

### Execution Checklist

- [ ] Tool executed correctly
- [ ] Output validated
- [ ] Errors handled gracefully
- [ ] Progress tracked
- [ ] Reflection after each step

## Phase 4: REFLECT

Learn from execution and adjust.

```python
class Reflector:
    """Reflects on execution and adjusts strategy."""

    def reflect(self, task: Task, result: Result) -> Reflection:
        return Reflection(
            success=result.status == "success",
            lessons_learned=self.extract_lessons(result),
            plan_adjustments=self.suggest_adjustments(result),
            should_continue=self.evaluate_progress(result),
        )

    def extract_lessons(self, result: Result) -> list[str]:
        """What worked? What didn't?"""
        pass
```

## Tool Design Pattern

```python
from abc import ABC, abstractmethod
from pydantic import BaseModel

class ToolInput(BaseModel):
    """Base class for tool inputs with validation."""
    pass

class ToolOutput(BaseModel):
    """Base class for tool outputs."""
    success: bool
    data: Any
    error: str | None = None

class Tool(ABC):
    """Base tool interface."""

    @property
    @abstractmethod
    def name(self) -> str:
        pass

    @property
    @abstractmethod
    def description(self) -> str:
        """Used by LLM to decide when to use this tool."""
        pass

    @property
    @abstractmethod
    def parameters_schema(self) -> dict:
        """JSON schema for parameters."""
        pass

    @abstractmethod
    def execute(self, params: ToolInput) -> ToolOutput:
        pass
```

## Agent Design Template

```markdown
# Agent Design: [Agent Name]

## Purpose
[What problem does this agent solve?]

## Capabilities
- [ ] Capability 1
- [ ] Capability 2

## Tools Available

| Tool | Purpose | Risk Level |
|------|---------|------------|
| read_file | Read file contents | Low |
| write_file | Write file contents | Medium |
| execute_code | Run code | High |

## Workflow

### Perceive
- Inputs: [What the agent receives]
- Extraction: [What it identifies]

### Plan
- Decomposition strategy: [How it breaks down tasks]
- Tool selection criteria: [How it chooses tools]

### Perform
- Execution strategy: [Sequential, Parallel]
- Error handling: [Recovery strategies]

### Reflect
- Success criteria: [How it knows it succeeded]
- Learning: [What it remembers]

## Safety Constraints

- [ ] Confirmation required for: [destructive actions]
- [ ] Rate limits: [X calls per minute]
- [ ] Sandboxing: [isolated execution]
- [ ] Audit logging: [all actions logged]

## Example Interaction

```
User: [Example input]

PERCEIVE:
- Intent: [identified intent]
- Entities: [extracted entities]

PLAN:
1. [Step 1]
2. [Step 2]

PERFORM:
- Tool: [tool used]
- Result: [output]

REFLECT:
- Success: [yes/no]
- Adjustment: [if needed]

Response: [Final output to user]
```
```

## Anti-Patterns

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| No planning | Random tool calls | Always plan first |
| No reflection | Repeats mistakes | Reflect after each step |
| Overconfidence | Assumes success | Verify outputs |
| No error handling | Crashes on failure | Graceful recovery |
| No constraints | Dangerous actions | Safety boundaries |

## Process

1. **Define agent purpose and scope**
2. **Design perception layer**
3. **Create planning strategy**
4. **Implement tool interfaces**
5. **Add reflection loop**
6. **Define safety constraints**
7. **Test with edge cases**
